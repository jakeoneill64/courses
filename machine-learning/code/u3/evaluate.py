import argparse
import re

import numpy as np
import pyarrow.parquet as pq
import torch

from aif import bpe, chat, check, data, device, evals, gpt, results, sample
from u3.grpo import problem, reward
from u3.prefs import pairs

LETTERS = "ABCDE"


def arc(split: str) -> list[dict]:
    rows = pq.read_table(
        data.fetch("allenai/ai2_arc", f"{split}/test-00000-of-00001.parquet")
    ).to_pylist()
    return [r for r in rows if r["answerKey"] in r["choices"]["label"]]


# snippet:begin arc
def arc_correct(model, tok, items, dev) -> np.ndarray:
    right = []
    for r in items:
        context = f"Question: {r['question']}\nAnswer:"
        options = [" " + t for t in r["choices"]["text"]]
        picked = evals.choose(model, tok, context, options, dev)
        right.append(r["choices"]["label"][picked] == r["answerKey"])
    return np.array(right)


# snippet:end arc


def load(name: str, dev):
    if name.startswith("HuggingFaceTB/"):
        return gpt.from_huggingface(data.model_files(name)).to(dev).eval()
    return gpt.load(data.RUNS / name / "model.pt", dev).eval()


# snippet:begin judge
JUDGE = (
    "You are judging two replies to the same request. Request:\n{prompt}\n\n"
    "Reply A:\n{a}\n\nReply B:\n{b}\n\n"
    "Which reply is more helpful, accurate and well written? "
    "Answer with the single letter A or B."
)


@torch.no_grad()
def judge_prefers_b(judge, tok, prompt: str, a: str, b: str, dev) -> float:
    ids = tok.encode(
        chat.render([{"role": "user", "content": JUDGE.format(prompt=prompt, a=a, b=b)}])
    )
    logits = judge(torch.tensor([ids], device=dev))[0, -1].float()
    pair = logits[[tok.encode("A")[0], tok.encode("B")[0]]]
    return float(pair.softmax(-1)[1])


