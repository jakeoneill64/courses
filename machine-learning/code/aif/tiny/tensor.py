import contextlib

import numpy as np

_grad_enabled = True


@contextlib.contextmanager
def no_grad():
    global _grad_enabled
    previous, _grad_enabled = _grad_enabled, False
    try:
        yield
    finally:
        _grad_enabled = previous


# snippet:begin unbroadcast
def unbroadcast(grad: np.ndarray, shape: tuple) -> np.ndarray:
    while grad.ndim > len(shape):
        grad = grad.sum(axis=0)
    for axis, size in enumerate(shape):
        if size == 1 and grad.shape[axis] != 1:
            grad = grad.sum(axis=axis, keepdims=True)
    return grad


# snippet:end unbroadcast


# snippet:begin tensor
class Tensor:
    def __init__(self, data, requires_grad: bool = False):
        array = np.asarray(data)
        self.data = array if array.dtype.kind == "f" else array.astype(np.float64)
        self.requires_grad = requires_grad
        self.grad: np.ndarray | None = None
        self.parents: tuple = ()
        self.backward_step = None

    def child(self, data: np.ndarray, parents: tuple) -> "Tensor":
        out = Tensor(data)
        if _grad_enabled and any(p.requires_grad for p in parents):
            out.requires_grad = True
            out.parents = parents
        return out

    def accumulate(self, grad: np.ndarray) -> None:
        if self.requires_grad:
            self.grad = grad if self.grad is None else self.grad + grad

    def wrap(self, other) -> "Tensor":
        return (
            other
            if isinstance(other, Tensor)
            else Tensor(np.asarray(other, dtype=self.data.dtype))
        )

    # snippet:end tensor

    @property
    def shape(self) -> tuple:
        return self.data.shape

    @property
    def ndim(self) -> int:
        return self.data.ndim

    def item(self) -> float:
        return float(self.data.item())

    def numpy(self) -> np.ndarray:
        return self.data

    def detach(self) -> "Tensor":
        return Tensor(self.data)

    def __repr__(self) -> str:
        return f"Tensor(shape={self.shape}, requires_grad={self.requires_grad})"

    # snippet:begin binary
    def __add__(self, other) -> "Tensor":
        other = self.wrap(other)
        out = self.child(self.data + other.data, (self, other))

        def step():
            self.accumulate(unbroadcast(out.grad, self.shape))
            other.accumulate(unbroadcast(out.grad, other.shape))

        out.backward_step = step
        return out

    def __mul__(self, other) -> "Tensor":
        other = self.wrap(other)
        out = self.child(self.data * other.data, (self, other))

        def step():
            self.accumulate(unbroadcast(out.grad * other.data, self.shape))
            other.accumulate(unbroadcast(out.grad * self.data, other.shape))

        out.backward_step = step
        return out

    def __matmul__(self, other) -> "Tensor":
        out = self.child(self.data @ other.data, (self, other))

        def step():
            self.accumulate(unbroadcast(out.grad @ other.data.swapaxes(-1, -2), self.shape))
            other.accumulate(unbroadcast(self.data.swapaxes(-1, -2) @ out.grad, other.shape))

        out.backward_step = step
        return out

    # snippet:end binary

    def __pow__(self, k: float) -> "Tensor":
        out = self.child(self.data**k, (self,))

        def step():
            self.accumulate(out.grad * k * self.data ** (k - 1))

        out.backward_step = step
        return out

    def __neg__(self) -> "Tensor":
        return self * -1.0

    def __sub__(self, other) -> "Tensor":
        return self + (-self.wrap(other))

    def __rsub__(self, other) -> "Tensor":
        return self.wrap(other) - self

    def __truediv__(self, other) -> "Tensor":
        return self * self.wrap(other) ** -1.0

    def __rtruediv__(self, other) -> "Tensor":
        return self.wrap(other) * self**-1.0

    __radd__ = __add__
    __rmul__ = __mul__

    # snippet:begin elementwise
    def exp(self) -> "Tensor":
        out = self.child(np.exp(self.data), (self,))

        def step():
            self.accumulate(out.grad * out.data)

        out.backward_step = step
        return out

    def log(self) -> "Tensor":
        out = self.child(np.log(self.data), (self,))

        def step():
            self.accumulate(out.grad / self.data)

        out.backward_step = step
        return out

    def relu(self) -> "Tensor":
        out = self.child(np.maximum(self.data, 0), (self,))

        def step():
            self.accumulate(out.grad * (self.data > 0))

        out.backward_step = step
        return out

    # snippet:end elementwise

    def tanh(self) -> "Tensor":
        out = self.child(np.tanh(self.data), (self,))

        def step():
            self.accumulate(out.grad * (1 - out.data**2))

        out.backward_step = step
        return out

    def sigmoid(self) -> "Tensor":
        out = self.child(1 / (1 + np.exp(-self.data)), (self,))

        def step():
            self.accumulate(out.grad * out.data * (1 - out.data))

        out.backward_step = step
        return out

    # snippet:begin reductions
    def sum(self, axis=None, keepdims: bool = False) -> "Tensor":
        out = self.child(self.data.sum(axis=axis, keepdims=keepdims), (self,))

        def step():
            grad = out.grad
            if axis is not None and not keepdims:
                grad = np.expand_dims(grad, axis)
            self.accumulate(np.broadcast_to(grad, self.shape).copy())

        out.backward_step = step
        return out

    def mean(self, axis=None, keepdims: bool = False) -> "Tensor":
        count = self.data.size // np.asarray(self.data.sum(axis=axis, keepdims=keepdims)).size
        return self.sum(axis, keepdims) / count

    def max(self, axis=None, keepdims: bool = False) -> "Tensor":
        out = self.child(self.data.max(axis=axis, keepdims=keepdims), (self,))

        def step():
            peak = self.data.max(axis=axis, keepdims=True)
            winners = (self.data == peak).astype(self.data.dtype)
            winners /= winners.sum(axis=axis, keepdims=True)
            grad = out.grad if keepdims or axis is None else np.expand_dims(out.grad, axis)
            self.accumulate(winners * grad)

        out.backward_step = step
        return out

    # snippet:end reductions

    # snippet:begin shape-ops
    def reshape(self, *shape) -> "Tensor":
        out = self.child(self.data.reshape(*shape), (self,))

        def step():
            self.accumulate(out.grad.reshape(self.shape))

        out.backward_step = step
        return out

    def transpose(self, *axes) -> "Tensor":
        axes = axes or tuple(reversed(range(self.ndim)))
        out = self.child(self.data.transpose(axes), (self,))

        def step():
            self.accumulate(out.grad.transpose(np.argsort(axes)))

        out.backward_step = step
        return out

    def __getitem__(self, index) -> "Tensor":
        out = self.child(self.data[index], (self,))

        def step():
            grad = np.zeros_like(self.data)
            np.add.at(grad, index, out.grad)
            self.accumulate(grad)

        out.backward_step = step
        return out

    # snippet:end shape-ops

    @property
    def T(self) -> "Tensor":
        return self.transpose()

    # snippet:begin backward
    def backward(self, grad: np.ndarray | None = None) -> None:
        order, seen, stack = [], set(), [(self, False)]
        while stack:
            node, expanded = stack.pop()
            if expanded:
                order.append(node)
            elif id(node) not in seen:
                seen.add(id(node))
                stack.append((node, True))
                stack.extend((p, False) for p in node.parents if p.requires_grad)
        self.grad = np.ones_like(self.data) if grad is None else grad
        for node in reversed(order):
            if node.backward_step is not None:
                node.backward_step()

    # snippet:end backward


# snippet:begin log-softmax
def log_softmax(x: Tensor, axis: int = -1) -> Tensor:
    shifted = x.data - x.data.max(axis=axis, keepdims=True)
    out = x.child(shifted - np.log(np.exp(shifted).sum(axis=axis, keepdims=True)), (x,))

    def step():
        softmax = np.exp(out.data)
        x.accumulate(out.grad - softmax * out.grad.sum(axis=axis, keepdims=True))

    out.backward_step = step
    return out


def cross_entropy(logits: Tensor, targets: np.ndarray) -> Tensor:
    picked = log_softmax(logits)[np.arange(len(targets)), targets]
    return -picked.mean()


# snippet:end log-softmax
