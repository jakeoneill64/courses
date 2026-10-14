import argparse
import time

import numpy as np

from aif import check
from aif.tiny import Tensor, cross_entropy, nn, no_grad, optim
from u1.common import batches, mnist_split


def accuracy(model, x: np.ndarray, y: np.ndarray) -> float:
    model.eval()
    with no_grad():
        predictions = model(Tensor(x)).data.argmax(axis=1)
    model.train()
    return float((predictions == y).mean())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--batch", type=int, default=128)
    args = parser.parse_args()

    (x, y), (x_val, y_val), (x_test, y_test) = mnist_split()
    rng = np.random.default_rng(1)
    # snippet:begin train
    model = nn.mlp([784, 256, 128, 10], rng)
    opt = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    for epoch in range(1, args.epochs + 1):
        start, total, count = time.perf_counter(), 0.0, 0
        for idx in batches(len(x), args.batch, rng):
            loss = cross_entropy(model(Tensor(x[idx])), y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
            total, count = total + loss.item() * len(idx), count + len(idx)
        print(
            f"epoch {epoch}  loss {total / count:.4f}  validation accuracy "
            f"{accuracy(model, x_val, y_val):.2%}  {time.perf_counter() - start:.1f} s"
        )
    # snippet:end train
    test = accuracy(model, x_test, y_test)
    params = sum(p.data.size for p in model.parameters())
    print(f"test accuracy {test:.2%} with {params:,} parameters")
    check.expect("test accuracy", test >= 0.975, f"{test:.2%} is below 97.5%")


if __name__ == "__main__":
    check.main(main)
