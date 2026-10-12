import argparse
import copy
import re
import time

import numpy as np
import torch

from aif import bpe, chat, check, data, device, finetune, gpt, results, sample


# snippet:begin task
SIGN = {1: "+", -1: "-"}


def problem(rng: np.random.Generator) -> tuple[str, int]:
    a, b, c = (int(v) for v in rng.integers(10, 100, 3))
    signs = [1 if rng.random() < 0.5 else -1 for _ in range(2)]
    if rng.random() < 0.5:
        expression, answer = f"{a} {SIGN[signs[0]]} {b}", a + signs[0] * b
    else:
        m = int(rng.integers(2, 10))
        expression, answer = f"{a} * {m}", a * m
    expression, answer = f"{expression} {SIGN[signs[1]]} {c}", answer + signs[1] * c
    question = (
        f"Calculate {expression}. Work it out step by step, and end your reply with the "
        f"final answer."
    )
    return question, answer


def reward(text: str, answer: int) -> float:
    """1 if the last number in the reply is the answer, whatever came before it."""
    numbers = re.findall(r"-?\d+", text)
    return 1.0 if numbers and int(numbers[-1]) == answer else 0.0


# snippet:end task


@torch.no_grad()
def solve_rate(model, tok, problems, max_new: int) -> tuple[float, float]:
    end = tok.special[chat.END]
    right, length = 0.0, 0
    for question, answer in problems:
        prompt = tok.encode(chat.render([{"role": "user", "content": question}]))
        out = sample.generate(model, prompt, max_new, stop=end, temperature=0.0)
        right += reward(tok.decode(out), answer)
        length += len(out)
    n = len(problems)
    return right / n, length / n


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="HuggingFaceTB/SmolLM2-360M-Instruct")
    parser.add_argument("--steps", type=int, default=100)
    parser.add_argument("--prompts", type=int, default=8)
    parser.add_argument("--group", type=int, default=8)
    parser.add_argument("--max-new", type=int, default=160)
    parser.add_argument("--lr", type=float, default=2e-6)
    parser.add_argument("--beta", type=float, default=0.04)
    parser.add_argument("--eval", type=int, default=200)
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    folder = data.model_files(args.model)
    tok = bpe.BPE.from_huggingface(folder / "tokenizer.json")
    end, pad_id = tok.special[chat.END], tok.special["<|endoftext|>"]
    policy = gpt.from_huggingface(folder).to(dev)
    reference = copy.deepcopy(policy).eval()
    for p in reference.parameters():
        p.requires_grad_(False)
    held_out = [problem(np.random.default_rng(10_000 + i)) for i in range(args.eval)]
    policy.eval()
    before = solve_rate(policy, tok, held_out, args.max_new)
    print(
        f"before: solves {before[0]:.1%} of {args.eval} held-out problems, "
        f"{before[1]:.0f} tokens per reply"
    )
    if args.steps == 0:
        return
    policy.train()
    opt = torch.optim.AdamW(policy.parameters(), lr=args.lr, weight_decay=0.0)
    rng = np.random.default_rng(0)
    g = torch.Generator(dev).manual_seed(0)
    history, start = [], time.perf_counter()
    for step in range(1, args.steps + 1):
        # snippet:begin rollouts
        groups = []
        policy.eval()
        for _ in range(args.prompts):
            question, answer = problem(rng)
            prompt = tok.encode(chat.render([{"role": "user", "content": question}]))
            outs = sample.generate_group(
                policy, prompt, args.group, args.max_new, end, temperature=1.0, generator=g
            )
            rewards = torch.tensor([reward(tok.decode(o), answer) for o in outs])
            advantages = (rewards - rewards.mean()) / (rewards.std() + 1e-4)
            groups.append((prompt, outs, rewards, advantages))
        policy.train()
        # snippet:end rollouts
        # snippet:begin update
        opt.zero_grad(set_to_none=True)
        for prompt, outs, rewards, advantages in groups:
            if rewards.std() == 0:
                continue
            examples = [(prompt + o, [-100] * len(prompt) + o) for o in outs]
            ids, labels = finetune.pad(examples, range(len(examples)), pad_id, dev)
            logp, mask = finetune.token_logprobs(policy, ids, labels)
            with torch.no_grad():
                ref_logp, _ = finetune.token_logprobs(reference, ids, labels)
            ratio = torch.exp(logp - logp.detach())
            kl = torch.exp(ref_logp - logp) - (ref_logp - logp) - 1
            per_token = -(ratio * advantages.to(dev)[:, None] - args.beta * kl) * mask
            loss = (per_token.sum(1) / mask.sum(1)).mean() / args.prompts
            loss.backward()
        torch.nn.utils.clip_grad_norm_(policy.parameters(), 1.0)
        opt.step()
        # snippet:end update
        device.release(dev)
        mean_reward = float(torch.cat([r for _, _, r, _ in groups]).mean())
        mean_len = float(np.mean([len(o) for _, outs, _, _ in groups for o in outs]))
        history.append((step, mean_reward, mean_len))
        if step % 10 == 0:
            print(
                f"step {step:3d}  mean reward {np.mean([h[1] for h in history[-10:]]):.3f}  reply length "
                f"{mean_len:5.0f}  {time.perf_counter() - start:5.0f} s",
                flush=True,
            )
    policy.eval()
    after = solve_rate(policy, tok, held_out, args.max_new)
    print(
        f"after:  solves {after[0]:.1%} of the held-out problems, {after[1]:.0f} tokens per reply"
    )
    gpt.save(policy, data.RUNS / "u3-grpo" / "model.pt", base=args.model)
    results.save("u3-grpo", {"history": history, "before": before, "after": after})
    check.expect(
        "GRPO raised the solve rate",
        after[0] > before[0] + 0.05,
        f"{before[0]:.1%} -> {after[0]:.1%}",
    )


if __name__ == "__main__":
    check.main(main)
