import numpy as np

from aif import check, results


# snippet:begin depth
def activation_scales(
    std_fn, activation, depth: int = 30, width: int = 512, seed: int = 0
) -> list[float]:
    rng = np.random.default_rng(seed)
    h = rng.normal(size=(1000, width))
    scales = []
    for _ in range(depth):
        w = rng.normal(0.0, std_fn(width), (width, width))
        h = activation(h @ w)
        scales.append(float(h.std()))
    return scales


# snippet:end depth


def main() -> None:
    relu = lambda z: np.maximum(z, 0)
    # snippet:begin schemes
    schemes = {
        "std 0.01, ReLU": (lambda n: 0.01, relu),
        "std 0.1, ReLU": (lambda n: 0.1, relu),
        "Xavier 1/sqrt(n), ReLU": (lambda n: np.sqrt(1 / n), relu),
        "He sqrt(2/n), ReLU": (lambda n: np.sqrt(2 / n), relu),
        "Xavier 1/sqrt(n), tanh": (lambda n: np.sqrt(1 / n), np.tanh),
    }
    # snippet:end schemes
    curves = {}
    print(f"{'initialisation':<26}{'layer 1':>12}{'layer 10':>12}{'layer 30':>12}")
    for name, (std_fn, act) in schemes.items():
        with np.errstate(over="ignore", invalid="ignore"):
            s = activation_scales(std_fn, act)
        curves[name] = s
        print(f"{name:<26}" + "".join(f"{s[i]:12.3g}" for i in (0, 9, 29)))
    results.save("u1-init", curves)
    he = curves["He sqrt(2/n), ReLU"]
    check.expect(
        "He keeps the scale", 0.3 < he[-1] / he[0] < 3, f"{he[0]:.3g} -> {he[-1]:.3g}"
    )


if __name__ == "__main__":
    check.main(main)
