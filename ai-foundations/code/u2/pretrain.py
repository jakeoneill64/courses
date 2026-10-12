import argparse
import json
import math
import time

import numpy as np
import torch

from aif import bpe, check, data, device, gpt, sample, train

PRESETS = {
    "tiny": dict(d_model=128, n_layers=4, n_heads=4, n_kv_heads=2),
    "small": dict(d_model=256, n_layers=6, n_heads=4, n_kv_heads=2),
    "base": dict(d_model=512, n_layers=8, n_heads=8, n_kv_heads=4),
}


def ffn_width(d_model: int) -> int:
    return 64 * math.ceil(8 * d_model / 3 / 64)


def kv_heads(heads: int) -> int:
    """Half the query heads where that divides them evenly, otherwise the largest divisor below."""
    return max([k for k in range(1, heads // 2 + 1) if heads % k == 0], default=1)


def arguments() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Pretrain a GPT on TinyStories.")
    p.add_argument("--name", default="tinystories-28m")
    p.add_argument("--preset", choices=PRESETS, default="base")
    p.add_argument("--d-model", type=int)
    p.add_argument("--layers", type=int)
    p.add_argument("--kv-heads", type=int)
    p.add_argument("--head-dim", type=int, default=64)
    p.add_argument("--vocab", type=int, default=8192)
    p.add_argument("--seq", type=int, default=512)
    p.add_argument("--batch", type=int, default=32)
    p.add_argument("--accum", type=int, default=1)
    p.add_argument("--tokens", type=float, default=300e6)
    p.add_argument("--lr", type=float, default=2e-3)
    p.add_argument("--warmup", type=int, default=500)
    p.add_argument("--wd", type=float, default=0.1)
    p.add_argument("--beta2", type=float, default=0.95)
    p.add_argument("--clip", type=float, default=1.0, help="0 turns clipping off")
    p.add_argument("--dtype", choices=["fp32", "fp16", "bf16"], default="fp32")
    p.add_argument("--no-compile", action="store_true")
    p.add_argument("--eval-every", type=int, default=500)
    p.add_argument("--eval-windows", type=int, default=64)
    p.add_argument("--ckpt-every", type=int, default=2000)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--seed", type=int, default=1)
    return p.parse_args()


def main() -> None:
    args = arguments()
    dev = device.device()
    device.seed(args.seed)
    folder = data.DATA / "tinystories"
    tok = bpe.BPE.load(folder / f"bpe{args.vocab}.json")
    stats = json.loads((folder / f"stats-{args.vocab}.json").read_text())
    bytes_per_token = stats["valid"]["bytes"] / stats["valid"]["tokens"]
    run = data.RUNS / args.name

    # snippet:begin setup
    shape = dict(PRESETS[args.preset])
    if args.d_model:
        heads = args.d_model // args.head_dim
        shape.update(d_model=args.d_model, n_heads=heads, n_kv_heads=kv_heads(heads))
    if args.layers:
        shape["n_layers"] = args.layers
    if args.kv_heads:
        shape["n_kv_heads"] = args.kv_heads
    config = gpt.Config(
        vocab_size=tok.vocab_size, max_seq=args.seq, d_ff=ffn_width(shape["d_model"]), **shape
    )
    model = gpt.GPT(config).to(dev)
    step_model = model if args.no_compile else torch.compile(model)
    optimizer = torch.optim.AdamW(
        train.param_groups(model, args.wd), lr=args.lr, betas=(0.9, args.beta2)
    )
    dtype = {"fp32": None, "fp16": torch.float16, "bf16": torch.bfloat16}[args.dtype]
    scaler = torch.amp.GradScaler(dev.type, enabled=args.dtype == "fp16")
    tokens_per_step = args.batch * args.accum * args.seq
    total_steps = int(args.tokens // tokens_per_step)
    # snippet:end setup

    train_ids = train.TokenFile(folder / f"train-{args.vocab}.bin", args.seq)
    valid = train.TokenFile(folder / f"valid-{args.vocab}.bin", args.seq).fixed(
        args.eval_windows, dev
    )
    rng = np.random.default_rng(args.seed)
    step = 0
    if args.resume and (run / "last.pt").exists():
        state = torch.load(run / "last.pt", map_location="cpu", weights_only=False)
        model.load_state_dict(state["model"])
        optimizer.load_state_dict(state["optimizer"])
        rng.bit_generator.state = state["rng"]
        step = state["step"]
        print(f"resumed at step {step}")
    log = train.Log(run / "log.jsonl", resume=args.resume)
    params = gpt.param_count(config)
    flops = gpt.train_flops_per_token(config, args.seq)
    print(
        f"{params / 1e6:.1f}M parameters, {flops / 1e6:.0f} MFLOP per token, "
        f"{total_steps} steps of {tokens_per_step} tokens"
    )
    log.write(
        event="start", params=params, flops_per_token=flops, steps=total_steps, args=vars(args)
    )

    # snippet:begin loop
    eot = tok.special["<|endoftext|>"]
    started, seen = time.perf_counter(), 0
    while step < total_steps:
        lr = train.lr_at(step, total_steps, args.lr, args.warmup)
        for group in optimizer.param_groups:
            group["lr"] = lr
        total = 0.0
        for _ in range(args.accum):
            x, y = train_ids.batch(args.batch, rng, dev)
            with torch.autocast(dev.type, dtype=dtype, enabled=dtype is not None):
                _, loss = step_model(x, y)
            scaler.scale(loss / args.accum).backward()
            total += loss.item() / args.accum
        scaler.unscale_(optimizer)
        norm = torch.nn.utils.clip_grad_norm_(model.parameters(), args.clip or float("inf"))
        scaler.step(optimizer)
        scaler.update()
        optimizer.zero_grad(set_to_none=True)
        step += 1
        seen += tokens_per_step
        # snippet:end loop
        if step % 50 == 0:
            rate = seen / (time.perf_counter() - started)
            log.write(
                step=step,
                tokens=step * tokens_per_step,
                loss=round(total, 4),
                lr=lr,
                grad_norm=round(float(norm), 4),
                tokens_per_s=round(rate),
            )
        if step % args.eval_every == 0 or step == total_steps:
            val = train.evaluate(model, valid, dtype)
            story = sample.generate(
                model,
                [eot],
                120,
                stop=eot,
                temperature=0.8,
                generator=torch.Generator(dev).manual_seed(0),
            )
            log.write(
                step=step,
                tokens=step * tokens_per_step,
                val_loss=round(val, 4),
                val_bpb=round(val / math.log(2) / bytes_per_token, 4),
                sample=tok.decode(story),
            )
            rate = seen / (time.perf_counter() - started)
            print(
                f"step {step:6d}  train {total:.3f}  val {val:.3f} "
                f"({val / math.log(2) / bytes_per_token:.3f} bits/byte)  {rate:,.0f} tokens/s",
                flush=True,
            )
        if step % args.ckpt_every == 0 or step == total_steps:
            torch.save(
                {
                    "model": model.state_dict(),
                    "optimizer": optimizer.state_dict(),
                    "rng": rng.bit_generator.state,
                    "step": step,
                },
                run / "last.pt",
            )
    gpt.save(model, run / "model.pt", tokenizer=f"tinystories/bpe{args.vocab}.json")
    check.expect(
        "the model learned",
        val < 0.5 * math.log(config.vocab_size),
        f"final validation loss {val:.3f}",
    )


if __name__ == "__main__":
    check.main(main)
