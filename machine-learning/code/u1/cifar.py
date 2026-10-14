import argparse
import time

import torch
import torch.nn.functional as F

from aif import check, data, device, results
from u1.vision import ResNet9, cifar_tensors, crop_and_flip, embed


def accuracy(model, x, y) -> float:
    model.eval()
    with torch.no_grad():
        right = sum(
            (model(x[i : i + 1000]).argmax(1) == y[i : i + 1000]).sum().item()
            for i in range(0, len(x), 1000)
        )
    model.train()
    return right / len(x)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=16)
    parser.add_argument("--batch", type=int, default=512)
    parser.add_argument("--lr", type=float, default=0.2)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    d = cifar_tensors(dev)
    x, y = d["x_train"], d["y_train"]
    if args.limit:
        x, y = x[: args.limit], y[: args.limit]
    # snippet:begin train
    model = ResNet9().to(dev).to(memory_format=torch.channels_last)
    opt = torch.optim.SGD(
        model.parameters(), lr=args.lr, momentum=0.9, nesterov=True, weight_decay=5e-4
    )
    steps = args.epochs * (len(x) // args.batch)
    warm = max(1, steps // 4)
    schedule = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: (s + 1) / warm if s < warm else max(0.0, (steps - s) / (steps - warm))
    )
    start = time.perf_counter()
    for epoch in range(1, args.epochs + 1):
        order = torch.randperm(len(x), device=dev)
        for idx in order[: len(x) // args.batch * args.batch].view(-1, args.batch):
            loss = F.cross_entropy(model(crop_and_flip(x[idx])), y[idx], label_smoothing=0.2)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            schedule.step()
        test = accuracy(model, d["x_test"], d["y_test"])
        print(
            f"epoch {epoch:2d}  loss {loss.item():.3f}  test accuracy {test:.2%}  "
            f"{time.perf_counter() - start:5.0f} s",
            flush=True,
        )
    # snippet:end train
    params = sum(p.numel() for p in model.parameters())
    print(
        f"{params / 1e6:.1f}M parameters; {args.epochs} epochs in {time.perf_counter() - start:.0f} s"
    )
    torch.save(model.state_dict(), data.RUNS / "u1-cifar.pt")

    # snippet:begin neighbours
    feats = F.normalize(embed(model.features, d["x_test"]), dim=1)
    queries = [3, 10, 25, 42, 77, 101]
    similar = feats[queries] @ feats.T
    similar[torch.arange(len(queries)), queries] = -1
    neighbours = similar.topk(5, dim=1).indices.cpu().numpy()
    # snippet:end neighbours
    labels = d["y_test"].cpu().numpy()
    agree = float((labels[neighbours] == labels[queries][:, None]).mean())
    all_sim = feats @ feats[:2000].T
    all_sim[torch.arange(2000), torch.arange(2000)] = -1
    nn_label = labels[all_sim.argmax(0).cpu().numpy()]
    knn = float((nn_label == labels[:2000]).mean())
    print(
        f"nearest neighbour in feature space has the same class for {knn:.1%} of 2,000 test images"
    )
    results.save(
        "u1-cifar",
        {
            "queries": queries,
            "neighbours": neighbours.tolist(),
            "agree": agree,
            "knn": knn,
            "filters": model.features[0][0].weight.detach().cpu().numpy().tolist(),
        },
    )
    if not args.limit:
        check.expect("test accuracy", test >= 0.90, f"{test:.2%}")


if __name__ == "__main__":
    check.main(main)
