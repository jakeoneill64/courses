import statistics
import time

from .device import sync


def median_time(fn, runs: int = 10, warmup: int = 2, dev=None) -> float:
    for _ in range(warmup):
        fn()
    if dev is not None:
        sync(dev)
    times = []
    for _ in range(runs):
        start = time.perf_counter()
        fn()
        if dev is not None:
            sync(dev)
        times.append(time.perf_counter() - start)
    return statistics.median(times)
