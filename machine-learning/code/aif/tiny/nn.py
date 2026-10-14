import numpy as np

from .tensor import Tensor


# snippet:begin module
class Module:
    training = True

    def parameters(self) -> list[Tensor]:
        found = []
        for value in vars(self).values():
            items = value if isinstance(value, (list, tuple)) else [value]
            for item in items:
                if isinstance(item, Tensor) and item.requires_grad:
                    found.append(item)
                elif isinstance(item, Module):
                    found.extend(item.parameters())
        return found

    def modules(self) -> list["Module"]:
        found = [self]
        for value in vars(self).values():
            for item in value if isinstance(value, (list, tuple)) else [value]:
                if isinstance(item, Module):
                    found.extend(item.modules())
        return found

    def train(self, mode: bool = True) -> "Module":
        for m in self.modules():
            m.training = mode
        return self

    def eval(self) -> "Module":
        return self.train(False)

    def zero_grad(self) -> None:
        for p in self.parameters():
            p.grad = None

    def __call__(self, *args):
        return self.forward(*args)


# snippet:end module


# snippet:begin linear
class Linear(Module):
    def __init__(
        self,
        n_in: int,
        n_out: int,
        rng: np.random.Generator,
        gain: float = 2.0,
        dtype=np.float32,
    ):
        std = np.sqrt(gain / n_in)
        self.weight = Tensor(
            rng.normal(0.0, std, (n_in, n_out)).astype(dtype), requires_grad=True
        )
        self.bias = Tensor(np.zeros(n_out, dtype=dtype), requires_grad=True)

    def forward(self, x: Tensor) -> Tensor:
        return x @ self.weight + self.bias


# snippet:end linear


class ReLU(Module):
    def forward(self, x: Tensor) -> Tensor:
        return x.relu()


class Tanh(Module):
    def forward(self, x: Tensor) -> Tensor:
        return x.tanh()


# snippet:begin dropout
class Dropout(Module):
    def __init__(self, p: float, rng: np.random.Generator):
        self.p, self.rng = p, rng

    def forward(self, x: Tensor) -> Tensor:
        if not self.training or self.p == 0.0:
            return x
        keep = (self.rng.random(x.shape) >= self.p).astype(x.data.dtype)
        return x * (keep / (1.0 - self.p))


# snippet:end dropout


class Sequential(Module):
    def __init__(self, *layers: Module):
        self.layers = list(layers)

    def forward(self, x: Tensor) -> Tensor:
        for layer in self.layers:
            x = layer(x)
        return x


# snippet:begin mlp
def mlp(sizes: list[int], rng: np.random.Generator, dropout: float = 0.0) -> Sequential:
    layers = []
    for i, (n_in, n_out) in enumerate(zip(sizes, sizes[1:])):
        last = i == len(sizes) - 2
        layers.append(Linear(n_in, n_out, rng, gain=1.0 if last else 2.0))
        if not last:
            layers.append(ReLU())
            if dropout:
                layers.append(Dropout(dropout, rng))
    return Sequential(*layers)


# snippet:end mlp
