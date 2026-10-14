import argparse
import math

import numpy as np

from aif import check, results
from aif.tiny import Tensor, cross_entropy, nn, optim
from u1.common import batches, mnist_split


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    (x, y), _, _ = mnist_split()
    rng = np.random.default_rng(args.seed)
    model = nn.mlp([784, 256, 128, 10], rng)
    opt = optim.AdamW(model.parameters(), lr=1e-6, weight_decay=0.01)
    # snippet:begin range-test
    low, high, steps = 1e-6, 1.0, 300
    record, smooth = [], None
    order = (idx for _ in range(10) for idx in batches(len(x), 128, rng))
    for step in range(steps):
        opt.lr = low * (high / low) ** (step / (steps - 1))
        idx = next(order)
        loss = cross_entropy(model(Tensor(x[idx])), y[idx])
        opt.zero_grad()
        loss.backward()
        opt.step()
        smooth = loss.item() if smooth is None else 0.9 * smooth + 0.1 * loss.item()
        record.append((opt.lr, smooth))
        if not math.isfinite(smooth) or smooth > 1.5 * record[0][1]:
            break
    # snippet:end range-test
    lrs, losses = map(np.array, zip(*record))
    best = lrs[np.argmin(losses)]
    worse = lrs[np.argmax((losses > losses[0]) & (lrs > best))]
    print(
        f"lowest smoothed loss {losses.min():.3f} at lr {best:.1e}; loss back above its start at lr "
        f"{worse:.1e}; stopped at lr {lrs[-1]:.1e}"
    )
    print(f"suggested learning rate: about {best / 10:.0e}, a tenth of the minimum's")
    results.save("u1-lr-range", {"lr": lrs.tolist(), "loss": losses.tolist()})
    check.expect("the test found a minimum", 1e-4 < best < 0.5, f"{best:.1e}")


if __name__ == "__main__":
    check.main(main)
