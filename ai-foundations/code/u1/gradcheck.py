import numpy as np
import torch

from aif import check
from aif.tiny import Tensor, cross_entropy, log_softmax
from aif.tiny.scalar import Value


# snippet:begin numeric
def numeric_grad(f, x: np.ndarray, h: float = 1e-6) -> np.ndarray:
    grad = np.zeros_like(x)
    for i in np.ndindex(x.shape):
        saved = x[i]
        x[i] = saved + h
        up = f()
        x[i] = saved - h
        down = f()
        x[i] = saved
        grad[i] = (up - down) / (2 * h)
    return grad


# snippet:end numeric


# snippet:begin compare
def gradcheck(
    name: str, fn, *shapes, rng: np.random.Generator, positive: bool = False
) -> float:
    arrays = [rng.uniform(0.5, 2.0, s) if positive else rng.normal(size=s) for s in shapes]
    inputs = [Tensor(a, requires_grad=True) for a in arrays]
    fn(*inputs).sum().backward()
    worst = 0.0
    for t, a in zip(inputs, arrays):
        numeric = numeric_grad(lambda: fn(*[Tensor(b) for b in arrays]).sum().item(), a)
        scale = np.maximum(np.abs(numeric) + np.abs(t.grad), 1e-8)
        worst = max(worst, float(np.max(np.abs(t.grad - numeric) / scale)))
    check.expect(name, worst < 1e-6, f"relative error {worst:.2e}")
    print(f"  {name:<34} {worst:9.1e}")
    return worst


# snippet:end compare


def scalar_demo() -> None:
    # snippet:begin scalar
    a, b = Value(2.0), Value(-3.0)
    c = a * b + a.exp()
    d = c.tanh() * b
    d.backward()
    # snippet:end scalar
    da = b.data * (1 - np.tanh(c.data) ** 2) * (b.data + np.exp(a.data))
    db = np.tanh(c.data) + b.data * (1 - np.tanh(c.data) ** 2) * a.data
    check.close("dd/da", a.grad, da)
    check.close("dd/db", b.grad, db)
    print(
        f"scalar engine: d = {d.data:.6f}, dd/da = {a.grad:.6f}, dd/db = {b.grad:.6f} (match the chain rule)"
    )


def tensor_checks(rng: np.random.Generator) -> None:
    print("tensor operations against central differences (float64):")
    print(f"  {'operation':<34} {'rel. error':>9}")
    # snippet:begin cases
    gradcheck("add, broadcast (3,4)+(4,)", lambda x, y: x + y, (3, 4), (4,), rng=rng)
    gradcheck("mul, broadcast (3,1)*(1,4)", lambda x, y: x * y, (3, 1), (1, 4), rng=rng)
    gradcheck("matmul (3,5)@(5,2)", lambda x, y: x @ y, (3, 5), (5, 2), rng=rng)
    gradcheck("batched matmul (2,3,4)@(4,5)", lambda x, y: x @ y, (2, 3, 4), (4, 5), rng=rng)
    gradcheck(
        "divide, broadcast (3,4)/(3,1)",
        lambda x, y: x / y,
        (3, 4),
        (3, 1),
        rng=rng,
        positive=True,
    )
    gradcheck("power 1.5", lambda x: x**1.5, (3, 4), rng=rng, positive=True)
    gradcheck("exp, log", lambda x: x.exp() + x.log(), (3, 4), rng=rng, positive=True)
    gradcheck(
        "relu, tanh, sigmoid", lambda x: x.relu() + x.tanh() + x.sigmoid(), (3, 4), rng=rng
    )
    gradcheck("sum over axis 0", lambda x: x.sum(axis=0) * 2.0, (3, 4), rng=rng)
    gradcheck("mean keepdims", lambda x: x * x.mean(axis=1, keepdims=True), (3, 4), rng=rng)
    gradcheck("max over axis 1", lambda x: x.max(axis=1), (3, 4), rng=rng)
    gradcheck("reshape, transpose", lambda x: x.reshape(4, 3) @ x + x.T @ x, (3, 4), rng=rng)
    gradcheck("index rows [0, 2, 2]", lambda x: x[np.array([0, 2, 2])], (3, 4), rng=rng)
    gradcheck(
        "log_softmax", lambda x: log_softmax(x) * Tensor(np.arange(4.0)), (3, 4), rng=rng
    )
    gradcheck(
        "cross_entropy", lambda x: cross_entropy(x, np.array([1, 0, 3])), (3, 4), rng=rng
    )
    # snippet:end cases


def against_pytorch(rng: np.random.Generator) -> None:
    # snippet:begin pytorch
    x = rng.normal(size=(16, 8))
    targets = rng.integers(0, 5, 16)
    w1, b1 = rng.normal(size=(8, 32)) * 0.3, np.zeros(32)
    w2, b2 = rng.normal(size=(32, 5)) * 0.3, np.zeros(5)

    params = [Tensor(a, requires_grad=True) for a in (w1, b1, w2, b2)]
    loss = cross_entropy(
        (Tensor(x) @ params[0] + params[1]).tanh() @ params[2] + params[3], targets
    )
    loss.backward()

    ref = [torch.tensor(a, requires_grad=True) for a in (w1, b1, w2, b2)]
    logits = torch.tanh(torch.tensor(x) @ ref[0] + ref[1]) @ ref[2] + ref[3]
    ref_loss = torch.nn.functional.cross_entropy(logits, torch.tensor(targets))
    ref_loss.backward()
    # snippet:end pytorch
    check.close("loss", loss.item(), ref_loss.item(), rtol=1e-12)
    worst = max(
        check.close(f"grad {i}", p.grad, r.grad.numpy(), rtol=1e-10, atol=1e-12)
        for i, (p, r) in enumerate(zip(params, ref))
    )
    print(
        f"two-layer net vs PyTorch: loss {loss.item():.12f} vs {ref_loss.item():.12f}, "
        f"gradients within {worst:.1e}"
    )


def main() -> None:
    rng = np.random.default_rng(0)
    scalar_demo()
    tensor_checks(rng)
    against_pytorch(rng)


if __name__ == "__main__":
    check.main(main)
