import argparse
import json
import time

import numpy as np

from aif import bpe, check, corpus, data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train the TinyStories tokeniser and encode the corpus."
    )
    parser.add_argument("--vocab", type=int, default=8192)
    args = parser.parse_args()

    out = data.DATA / "tinystories"
    out.mkdir(parents=True, exist_ok=True)
    tokenizer = out / f"bpe{args.vocab}.json"
    train_txt, valid_txt = data.tinystories("train"), data.tinystories("valid")

    # snippet:begin prepare
    if not tokenizer.exists():
        start = time.perf_counter()
        counts = corpus.count_file(train_txt)
        tok = bpe.train(counts, args.vocab, special=[corpus.EOT])
        tok.save(tokenizer)
        print(
            f"tokeniser: {len(counts):,} distinct chunks, {args.vocab} tokens "
            f"in {time.perf_counter() - start:.0f} s"
        )
    tok = bpe.BPE.load(tokenizer)

    stats = {}
    for split, path in (("train", train_txt), ("valid", valid_txt)):
        start = time.perf_counter()
        n = corpus.encode_file(path, tokenizer, out / f"{split}-{args.vocab}.bin")
        size = path.stat().st_size
        stats[split] = {"tokens": n, "bytes": size}
        print(
            f"{split}: {size / 1e6:,.0f} MB of text -> {n / 1e6:,.1f}M tokens "
            f"({size / n:.2f} bytes per token) in {time.perf_counter() - start:.0f} s"
        )
    # snippet:end prepare
    (out / f"stats-{args.vocab}.json").write_text(json.dumps(stats))

    ids = np.memmap(out / f"valid-{args.vocab}.bin", dtype=np.uint16, mode="r")
    sample = valid_txt.read_text()[:20000].split(corpus.EOT)[2].strip()
    check.expect("round trip", tok.decode(tok.encode(sample)) == sample)
    check.expect("token range", int(ids.max()) < tok.vocab_size)
    first = int(np.flatnonzero(ids == tok.special[corpus.EOT])[0]) + 1
    print(
        "the first complete validation story begins:",
        repr(tok.decode(list(ids[first : first + 30]))),
    )


if __name__ == "__main__":
    check.main(main)
