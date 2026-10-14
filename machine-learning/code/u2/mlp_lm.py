import argparse
import json
import math
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from aif import check, data, device, results


# snippet:begin model
class MLPLanguageModel(nn.Module):
    def __init__(self, vocab: int, context: int, d_embed: int = 128, hidden: int = 1024):
        super().__init__()
        self.embed = nn.Embedding(vocab, d_embed)
        self.net = nn.Sequential(
            nn.Linear(context * d_embed, hidden),
            nn.LayerNorm(hidden),
            nn.ReLU(),
            nn.Linear(hidden, hidden),
            nn.LayerNorm(hidden),
            nn.ReLU(),
            nn.Linear(hidden, vocab),
        )

    def forward(self, ctx: torch.Tensor) -> torch.Tensor:
        return self.net(self.embed(ctx).flatten(1))


# snippet:end model


def windows(ids: np.ndarray, starts: np.ndarray, context: int) -> np.ndarray:
    return np.stack([ids[s : s + context + 1] for s in starts]).astype(np.int64)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--context", type=int, default=8)
    parser.add_argument("--steps", type=int, default=15000)
    parser.add_argument("--batch", type=int, default=2048)
    parser.add_argument("--valid-tokens", type=int, default=500_000)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    folder = data.DATA / "tinystories"
    stats = json.loads((folder / "stats-8192.json").read_text())
    bytes_per_token = stats["valid"]["bytes"] / stats["valid"]["tokens"]
    train = np.memmap(folder / "train-8192.bin", dtype=np.uint16, mode="r")
    valid = np.memmap(folder / "valid-8192.bin", dtype=np.uint16, mode="r")[
        : args.valid_tokens
    ]
    k = args.context
    model = MLPLanguageModel(8192, k).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=0.01)
    rng = np.random.default_rng(0)
    print(
        f"{sum(p.numel() for p in model.parameters()) / 1e6:.1f}M parameters, context of {k} tokens"
    )
    # snippet:begin train
    start = time.perf_counter()
    for step in range(1, args.steps + 1):
        for group in opt.param_groups:
            group["lr"] = 2e-3 * 0.5 * (1 + math.cos(math.pi * step / args.steps))
        rows = torch.from_numpy(
            windows(train, rng.integers(0, len(train) - k - 1, args.batch), k)
        ).to(dev)
        loss = F.cross_entropy(model(rows[:, :k]), rows[:, k])
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
        if step % 2000 == 0:
            print(
                f"step {step:5d}  training loss {loss.item():.3f}  "
                f"{time.perf_counter() - start:4.0f} s",
                flush=True,
            )
    # snippet:end train
    # snippet:begin valid
    model.eval()
    total = 0.0
    starts = np.arange(0, len(valid) - k - 1)
    with torch.no_grad():
        for chunk in np.array_split(starts, len(starts) // 4096):
            rows = torch.from_numpy(windows(valid, chunk, k)).to(dev)
            total += F.cross_entropy(model(rows[:, :k]), rows[:, k], reduction="sum").item()
    nats = total / len(starts)
    # snippet:end valid
    print(
        f"validation: {nats:.3f} nats per token, {nats / math.log(2) / bytes_per_token:.3f} bits per byte, "
        f"perplexity {math.exp(nats):.1f}"
    )
    results.save("u2-mlp-lm", {"nats": nats, "context": k})
    check.expect("the neural model learned", nats < 3.0, f"{nats:.3f}")


if __name__ == "__main__":
    check.main(main)
