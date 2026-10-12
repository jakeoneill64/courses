import argparse

import numpy as np
import torch
import torch.nn.functional as F

from aif import check, data, device, inspect, results
from u2.common import tinystories_model

PROMPT = "Once upon a time, there was a little girl named Lily. She loved to play with her"


# snippet:begin lens
def lens(model, state: torch.Tensor) -> torch.Tensor:
    return model.head(model.norm(state))


# snippet:end lens


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    args = parser.parse_args()
    dev = device.device()
    model, tok = tinystories_model(dev, args.model)
    ids = torch.tensor([tok.encode(PROMPT)], device=dev)
    states = inspect.residual_stream(model, ids)
    print(f"prompt: {PROMPT!r}")
    print("top three next tokens read from the residual stream after each layer:")
    for layer, state in enumerate(states):
        with torch.no_grad():
            probs = lens(model, state[:, -1]).softmax(-1)[0]
        top = probs.topk(3)
        words = ", ".join(
            f"{tok.decode([i])!r} {p:.2f}"
            for p, i in zip(top.values.tolist(), top.indices.tolist())
        )
        print(f"  {'embedding' if layer == 0 else f'layer {layer}':<10} {words}")
    # snippet:begin by-layer
    valid = np.memmap(data.DATA / "tinystories" / "valid-8192.bin", dtype=np.uint16, mode="r")
    starts = np.linspace(0, len(valid) - 257, 64).astype(int)
    batch = torch.from_numpy(
        np.stack([valid[s : s + 257] for s in starts]).astype(np.int64)
    ).to(dev)
    losses = []
    for state in inspect.residual_stream(model, batch[:, :-1]):
        with torch.no_grad():
            logits = lens(model, state)
        losses.append(
            F.cross_entropy(logits.flatten(0, 1).float(), batch[:, 1:].flatten()).item()
        )
    # snippet:end by-layer
    print(
        "validation loss of the lens at each depth: " + ", ".join(f"{l:.2f}" for l in losses)
    )
    results.save("u2-logit-lens", {"losses": losses})
    check.expect("the lens sharpens with depth", losses[-1] < losses[1])


if __name__ == "__main__":
    check.main(main)
