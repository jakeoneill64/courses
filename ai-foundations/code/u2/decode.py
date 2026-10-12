import argparse

import torch

from aif import check, device, results, sample
from u2.common import tinystories_model

PROMPT = "Once upon a time, there was a little dog named"


# snippet:begin metrics
def repetition(ids: list[int], n: int = 4) -> float:
    grams = [tuple(ids[i : i + n]) for i in range(len(ids) - n + 1)]
    return 1 - len(set(grams)) / max(1, len(grams))


def distinct(samples: list[list[int]], n: int = 3) -> float:
    grams = [tuple(s[i : i + n]) for s in samples for i in range(len(s) - n + 1)]
    return len(set(grams)) / max(1, len(grams))


# snippet:end metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--tokens", type=int, default=120)
    args = parser.parse_args()
    dev = device.device()
    model, tok = tinystories_model(dev, args.model)
    prompt = tok.encode(PROMPT)
    eot = tok.special["<|endoftext|>"]
    # snippet:begin strategies
    strategies = {
        "greedy": dict(temperature=0.0),
        "beam search, width 4": None,
        "temperature 0.7": dict(temperature=0.7),
        "temperature 1.0": dict(temperature=1.0),
        "temperature 1.5": dict(temperature=1.5),
        "top-k 40": dict(temperature=1.0, top_k=40),
        "top-p 0.9": dict(temperature=1.0, top_p=0.9),
        "min-p 0.1": dict(temperature=1.0, min_p=0.1),
    }
    # snippet:end strategies
    rows, examples = [], {}
    print(
        f"prompt: {PROMPT!r}; {args.samples} continuations of up to {args.tokens} tokens each"
    )
    print(
        f"{'strategy':<22}{'log-prob/token':>15}{'repeated 4-grams':>18}{'distinct 3-grams':>18}"
    )
    for name, settings in strategies.items():
        g = torch.Generator(dev).manual_seed(0)
        runs = 1 if settings is None or settings.get("temperature") == 0.0 else args.samples
        outs = []
        for _ in range(runs):
            if settings is None:
                out = sample.beam_search(model, prompt, 4, args.tokens, stop=eot)
            else:
                out = sample.generate(
                    model, prompt, args.tokens, stop=eot, generator=g, **settings
                )
            outs.append([t for t in out if t != eot])
        logp = sum(
            sample.log_prob(model, prompt + o) - sample.log_prob(model, prompt) for o in outs
        ) / sum(len(o) for o in outs)
        rep = sum(repetition(o) for o in outs) / len(outs)
        div = distinct(outs) if runs > 1 else float("nan")
        rows.append({"strategy": name, "logp": logp, "repetition": rep, "distinct": div})
        examples[name] = tok.decode(outs[0])
        print(
            f"{name:<22}{logp:15.3f}{rep:18.1%}{div:18.1%}"
            if runs > 1
            else f"{name:<22}{logp:15.3f}{rep:18.1%}{'one output':>18}"
        )
    for name in ("greedy", "beam search, width 4", "temperature 1.5", "min-p 0.1"):
        text = " ".join(examples[name].split())
        print(f"\n{name}: ...{text[:300]}")
    results.save("u2-decode", {"rows": rows, "examples": examples})
    check.expect("greedy is the most probable per token", rows[0]["logp"] > rows[4]["logp"])


if __name__ == "__main__":
    check.main(main)
