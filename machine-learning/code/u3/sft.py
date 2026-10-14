import argparse
import time

import pyarrow.parquet as pq
import torch

from aif import bpe, chat, check, data, device, finetune, gpt, sample

PROMPTS = [
    "What is the boiling point of water at sea level?",
    "Write a haiku about autumn leaves.",
    "Explain in two sentences why the sky is blue.",
    "Give me a Python function that reverses a string.",
]


def conversations(split: str, limit: int) -> list[list[dict]]:
    name = (
        "data/train-00000-of-00004.parquet"
        if split == "train"
        else "data/test-00000-of-00001.parquet"
    )
    rows = pq.read_table(
        data.fetch("HuggingFaceTB/smol-smoltalk", name), columns=["messages"]
    ).to_pylist()
    return [r["messages"] for r in rows[:limit]]


def replies(model, tok, prompts, tokens: int = 80) -> list[str]:
    out = []
    for p in prompts:
        ids = tok.encode(chat.render([{"role": "user", "content": p}]))
        reply = sample.generate(
            model, ids, tokens, stop=tok.special[chat.END], temperature=0.0
        )
        out.append(tok.decode(reply).replace(chat.END, "").strip())
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="HuggingFaceTB/SmolLM2-135M")
    parser.add_argument("--name", default="u3-sft-135m")
    parser.add_argument("--examples", type=int, default=10000)
    parser.add_argument("--seq", type=int, default=1024)
    parser.add_argument("--batch-tokens", type=int, default=4096)
    parser.add_argument("--accum", type=int, default=4, help="batches per optimiser step")
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--epochs", type=int, default=1)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    folder = data.model_files(args.model)
    tok = bpe.BPE.from_huggingface(folder / "tokenizer.json")
    model = gpt.from_huggingface(folder).to(dev)
    pad_id = tok.special["<|endoftext|>"]
    # snippet:begin data
    train = [
        chat.encode_for_training(tok, m, args.seq)
        for m in conversations("train", args.examples)
    ]
    train = [(x, y) for x, y in train if any(t != -100 for t in y)]
    test = [chat.encode_for_training(tok, m, args.seq) for m in conversations("test", 500)]
    test = [(x, y) for x, y in test if any(t != -100 for t in y)]
    # snippet:end data
    trained_on = sum(sum(t != -100 for t in y) for _, y in train)
    print(
        f"{len(train):,} conversations, {sum(len(x) for x, _ in train) / 1e6:.1f}M tokens, of which "
        f"{trained_on / 1e6:.1f}M are the assistant's and carry the loss"
    )
    before = finetune.evaluate(model, test, args.batch_tokens, pad_id, dev)
    print(f"held-out loss on assistant tokens before fine-tuning: {before:.3f}")
    before_replies = replies(model.eval(), tok, PROMPTS)
    model.train()
    # snippet:begin loop
    opt = torch.optim.AdamW(
        model.parameters(), lr=args.lr, weight_decay=0.0, betas=(0.9, 0.95)
    )
    batches = finetune.token_batches(train, args.batch_tokens)
    steps = [batches[i : i + args.accum] for i in range(0, len(batches), args.accum)]
    total = len(steps) * args.epochs
    start, step = time.perf_counter(), 0
    for epoch in range(args.epochs):
        for micro in steps:
            for group in opt.param_groups:
                group["lr"] = args.lr * finetune.cosine(step, total, warmup=50)
            tokens = sum(finetune.labelled(train, indices) for indices in micro)
            opt.zero_grad(set_to_none=True)
            loss = 0.0
            for indices in micro:
                ids, labels = finetune.pad(train, indices, pad_id, dev)
                logp, _ = finetune.token_logprobs(model, ids, labels)
                part = -logp.sum() / tokens
                part.backward()
                loss += part.item()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            step += 1
            device.release(dev)
            if step % 200 == 0 or step == total:
                print(
                    f"step {step:5d}/{total}  loss {loss:.3f}  "
                    f"{time.perf_counter() - start:5.0f} s",
                    flush=True,
                )
    # snippet:end loop
    after = finetune.evaluate(model, test, args.batch_tokens, pad_id, dev)
    print(f"held-out loss on assistant tokens after fine-tuning: {after:.3f}")
    model.eval()
    official = gpt.from_huggingface(data.model_files(args.model + "-Instruct")).to(dev).eval()
    reference = finetune.evaluate(official, test, args.batch_tokens, pad_id, dev)
    print(
        f"the official {args.model.split('/')[1]}-Instruct on the same text: {reference:.3f}"
    )
    for prompt, a, b, c in zip(
        PROMPTS, before_replies, replies(model, tok, PROMPTS), replies(official, tok, PROMPTS)
    ):
        print(
            f"\nuser: {prompt}\n  base:     {a[:200]!r}\n  yours:    {b[:200]!r}\n  official: {c[:200]!r}"
        )
    gpt.save(model, data.RUNS / args.name / "model.pt", base=args.model)
    check.expect(
        "fine-tuning lowered the held-out loss",
        after < before - 0.2,
        f"{before:.3f} -> {after:.3f}",
    )


if __name__ == "__main__":
    check.main(main)
