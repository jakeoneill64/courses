import argparse
import math
import time

import numpy as np
import torch

from aif import check, data, device, gpt, results, train


# snippet:begin measure
def tokens_per_second(
    dev, dtype, compiled: bool, batch: int, steps: int
) -> tuple[float, float]:
    device.seed(0)
    model = gpt.GPT(gpt.Config()).to(dev)
    step_model = torch.compile(model) if compiled else model
    opt = torch.optim.AdamW(train.param_groups(model, 0.1), lr=1e-3, betas=(0.9, 0.95))
    scaler = torch.amp.GradScaler(dev.type, enabled=dtype == torch.float16)
    tokens = train.TokenFile(data.DATA / "tinystories" / "train-8192.bin", 512)
    rng = np.random.default_rng(0)
    times = []
    for _ in range(steps + 5):
        x, y = tokens.batch(batch, rng, dev)
        start = time.perf_counter()
        with torch.autocast(dev.type, dtype=dtype, enabled=dtype is not None):
            _, loss = step_model(x, y)
        scaler.scale(loss).backward()
        scaler.unscale_(opt)
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        scaler.step(opt)
        scaler.update()
        opt.zero_grad(set_to_none=True)
        device.sync(dev)
        times.append(time.perf_counter() - start)
    return batch * 512 / float(np.median(times[5:])), loss.item()


# snippet:end measure


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", type=int, default=32)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--peak", type=float, default=6.8, help="the GPU's float32 TFLOP/s")
    args = parser.parse_args()
    dev = device.device()
    flops = gpt.train_flops_per_token(gpt.Config(), 512)
    print(f"Chapter 2.5's model, batch {args.batch} x 512 tokens, on {dev.type}:")
    print(f"{'precision':<10}{'mode':<10}{'tokens/s':>10}{'TFLOP/s':>9}{'of peak':>9}")
    rows = []
    for name, dtype, compiled in (
        ("float32", None, False),
        ("float32", None, True),
        ("float16", torch.float16, True),
        ("bfloat16", torch.bfloat16, True),
    ):
        rate, loss = tokens_per_second(dev, dtype, compiled, args.batch, args.steps)
        achieved = rate * flops / 1e12
        mode = "compiled" if compiled else "eager"
        print(f"{name:<10}{mode:<10}{rate:10,.0f}{achieved:9.2f}{achieved / args.peak:9.0%}")
        rows.append({"dtype": name, "compiled": compiled, "tokens_per_s": rate, "loss": loss})
        check.expect(
            f"{name} {mode} trains", math.isfinite(loss) and loss < 9.0, f"loss {loss}"
        )
    results.save("u2-throughput", rows)


if __name__ == "__main__":
    check.main(main)
