import argparse
import time

import torch
import torch.nn.functional as F

from aif import bpe, check, data, device, gpt
from u3.prefs import RewardModel, pairs, sequences


@torch.no_grad()
def accuracy(
    rm: RewardModel, test: list[dict], pad_id: int, dev, batch: int = 16
) -> tuple[float, float]:
    rm.eval()
    right, margin = 0, 0.0
    for i in range(0, len(test), batch):
        chunk = test[i : i + batch]
        diff = rm(*sequences(chunk, "chosen", pad_id, dev)) - rm(
            *sequences(chunk, "rejected", pad_id, dev)
        )
        right += (diff > 0).sum().item()
        margin += diff.sum().item()
    rm.train()
    return right / len(test), margin / len(test)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sft", default="u3-sft-135m")
    parser.add_argument("--pairs", type=int, default=4000)
    parser.add_argument("--batch", type=int, default=4)
    parser.add_argument("--lr", type=float, default=1e-5)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    tok = bpe.BPE.from_huggingface(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    )
    pad_id = tok.special["<|endoftext|>"]
    train, test = pairs("train", args.pairs, tok), pairs("test", 1000, tok)
    print(f"{len(train):,} training pairs and {len(test):,} test pairs from UltraFeedback")
    rm = RewardModel(gpt.load(data.RUNS / args.sft / "model.pt")).to(dev)
    acc, _ = accuracy(rm, test, pad_id, dev)
    print(
        f"before training: test accuracy {acc:.1%} (the head starts at zero, so every pair ties)"
    )
    # snippet:begin bradley-terry
    opt = torch.optim.AdamW(rm.parameters(), lr=args.lr, weight_decay=0.0)
    steps = len(train) // args.batch
    start = time.perf_counter()
    for step in range(steps):
        batch = train[step * args.batch : (step + 1) * args.batch]
        r_chosen = rm(*sequences(batch, "chosen", pad_id, dev))
        r_rejected = rm(*sequences(batch, "rejected", pad_id, dev))
        loss = -F.logsigmoid(r_chosen - r_rejected).mean()
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
        # snippet:end bradley-terry
        device.release(dev)
        if (step + 1) % 100 == 0:
            print(
                f"step {step + 1:4d}/{steps}  loss {loss.item():.3f}  {time.perf_counter() - start:5.0f} s",
                flush=True,
            )
    acc, margin = accuracy(rm, test, pad_id, dev)
    print(f"after training: test accuracy {acc:.1%}, mean reward margin {margin:.2f}")
    torch.save(rm.state_dict(), data.RUNS / "u3-reward.pt")
    check.expect("the reward model learned", acc > 0.58, f"{acc:.1%}")


if __name__ == "__main__":
    check.main(main)
