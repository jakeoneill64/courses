from itertools import zip_longest

import numpy as np

from aif import check
from aif.timing import median_time


# snippet:begin rule
def broadcast_shape(a: tuple, b: tuple) -> tuple:
    out = []
    for x, y in zip_longest(reversed(a), reversed(b), fillvalue=1):
        if x != y and 1 not in (x, y):
            raise ValueError(f"cannot broadcast {a} with {b}")
        out.append(y if x == 1 else x)
    return tuple(reversed(out))


# snippet:end rule


# snippet:begin distances
def distances_loops(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    out = np.empty((len(x), len(y)), dtype=x.dtype)
    for i in range(len(x)):
        for j in range(len(y)):
            out[i, j] = np.sum((x[i] - y[j]) ** 2)
    return out


def distances_broadcast(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    return ((x[:, None, :] - y[None, :, :]) ** 2).sum(axis=-1)


def distances_matmul(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    return (x * x).sum(1)[:, None] + (y * y).sum(1)[None, :] - 2 * x @ y.T


# snippet:end distances


def main() -> None:
    cases = [
        ((3, 4), (4,)),
        ((3, 1), (1, 4)),
        ((2, 3, 4), (3, 1)),
        ((8, 1, 6, 1), (7, 1, 5)),
        ((3, 4), (3,)),
        ((2, 1), (8, 4, 3)),
    ]
    for a, b in cases:
        try:
            mine = broadcast_shape(a, b)
        except ValueError:
            mine = "error"
        try:
            ref = np.broadcast_shapes(a, b)
        except ValueError:
            ref = "error"
        check.expect(f"{a} with {b}", mine == ref, f"{mine} != {ref}")
        print(f"{str(a):>14} with {str(b):<10} -> {mine}")

    rng = np.random.default_rng(0)
    x = rng.normal(size=(1000, 64)).astype(np.float32)
    y = rng.normal(size=(1000, 64)).astype(np.float32)
    want = distances_loops(x[:50], y[:50])
    for name, fn in (("broadcast", distances_broadcast), ("matmul", distances_matmul)):
        check.close(name, fn(x[:50], y[:50]), want, rtol=1e-3, atol=1e-3)
    loops = median_time(lambda: distances_loops(x[:100], y[:100]), runs=1, warmup=0) * 100
    print("1000 x 1000 squared distances, 64 dimensions:")
    print(f"  Python loops (estimated from 100 x 100)  {loops * 1e3:8.0f} ms")
    for name, fn, temp in (
        ("broadcasting", distances_broadcast, x.nbytes * len(y)),
        ("|x|^2 + |y|^2 - 2 x.y", distances_matmul, 0),
    ):
        seconds = median_time(lambda: fn(x, y), runs=5)
        extra = f", {temp / 2**20:.0f} MiB temporary" if temp else ""
        print(f"  {name:<40} {seconds * 1e3:8.1f} ms{extra}")


if __name__ == "__main__":
    check.main(main)
