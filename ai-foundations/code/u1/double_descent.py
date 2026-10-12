import numpy as np

from aif import check, results
from u1.common import mnist_split


# snippet:begin features
def random_features(x: np.ndarray, w: np.ndarray) -> np.ndarray:
    return np.maximum(x @ w, 0) / np.sqrt(w.shape[1])


def fit_min_norm(phi: np.ndarray, targets: np.ndarray) -> np.ndarray:
    return np.linalg.pinv(phi, rcond=1e-10) @ targets


# snippet:end features


def main() -> None:
    (x, y), _, (x_test, y_test) = mnist_split(dtype=np.float64)
    rng = np.random.default_rng(0)
    n = 400
    x, y = x[:n], y[:n]
    # snippet:begin noise
    noisy = y.copy()
    flip = rng.random(n) < 0.2
    noisy[flip] = rng.integers(0, 10, flip.sum())
    targets = np.eye(10)[noisy]
    # snippet:end noise
    x_test, y_test = x_test[:5000], y_test[:5000]
    widths = [
        20,
        50,
        100,
        200,
        300,
        350,
        380,
        400,
        420,
        450,
        500,
        600,
        800,
        1200,
        2000,
        4000,
        8000,
    ]
    rows = []
    print(
        f"{n} training images, 20% of labels randomised; min-norm least squares on random ReLU features"
    )
    print(
        f"{'features':>9}{'train error':>13}{'test error':>12}{'test MSE':>10}{'weight norm':>13}"
    )
    # snippet:begin sweep
    for p in widths:
        errors, mses, norms, train_errs = [], [], [], []
        for trial in range(3):
            w = np.random.default_rng(trial).normal(size=(784, p))
            beta = fit_min_norm(random_features(x, w), targets)
            out = random_features(x_test, w) @ beta
            errors.append((out.argmax(1) != y_test).mean())
            mses.append(((out - np.eye(10)[y_test]) ** 2).sum(1).mean())
            norms.append(np.linalg.norm(beta))
            train_errs.append((random_features(x, w) @ beta).argmax(1).__ne__(noisy).mean())
        rows.append(
            (
                p,
                float(np.mean(train_errs)),
                float(np.mean(errors)),
                float(np.mean(mses)),
                float(np.mean(norms)),
            )
        )
        print(
            f"{p:9d}{rows[-1][1]:13.1%}{rows[-1][2]:12.1%}"
            f"{rows[-1][3]:10.2f}{rows[-1][4]:13.1f}"
        )
    # snippet:end sweep
    results.save("u1-double-descent", {"n": n, "rows": rows})
    peak = max(rows, key=lambda r: r[3])
    check.expect(
        "the error peaks near the interpolation threshold",
        300 <= peak[0] <= 500,
        f"peak at {peak[0]}",
    )
    check.expect("wide models recover", rows[-1][3] < peak[3] / 2)


if __name__ == "__main__":
    check.main(main)
