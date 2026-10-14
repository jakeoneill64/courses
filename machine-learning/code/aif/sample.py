import torch
import torch.nn.functional as F

from .device import release
from .gpt import GPT, KVCache


# snippet:begin filters
def filter_logits(
    logits: torch.Tensor, top_k: int = 0, top_p: float = 1.0, min_p: float = 0.0
) -> torch.Tensor:
    if top_k > 0:
        kth = torch.topk(logits, top_k, dim=-1).values[..., -1:]
        logits = logits.masked_fill(logits < kth, float("-inf"))
    if top_p < 1.0:
        sorted_logits, order = torch.sort(logits, descending=True, dim=-1)
        probs = sorted_logits.softmax(-1)
        outside = probs.cumsum(-1) - probs > top_p
        logits = logits.scatter(-1, order, sorted_logits.masked_fill(outside, float("-inf")))
    if min_p > 0.0:
        probs = logits.softmax(-1)
        logits = logits.masked_fill(
            probs < min_p * probs.max(-1, keepdim=True).values, float("-inf")
        )
    return logits


# snippet:end filters


# snippet:begin next-token
def next_token(
    logits: torch.Tensor, temperature: float = 1.0, generator=None, **filters
) -> torch.Tensor:
    if temperature == 0.0:
        return logits.argmax(-1)
    logits = filter_logits(logits / temperature, **filters)
    probs = logits.float().softmax(-1)
    return torch.multinomial(probs, 1, generator=generator).squeeze(-1)


# snippet:end next-token


# snippet:begin generate
@torch.no_grad()
def generate(
    model: GPT,
    prompt: list[int],
    max_new: int,
    stop: int | None = None,
    use_cache: bool = True,
    generator=None,
    **sampling,
) -> list[int]:
    device = next(model.parameters()).device
    ids = torch.tensor([prompt], device=device)
    limit = min(model.config.max_seq, len(prompt) + max_new)
    cache = (
        KVCache(model.config, 1, limit, device, next(model.parameters()).dtype)
        if use_cache
        else None
    )
    logits = model(ids, cache=cache)[:, -1]
    out = list(prompt)
    while len(out) < limit:
        token = next_token(logits, generator=generator, **sampling)
        out.append(int(token))
        if stop is not None and out[-1] == stop:
            break
        if cache is not None:
            logits = model(token.view(1, 1), cache=cache)[:, -1]
        else:
            logits = model(torch.tensor([out], device=device))[:, -1]
    release(device)
    return out[len(prompt) :]


# snippet:end generate


def log_prob(model: GPT, ids: list[int]) -> float:
    x = torch.tensor([ids], device=next(model.parameters()).device)
    with torch.no_grad():
        logits = model(x[:, :-1])
    return float(F.log_softmax(logits.float(), -1).gather(-1, x[:, 1:, None]).sum())


# snippet:begin beam
@torch.no_grad()
def beam_search(
    model: GPT,
    prompt: list[int],
    width: int,
    max_new: int,
    stop: int | None = None,
    length_penalty: float = 1.0,
) -> list[int]:
    device = next(model.parameters()).device
    limit = min(model.config.max_seq, len(prompt) + max_new)
    cache = KVCache(model.config, width, limit, device, next(model.parameters()).dtype)
    logits = model(torch.tensor([prompt] * width, device=device), cache=cache)[:, -1]
    beams = [[] for _ in range(width)]
    scores = torch.zeros(width, device=device)
    scores[1:] = float("-inf")
    finished = []
    while len(prompt) + len(beams[0]) < limit and len(finished) < width:
        logp = F.log_softmax(logits.float(), -1) + scores[:, None]
        top = logp.flatten().topk(width)
        rows, tokens = top.indices // logits.shape[-1], top.indices % logits.shape[-1]
        beams = [beams[r] + [int(t)] for r, t in zip(rows.tolist(), tokens.tolist())]
        scores = top.values.clone()
        for i, beam in enumerate(beams):
            if stop is not None and beam[-1] == stop:
                finished.append((float(scores[i]) / len(beam) ** length_penalty, beam))
                scores[i] = float("-inf")
        cache.k, cache.v = cache.k[:, rows], cache.v[:, rows]
        logits = model(tokens.view(-1, 1), cache=cache)[:, -1]
    finished += [
        (float(s) / len(b) ** length_penalty, b)
        for s, b in zip(scores.tolist(), beams)
        if s != float("-inf")
    ]
    release(device)
    return max(finished)[1]


# snippet:end beam


# snippet:begin group
@torch.no_grad()
def generate_group(
    model: GPT,
    prompt: list[int],
    n: int,
    max_new: int,
    stop: int,
    temperature: float = 1.0,
    generator=None,
) -> list[list[int]]:
    device = next(model.parameters()).device
    cache = KVCache(
        model.config, n, len(prompt) + max_new, device, next(model.parameters()).dtype
    )
    logits = model(torch.tensor([prompt] * n, device=device), cache=cache)[:, -1]
    outs = [[] for _ in range(n)]
    done = [False] * n
    for _ in range(max_new):
        tokens = next_token(logits, temperature, generator)
        for i, t in enumerate(tokens.tolist()):
            if not done[i]:
                outs[i].append(t)
                done[i] = t == stop
        if all(done):
            break
        logits = model(tokens.view(n, 1), cache=cache)[:, -1]
    release(device)
    return outs


# snippet:end group
