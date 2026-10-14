import argparse
import time

import torch
import torch.nn as nn
import torch.nn.functional as F

from aif import check, data, device, results
from u1.vision import ResNet9, cifar_tensors, embed, linear_probe, random_view


# snippet:begin info-nce
def info_nce(z: torch.Tensor, temperature: float) -> torch.Tensor:
    z = F.normalize(z, dim=1)
    n = z.shape[0] // 2
    logits = z @ z.T / temperature
    logits.fill_diagonal_(float("-inf"))
    targets = torch.cat([torch.arange(n, 2 * n), torch.arange(0, n)]).to(z.device)
    return F.cross_entropy(logits, targets)


# snippet:end info-nce


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch", type=int, default=512)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    d = cifar_tensors(dev)
    x = d["x_train"][: args.limit] if args.limit else d["x_train"]
    y = d["y_train"][: args.limit] if args.limit else d["y_train"]

    def probe(features) -> float:
        return linear_probe(
            embed(features, x),
            y,
            embed(features, d["x_test"]),
            d["y_test"],
            epochs=10 if args.limit else 100,
        )

    baseline = ResNet9().to(dev)
    random_acc = probe(baseline.features)
    print(f"linear probe on an untrained encoder: {random_acc:.2%}")

    # snippet:begin simclr
    encoder = ResNet9().to(dev).features
    projector = nn.Sequential(nn.Linear(512, 512), nn.ReLU(), nn.Linear(512, 128)).to(dev)
    params = list(encoder.parameters()) + list(projector.parameters())
    opt = torch.optim.AdamW(params, lr=2e-3, weight_decay=1e-5)
    start = time.perf_counter()
    for epoch in range(1, args.epochs + 1):
        for idx in torch.randperm(len(x), device=dev)[
            : len(x) // args.batch * args.batch
        ].view(-1, args.batch):
            views = torch.cat([random_view(x[idx]), random_view(x[idx])])
            loss = info_nce(projector(encoder(views)), args.temperature)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
        print(
            f"epoch {epoch:2d}  InfoNCE loss {loss.item():.3f}  "
            f"{time.perf_counter() - start:5.0f} s",
            flush=True,
        )
    # snippet:end simclr
    learned = probe(encoder)
    print(f"linear probe on the contrastive encoder: {learned:.2%}")
    supervised = None
    if (data.RUNS / "u1-cifar.pt").exists():
        model = ResNet9().to(dev)
        model.load_state_dict(torch.load(data.RUNS / "u1-cifar.pt", map_location=dev))
        supervised = probe(model.features)
        print(f"linear probe on Chapter 1.8's supervised encoder: {supervised:.2%}")
    results.save(
        "u1-contrastive",
        {"random": random_acc, "contrastive": learned, "supervised": supervised},
    )
    if not args.limit:
        check.expect(
            "contrastive beats random",
            learned > random_acc + 0.15,
            f"{learned:.2%} vs {random_acc:.2%}",
        )


if __name__ == "__main__":
    check.main(main)
