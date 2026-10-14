import numpy as np
import torch

from aif import check
from aif.tiny import Tensor, cross_entropy, optim


def run_tiny(make, x, y, w0, steps):
    w = Tensor(w0.copy(), requires_grad=True)
    opt = make([w])
    for _ in range(steps):
        opt.zero_grad()
        cross_entropy(Tensor(x) @ w, y).backward()
        opt.step()
    return w.data


def run_torch(make, x, y, w0, steps):
    w = torch.tensor(w0.copy(), requires_grad=True)
    opt = make([w])
    for _ in range(steps):
        opt.zero_grad()
        torch.nn.functional.cross_entropy(torch.tensor(x) @ w, torch.tensor(y)).backward()
        opt.step()
    return w.detach().numpy()


def main() -> None:
    rng = np.random.default_rng(0)
    x = rng.normal(size=(64, 10))
    y = rng.integers(0, 3, 64)
    w0 = rng.normal(size=(10, 3)) * 0.1
    # snippet:begin pairs
    pairs = {
        "SGD": (lambda p: optim.SGD(p, 0.1), lambda p: torch.optim.SGD(p, 0.1)),
        "SGD, momentum 0.9": (
            lambda p: optim.SGD(p, 0.1, momentum=0.9),
            lambda p: torch.optim.SGD(p, 0.1, momentum=0.9),
        ),
        "SGD, Nesterov": (
            lambda p: optim.SGD(p, 0.1, momentum=0.9, nesterov=True),
            lambda p: torch.optim.SGD(p, 0.1, momentum=0.9, nesterov=True),
        ),
        "RMSProp": (lambda p: optim.RMSProp(p, 0.01), lambda p: torch.optim.RMSprop(p, 0.01)),
        "Adam, L2 0.1": (
            lambda p: optim.Adam(p, 0.01, weight_decay=0.1),
            lambda p: torch.optim.Adam(p, 0.01, weight_decay=0.1),
        ),
        "AdamW, decay 0.1": (
            lambda p: optim.AdamW(p, 0.01, weight_decay=0.1),
            lambda p: torch.optim.AdamW(p, 0.01, weight_decay=0.1),
        ),
    }
    # snippet:end pairs
    print(f"{'optimiser':<20} {'max |w_tiny - w_torch| after 50 steps':>40}")
    for name, (mine, theirs) in pairs.items():
        a = run_tiny(mine, x, y, w0, 50)
        b = run_torch(theirs, x, y, w0, 50)
        diff = check.close(name, a, b, rtol=1e-9, atol=1e-12)
        print(f"{name:<20} {diff:>40.1e}")


if __name__ == "__main__":
    check.main(main)
