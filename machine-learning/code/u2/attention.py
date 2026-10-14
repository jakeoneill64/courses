import numpy as np
import torch
import torch.nn.functional as F

from aif import check
from aif.tiny import Tensor, log_softmax


# snippet:begin numpy
def softmax(z: np.ndarray) -> np.ndarray:
    e = np.exp(z - z.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)


def attention(q: np.ndarray, k: np.ndarray, v: np.ndarray, causal: bool = False) -> np.ndarray:
    scores = q @ k.swapaxes(-1, -2) / np.sqrt(q.shape[-1])
    if causal:
        T = q.shape[-2]
        scores = np.where(np.tril(np.ones((T, T), dtype=bool)), scores, -np.inf)
    return softmax(scores) @ v


# snippet:end numpy


# snippet:begin heads
def multi_head(x: np.ndarray, wq, wk, wv, wo, heads: int, causal: bool = True) -> np.ndarray:
    T, d = x.shape
    split = lambda m: m.reshape(T, heads, d // heads).transpose(1, 0, 2)
    q, k, v = split(x @ wq), split(x @ wk), split(x @ wv)
    y = attention(q, k, v, causal)
    return y.transpose(1, 0, 2).reshape(T, d) @ wo


# snippet:end heads


def tiny_attention(q: Tensor, k: Tensor, v: Tensor, mask: np.ndarray) -> Tensor:
    scores = q @ k.transpose(1, 0) * (1 / np.sqrt(q.shape[-1])) + Tensor(
        np.where(mask, 0.0, -1e9)
    )
    return log_softmax(scores).exp() @ v


def main() -> None:
    rng = np.random.default_rng(0)
    T, d, heads = 6, 16, 4
    x = rng.normal(size=(T, d))
    wq, wk, wv, wo = (rng.normal(size=(d, d)) / np.sqrt(d) for _ in range(4))
    ours = multi_head(x, wq, wk, wv, wo, heads)
    # snippet:begin torch
    tq, tk, tv = (
        torch.tensor(x @ w).view(T, heads, d // heads).transpose(0, 1) for w in (wq, wk, wv)
    )
    y = F.scaled_dot_product_attention(tq, tk, tv, is_causal=True)
    ref = (y.transpose(0, 1).reshape(T, d) @ torch.tensor(wo)).numpy()
    # snippet:end torch
    err = check.close("multi-head attention", ours, ref, rtol=1e-12, atol=1e-12)
    print(
        f"multi-head causal attention in NumPy against PyTorch: largest difference {err:.1e}"
    )
    q, k, v = (rng.normal(size=(T, 8)) for _ in range(3))
    first = attention(q[:1], k[:1], v[:1])
    check.close("causal first row", attention(q, k, v, causal=True)[0], first[0])
    mask = np.tril(np.ones((T, T), dtype=bool))
    tensors = [Tensor(a, requires_grad=True) for a in (q, k, v)]
    tiny_attention(*tensors, mask).sum().backward()
    tq, tk, tv = (torch.tensor(a, requires_grad=True) for a in (q, k, v))
    F.scaled_dot_product_attention(
        tq[None], tk[None], tv[None], is_causal=True
    ).sum().backward()
    worst = max(
        check.close("gradient", t.grad, r.grad.numpy(), rtol=1e-9, atol=1e-12)
        for t, r in zip(tensors, (tq, tk, tv))
    )
    print(f"attention built from tiny's operations: gradients match PyTorch's to {worst:.1e}")

    # snippet:begin scale
    for dim in (16, 64, 256):
        keys = rng.normal(size=(1000, 128, dim))
        query = rng.normal(size=dim)
        scores = keys @ query
        unscaled = softmax(scores).max(1).mean()
        scaled = softmax(scores / np.sqrt(dim)).max(1).mean()
        print(
            f"d = {dim:3d}: scores have standard deviation {scores.std():4.1f}; "
            f"the largest of 128 weights "
            f"averages {unscaled:.2f} unscaled, {scaled:.2f} scaled"
        )
    # snippet:end scale


if __name__ == "__main__":
    check.main(main)
