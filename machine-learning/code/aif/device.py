import os
import random

import numpy as np
import torch


def device() -> torch.device:
    name = os.environ.get("AIF_DEVICE")
    if name:
        return torch.device(name)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def sync(dev: torch.device) -> None:
    if dev.type == "cuda":
        torch.cuda.synchronize()
    elif dev.type == "mps":
        torch.mps.synchronize()


def seed(n: int) -> None:
    random.seed(n)
    np.random.seed(n)
    torch.manual_seed(n)


def release(dev: torch.device) -> None:
    """Return cached memory; with batches of varying shape the cache otherwise grows."""
    if dev.type == "cuda":
        torch.cuda.empty_cache()
    elif dev.type == "mps":
        torch.mps.empty_cache()


def allocated(dev: torch.device) -> int:
    if dev.type == "cuda":
        return torch.cuda.memory_allocated()
    if dev.type == "mps":
        return torch.mps.current_allocated_memory()
    return 0
