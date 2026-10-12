import argparse

import numpy as np
import torch
import torch.nn.functional as F

from aif import check, device, inspect, results
from u2.common import tinystories_model

# snippet:begin names
TEMPLATES = [
    "Once upon a time, there was a little girl named {}. {} liked to play in the park. "
    "One day, {} saw a big red bird.",
    "There was a boy called {}. Every morning, {} ran to school. "
    "His friend waved at {} from the gate.",
    "A happy dog named {} lived on a farm. {} loved to dig in the mud. "
    "The farmer laughed at {} every day.",
    "In a small house lived a cat named {}. {} liked warm milk. "
    "When it rained, {} slept by the fire.",
]


def stories(tok, count: int, rng: np.random.Generator):
    """Stories that mention an invented name three times: a capital and two lower-case pieces."""
    pieces = [tok.decode([i]) for i in range(tok.vocab_size)]
    capitals = [
        i for i, p in enumerate(pieces) if len(p) == 3 and p[1].isupper() and p[0] == " "
    ]
    lower = [
        i for i, p in enumerate(pieces) if 2 <= len(p) <= 4 and p.isalpha() and p.islower()
    ]
    rows, starts = [], []
    for n in range(count):
        name = [int(rng.choice(capitals)), int(rng.choice(lower)), int(rng.choice(lower))]
        parts = TEMPLATES[n % len(TEMPLATES)].split(" {}")
        ids, at = tok.encode(parts[0]), []
        for part in parts[1:]:
            at.append(len(ids))
            ids += name + tok.encode(part)
        rows.append(ids)
        starts.append(at)
    width = max(len(r) for r in rows)
    eot = tok.special["<|endoftext|>"]
    batch = torch.tensor([r + [eot] * (width - len(r)) for r in rows])
    return batch, torch.tensor(starts)


# snippet:end names


def name_losses(model, batch, starts, head_mask=None) -> list[float]:
    """Mean loss on the second and third tokens of the name, at each of its three mentions."""
    with torch.no_grad(), inspect.recording(model, head_mask):
        logp = F.log_softmax(model(batch[:, :-1]).float(), -1)
    rows = torch.arange(len(batch), device=batch.device)[:, None]
    out = []
    for k in range(starts.shape[1]):
        at = starts[:, k : k + 1] + torch.tensor([[1, 2]], device=batch.device)
        out.append(-logp[rows, at - 1, batch[rows, at]].mean().item())
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    args = parser.parse_args()
    dev = device.device()
    model, tok = tinystories_model(dev, args.model)
    c = model.config
    batch, starts = stories(tok, 128, np.random.default_rng(0))
    batch, starts = batch.to(dev), starts.to(dev)
    print("128 short stories, each naming an invented character three times, e.g.:")
    print(f"  {tok.decode(batch[0][: starts[0, 1] + 5].tolist())!r}")
    losses = name_losses(model, batch, starts)
    print(
        "loss on the name's second and third tokens, at each mention: "
        + ", ".join(f"{loss:.2f}" for loss in losses)
        + " nats"
    )
    # snippet:begin score
    with torch.no_grad(), inspect.recording(model):
        model(batch[:, :-1])
        rows = torch.arange(len(batch), device=dev)
        query, key = starts[:, 1], starts[:, 0] + 1
        scores = torch.stack(
            [b.attn.weights[rows, :, query, key].mean(dim=0) for b in model.blocks]
        )
    # snippet:end score
    top = scores.flatten().topk(4)
    print("strongest induction heads, attention from the name's second mention to the token")
    print("that followed its first mention's first token:")
    for value, index in zip(top.values.tolist(), top.indices.tolist()):
        print(f"  layer {index // c.n_heads + 1}, head {index % c.n_heads}: {value:.2f}")
    # snippet:begin ablate
    mask = torch.ones(c.n_layers, c.n_heads, device=dev)
    mask.view(-1)[top.indices] = 0
    ablated = name_losses(model, batch, starts, mask)
    others = torch.randperm(c.n_layers * c.n_heads, generator=torch.Generator().manual_seed(1))
    others = [i for i in others.tolist() if i not in top.indices.tolist()][:4]
    control = torch.ones(c.n_layers, c.n_heads, device=dev)
    control.view(-1)[others] = 0
    controlled = name_losses(model, batch, starts, control)
    # snippet:end ablate
    print(
        f"second mention with those 4 heads switched off: {ablated[1]:.2f} nats; "
        f"with 4 other heads off: {controlled[1]:.2f}"
    )
    g = torch.Generator(device=dev).manual_seed(0)
    first = torch.randint(300, 4000, (32, 100), device=dev, generator=g)
    seq = torch.cat([first, first], dim=1)
    with torch.no_grad():
        logp = F.log_softmax(model(seq[:, :-1]).float(), -1)
    nll = -logp.gather(-1, seq[:, 1:, None])[..., 0]
    print(
        f"for contrast, 100 random tokens repeated: {nll[:, :99].mean():.2f} nats on the first "
        f"copy, {nll[:, 100:].mean():.2f} on the second"
    )
    results.save(
        "u2-induction",
        {
            "scores": scores.cpu().tolist(),
            "losses": losses,
            "ablated": ablated,
            "control": controlled,
        },
    )
    check.expect(
        "the model copies the name",
        losses[1] < losses[0] - 2,
        f"{losses[1]:.2f} vs {losses[0]:.2f}",
    )
    check.expect("switching off the induction heads hurts", ablated[1] > controlled[1] + 0.5)


if __name__ == "__main__":
    check.main(main)
