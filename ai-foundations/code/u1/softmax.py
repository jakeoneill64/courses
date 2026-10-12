import numpy as np

from aif import check


# snippet:begin naive
def softmax_naive(z: np.ndarray) -> np.ndarray:
    e = np.exp(z)
    return e / e.sum(axis=-1, keepdims=True)


# snippet:end naive


# snippet:begin stable
def softmax(z: np.ndarray) -> np.ndarray:
    e = np.exp(z - z.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)


def logsumexp(z: np.ndarray) -> np.ndarray:
    m = z.max(axis=-1, keepdims=True)
    return (m + np.log(np.exp(z - m).sum(axis=-1, keepdims=True))).squeeze(-1)


def cross_entropy(z: np.ndarray, target: int) -> float:
    return float(logsumexp(z) - z[target])


# snippet:end stable


def main() -> None:
    z = np.array([1000.0, 1001.0, 1002.0], dtype=np.float32)
    with np.errstate(over="ignore", invalid="ignore"):
        print("naive softmax of [1000, 1001, 1002]: ", softmax_naive(z))
    print("stable softmax of [1000, 1001, 1002]:", softmax(z))
    check.close("shift invariance", softmax(z), softmax(z - 1000.0))

    far = np.array([0.0, -120.0], dtype=np.float32)
    with np.errstate(divide="ignore"):
        print("log of naive softmax of [0, -120]:   ", np.log(softmax_naive(far)))
    print("log-softmax via logsumexp:           ", far - logsumexp(far))

    # snippet:begin gradient
    rng = np.random.default_rng(0)
    z = rng.normal(size=5)
    target = 2
    analytic = softmax(z) - np.eye(5)[target]
    h = 1e-6
    numeric = np.array(
        [
            (cross_entropy(z + h * e, target) - cross_entropy(z - h * e, target)) / (2 * h)
            for e in np.eye(5)
        ]
    )
    # snippet:end gradient
    err = check.close("dCE/dz", analytic, numeric, rtol=1e-6, atol=1e-9)
    print(f"gradient of cross-entropy = softmax - one-hot: largest error {err:.1e}")


if __name__ == "__main__":
    check.main(main)
