import math


# snippet:begin value
class Value:
    def __init__(self, data: float, parents: tuple = (), op: str = ""):
        self.data = float(data)
        self.grad = 0.0
        self.parents = parents
        self.op = op
        self.backward_step = lambda: None

    def __add__(self, other):
        other = other if isinstance(other, Value) else Value(other)
        out = Value(self.data + other.data, (self, other), "+")

        def step():
            self.grad += out.grad
            other.grad += out.grad

        out.backward_step = step
        return out

    def __mul__(self, other):
        other = other if isinstance(other, Value) else Value(other)
        out = Value(self.data * other.data, (self, other), "*")

        def step():
            self.grad += other.data * out.grad
            other.grad += self.data * out.grad

        out.backward_step = step
        return out

    # snippet:end value

    def __pow__(self, k: float):
        out = Value(self.data**k, (self,), f"**{k}")

        def step():
            self.grad += k * self.data ** (k - 1) * out.grad

        out.backward_step = step
        return out

    # snippet:begin unary
    def exp(self):
        out = Value(math.exp(self.data), (self,), "exp")

        def step():
            self.grad += out.data * out.grad

        out.backward_step = step
        return out

    def log(self):
        out = Value(math.log(self.data), (self,), "log")

        def step():
            self.grad += out.grad / self.data

        out.backward_step = step
        return out

    def tanh(self):
        out = Value(math.tanh(self.data), (self,), "tanh")

        def step():
            self.grad += (1 - out.data**2) * out.grad

        out.backward_step = step
        return out

    # snippet:end unary

    def relu(self):
        out = Value(max(0.0, self.data), (self,), "relu")

        def step():
            self.grad += (self.data > 0) * out.grad

        out.backward_step = step
        return out

    def __neg__(self):
        return self * -1

    def __sub__(self, other):
        return self + (-other)

    def __truediv__(self, other):
        return self * (other if isinstance(other, Value) else Value(other)) ** -1

    __radd__ = __add__
    __rmul__ = __mul__

    def __rsub__(self, other):
        return Value(other) - self

    def __rtruediv__(self, other):
        return Value(other) / self

    # snippet:begin backward
    def backward(self) -> None:
        order, seen, stack = [], set(), [(self, False)]
        while stack:
            node, expanded = stack.pop()
            if expanded:
                order.append(node)
            elif id(node) not in seen:
                seen.add(id(node))
                stack.append((node, True))
                stack.extend((p, False) for p in node.parents)
        self.grad = 1.0
        for node in reversed(order):
            node.backward_step()

    # snippet:end backward

    def __repr__(self) -> str:
        return f"Value(data={self.data:.4g}, grad={self.grad:.4g})"
