import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F


# snippet:begin config
@dataclass
class Config:
    vocab_size: int = 8192
    d_model: int = 512
    n_layers: int = 8
    n_heads: int = 8
    n_kv_heads: int = 4
    d_ff: int = 1408
    max_seq: int = 512
    rope_theta: float = 10000.0
    norm_eps: float = 1e-5
    tie_embeddings: bool = True

    @property
    def head_dim(self) -> int:
        return self.d_model // self.n_heads


# snippet:end config


# snippet:begin rmsnorm
class RMSNorm(nn.Module):
    def __init__(self, dim: int, eps: float):
        super().__init__()
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(dim))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        dtype = x.dtype
        x = x.float()
        x = x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps)
        return self.weight * x.to(dtype)


# snippet:end rmsnorm


# snippet:begin rope
def rope_tables(head_dim: int, length: int, theta: float) -> tuple[torch.Tensor, torch.Tensor]:
    inv_freq = 1.0 / theta ** (torch.arange(0, head_dim, 2).float() / head_dim)
    angles = torch.outer(torch.arange(length).float(), inv_freq)
    angles = torch.cat([angles, angles], dim=-1)
    return angles.cos(), angles.sin()


def rotate_half(x: torch.Tensor) -> torch.Tensor:
    x1, x2 = x.chunk(2, dim=-1)
    return torch.cat([-x2, x1], dim=-1)


