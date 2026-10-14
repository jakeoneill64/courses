import math

import torch

from .device import release


# snippet:begin batches
def token_batches(
    examples: list[tuple[list[int], list[int]]], max_tokens: int, shuffle_seed: int | None = 0
):
    """Group examples of similar length into padded batches of about max_tokens."""
    order = sorted(range(len(examples)), key=lambda i: len(examples[i][0]))
    batches, current = [], []
    for i in order:
        longest = max([len(examples[j][0]) for j in current] + [len(examples[i][0])])
        if current and longest * (len(current) + 1) > max_tokens:
            batches.append(current)
            current = []
        current.append(i)
    if current:
        batches.append(current)
    if shuffle_seed is not None:
        g = torch.Generator().manual_seed(shuffle_seed)
        batches = [batches[i] for i in torch.randperm(len(batches), generator=g)]
    return batches


def pad(examples, indices, pad_id: int, device) -> tuple[torch.Tensor, torch.Tensor]:
    longest = max(len(examples[i][0]) for i in indices)
    ids = torch.full((len(indices), longest), pad_id, dtype=torch.long)
    labels = torch.full((len(indices), longest), -100, dtype=torch.long)
    for row, i in enumerate(indices):
        x, y = examples[i]
        ids[row, : len(x)] = torch.tensor(x)
        labels[row, : len(y)] = torch.tensor(y)
    return ids.to(device), labels.to(device)


# snippet:end batches


# snippet:begin logprobs
def token_logprobs(
    model, ids: torch.Tensor, labels: torch.Tensor
) -> tuple[torch.Tensor, torch.Tensor]:
    """Log-probability of each labelled token given those before it, and the label mask."""
    logits = model(ids[:, :-1]).float()
    targets = labels[:, 1:]
    mask = targets != -100
    picked = logits.gather(2, targets.clamp(min=0).unsqueeze(-1)).squeeze(-1)
    logp = picked - torch.logsumexp(logits, -1)
    return logp * mask, mask


def masked_loss(model, ids: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
    logp, mask = token_logprobs(model, ids, labels)
    return -logp.sum() / mask.sum()


# snippet:end logprobs


def labelled(examples, indices) -> int:
    """The number of tokens that carry the loss, counted as token_logprobs counts them."""
    return sum(sum(t != -100 for t in examples[i][1][1:]) for i in indices)


def cosine(step: int, total: int, warmup: int, floor: float = 0.1) -> float:
    if step < warmup:
        return (step + 1) / warmup
    progress = min(1.0, (step - warmup) / max(1, total - warmup))
    return floor + (1 - floor) * 0.5 * (1 + math.cos(math.pi * progress))


@torch.no_grad()
def evaluate(model, examples, max_tokens: int, pad_id: int, device) -> float:
    model.eval()
    total, count = 0.0, 0
    for indices in token_batches(examples, max_tokens, shuffle_seed=None):
        ids, labels = pad(examples, indices, pad_id, device)
        logp, mask = token_logprobs(model, ids, labels)
        total -= logp.sum().item()
        count += mask.sum().item()
        release(device)
    model.train()
    return total / count
