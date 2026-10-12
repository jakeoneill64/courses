import math

import numpy as np

from aif import check, results
from aif.tiny import Tensor, optim

# snippet:begin valley
ANGLE = math.radians(30)
R = np.array([[math.cos(ANGLE), -math.sin(ANGLE)], [math.sin(ANGLE), math.cos(ANGLE)]])
H = R @ np.diag([1.0, 50.0]) @ R.T


def loss(v: Tensor) -> Tensor:
    return 0.5 * (v @ Tensor(H) * v).sum()


# snippet:end valley


def run(make, start=(-4.3, -1.5), tol: float = 1e-8, limit: int = 2000):
    v = Tensor(np.array([list(start)]), requires_grad=True)
    opt = make([v])
    path = [v.data[0].tolist()]
    for step in range(1, limit + 1):
        f = loss(v)
        opt.zero_grad()
        f.backward()
        opt.step()
        path.append(v.data[0].tolist())
        if loss(v).item() < tol:
            return step, path
    return None, path


def main() -> None:
    lam_min, lam_max = 1.0, 50.0
    kappa = lam_max / lam_min
    # snippet:begin tuned
    gd_lr = 2 / (lam_min + lam_max)
    hb_lr = 4 / (math.sqrt(lam_max) + math.sqrt(lam_min)) ** 2
    hb_mu = ((math.sqrt(kappa) - 1) / (math.sqrt(kappa) + 1)) ** 2
    contenders = {
        "gradient descent, lr 0.039": lambda p: optim.SGD(p, gd_lr),
        f"momentum, lr {hb_lr:.3f}, mu {hb_mu:.2f}": lambda p: optim.SGD(
            p, hb_lr, momentum=hb_mu
        ),
        "RMSProp, lr 0.01": lambda p: optim.RMSProp(p, 0.01),
        "Adam, lr 0.1": lambda p: optim.Adam(p, 0.1),
    }
    # snippet:end tuned
    print(f"quadratic valley with condition number {kappa:.0f}, rotated 30 degrees")
    paths = {}
    for name, make in contenders.items():
        steps, path = run(make)
        paths[name] = path[:400]
        print(
            f"  {name:<30} {'did not converge' if steps is None else f'{steps:5d} steps to loss < 1e-8'}"
        )
        if name.startswith("momentum"):
            check.expect("momentum converges", steps is not None and steps < 120)
    results.save("u1-valley", {"H": H.tolist(), "paths": paths})


if __name__ == "__main__":
    check.main(main)
