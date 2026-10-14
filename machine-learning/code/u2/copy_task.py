import argparse

import torch

from aif import check, device, gpt, inspect, results


# snippet:begin task
def batch(size: int, half: int, vocab: int, dev) -> tuple[torch.Tensor, torch.Tensor]:
    first = torch.randint(0, vocab, (size, half), device=dev)
    seq = torch.cat([first, first], dim=1)
    targets = seq[:, 1:].clone()
    targets[:, : half - 1] = -100
    return seq[:, :-1], targets


# snippet:end task


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--steps", type=int, default=3000)
    parser.add_argument("--layers", type=int, default=2)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    dev = device.device()
    device.seed(args.seed)
    half, vocab = 16, 64
    # snippet:begin model
    config = gpt.Config(
        vocab_size=vocab,
        d_model=64,
        n_layers=args.layers,
        n_heads=2,
        n_kv_heads=2,
        d_ff=128,
        max_seq=2 * half,
    )
    model = gpt.GPT(config).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3)
    for step in range(1, args.steps + 1):
        x, y = batch(64, half, vocab, dev)
        _, loss = model(x, y)
        opt.zero_grad()
        loss.backward()
        opt.step()
        if step % 500 == 0:
            print(f"step {step:4d}  loss on the repeated half {loss.item():.3f}")
    # snippet:end model
    x, y = batch(500, half, vocab, dev)
    with torch.no_grad(), inspect.recording(model):
        logits = model(x)
        weights = model.blocks[-1].attn.weights[0].cpu()
    mask = y != -100
    accuracy = (logits.argmax(-1)[mask] == y[mask]).float().mean().item()
    print(f"copying accuracy on the repeated half: {accuracy:.2%} (chance is {1 / vocab:.1%})")
    for h, w in enumerate(weights):
        offsets = [int(w[t].argmax()) - t for t in range(half - 1, 2 * half - 1)]
        common = max(set(offsets), key=offsets.count)
        print(
            f"head {h}: in the repeated half, the strongest attention is {-common} positions back "
            f"for {offsets.count(common)} of {len(offsets)} positions, with mean weight "
            f"{float(w[half - 1 :, :].max(1).values.mean()):.2f}"
        )
    if args.layers >= 2:
        results.save("u2-copy", {"weights": weights.tolist(), "half": half})
        check.expect("the model copies", accuracy > 0.95, f"{accuracy:.2%}")


if __name__ == "__main__":
    check.main(main)
