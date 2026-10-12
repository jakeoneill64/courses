import argparse
import copy
import time

import torch
import torch.nn.functional as F

from aif import bpe, chat, check, data, device, finetune, gpt, sample
from u3.prefs import RewardModel, pairs, sequences


# snippet:begin seq-logp
def reply_logp(model, batch, side: str, pad_id: int, dev) -> torch.Tensor:
    logp, _ = finetune.token_logprobs(model, *sequences(batch, side, pad_id, dev))
    return logp.sum(1)


# snippet:end seq-logp


@torch.no_grad()
def implicit_accuracy(
    policy, reference, test, beta: float, pad_id: int, dev, batch: int = 16
) -> float:
    right = 0
    for i in range(0, len(test), batch):
        chunk = test[i : i + batch]
        margin = (
            reply_logp(policy, chunk, "chosen", pad_id, dev)
            - reply_logp(reference, chunk, "chosen", pad_id, dev)
        ) - (
            reply_logp(policy, chunk, "rejected", pad_id, dev)
            - reply_logp(reference, chunk, "rejected", pad_id, dev)
        )
        right += (margin > 0).sum().item()
        device.release(dev)
    return right / len(test)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sft", default="u3-sft-135m")
    parser.add_argument("--pairs", type=int, default=4000)
    parser.add_argument("--batch", type=int, default=4)
    parser.add_argument("--beta", type=float, default=0.1)
    parser.add_argument("--lr", type=float, default=2e-6)
    parser.add_argument("--judge-prompts", type=int, default=200)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    tok = bpe.BPE.from_huggingface(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    )
    pad_id = tok.special["<|endoftext|>"]
    train, test = pairs("train", args.pairs, tok), pairs("test", 1000, tok)
    # snippet:begin setup
    policy = gpt.load(data.RUNS / args.sft / "model.pt", dev)
    reference = copy.deepcopy(policy).eval()
    for p in reference.parameters():
        p.requires_grad_(False)
    # snippet:end setup
    print(f"{len(train):,} training pairs; beta {args.beta}, learning rate {args.lr}")
    # snippet:begin loss
    opt = torch.optim.AdamW(policy.parameters(), lr=args.lr, weight_decay=0.0)
    steps = len(train) // args.batch
    start = time.perf_counter()
    for step in range(steps):
        batch = train[step * args.batch : (step + 1) * args.batch]
        with torch.no_grad():
            ref_c = reply_logp(reference, batch, "chosen", pad_id, dev)
            ref_r = reply_logp(reference, batch, "rejected", pad_id, dev)
        pol_c = reply_logp(policy, batch, "chosen", pad_id, dev)
        pol_r = reply_logp(policy, batch, "rejected", pad_id, dev)
        margin = args.beta * ((pol_c - ref_c) - (pol_r - ref_r))
        loss = -F.logsigmoid(margin).mean()
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(policy.parameters(), 1.0)
        opt.step()
        # snippet:end loss
        device.release(dev)
        if (step + 1) % 100 == 0:
            print(
                f"step {step + 1:4d}/{steps}  loss {loss.item():.3f}  margin {margin.mean().item():+.3f}  "
                f"{time.perf_counter() - start:5.0f} s",
                flush=True,
            )
    policy.eval()
    acc = implicit_accuracy(policy, reference, test, args.beta, pad_id, dev)
    print(f"test pairs ranked correctly by the implicit reward: {acc:.1%}")
    gpt.save(policy, data.RUNS / "u3-dpo-135m" / "model.pt")
    # snippet:begin judge
    rm = RewardModel(gpt.load(data.RUNS / args.sft / "model.pt"))
    rm.load_state_dict(torch.load(data.RUNS / "u3-reward.pt", map_location="cpu"))
    rm = rm.to(dev).eval()
    wins, lengths = 0, [[], []]
    for p in test[: args.judge_prompts]:
        outs = [
            sample.generate(m, p["prompt"], 200, stop=tok.special[chat.END], temperature=0.0)
            for m in (reference, policy)
        ]
        outs = [
            o if o and o[-1] == tok.special[chat.END] else o + [tok.special[chat.END]]
            for o in outs
        ]
        scores = [
            rm(*sequences([{"prompt": p["prompt"], "reply": o}], "reply", pad_id, dev)).item()
            for o in outs
        ]
        wins += scores[1] > scores[0]
        for i, o in enumerate(outs):
            lengths[i].append(len(o))
    # snippet:end judge
    rate = wins / args.judge_prompts
    print(
        f"DPO model's reply preferred by the reward model on {rate:.1%} of {args.judge_prompts} test prompts"
    )
    print(
        f"mean reply length: {sum(lengths[0]) / len(lengths[0]):.0f} tokens before DPO, "
        f"{sum(lengths[1]) / len(lengths[1]):.0f} after"
    )
    check.expect("DPO learned the preferences", acc > 0.55, f"{acc:.1%}")


if __name__ == "__main__":
    check.main(main)
