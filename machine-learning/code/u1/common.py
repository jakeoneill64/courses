import numpy as np

from aif import data


# snippet:begin split
def mnist_split(seed: int = 0, dtype=np.float32, validation: int = 5000):
    d = data.mnist()

    def prepare(images):
        x = images.reshape(len(images), -1).astype(dtype) / 255
        return (x - dtype(0.1307)) / dtype(0.3081)

    x, y = prepare(d["x_train"]), d["y_train"]
    order = np.random.default_rng(seed).permutation(len(x))
    val, train = order[:validation], order[validation:]
    return (x[train], y[train]), (x[val], y[val]), (prepare(d["x_test"]), d["y_test"])


# snippet:end split


def batches(n: int, size: int, rng: np.random.Generator):
    order = rng.permutation(n)
    for i in range(0, n, size):
        yield order[i : i + size]
