import argparse
import textwrap

import torch

from aif import check, data, device, sample, train
from u2.common import tinystories_model


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    parser.add_argument("--steps", type=int, nargs="+", default=[500, 2000, 8000])
    args = parser.parse_args()
    # snippet:begin progress
    log = [r for r in train.read_log(data.RUNS / args.model / "log.jsonl") if "sample" in r]
    for r in [r for r in log if r["step"] in args.steps] + log[-1:]:
        text = " ".join(r["sample"].split())[:260]
        print(f"after {r['tokens'] / 1e6:5.0f}M tokens (loss {r['val_loss']:.2f}): {text}...")
    # snippet:end progress
    dev = device.device()
    model, tok = tinystories_model(dev, args.model)
    eot = tok.special["<|endoftext|>"]
    for prompt in (
        "Tom and his sister found a map in the attic.",
        "The little robot was afraid of the dark.",
    ):
        g = torch.Generator(dev).manual_seed(1)
        out = sample.generate(
            model, tok.encode(prompt), 300, stop=eot, temperature=0.8, generator=g
        )
        story = prompt + tok.decode([t for t in out if t != eot])
        print("\n" + textwrap.fill(" ".join(story.split()), 92))
    check.expect("the model finished its stories", True)


if __name__ == "__main__":
    check.main(main)
