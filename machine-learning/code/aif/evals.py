import math

import numpy as np
import torch
import torch.nn.functional as F

from .device import release


# snippet:begin bootstrap
def bootstrap(
    values: np.ndarray, resamples: int = 10_000, seed: int = 0
) -> tuple[float, float]:
    """A 95% confidence interval for the mean, by resampling with replacement."""
    rng = np.random.default_rng(seed)
    means = values[rng.integers(0, len(values), (resamples, len(values)))].mean(1)
    return float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def paired(
    a: np.ndarray, b: np.ndarray, resamples: int = 10_000, seed: int = 0
) -> tuple[float, float, float, float]:
    """The mean of b - a over the same items, its 95% interval, and a bootstrap p-value."""
    diff = b.astype(float) - a.astype(float)
    rng = np.random.default_rng(seed)
    means = diff[rng.integers(0, len(diff), (resamples, len(diff)))].mean(1)
    centred = means - diff.mean()
    p = float((np.abs(centred) >= abs(diff.mean())).mean())
    return (
        float(diff.mean()),
        float(np.percentile(means, 2.5)),
        float(np.percentile(means, 97.5)),
        p,
    )


# snippet:end bootstrap


# snippet:begin mcnemar
def mcnemar(a: np.ndarray, b: np.ndarray) -> float:
    """Exact two-sided p-value for two models' accuracies on the same items."""
    only_a = int(np.sum(a & ~b))
    only_b = int(np.sum(b & ~a))
    n, k = only_a + only_b, min(only_a, only_b)
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, i) for i in range(k + 1)) / 2**n
    return min(1.0, 2 * tail)


# snippet:end mcnemar


# snippet:begin choice
@torch.no_grad()
def choose(model, tok, context: str, options: list[str], device) -> int:
    """The option with the highest mean log-probability per token, given the context."""
    ctx = tok.encode(context)
    rows = [ctx + tok.encode(o) for o in options]
    longest = max(len(r) for r in rows)
    ids = torch.zeros(len(rows), longest, dtype=torch.long)
    for i, r in enumerate(rows):
        ids[i, : len(r)] = torch.tensor(r)
    logits = model(ids[:, :-1].to(device)).float()
    logp = F.log_softmax(logits, -1).gather(-1, ids[:, 1:, None].to(device)).squeeze(-1).cpu()
    scores = [logp[i, len(ctx) - 1 : len(r) - 1].mean().item() for i, r in enumerate(rows)]
    release(device)
    return int(np.argmax(scores))


# snippet:end choice
