import math

import torch
import torch.nn as nn

TARGETS = {"attn": ("q", "k", "v", "o"), "mlp": ("gate", "up", "down")}


# snippet:begin lora
class LoRALinear(nn.Module):
    def __init__(self, base: nn.Module, rank: int, alpha: float):
        super().__init__()
        self.base = base
        for p in base.parameters():
            p.requires_grad_(False)
        self.a = nn.Parameter(torch.empty(rank, base.in_features))
        self.b = nn.Parameter(torch.zeros(base.out_features, rank))
        nn.init.kaiming_uniform_(self.a, a=math.sqrt(5))
        self.scale = alpha / rank

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.base(x) + (x @ self.a.T @ self.b.T) * self.scale


# snippet:end lora


# snippet:begin attach
def add_lora(model, rank: int = 16, alpha: float = 32.0) -> list[nn.Parameter]:
    for p in model.parameters():
        p.requires_grad_(False)
    adapters = []
    for block in model.blocks:
        for part, names in TARGETS.items():
            parent = getattr(block, part)
            for name in names:
                layer = LoRALinear(getattr(parent, name), rank, alpha)
                setattr(parent, name, layer.to(next(model.parameters()).device))
                adapters += [layer.a, layer.b]
    return adapters


# snippet:end attach


# snippet:begin merge
@torch.no_grad()
def merge_lora(model) -> None:
    for block in model.blocks:
        for part, names in TARGETS.items():
            parent = getattr(block, part)
            for name in names:
                layer = getattr(parent, name)
                if isinstance(layer, LoRALinear) and isinstance(layer.base, nn.Linear):
                    layer.base.weight += (layer.b @ layer.a) * layer.scale
                    setattr(parent, name, layer.base)


# snippet:end merge
