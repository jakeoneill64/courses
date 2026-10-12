import argparse
import json
import math
import time

import numpy as np

from aif import bpe, check, data, results


# snippet:begin keys
def gram_keys(ids: np.ndarray, n: int, vocab: int) -> np.ndarray:
    """Every run of n tokens as one integer; 13 bits a token, so n is at most 4."""
    keys = np.zeros(len(ids) - n + 1, dtype=np.int64)
    for j in range(n):
        keys = keys * vocab + ids[j : len(ids) - n + 1 + j]
    return keys


def count_pairs(ctx: np.ndarray, tok: np.ndarray, vocab: int):
    """Distinct (context, token) pairs, sorted, with how often each occurs."""
    contexts, rank = np.unique(ctx, return_inverse=True)
    keys, counts = np.unique(rank * vocab + tok, return_counts=True)
    return contexts[keys // vocab], keys % vocab, counts


def ngrams(ids: np.ndarray, n: int, vocab: int):
    return count_pairs(gram_keys(ids[:-1], n - 1, vocab), ids[n - 1 :], vocab)


# snippet:end keys


class Table:
    """N-gram counts by context, with per-context totals and distinct continuations."""

    def __init__(self, ctx: np.ndarray, tok: np.ndarray, counts: np.ndarray, vocab: int):
        self.vocab, self.counts = vocab, counts
        self.ctx, first, self.distinct = np.unique(ctx, return_index=True, return_counts=True)
        self.total = np.add.reduceat(counts, first)
        self.keys = np.repeat(np.arange(len(self.ctx)), self.distinct) * vocab + tok

    def find(self, ctx: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        at = np.clip(np.searchsorted(self.ctx, ctx), 0, len(self.ctx) - 1)
        return at, self.ctx[at] == ctx

    def lookup(self, ctx: np.ndarray, tok: np.ndarray) -> np.ndarray:
        at, hit = self.find(ctx)
        key = at * self.vocab + tok
        i = np.clip(np.searchsorted(self.keys, key), 0, len(self.keys) - 1)
        return np.where(hit & (self.keys[i] == key), self.counts[i], 0)

    def context(self, ctx: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        at, hit = self.find(ctx)
        return np.where(hit, self.total[at], 0), np.where(hit, self.distinct[at], 0)


# snippet:begin kneser-ney
class KneserNey:
    def __init__(self, ids: np.ndarray, order: int, vocab: int, discount: float = 0.75):
        self.order, self.vocab, self.d = order, vocab, discount
        self.tables = [None]
        for n in range(1, order + 1):
            if n == order:
                ctx, tok, counts = ngrams(ids, n, vocab)
            else:
                ctx, tok, _ = ngrams(ids, n + 1, vocab)
                ctx, tok, counts = count_pairs(ctx % vocab ** (n - 1), tok, vocab)
            self.tables.append(Table(ctx, tok, counts, vocab))

    def prob(self, history: np.ndarray, token: np.ndarray, n: int) -> np.ndarray:
        """P(token | the last n - 1 tokens of history), for arrays of positions."""
        t = self.tables[n]
        ctx = np.zeros(len(token), dtype=np.int64)
        for j in range(n - 1):
            ctx = ctx * self.vocab + history[:, history.shape[1] - n + 1 + j]
        count = t.lookup(ctx, token)
        if n == 1:
            return (count + 1.0) / (t.counts.sum() + self.vocab)
        total, distinct = t.context(ctx)
        lower = self.prob(history, token, n - 1)
        safe = np.maximum(total, 1)
        mixed = np.maximum(count - self.d, 0) / safe + self.d * distinct / safe * lower
        return np.where(total > 0, mixed, lower)


# snippet:end kneser-ney


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-tokens", type=float, default=100e6)
    parser.add_argument("--valid-tokens", type=int, default=500_000)
    parser.add_argument("--order", type=int, default=5)
    args = parser.parse_args()
    folder = data.DATA / "tinystories"
    tok = bpe.BPE.load(folder / "bpe8192.json")
    stats = json.loads((folder / "stats-8192.json").read_text())
    bytes_per_token = stats["valid"]["bytes"] / stats["valid"]["tokens"]
    train = np.memmap(folder / "train-8192.bin", dtype=np.uint16, mode="r")[
        : int(args.train_tokens)
    ].astype(np.int64)
    valid = np.memmap(folder / "valid-8192.bin", dtype=np.uint16, mode="r")[
        : args.valid_tokens
    ].astype(np.int64)
    # snippet:begin evaluate
    k = args.order - 1
    history = np.lib.stride_tricks.sliding_window_view(valid[:-1], k)
    targets = valid[k:]
    rows = []
    for n in range(1, args.order + 1):
        start = time.perf_counter()
        model = KneserNey(train, n, tok.vocab_size)
        nats = float(-np.log(model.prob(history, targets, n)).mean())
        rows.append(
            {
                "order": n,
                "nats": nats,
                "bpb": nats / math.log(2) / bytes_per_token,
                "perplexity": math.exp(nats),
            }
        )
        print(
            f"{n}-gram: {nats:.3f} nats per token, {rows[-1]['bpb']:.3f} bits per byte, "
            f"perplexity {rows[-1]['perplexity']:7.1f}  ({time.perf_counter() - start:.0f} s)"
        )
    # snippet:end evaluate
    rng = np.random.default_rng(3)
    eot = tok.special["<|endoftext|>"]
    out = [eot] * k
    everything = np.arange(tok.vocab_size)
    while len(out) < 80 + k:
        hist = np.tile(np.array(out[-k:]), (tok.vocab_size, 1))
        p = model.prob(hist, everything, args.order)
        out.append(int(rng.choice(tok.vocab_size, p=p / p.sum())))
    print(f"a sample from the {args.order}-gram model:")
    print("  " + tok.decode([t for t in out[k:] if t != eot]).replace("\n", " "))
    results.save("u2-ngram", rows)
    check.expect("higher orders help", rows[3]["nats"] < rows[1]["nats"])


if __name__ == "__main__":
    check.main(main)