def apply_rope(x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
    return x * cos + rotate_half(x) * sin


# snippet:end rope


# snippet:begin cache
class KVCache:
    def __init__(self, config: Config, batch: int, length: int, device, dtype=torch.float32):
        shape = (config.n_layers, batch, config.n_kv_heads, length, config.head_dim)
        self.k = torch.zeros(shape, device=device, dtype=dtype)
        self.v = torch.zeros(shape, device=device, dtype=dtype)
        self.length = 0

    def update(
        self, layer: int, k: torch.Tensor, v: torch.Tensor
    ) -> tuple[torch.Tensor, torch.Tensor]:
        end = self.length + k.shape[2]
        self.k[layer, :, :, self.length : end] = k
        self.v[layer, :, :, self.length : end] = v
        return self.k[layer, :, :, :end], self.v[layer, :, :, :end]


# snippet:end cache


# snippet:begin attention
class Attention(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.n_heads, self.n_kv_heads, self.head_dim = c.n_heads, c.n_kv_heads, c.head_dim
        self.q = nn.Linear(c.d_model, c.n_heads * c.head_dim, bias=False)
        self.k = nn.Linear(c.d_model, c.n_kv_heads * c.head_dim, bias=False)
        self.v = nn.Linear(c.d_model, c.n_kv_heads * c.head_dim, bias=False)
        self.o = nn.Linear(c.n_heads * c.head_dim, c.d_model, bias=False)

    def forward(self, x, cos, sin, cache: KVCache | None = None, layer: int = 0):
        B, T, _ = x.shape
        q = self.q(x).view(B, T, self.n_heads, self.head_dim).transpose(1, 2)
        k = self.k(x).view(B, T, self.n_kv_heads, self.head_dim).transpose(1, 2)
        v = self.v(x).view(B, T, self.n_kv_heads, self.head_dim).transpose(1, 2)
        q, k = apply_rope(q, cos, sin), apply_rope(k, cos, sin)
        past = 0
        if cache is not None:
            past = cache.length
            k, v = cache.update(layer, k, v)
        group = self.n_heads // self.n_kv_heads
        k, v = k.repeat_interleave(group, dim=1), v.repeat_interleave(group, dim=1)
        if past == 0:
            y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        else:
            mask = torch.ones(T, past + T, dtype=torch.bool, device=x.device).tril(
                diagonal=past
            )
            y = F.scaled_dot_product_attention(q, k, v, attn_mask=mask)
        return self.o(y.transpose(1, 2).reshape(B, T, -1))


# snippet:end attention


# snippet:begin mlp
class SwiGLU(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.gate = nn.Linear(c.d_model, c.d_ff, bias=False)
        self.up = nn.Linear(c.d_model, c.d_ff, bias=False)
        self.down = nn.Linear(c.d_ff, c.d_model, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.down(F.silu(self.gate(x)) * self.up(x))


# snippet:end mlp


# snippet:begin block
class Block(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.attn_norm = RMSNorm(c.d_model, c.norm_eps)
        self.attn = Attention(c)
        self.mlp_norm = RMSNorm(c.d_model, c.norm_eps)
        self.mlp = SwiGLU(c)

    def forward(self, x, cos, sin, cache=None, layer=0):
        x = x + self.attn(self.attn_norm(x), cos, sin, cache, layer)
        return x + self.mlp(self.mlp_norm(x))


# snippet:end block


# snippet:begin gpt
class GPT(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.config = c
        self.embed = nn.Embedding(c.vocab_size, c.d_model)
        self.blocks = nn.ModuleList(Block(c) for _ in range(c.n_layers))
        self.norm = RMSNorm(c.d_model, c.norm_eps)
        self.head = nn.Linear(c.d_model, c.vocab_size, bias=False)
        if c.tie_embeddings:
            self.head.weight = self.embed.weight
        cos, sin = rope_tables(c.head_dim, c.max_seq, c.rope_theta)
        self.register_buffer("cos", cos, persistent=False)
        self.register_buffer("sin", sin, persistent=False)
        self.apply(self._init)
        for block in self.blocks:
            for proj in (block.attn.o, block.mlp.down):
                nn.init.normal_(proj.weight, std=0.02 / math.sqrt(2 * c.n_layers))

    @staticmethod
    def _init(m: nn.Module) -> None:
        if isinstance(m, (nn.Linear, nn.Embedding)):
            nn.init.normal_(m.weight, std=0.02)

    def forward(
        self,
        idx: torch.Tensor,
        targets: torch.Tensor | None = None,
        cache: KVCache | None = None,
    ):
        T = idx.shape[1]
        start = cache.length if cache is not None else 0
        cos, sin = self.cos[start : start + T], self.sin[start : start + T]
        x = self.embed(idx)
        for i, block in enumerate(self.blocks):
            x = block(x, cos, sin, cache, i)
        if cache is not None:
            cache.length += T
        logits = self.head(self.norm(x))
        if targets is None:
            return logits
        loss = F.cross_entropy(
            logits.float().flatten(0, 1), targets.flatten(), ignore_index=-100
        )
        return logits, loss


# snippet:end gpt


# snippet:begin count
def param_count(c: Config, embedding: bool = True) -> int:
    attn = c.d_model * c.head_dim * (2 * c.n_heads + 2 * c.n_kv_heads)
    mlp = 3 * c.d_model * c.d_ff
    per_layer = attn + mlp + 2 * c.d_model
    total = c.n_layers * per_layer + c.d_model
    if embedding:
        total += c.vocab_size * c.d_model * (1 if c.tie_embeddings else 2)
    return total


def train_flops_per_token(c: Config, seq: int) -> float:
    matmul_params = param_count(c, embedding=False) + c.vocab_size * c.d_model
    return 6 * matmul_params + 6 * c.n_layers * seq * c.d_model


# snippet:end count


def save(model: GPT, path: Path, **extra) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"config": asdict(model.config), "model": model.state_dict(), **extra}, path)


def load(path: Path, device="cpu") -> GPT:
    state = torch.load(path, map_location="cpu", weights_only=False)
    model = GPT(Config(**state["config"]))
    model.load_state_dict(state["model"])
    return model.to(device)


# snippet:begin hf-names
HF_NAMES = {
    "self_attn.q_proj": "attn.q",
    "self_attn.k_proj": "attn.k",
    "self_attn.v_proj": "attn.v",
    "self_attn.o_proj": "attn.o",
    "mlp.gate_proj": "mlp.gate",
    "mlp.up_proj": "mlp.up",
    "mlp.down_proj": "mlp.down",
    "input_layernorm": "attn_norm",
    "post_attention_layernorm": "mlp_norm",
}


def from_huggingface(directory: Path, max_seq: int = 2048, dtype=torch.float32) -> GPT:
    from safetensors.torch import load_file

    hf = json.loads((Path(directory) / "config.json").read_text())
    if hf.get("rope_scaling") or hf.get("attention_bias") or hf.get("mlp_bias"):
        raise ValueError("only plain Llama-style checkpoints are supported")
    config = Config(
        vocab_size=hf["vocab_size"],
        d_model=hf["hidden_size"],
        n_layers=hf["num_hidden_layers"],
        n_heads=hf["num_attention_heads"],
        n_kv_heads=hf["num_key_value_heads"],
        d_ff=hf["intermediate_size"],
        max_seq=max_seq,
        rope_theta=hf["rope_theta"],
        norm_eps=hf["rms_norm_eps"],
        tie_embeddings=hf["tie_word_embeddings"],
    )
    weights = load_file(Path(directory) / "model.safetensors")
    state = {}
    for name, tensor in weights.items():
        name = name.removeprefix("model.")
        if name.startswith("layers."):
            _, i, rest = name.split(".", 2)
            module, kind = rest.rsplit(".", 1)
            name = f"blocks.{i}.{HF_NAMES[module]}.{kind}"
        elif name == "embed_tokens.weight":
            name = "embed.weight"
        elif name == "lm_head.weight":
            name = "head.weight"
        state[name] = tensor.to(dtype)
    with torch.device("meta"):
        model = GPT(config)
    model.load_state_dict(state, strict=False, assign=True)
    if config.tie_embeddings:
        model.head.weight = model.embed.weight
    cos, sin = rope_tables(config.head_dim, config.max_seq, config.rope_theta)
    model.cos, model.sin = cos, sin
    missing = [n for n, p in model.named_parameters() if p.is_meta]
    if missing:
        raise ValueError(f"weights missing from the checkpoint: {missing[:4]}")
    return model.to(dtype)


# snippet:end hf-names
