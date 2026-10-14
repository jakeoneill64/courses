import numpy as np

from aif import check
from aif.timing import median_time


def describe(name: str, x: np.ndarray, a: np.ndarray) -> None:
    shared = "shares a's memory" if np.shares_memory(x, a) else "a copy"
    print(
        f"{name:<18} shape {str(x.shape):<8} strides {str(x.strides):<9} "
        f"contiguous {str(x.flags.c_contiguous):<5}  {shared}"
    )


def main() -> None:
    # snippet:begin views
    a = np.arange(12, dtype=np.float32).reshape(3, 4)
    describe("a", a, a)
    describe("a.T", a.T, a)
    describe("a[:, 1:3]", a[:, 1:3], a)
    describe("a[::2]", a[::2], a)
    describe("a.reshape(4, 3)", a.reshape(4, 3), a)
    describe("a.T.reshape(12)", a.T.reshape(12), a)
    # snippet:end views
    check.expect("transpose is a view", np.shares_memory(a, a.T))
    check.expect("reshape of a transpose copies", not np.shares_memory(a, a.T.reshape(12)))

    # snippet:begin windows
    signal = np.arange(10, dtype=np.float32)
    windows = np.lib.stride_tricks.as_strided(
        signal, shape=(8, 3), strides=(4, 4), writeable=False
    )
    print("sliding windows of 3 over 0..9, without copying:")
    print(windows)
    # snippet:end windows
    check.expect("windows share memory", np.shares_memory(signal, windows))
    check.close(
        "moving average",
        windows.mean(axis=1),
        np.convolve(signal, np.ones(3) / 3, mode="valid"),
    )

    # snippet:begin cost
    big = np.random.default_rng(0).random((8192, 8192), dtype=np.float32)
    straight = median_time(lambda: big.copy(), runs=5)
    across = median_time(lambda: big.T.copy(), runs=5)
    gb = 2 * big.nbytes / 1e9
    print(
        f"copy 256 MiB in memory order: {straight * 1e3:5.1f} ms ({gb / straight:5.1f} GB/s)"
    )
    print(f"copy it through a transpose:  {across * 1e3:5.1f} ms ({gb / across:5.1f} GB/s)")
    # snippet:end cost
    check.close("transposed copy", big.T.copy()[5, 7], big[7, 5])


if __name__ == "__main__":
    check.main(main)
