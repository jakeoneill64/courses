import time
from dataclasses import dataclass, field

import torch
import torch.nn.functional as F

from .gpt import GPT, KVCache, apply_rope


# snippet:begin paged
class PagedCache:
    """Keys and values in fixed-size blocks; each sequence owns a list of them."""

    def __init__(self, model: GPT, blocks: int, block_size: int = 16):
        c = model.config
        p = next(model.parameters())
        shape = (c.n_layers, blocks, block_size, c.n_kv_heads, c.head_dim)
        self.k = torch.zeros(shape, device=p.device, dtype=p.dtype)
        self.v = torch.zeros(shape, device=p.device, dtype=p.dtype)
        self.block_size = block_size
        self.free = list(range(blocks))

    def blocks_for(self, tokens: int) -> int:
        return (tokens + self.block_size - 1) // self.block_size


# snippet:end paged


@dataclass
class Sequence:
    prompt: list[int]
    max_new: int
    arrival: float = 0.0
    blocks: list[int] = field(default_factory=list)
    length: int = 0
    out: list[int] = field(default_factory=list)
    first: float = 0.0
    finish: float = 0.0
    sink: object = None


@torch.no_grad()
def prefill(model: GPT, cache: PagedCache, seq: Sequence) -> torch.Tensor:
    """Run the prompt through the model and copy its keys and values into the sequence's blocks."""
    p = next(model.parameters())
    tmp = KVCache(model.config, 1, len(seq.prompt), p.device, p.dtype)
    logits = model(torch.tensor([seq.prompt], device=p.device), cache=tmp)[0, -1]
    positions = torch.arange(len(seq.prompt), device=p.device)
    table = torch.tensor(seq.blocks, device=p.device)
    where, slot = table[positions // cache.block_size], positions % cache.block_size
    cache.k[:, where, slot] = tmp.k[:, 0].permute(0, 2, 1, 3)
    cache.v[:, where, slot] = tmp.v[:, 0].permute(0, 2, 1, 3)
    seq.length = len(seq.prompt)
    return logits


# snippet:begin decode
@torch.no_grad()
def decode_step(
    model: GPT, cache: PagedCache, seqs: list[Sequence], tokens: torch.Tensor
) -> torch.Tensor:
    """One new token for every running sequence, in one batch: logits (N, vocab)."""
    dev = tokens.device
    pos = torch.tensor([s.length for s in seqs], device=dev)
    width = max(len(s.blocks) for s in seqs)
    table = torch.tensor([s.blocks + [0] * (width - len(s.blocks)) for s in seqs], device=dev)
    where = table[torch.arange(len(seqs), device=dev), pos // cache.block_size]
    slot = pos % cache.block_size
    span = width * cache.block_size
    visible = (torch.arange(span, device=dev)[None, :] <= pos[:, None])[:, None, None, :]
    cos, sin = model.cos[pos][:, None, None, :], model.sin[pos][:, None, None, :]
    x = model.embed(tokens)[:, None, :]
    for layer, block in enumerate(model.blocks):
        a = block.attn
        h = block.attn_norm(x)
        q = a.q(h).view(-1, 1, a.n_heads, a.head_dim).transpose(1, 2)
        k = a.k(h).view(-1, a.n_kv_heads, a.head_dim)
        v = a.v(h).view(-1, a.n_kv_heads, a.head_dim)
        q, k = apply_rope(q, cos, sin), apply_rope(k[:, :, None], cos, sin)[:, :, 0]
        cache.k[layer, where, slot] = k
        cache.v[layer, where, slot] = v
        keys = cache.k[layer][table].flatten(1, 2).transpose(1, 2)
        values = cache.v[layer][table].flatten(1, 2).transpose(1, 2)
        group = a.n_heads // a.n_kv_heads
        keys, values = keys.repeat_interleave(group, 1), values.repeat_interleave(group, 1)
        y = F.scaled_dot_product_attention(q, keys, values, attn_mask=visible)
        x = x + a.o(y.transpose(1, 2).reshape(len(seqs), 1, -1))
        x = x + block.mlp(block.mlp_norm(x))
    for s in seqs:
        s.length += 1
    return model.head(model.norm(x))[:, 0]


# snippet:end decode


# snippet:begin scheduler
def run(
    model: GPT,
    cache: PagedCache,
    requests: list[Sequence],
    stop: int,
    max_batch: int,
    continuous: bool = True,
    clock=time.perf_counter,
) -> float:
    """Serve requests in arrival order; without continuous, each batch runs to completion."""
    dev = next(model.parameters()).device
    pending = sorted(requests, key=lambda s: s.arrival)
    running = []
    start = clock()
    while pending or running:
        now = clock() - start
        can_admit = continuous or not running
        while can_admit and pending and pending[0].arrival <= now and len(running) < max_batch:
            need = cache.blocks_for(len(pending[0].prompt) + pending[0].max_new)
            if need > len(cache.free):
                break
            seq = pending.pop(0)
            seq.blocks = [cache.free.pop() for _ in range(need)]
            logits = prefill(model, cache, seq)
            seq.out.append(int(logits.argmax()))
            seq.first = clock() - start
            running.append(seq)
        if not running:
            time.sleep(max(0.0, pending[0].arrival - (clock() - start)))
            continue
        tokens = torch.tensor([s.out[-1] for s in running], device=dev)
        logits = decode_step(model, cache, running, tokens)
        for s, t in zip(running, logits.argmax(-1).tolist()):
            s.out.append(t)
        for s in [s for s in running if s.out[-1] == stop or len(s.out) >= s.max_new]:
            s.finish = clock() - start
            cache.free += s.blocks
            running.remove(s)
    return clock() - start


# snippet:end scheduler


# snippet:begin speculative
@torch.no_grad()
def speculative(
    target: GPT, draft: GPT, prompt: list[int], max_new: int, k: int, stop: int
) -> tuple[list[int], int]:
    """Greedy speculative decoding: the output is exactly the target's greedy output."""
    dev = next(target.parameters()).device
    limit = len(prompt) + max_new + k + 2
    t_cache = KVCache(target.config, 1, limit, dev, next(target.parameters()).dtype)
    d_cache = KVCache(draft.config, 1, limit, dev, next(draft.parameters()).dtype)
    target(torch.tensor([prompt[:-1]], device=dev), cache=t_cache)
    draft(torch.tensor([prompt[:-1]], device=dev), cache=d_cache)
    out, last, behind, rounds = [], prompt[-1], [], 0
    while len(out) < max_new and stop not in out:
        logits = draft(torch.tensor([behind + [last]], device=dev), cache=d_cache)[0, -1]
        proposal = []
        for i in range(k):
            proposal.append(int(logits.argmax()))
            if i < k - 1:
                logits = draft(torch.tensor([[proposal[-1]]], device=dev), cache=d_cache)[
                    0, -1
                ]
        start = t_cache.length
        checks = (
            target(torch.tensor([[last] + proposal], device=dev), cache=t_cache)[0]
            .argmax(-1)
            .tolist()
        )
        n = 0
        while n < k and proposal[n] == checks[n]:
            n += 1
        out += proposal[:n]
        last = checks[n]
        out.append(last)
        t_cache.length = start + 1 + n
        d_cache.length = start + 1 + min(n, k - 1)
        behind = proposal[k - 1 : k] if n == k else []
        rounds += 1
    out = out[:max_new]
    return out[: out.index(stop) + 1] if stop in out else out, rounds


# snippet:end speculative
