import argparse

import numpy as np
import torch
import torch.nn.functional as F

from aif import check, data, device, gpt, inspect, results
from u2.common import tinystories_model


# snippet:begin labels
def inside_quotes(tok, ids: list[int]) -> np.ndarray:
    eot = tok.special["<|endoftext|>"]
    labels, quotes = [], 0
    for i in ids:
        if i == eot:
            quotes = 0
        labels.append(quotes % 2)
        quotes += tok.token_bytes[i].count(b'"')
    return np.array(labels)


# snippet:end labels


def features(model, rows: torch.Tensor) -> list[torch.Tensor]:
    return [s.flatten(0, 1).float() for s in inspect.residual_stream(model, rows)]


# snippet:begin fit
def probe_accuracy(train_x, train_y, test_x, test_y, steps: int = 300) -> float:
    mean, std = train_x.mean(0), train_x.std(0) + 1e-6
    w = torch.zeros(train_x.shape[1], 2, device=train_x.device, requires_grad=True)
    b = torch.zeros(2, device=train_x.device, requires_grad=True)
    opt = torch.optim.Adam([w, b], lr=0.01)
    for _ in range(steps):
        loss = F.cross_entropy((train_x - mean) / std @ w + b, train_y)
        opt.zero_grad()
        loss.backward()
        opt.step()
    with torch.no_grad():
        return (((test_x - mean) / std @ w + b).argmax(1) == test_y).float().mean().item()


# snippet:end fit


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    args = parser.parse_args()
    dev = device.device()
    model, tok = tinystories_model(dev, args.model)
    torch.manual_seed(0)
    untrained = gpt.GPT(model.config).to(dev).eval()
    valid = np.memmap(data.DATA / "tinystories" / "valid-8192.bin", dtype=np.uint16, mode="r")
    story_starts = np.flatnonzero(valid[:-257] == tok.special["<|endoftext|>"]) + 1
    starts = story_starts[np.linspace(0, len(story_starts) - 1, 400).astype(int)]
    rows = np.stack([valid[s : s + 256] for s in starts]).astype(np.int64)
    labels = np.concatenate([inside_quotes(tok, list(r)) for r in rows])
    y = torch.from_numpy(labels).to(dev)
    split = 300 * 256
    print(
        f"{len(labels):,} token positions, {labels.mean():.1%} of them inside quotation marks"
    )
    print(f"{'depth':<11}{'trained model':>15}{'untrained model':>17}")
    record = []
    for name, m in (("trained", model), ("untrained", untrained)):
        feats = features(m, torch.from_numpy(rows).to(dev))
        record.append(
            [probe_accuracy(f[:split], y[:split], f[split:], y[split:]) for f in feats]
        )
    for layer, (a, b) in enumerate(zip(*record)):
        print(f"{'embedding' if layer == 0 else f'layer {layer}':<11}{a:15.1%}{b:17.1%}")
    results.save(
        "u2-probe",
        {"trained": record[0], "untrained": record[1], "base_rate": float(labels.mean())},
    )
    check.expect("later layers know", max(record[0][4:]) > 0.9, f"{max(record[0]):.1%}")


if __name__ == "__main__":
    check.main(main)