# snippet:end judge


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--judge-prompts", type=int, default=100)
    args = parser.parse_args()
    dev = device.device()
    tok = bpe.BPE.from_huggingface(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    )
    record = {}
    easy, challenge = arc("ARC-Easy"), arc("ARC-Challenge")
    models = [
        "HuggingFaceTB/SmolLM2-135M",
        "u3-sft-135m",
        "u3-dpo-135m",
        "HuggingFaceTB/SmolLM2-135M-Instruct",
        "HuggingFaceTB/SmolLM2-360M",
        "HuggingFaceTB/SmolLM2-360M-Instruct",
    ]
    print(
        f"ARC multiple choice, scored by mean log-probability of each option "
        f"({len(easy):,} easy and {len(challenge):,} challenge questions; chance is about 25%)"
    )
    print(f"{'model':<34}{'ARC-Easy':>22}{'ARC-Challenge':>22}")
    correct = {}
    for name in models:
        model = load(name, dev)
        e, c = arc_correct(model, tok, easy, dev), arc_correct(model, tok, challenge, dev)
        correct[name] = (e, c)
        cells = [
            f"{x.mean():.1%} [{lo:.1%}, {hi:.1%}]"
            for x in (e, c)
            for lo, hi in [evals.bootstrap(x.astype(float))]
        ]
        print(f"{name.split('/')[-1]:<34}{cells[0]:>22}{cells[1]:>22}", flush=True)
        record[name] = {"easy": float(e.mean()), "challenge": float(c.mean())}
        del model
    # snippet:begin compare
    for a, b in (
        ("HuggingFaceTB/SmolLM2-135M", "u3-sft-135m"),
        ("u3-sft-135m", "u3-dpo-135m"),
        ("HuggingFaceTB/SmolLM2-135M", "HuggingFaceTB/SmolLM2-360M"),
    ):
        both = (
            np.concatenate([correct[a][0], correct[a][1]]),
            np.concatenate([correct[b][0], correct[b][1]]),
        )
        diff, lo, hi, _ = evals.paired(*both)
        print(
            f"{b.split('/')[-1]} minus {a.split('/')[-1]}, all ARC: "
            f"{diff:+.1%} [{lo:+.1%}, {hi:+.1%}], "
            f"McNemar p = {evals.mcnemar(*both):.2g}"
        )
    # snippet:end compare

    held_out = [problem(np.random.default_rng(10_000 + i)) for i in range(200)]
    solved_by = []
    for name in ("HuggingFaceTB/SmolLM2-360M-Instruct", "u3-grpo"):
        model = load(name, dev)
        solved = []
        for question, answer in held_out:
            prompt = tok.encode(chat.render([{"role": "user", "content": question}]))
            out = sample.generate(
                model, prompt, 160, stop=tok.special[chat.END], temperature=0.0
            )
            solved.append(reward(tok.decode(out), answer))
        solved = np.array(solved, dtype=bool)
        solved_by.append(solved)
        lo, hi = evals.bootstrap(solved)
        print(
            f"arithmetic, {name.split('/')[-1]}: {solved.mean():.1%} [{lo:.1%}, {hi:.1%}] of 200 problems"
        )
        record[f"arithmetic {name}"] = float(solved.mean())
        del model
    diff, lo, hi, _ = evals.paired(*solved_by)
    print(
        f"u3-grpo minus SmolLM2-360M-Instruct, arithmetic: {diff:+.1%} [{lo:+.1%}, {hi:+.1%}], "
        f"McNemar p = {evals.mcnemar(*solved_by):.2g}"
    )

    judge = load("HuggingFaceTB/SmolLM2-1.7B-Instruct", dev)
    sft, dpo = load("u3-sft-135m", dev), load("u3-dpo-135m", dev)
    test = pairs("test", args.judge_prompts, tok)
    forward, backward = [], []
    for p in test:
        replies = [
            tok.decode(
                sample.generate(
                    m, p["prompt"], 200, stop=tok.special[chat.END], temperature=0.0
                )
            )
            .replace(chat.END, "")
            .strip()
            for m in (sft, dpo)
        ]
        forward.append(judge_prefers_b(judge, tok, p["text"], replies[0], replies[1], dev))
        backward.append(
            1 - judge_prefers_b(judge, tok, p["text"], replies[1], replies[0], dev)
        )
        device.release(dev)
    forward, backward = np.array(forward), np.array(backward)
    print(
        f"judge, SmolLM2-1.7B-Instruct, on {len(test)} prompts: prefers the DPO reply with probability "
        f"{forward.mean():.2f} when it is shown second, {backward.mean():.2f} when it is shown first"
    )
    both_ways = (forward + backward) / 2
    lo, hi = evals.bootstrap(both_ways)
    print(
        f"  averaged over both orders: {both_ways.mean():.2f} [{lo:.2f}, {hi:.2f}]; the two orders agree on "
        f"{np.mean((forward > 0.5) == (backward > 0.5)):.0%} of prompts"
    )

    # snippet:begin contamination
    rows = pq.read_table(
        data.fetch("HuggingFaceTB/smol-smoltalk", "data/train-00000-of-00004.parquet"),
        columns=["messages"],
    ).to_pylist()
    words = lambda s: re.findall(r"[a-z0-9]+", s.lower())
    seen = set()
    for r in rows:
        w = words(" ".join(m["content"] for m in r["messages"]))
        seen.update(tuple(w[i : i + 13]) for i in range(len(w) - 12))
    hits = sum(
        any(tuple(w[i : i + 13]) in seen for i in range(len(w) - 12))
        for w in (words(r["question"]) for r in easy + challenge)
    )
    # snippet:end contamination
    print(
        f"contamination check: {hits} of {len(easy) + len(challenge):,} ARC test questions share a 13-word "
        f"sequence with the fine-tuning data"
    )
    record["judge"] = {"forward": float(forward.mean()), "backward": float(backward.mean())}
    results.save("u3-evaluate", record)
    check.expect(
        "the 360M base beats the 135M base",
        record["HuggingFaceTB/SmolLM2-360M"]["easy"]
        > record["HuggingFaceTB/SmolLM2-135M"]["easy"],
    )


if __name__ == "__main__":
    check.main(main)
