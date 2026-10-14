import torch

from aif import check


# snippet:begin batchnorm
class BatchNorm(torch.nn.Module):
    def __init__(self, features: int, momentum: float = 0.1, eps: float = 1e-5):
        super().__init__()
        self.weight = torch.nn.Parameter(torch.ones(features))
        self.bias = torch.nn.Parameter(torch.zeros(features))
        self.register_buffer("running_mean", torch.zeros(features))
        self.register_buffer("running_var", torch.ones(features))
        self.momentum, self.eps = momentum, eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        if self.training:
            mean, var = x.mean(0), x.var(0, unbiased=False)
            with torch.no_grad():
                n = x.shape[0]
                self.running_mean.lerp_(mean, self.momentum)
                self.running_var.lerp_(var * n / (n - 1), self.momentum)
        else:
            mean, var = self.running_mean, self.running_var
        return (x - mean) / torch.sqrt(var + self.eps) * self.weight + self.bias


# snippet:end batchnorm


# snippet:begin layernorm
class LayerNorm(torch.nn.Module):
    def __init__(self, features: int, eps: float = 1e-5):
        super().__init__()
        self.weight = torch.nn.Parameter(torch.ones(features))
        self.bias = torch.nn.Parameter(torch.zeros(features))
        self.eps = eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        mean = x.mean(-1, keepdim=True)
        var = x.var(-1, unbiased=False, keepdim=True)
        return (x - mean) / torch.sqrt(var + self.eps) * self.weight + self.bias


class RMSNorm(torch.nn.Module):
    def __init__(self, features: int, eps: float = 1e-5):
        super().__init__()
        self.weight = torch.nn.Parameter(torch.ones(features))
        self.eps = eps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps) * self.weight


# snippet:end layernorm


def compare(name: str, mine: torch.nn.Module, ref: torch.nn.Module, steps: int = 3) -> None:
    torch.manual_seed(0)
    with torch.no_grad():
        for p, q in zip(mine.parameters(), ref.parameters()):
            p.copy_(torch.randn_like(p))
            q.copy_(p)
    worst = 0.0
    for step in range(steps):
        x = torch.randn(32, 16, dtype=torch.float64) * 3 + 1
        x1, x2 = x.clone().requires_grad_(), x.clone().requires_grad_()
        a, b = mine(x1), ref(x2)
        (a * torch.arange(16.0, dtype=torch.float64)).sum().backward()
        (b * torch.arange(16.0, dtype=torch.float64)).sum().backward()
        worst = max(
            worst,
            check.close(f"{name} output", a.detach(), b.detach(), rtol=1e-10, atol=1e-12),
            check.close(f"{name} input grad", x1.grad, x2.grad, rtol=1e-8, atol=1e-10),
        )
    for p, q in zip(mine.parameters(), ref.parameters()):
        worst = max(
            worst, check.close(f"{name} parameter grad", p.grad, q.grad, rtol=1e-8, atol=1e-10)
        )
    for buffer in ("running_mean", "running_var"):
        if hasattr(ref, buffer):
            worst = max(
                worst,
                check.close(f"{name} {buffer}", getattr(mine, buffer), getattr(ref, buffer)),
            )
    mine.eval()
    ref.eval()
    x = torch.randn(8, 16, dtype=torch.float64)
    worst = max(
        worst,
        check.close(f"{name} eval output", mine(x).detach(), ref(x).detach(), rtol=1e-10),
    )
    print(f"{name:<10} matches torch.nn: largest difference {worst:.1e}")


def main() -> None:
    torch.set_default_dtype(torch.float64)
    compare("BatchNorm", BatchNorm(16), torch.nn.BatchNorm1d(16))
    compare("LayerNorm", LayerNorm(16), torch.nn.LayerNorm(16))
    compare("RMSNorm", RMSNorm(16), torch.nn.RMSNorm(16, eps=1e-5))


if __name__ == "__main__":
    check.main(main)
