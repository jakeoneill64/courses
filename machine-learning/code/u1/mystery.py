import argparse

import numpy as np
import torch
import torch.nn.functional as F

from aif import check
from u1.common import batches, mnist_split

# Each case plants one bug. Diagnose it from the output before reading run().
CASES = {"A": 3, "B": 1, "C": 2, "clean": 0}


def run(bug: int, steps: int = 600) -> None:
    (x, y), (x_val, y_val), _ = mnist_split()
    rng = np.random.default_rng(0)
    torch.manual_seed(0)
    if bug == 1:
        y = rng.permutation(y)
    model = torch.nn.Sequential(
        torch.nn.Linear(784, 256),
        torch.nn.ReLU(),
        torch.nn.Linear(256, 128),
        torch.nn.ReLU(),
        torch.nn.Linear(128, 10),
    )
    opt = torch.optim.SGD(model.parameters(), lr=0.05, momentum=0.9)
    xs, ys = torch.tensor(x), torch.tensor(y)
    order = (idx for _ in range(10) for idx in batches(len(x), 128, rng))
    print(f"{'step':>5}{'loss':>9}{'batch acc':>11}{'grad norm':>11}{'|logits| max':>14}")
    for step in range(steps + 1):
        idx = torch.from_numpy(next(order))
        logits = model(xs[idx])
        out = logits.softmax(-1) if bug == 2 else logits
        loss = F.cross_entropy(out, ys[idx])
        if bug != 3:
            opt.zero_grad()
        loss.backward()
        norm = torch.nn.utils.clip_grad_norm_(model.parameters(), float("inf"))
        opt.step()
        if step in (0, 25, 50, 100, 200, 400, 600):
            acc = (logits.argmax(1) == ys[idx]).float().mean().item()
            print(
                f"{step:5d}{loss.item():9.3f}{acc:11.1%}{norm.item():11.3g}{logits.abs().max().item():14.3g}"
            )
    with torch.no_grad():
        val = (
            (model(torch.tensor(x_val)).argmax(1) == torch.tensor(y_val)).float().mean().item()
        )
    print(f"validation accuracy {val:.2%}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", choices=CASES, default="clean")
    run(CASES[parser.parse_args().case])


if __name__ == "__main__":
    check.main(main)
