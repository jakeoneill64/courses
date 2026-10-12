import argparse
import re
import time
from collections import Counter

import numpy as np
import pyarrow.parquet as pq
import scipy.sparse as sp
import torch
import torch.nn.functional as F

from aif import bpe, chat, check, data, device, gpt, results, sample
from aif.hnsw import HNSW
from u3.prefs import final_hidden


def squad(split: str):
    rows = pq.read_table(
        data.fetch("rajpurkar/squad", f"plain_text/{split}-00000-of-00001.parquet")
    ).to_pylist()
    contexts = list(dict.fromkeys(r["context"] for r in rows))
    index = {c: i for i, c in enumerate(contexts)}
    questions = [(r["question"], index[r["context"]], r["answers"]["text"]) for r in rows]
    return contexts, questions


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


# snippet:begin bm25
class BM25:
    def __init__(self, docs: list[str], k1: float = 1.5, b: float = 0.75):
        tokenised = [words(d) for d in docs]
        self.vocab = {w: i for i, w in enumerate(sorted({w for d in tokenised for w in d}))}
        rows, cols, vals = [], [], []
        for i, d in enumerate(tokenised):
            for w, n in Counter(d).items():
                rows.append(i)
                cols.append(self.vocab[w])
                vals.append(n)
        tf = sp.csr_matrix(
            (vals, (rows, cols)), shape=(len(docs), len(self.vocab)), dtype=np.float32
        )
        lengths = np.array([len(d) for d in tokenised], dtype=np.float32)
        df = np.bincount(cols, minlength=len(self.vocab))
        self.idf = np.log(1 + (len(docs) - df + 0.5) / (df + 0.5)).astype(np.float32)
        norm = k1 * (1 - b + b * lengths / lengths.mean())
        tf = tf.tocoo()
        weighted = tf.data * (k1 + 1) / (tf.data + norm[tf.row]) * self.idf[tf.col]
        self.matrix = sp.csr_matrix((weighted, (tf.row, tf.col)), shape=tf.shape)

    def scores(self, query: str) -> np.ndarray:
        ids = [self.vocab[w] for w in set(words(query)) if w in self.vocab]
        return np.asarray(self.matrix[:, ids].sum(axis=1)).ravel()


# snippet:end bm25


# snippet:begin embed
def embed(
    model, tok, texts: list[str], dev, batch: int = 64, limit: int = 256
) -> torch.Tensor:
    out = []
    for i in range(0, len(texts), batch):
        rows = [tok.encode(t)[:limit] for t in texts[i : i + batch]]
        longest = max(len(r) for r in rows)
        ids = torch.zeros(len(rows), longest, dtype=torch.long, device=dev)
        mask = torch.zeros(len(rows), longest, device=dev)
        for j, r in enumerate(rows):
            ids[j, : len(r)] = torch.tensor(r)
            mask[j, : len(r)] = 1
        hidden = final_hidden(model, ids)
        pooled = (hidden * mask[..., None]).sum(1) / mask.sum(1, keepdim=True)
        out.append(F.normalize(pooled, dim=-1))
    return torch.cat(out)


# snippet:end embed


def recall(scores: np.ndarray, gold: np.ndarray, ks=(1, 5, 20)) -> list[float]:
    ranks = (scores > scores[np.arange(len(gold)), gold][:, None]).sum(1)
    return [float((ranks < k).mean()) for k in ks]


