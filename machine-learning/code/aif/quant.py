import torch
import torch.nn as nn


# snippet:begin int4
def quantise_int4(w: torch.Tensor, group: int = 64) -> tuple[torch.Tensor, torch.Tensor]:
    """Symmetric 4-bit values, one scale per group of inputs, two values per byte."""
    out_f, in_f = w.shape
    g = w.float().view(out_f, in_f // group, group)
    scale = g.abs().amax(-1, keepdim=True).clamp(min=1e-8) / 7
    q = torch.clamp(torch.round(g / scale), -8, 7).to(torch.int8).view(out_f, in_f)
    packed = (q[:, 0::2] & 0xF) | ((q[:, 1::2] & 0xF) << 4)
    return packed.to(torch.uint8), scale.squeeze(-1).to(torch.float16)


def dequantise_int4(
    packed: torch.Tensor, scale: torch.Tensor, group: int = 64
) -> torch.Tensor:
    low = (packed & 0xF).to(torch.int8)
    high = (packed >> 4).to(torch.int8)
    low = torch.where(low > 7, low - 16, low)
    high = torch.where(high > 7, high - 16, high)
    q = torch.stack([low, high], dim=-1).view(packed.shape[0], -1)
    w = q.float().view(q.shape[0], -1, group) * scale.float().unsqueeze(-1)
    return w.view(q.shape[0], -1)


# snippet:end int4


# snippet:begin int4-linear
class Int4Matmul(torch.autograd.Function):
    """x @ W.T with W rebuilt from 4 bits in both passes, so it is never kept in memory."""

    @staticmethod
    def forward(ctx, x, packed, scale, group):
        ctx.save_for_backward(packed, scale)
        ctx.group = group
        return x @ dequantise_int4(packed, scale, group).to(x.dtype).T

    @staticmethod
    def backward(ctx, grad):
        packed, scale = ctx.saved_tensors
        return (
            grad @ dequantise_int4(packed, scale, ctx.group).to(grad.dtype),
            None,
            None,
            None,
        )


class Int4Linear(nn.Module):
    def __init__(self, base: nn.Linear, group: int = 64):
        super().__init__()
        packed, scale = quantise_int4(base.weight.data, group)
        self.register_buffer("packed", packed)
        self.register_buffer("scale", scale)
        self.group, self.in_features, self.out_features = (
            group,
            base.in_features,
            base.out_features,
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return Int4Matmul.apply(x, self.packed, self.scale, self.group)


# snippet:end int4-linear


def quantise_model_int4(model, group: int = 64) -> None:
    for block in model.blocks:
        for parent, names in (
            (block.attn, ("q", "k", "v", "o")),
            (block.mlp, ("gate", "up", "down")),
        ):
            for name in names:
                layer = getattr(parent, name)
                if isinstance(layer, nn.Linear):
                    setattr(parent, name, Int4Linear(layer, group))
