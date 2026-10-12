import numpy as np

from .tensor import Tensor


class Optimizer:
    def __init__(self, params: list[Tensor], lr: float):
        self.params = list(params)
        self.lr = lr
        self.state = [dict() for _ in self.params]

    def zero_grad(self) -> None:
        for p in self.params:
            p.grad = None

    def step(self) -> None:
        for p, state in zip(self.params, self.state):
            if p.grad is not None:
                self.update(p, p.grad, state)

    def update(self, p: Tensor, g: np.ndarray, state: dict) -> None:
        raise NotImplementedError


# snippet:begin sgd
class SGD(Optimizer):
    def __init__(
        self,
        params,
        lr: float,
        momentum: float = 0.0,
        nesterov: bool = False,
        weight_decay: float = 0.0,
    ):
        super().__init__(params, lr)
        self.momentum, self.nesterov, self.weight_decay = momentum, nesterov, weight_decay

    def update(self, p, g, state):
        if self.weight_decay:
            g = g + self.weight_decay * p.data
        if self.momentum:
            buf = state.get("buf")
            buf = g.copy() if buf is None else self.momentum * buf + g
            state["buf"] = buf
            g = g + self.momentum * buf if self.nesterov else buf
        p.data -= self.lr * g


# snippet:end sgd


# snippet:begin rmsprop
class RMSProp(Optimizer):
    def __init__(self, params, lr: float, alpha: float = 0.99, eps: float = 1e-8):
        super().__init__(params, lr)
        self.alpha, self.eps = alpha, eps

    def update(self, p, g, state):
        v = state.get("v", np.zeros_like(p.data))
        v = self.alpha * v + (1 - self.alpha) * g * g
        state["v"] = v
        p.data -= self.lr * g / (np.sqrt(v) + self.eps)


# snippet:end rmsprop


# snippet:begin adam
class Adam(Optimizer):
    def __init__(
        self,
        params,
        lr: float,
        betas=(0.9, 0.999),
        eps: float = 1e-8,
        weight_decay: float = 0.0,
        decoupled: bool = False,
    ):
        super().__init__(params, lr)
        self.beta1, self.beta2 = betas
        self.eps, self.weight_decay, self.decoupled = eps, weight_decay, decoupled

    def update(self, p, g, state):
        if self.weight_decay and self.decoupled:
            p.data -= self.lr * self.weight_decay * p.data
        elif self.weight_decay:
            g = g + self.weight_decay * p.data
        t = state["t"] = state.get("t", 0) + 1
        m = state["m"] = self.beta1 * state.get("m", 0.0) + (1 - self.beta1) * g
        v = state["v"] = self.beta2 * state.get("v", 0.0) + (1 - self.beta2) * g * g
        m_hat = m / (1 - self.beta1**t)
        v_hat = v / (1 - self.beta2**t)
        p.data -= self.lr * m_hat / (np.sqrt(v_hat) + self.eps)


class AdamW(Adam):
    def __init__(
        self,
        params,
        lr: float,
        betas=(0.9, 0.999),
        eps: float = 1e-8,
        weight_decay: float = 0.01,
    ):
        super().__init__(params, lr, betas, eps, weight_decay, decoupled=True)


# snippet:end adam
