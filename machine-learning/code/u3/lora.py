import argparse
import time

import torch

from aif import bpe, chat, check, data, device, finetune, gpt, lora, quant
from u3.sft import PROMPTS, conversations, replies


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="HuggingFaceTB/SmolLM2-135M")
    parser.add_argument(
        "--int4", action="store_true", help="store the frozen weights in 4 bits"
    )
    parser.add_argument(
        "--full", action="store_true", help="train every weight instead of adapters"
    )
    parser.add_argument("--rank", type=int, default=16)
    parser.add_argument("--examples", type=int, default=10000)
    parser.add_argument("--batch-tokens", type=int, default=4096)
    parser.add_argument("--accum", type=int, default=4, help="batches per optimiser step")
    parser.add_argument("--lr", type=float, help="default 1e-3, or 1e-4 with --full")
    args = parser.parse_args()
    if args.full and args.int4:
        parser.error("4-bit weights are frozen, so --full cannot be combined with --int4")
    lr = args.lr or (1e-4 if args.full else 1e-3)
    dev = device.device()
    device.seed(0)
    folder = data.model_files(args.model)
    tok = bpe.BPE.from_huggingface(folder / "tokenizer.json")
    pad_id = tok.special["<|endoftext|>"]
    # snippet:begin setup
    model = gpt.from_huggingface(folder)
    if args.int4:
        quant.quantise_model_int4(model)
    model.to(dev)
    if args.full:
        params = list(model.parameters())
    else:
        params = lora.add_lora(model, rank=args.rank, alpha=2.0 * args.rank)
    # snippet:end setup
    frozen = sum(p.numel() for p in model.parameters() if not p.requires_grad)
    stored = sum(
        b.numel() * b.element_size()
        for b in model.buffers()
        if b.dtype in (torch.uint8, torch.float16)
    )
    trainable = sum(p.numel() for p in params)
    print(
        f"{args.model.split('/')[1]}{', 4-bit' if args.int4 else ''}: {trainable / 1e6:.2f}M trainable "
        f"parameters ({trainable / (trainable + frozen + stored * 2):.2%} of the model); frozen weights take "
        f"{(frozen * 4 + stored) / 2**20:,.0f} MiB"
    )
    train = [
        chat.encode_for_training(tok, m, 1024) for m in conversations("train", args.examples)
    ]
    train = [(x, y) for x, y in train if any(t != -100 for t in y)]
    test = [chat.encode_for_training(tok, m, 1024) for m in conversations("test", 500)]
    test = [(x, y) for x, y in test if any(t != -100 for t in y)]
    before = finetune.evaluate(model, test, args.batch_tokens, pad_id, dev)
    # snippet:begin train
    opt = torch.optim.AdamW(params, lr=lr, weight_decay=0.0)
    batches = finetune.token_batches(train, args.batch_tokens)
    steps = [batches[i : i + args.accum] for i in range(0, len(batches), args.accum)]
    start, peak = time.perf_counter(), 0
    for step, micro in enumerate(steps, 1):
        for group in opt.param_groups:
            group["lr"] = lr * finetune.cosine(step - 1, len(steps), warmup=50)
        tokens = sum(finetune.labelled(train, indices) for indices in micro)
        opt.zero_grad(set_to_none=True)
        loss = 0.0
        for indices in micro:
            ids, labels = finetune.pad(train, indices, pad_id, dev)
            logp, _ = finetune.token_logprobs(model, ids, labels)
            part = -logp.sum() / tokens
            peak = max(peak, device.allocated(dev))
            part.backward()
            peak = max(peak, device.allocated(dev))
            loss += part.item()
        opt.step()
        device.release(dev)
        if step % 200 == 0 or step == len(steps):
            print(
                f"step {step:5d}/{len(steps)}  loss {loss:.3f}  "
                f"{time.perf_counter() - start:5.0f} s",
                flush=True,
            )
    # snippet:end train
    after = finetune.evaluate(model, test, args.batch_tokens, pad_id, dev)
    seconds = time.perf_counter() - start
    print(
        f"held-out loss {before:.3f} -> {after:.3f}; {seconds / len(steps):.2f} s per step; peak memory "
        f"while training {peak / 2**30:.2f} GiB"
    )
    model.eval()
    for prompt, reply in zip(PROMPTS[:2], replies(model, tok, PROMPTS[:2])):
        print(f"user: {prompt}\n  assistant: {reply[:200]!r}")
    if not args.int4 and not args.full:
        lora.merge_lora(model)
        merged = finetune.evaluate(model, test, args.batch_tokens, pad_id, dev)
        print(f"after merging the adapters into the weights: held-out loss {merged:.3f}")
        check.close("merging changes nothing", merged, after, rtol=1e-3)
    check.expect(
        "fine-tuning lowered the held-out loss",
        after < before - 0.2,
        f"{before:.3f} -> {after:.3f}",
    )


if __name__ == "__main__":
    check.main(main)
