import contextlib
import math

import torch

from .gpt import GPT, apply_rope


# snippet:begin recording
@contextlib.contextmanager
def recording(model: GPT, head_mask: torch.Tensor | None = None):
    """Attention layers keep their weights in .weights; head_mask scales each head."""

    def instrument(attn, layer: int):
        def forward(x, cos, sin, cache=None, layer_index=0):
            B, T, _ = x.shape
            q = attn.q(x).view(B, T, attn.n_heads, attn.head_dim).transpose(1, 2)
            k = attn.k(x).view(B, T, attn.n_kv_heads, attn.head_dim).transpose(1, 2)
            v = attn.v(x).view(B, T, attn.n_kv_heads, attn.head_dim).transpose(1, 2)
            q, k = apply_rope(q, cos, sin), apply_rope(k, cos, sin)
            group = attn.n_heads // attn.n_kv_heads
            k, v = k.repeat_interleave(group, dim=1), v.repeat_interleave(group, dim=1)
            scores = q @ k.transpose(-1, -2) / math.sqrt(attn.head_dim)
            causal = torch.ones(T, T, dtype=torch.bool, device=x.device).tril()
            weights = scores.masked_fill(~causal, float("-inf")).softmax(-1)
            attn.weights = weights.detach()
            y = weights @ v
            if head_mask is not None:
                y = y * head_mask[layer].view(1, -1, 1, 1)
            return attn.o(y.transpose(1, 2).reshape(B, T, -1))

        return forward

    for i, block in enumerate(model.blocks):
        block.attn.forward = instrument(block.attn, i)
    try:
        yield
    finally:
        for block in model.blocks:
            del block.attn.forward


# snippet:end recording


# snippet:begin residual
@torch.no_grad()
def residual_stream(model: GPT, idx: torch.Tensor) -> list[torch.Tensor]:
    T = idx.shape[1]
    cos, sin = model.cos[:T], model.sin[:T]
    x = model.embed(idx)
    states = [x]
    for block in model.blocks:
        x = block(x, cos, sin)
        states.append(x)
    return states


# snippet:end residual