def f1(prediction: str, answers: list[str]) -> float:
    p = words(prediction)
    best = 0.0
    for a in answers:
        g = words(a)
        common = sum((Counter(p) & Counter(g)).values())
        if common:
            precision, rec = common / len(p), common / len(g)
            best = max(best, 2 * precision * rec / (precision + rec))
    return best


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--steps", type=int, default=1500)
    parser.add_argument("--rag-questions", type=int, default=300)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    contexts, questions = squad("validation")
    train_contexts, train_questions = squad("train")
    gold = np.array([q[1] for q in questions])
    print(f"SQuAD validation: {len(questions):,} questions about {len(contexts):,} paragraphs")
    table = {}
    # snippet:begin compare
    bm25 = BM25(contexts)
    lexical = np.stack([bm25.scores(q) for q, _, _ in questions])
    table["BM25"] = recall(lexical, gold)
    folder = data.model_files("HuggingFaceTB/SmolLM2-135M")
    tok = bpe.BPE.from_huggingface(folder / "tokenizer.json")
    encoder = gpt.from_huggingface(folder).to(dev).eval()
    with torch.no_grad():
        c_vec = embed(encoder, tok, contexts, dev)
        q_vec = embed(encoder, tok, [q for q, _, _ in questions], dev)
    table["SmolLM2-135M, mean-pooled"] = recall((q_vec @ c_vec.T).cpu().numpy(), gold)
    # snippet:end compare
    # snippet:begin contrastive
    encoder.train()
    opt = torch.optim.AdamW(encoder.parameters(), lr=2e-5, weight_decay=0.0)
    rng = np.random.default_rng(0)
    start = time.perf_counter()
    for step in range(1, args.steps + 1):
        picks = rng.choice(len(train_questions), 32, replace=False)
        qs = [train_questions[i][0] for i in picks]
        cs = [train_contexts[train_questions[i][1]] for i in picks]
        logits = embed(encoder, tok, qs, dev) @ embed(encoder, tok, cs, dev).T / 0.05
        target = torch.arange(len(picks), device=dev)
        loss = (F.cross_entropy(logits, target) + F.cross_entropy(logits.T, target)) / 2
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
        device.release(dev)
        if step % 500 == 0:
            print(
                f"contrastive step {step}  loss {loss.item():.3f}  "
                f"{time.perf_counter() - start:4.0f} s",
                flush=True,
            )
    # snippet:end contrastive
    encoder.eval()
    with torch.no_grad():
        c_vec = embed(encoder, tok, contexts, dev)
        q_vec = embed(encoder, tok, [q for q, _, _ in questions], dev)
    dense = (q_vec @ c_vec.T).cpu().numpy()
    table["SmolLM2-135M, fine-tuned"] = recall(dense, gold)
    # snippet:begin fusion
    ranks = lambda s: np.argsort(np.argsort(-s, axis=1), axis=1)
    fused = 1 / (60 + ranks(lexical)) + 1 / (60 + ranks(dense))
    # snippet:end fusion
    table["fusion of BM25 and fine-tuned"] = recall(fused, gold)
    print(f"{'retriever':<34}{'recall@1':>10}{'recall@5':>10}{'recall@20':>11}")
    for name, (r1, r5, r20) in table.items():
        print(f"{name:<34}{r1:10.1%}{r5:10.1%}{r20:11.1%}")

    with torch.no_grad():
        corpus = embed(encoder, tok, train_contexts + contexts, dev).cpu().numpy()
    start = time.perf_counter()
    index = HNSW(corpus, m=16, ef_construction=100)
    built = time.perf_counter() - start
    queries = q_vec.cpu().numpy()[:500]
    exact = np.argsort(-(queries @ corpus.T), axis=1)[:, :10]
    print(
        f"HNSW over {len(corpus):,} paragraphs built in {built:.0f} s; 500 queries, 10 neighbours each:"
    )
    for ef in (10, 32, 100):
        index.computed = 0
        found = [index.search(q, 10, ef) for q in queries]
        hit = np.mean([len(set(f) & set(e)) / 10 for f, e in zip(found, exact)])
        print(
            f"  ef {ef:3d}: recall@10 against exact search {hit:.1%}, "
            f"{index.computed / len(queries):,.0f} distances per query instead of {len(corpus):,}"
        )

    reader_dir = data.model_files("HuggingFaceTB/SmolLM2-360M-Instruct")
    reader = gpt.from_huggingface(reader_dir).to(dev).eval()
    end = tok.special[chat.END]

    # snippet:begin rag
    def answer(question: str, passages: list[str]) -> str:
        context = "".join(f"[{i + 1}] {p}\n\n" for i, p in enumerate(passages))
        content = (
            (f"Passages:\n{context}" if passages else "")
            + f"Question: {question}\nReply with a short answer only, a few words, "
            "taken from the passages if any."
        )
        ids = tok.encode(chat.render([{"role": "user", "content": content}]))
        return tok.decode(sample.generate(reader, ids, 32, stop=end, temperature=0.0)).replace(
            chat.END, ""
        )

    # snippet:end rag
    picks = np.random.default_rng(1).choice(len(questions), args.rag_questions, replace=False)
    scores = {"closed book": [], "top 3 retrieved": [], "the right paragraph": []}
    for i in picks:
        q, g, answers = questions[i]
        top = np.argsort(-fused[i])[:3]
        scores["closed book"].append(f1(answer(q, []), answers))
        scores["top 3 retrieved"].append(f1(answer(q, [contexts[t] for t in top]), answers))
        scores["the right paragraph"].append(f1(answer(q, [contexts[g]]), answers))
    print(
        f"SmolLM2-360M-Instruct answering {args.rag_questions} questions (token F1 against the reference answers):"
    )
    for name, s in scores.items():
        print(f"  {name:<22} {np.mean(s):.1%}")
    results.save(
        "u3-retrieval",
        {"table": table, "rag": {k: float(np.mean(v)) for k, v in scores.items()}},
    )
    check.expect(
        "fine-tuning helps",
        table["SmolLM2-135M, fine-tuned"][1] > table["SmolLM2-135M, mean-pooled"][1],
    )


if __name__ == "__main__":
    check.main(main)
