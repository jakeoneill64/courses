import math

import numpy as np

from aif import check
from aif.tiny import Tensor, optim


def main() -> None:
    rng = np.random.default_rng(0)
    # snippet:begin data
    n, true_w, true_b, sigma = 200, np.array([2.0, -1.0, 0.5]), 0.3, 0.5
    x = rng.normal(size=(n, 3))
    y = (x @ true_w + true_b + rng.normal(scale=sigma, size=n))[:, None]
    # snippet:end data

    # snippet:begin closed-form
    design = np.hstack([x, np.ones((n, 1))])
    solution = np.linalg.lstsq(design, y, rcond=None)[0].ravel()
    # snippet:end closed-form

    # snippet:begin descent
    w = Tensor(np.zeros((3, 1)), requires_grad=True)
    b = Tensor(np.zeros(1), requires_grad=True)
    opt = optim.SGD([w, b], lr=0.1)
    for _ in range(500):
        residual = Tensor(x) @ w + b - Tensor(y)
        loss = (residual * residual).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
    # snippet:end descent

    # snippet:begin likelihood
    w2 = Tensor(np.zeros((3, 1)), requires_grad=True)
    b2 = Tensor(np.zeros(1), requires_grad=True)
    log_sigma = Tensor(np.zeros(1), requires_grad=True)
    opt = optim.Adam([w2, b2, log_sigma], lr=0.05)
    for _ in range(2000):
        residual = Tensor(x) @ w2 + b2 - Tensor(y)
        var = (log_sigma * 2.0).exp()
        nll = (
            (residual * residual / (var * 2.0)).mean()
            + log_sigma.mean()
            + 0.5 * math.log(2 * math.pi)
        )
        opt.zero_grad()
        nll.backward()
        opt.step()
    # snippet:end likelihood

    fitted = np.append(w.data.ravel(), b.data)
    mle = np.append(w2.data.ravel(), b2.data)
    rows = [
        ("true", np.append(true_w, true_b)),
        ("least squares", solution),
        ("gradient descent on MSE", fitted),
        ("maximum likelihood", mle),
    ]
    print(f"{'':<26}{'w1':>8}{'w2':>8}{'w3':>8}{'b':>8}")
    for name, values in rows:
        print(f"{name:<26}" + "".join(f"{v:8.4f}" for v in values))
    residual_rms = math.sqrt(np.mean((design @ solution - y.ravel()) ** 2))
    print(
        f"noise: true sigma {sigma}, learned sigma {math.exp(log_sigma.item()):.5f}, "
        f"RMS residual {residual_rms:.5f}"
    )
    check.close("descent reaches least squares", fitted, solution, rtol=1e-4)
    check.close("likelihood reaches least squares", mle, solution, rtol=1e-3)
    check.close(
        "sigma is the RMS residual", math.exp(log_sigma.item()), residual_rms, rtol=1e-3
    )


if __name__ == "__main__":
    check.main(main)
