import sys

import numpy as np


class CheckFailed(Exception):
    pass


def close(name: str, got, want, rtol: float = 1e-5, atol: float = 1e-8) -> float:
    got = np.asarray(got, dtype=np.float64)
    want = np.asarray(want, dtype=np.float64)
    if got.shape != want.shape:
        raise CheckFailed(f"{name}: shape {got.shape}, expected {want.shape}")
    err = np.abs(got - want)
    worst = float(np.max(err / (atol + rtol * np.abs(want)))) if err.size else 0.0
    if worst > 1.0:
        raise CheckFailed(
            f"{name}: max error {float(err.max()):.3g} exceeds rtol={rtol:g}, atol={atol:g}"
        )
    return float(err.max()) if err.size else 0.0


def expect(name: str, ok: bool, detail: str = "") -> None:
    if not ok:
        raise CheckFailed(f"{name}: {detail}" if detail else name)


def main(fn) -> None:
    try:
        fn()
    except CheckFailed as e:
        print(f"CHECK FAILED  {e}", file=sys.stderr)
        sys.exit(1)
