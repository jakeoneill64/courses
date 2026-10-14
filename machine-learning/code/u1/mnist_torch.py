import time

import numpy as np
import torch
import torch.nn.functional as F

from aif import check, device
from aif.tiny import Tensor, cross_entropy, nn, optim
from u1.common import batches, mnist_split


# snippet:begin twin
def torch_twin(model: nn.Sequential, dtype=torch.float64) -> torch.nn.Sequential:
    layers = []
    for layer in model.layers:
        if isinstance(layer, nn.Linear):
            linear = torch.nn.Linear(*layer.weight.shape, dtype=dtype)
            with torch.no_grad():
                linear.weight.copy_(torch.tensor(layer.weight.data.T))
                linear.bias.copy_(torch.tensor(layer.bias.data))
            layers.append(linear)
        else:
            layers.append(torch.nn.ReLU())
    return torch.nn.Sequential(*layers)


# snippet:end twin


def step_for_step(x: np.ndarray, y: np.ndarray, steps: int = 100) -> float:
    rng = np.random.default_rng(1)
    mine = nn.mlp([784, 256, 128, 10], rng)
    for p in mine.parameters():
        p.data = p.data.astype(np.float64)
    theirs = torch_twin(mine)
    opt_mine = optim.AdamW(mine.parameters(), lr=1e-3, weight_decay=0.01)
    opt_theirs = torch.optim.AdamW(theirs.parameters(), lr=1e-3, weight_decay=0.01)
    worst = 0.0
    # snippet:begin lockstep
    for _, idx in zip(range(steps), batches(len(x), 128, rng)):
        xb, yb = x[idx].astype(np.float64), y[idx]
        loss = cross_entropy(mine(Tensor(xb)), yb)
        opt_mine.zero_grad()
        loss.backward()
        opt_mine.step()
        ref = F.cross_entropy(theirs(torch.tensor(xb)), torch.tensor(yb))
        opt_theirs.zero_grad()
        ref.backward()
        opt_theirs.step()
        worst = max(worst, abs(loss.item() - ref.item()))
    # snippet:end lockstep
    check.expect("lockstep losses", worst < 1e-9, f"losses differ by {worst:.2e}")
    return worst


def train_on(dev: torch.device, data, epochs: int = 8) -> tuple[float, float]:
    (x, y), _, (x_test, y_test) = data
    torch.manual_seed(1)
    # snippet:begin pytorch
    model = torch.nn.Sequential(
        torch.nn.Linear(784, 256),
        torch.nn.ReLU(),
        torch.nn.Linear(256, 128),
        torch.nn.ReLU(),
        torch.nn.Linear(128, 10),
    ).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=0.01)
    xs, ys = torch.tensor(x, device=dev), torch.tensor(y, device=dev)
    rng = np.random.default_rng(1)
    start = time.perf_counter()
    for _ in range(epochs):
        for idx in batches(len(x), 128, rng):
            idx = torch.from_numpy(idx).to(dev)
            loss = F.cross_entropy(model(xs[idx]), ys[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
    device.sync(dev)
    seconds = (time.perf_counter() - start) / epochs
    with torch.no_grad():
        predictions = model(torch.tensor(x_test, device=dev)).argmax(1).cpu().numpy()
    # snippet:end pytorch
    return seconds, float((predictions == y_test).mean())


def main() -> None:
    data = mnist_split()
    (x, y), _, _ = data
    worst = step_for_step(x, y)
    print(
        f"tiny and PyTorch in lockstep for 100 steps (float64): largest loss difference {worst:.1e}"
    )
    for dev in dict.fromkeys([torch.device("cpu"), device.device()]):
        seconds, accuracy = train_on(dev, data)
        print(
            f"PyTorch on {dev.type}: {seconds:.2f} s per epoch, test accuracy {accuracy:.2%}"
        )
        check.expect(f"accuracy on {dev.type}", accuracy >= 0.975)


if __name__ == "__main__":
    check.main(main)
