import argparse

import numpy as np
import torch

from aif import check, device, results
from aif.timing import median_time


# snippet:begin loops
def matmul_loops(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    n, k, m = len(a), len(b), len(b[0])
    c = [[0.0] * m for _ in range(n)]
    for i in range(n):
        for j in range(m):
            total = 0.0
            for p in range(k):
                total += a[i][p] * b[p][j]
            c[i][j] = total
    return c


# snippet:end loops


# snippet:begin outer
def matmul_outer(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    c = np.zeros((a.shape[0], b.shape[1]), dtype=a.dtype)
    for p in range(a.shape[1]):
        c += np.outer(a[:, p], b[p])
    return c


# snippet:end outer


def report(method: str, n: int, seconds: float) -> float:
    rate = 2 * n**3 / seconds / 1e9
    print(f"{method:<26} n={n:<5} {seconds * 1e3:11.3f} ms {rate:9.1f} GFLOP/s")
    return rate


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sizes", type=int, nargs="+", default=[64, 128, 256, 512, 1024, 2048, 4096]
    )
    args = parser.parse_args()
    rng = np.random.default_rng(0)
    dev = device.device()
    rates = {}
    # snippet:begin ladder
    for n in args.sizes:
        a = rng.random((n, n), dtype=np.float32)
        b = rng.random((n, n), dtype=np.float32)
        want = a.astype(np.float64) @ b.astype(np.float64)
        if n <= 128:
            got = np.array(matmul_loops(a.tolist(), b.tolist()))
            check.close("loops", got, want, rtol=1e-4)
            rates["Python loops", n] = report(
                "Python loops",
                n,
                median_time(lambda: matmul_loops(a.tolist(), b.tolist()), runs=1, warmup=0),
            )
        if n <= 2048:
            check.close("outer products", matmul_outer(a, b), want, rtol=1e-4)
            rates["NumPy outer products", n] = report(
                "NumPy outer products",
                n,
                median_time(lambda: matmul_outer(a, b), runs=3, warmup=1),
            )
        check.close("BLAS", a @ b, want, rtol=1e-4)
        rates["NumPy a @ b (BLAS)", n] = report(
            "NumPy a @ b (BLAS)", n, median_time(lambda: a @ b)
        )
        ta, tb = torch.from_numpy(a).to(dev), torch.from_numpy(b).to(dev)
        check.close(f"PyTorch on {dev.type}", (ta @ tb).cpu().numpy(), want, rtol=1e-3)
        rates[f"PyTorch on {dev.type}", n] = report(
            f"PyTorch on {dev.type}", n, median_time(lambda: ta @ tb, runs=20, dev=dev)
        )
    # snippet:end ladder
    results.save(
        "u1-matmul", [{"method": k[0], "n": k[1], "gflops": v} for k, v in rates.items()]
    )


if __name__ == "__main__":
    check.main(main)
