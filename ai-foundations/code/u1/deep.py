import argparse
import math

import numpy as np
import torch
import torch.nn.functional as F

from aif import check, device, results
from u1.common import batches, mnist_split


# snippet:begin variants
class DeepNet(torch.nn.Module):
    def __init__(self, depth: int, width: int, kind: str):
        super().__init__()
        self.kind = kind
        self.stem = torch.nn.Linear(784, width)
        self.layers = torch.nn.ModuleList(torch.nn.Linear(width, width) for _ in range(depth))
        self.norms = torch.nn.ModuleList(torch.nn.LayerNorm(width) for _ in range(depth))
        self.head = torch.nn.Linear(width, 10)
        if kind != "plain, default init":
            for layer in self.layers:
                torch.nn.init.kaiming_normal_(layer.weight, nonlinearity="relu")
                torch.nn.init.zeros_(layer.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h = self.stem(x)
        for layer, norm in zip(self.layers, self.norms):
            if self.kind.startswith("plain"):
                h = F.relu(layer(h))
            elif self.kind == "post-norm":
                h = norm(h + layer(F.relu(h)))
            else:
                h = h + layer(F.relu(norm(h))) / math.sqrt(len(self.layers))
        return self.head(h)


# snippet:end variants


# snippet:begin grad-norms
def gradient_norms(model: DeepNet, x: torch.Tensor, y: torch.Tensor) -> list[float]:
    model.zero_grad()
    F.cross_entropy(model(x), y).backward()
    return [layer.weight.grad.norm().item() for layer in model.layers]


# snippet:end grad-norms

KINDS = ["plain, default init", "plain, He init", "post-norm", "pre-norm residual"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--depth", type=int, default=30)
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--warmup", type=int, default=0, help="steps of linear warm-up")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--kinds", nargs="+", choices=KINDS, default=KINDS)
    args = parser.parse_args()
    dev = device.device()
    (x, y), (x_val, y_val), _ = mnist_split()
    xs, ys = torch.tensor(x, device=dev), torch.tensor(y, device=dev)
    xv, yv = torch.tensor(x_val, device=dev), torch.tensor(y_val, device=dev)
    record = {}
    print(
        f"{args.depth} hidden layers of 256 units on MNIST, AdamW at lr {args.lr:g}, "
        f"{args.epochs} epochs, seed {args.seed}"
    )
    print(
        f"{'network':<22}{'grad norm, layer 1':>20}{'layer ' + str(args.depth):>10}"
        f"{'loss at 100':>13}{'val accuracy':>14}"
    )
    for kind in args.kinds:
        torch.manual_seed(args.seed)
        model = DeepNet(args.depth, 256, kind).to(dev)
        norms = gradient_norms(model, xs[:512], ys[:512])
        opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
        rng = np.random.default_rng(args.seed)
        losses = []
        for _ in range(args.epochs):
            for idx in batches(len(x), 128, rng):
                if len(losses) < args.warmup:
                    opt.param_groups[0]["lr"] = args.lr * (len(losses) + 1) / args.warmup
                idx = torch.from_numpy(idx).to(dev)
                loss = F.cross_entropy(model(xs[idx]), ys[idx])
                opt.zero_grad()
                loss.backward()
                opt.step()
                losses.append(loss.item())
        with torch.no_grad():
            acc = (model(xv).argmax(1) == yv).float().mean().item()
        record[kind] = {"grad_norms": norms, "losses": losses[::10], "accuracy": acc}
        print(
            f"{kind:<22}{norms[0]:20.2e}{norms[-1]:10.2e}{np.mean(losses[90:110]):13.3f}{acc:14.2%}"
        )
    if args.kinds != KINDS or (args.depth, args.lr, args.warmup, args.seed) != (
        30,
        1e-3,
        0,
        0,
    ):
        return
    results.save("u1-deep", record)
    check.expect(
        "the default plain network fails", record["plain, default init"]["accuracy"] < 0.5
    )
    check.expect(
        "the pre-norm residual network trains", record["pre-norm residual"]["accuracy"] > 0.95
    )


if __name__ == "__main__":
    check.main(main)
