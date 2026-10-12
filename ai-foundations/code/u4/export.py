import argparse
import json
import struct
from pathlib import Path

import numpy as np
import torch

from aif import bpe, check, data, gpt

ALIGN = 64


def quantise_rows_int8(w: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    scale = np.maximum(np.abs(w).max(1), 1e-8) / 127
    return np.clip(np.round(w / scale[:, None]), -127, 127).astype(np.int8), scale.astype(
        np.float32
    )


def quantise_groups_int4(w: np.ndarray, group: int = 32) -> tuple[np.ndarray, np.ndarray]:
    g = w.reshape(w.shape[0], -1, group)
    scale = np.maximum(np.abs(g).max(-1), 1e-8) / 7
    q = np.clip(np.round(g / scale[..., None]), -8, 7).astype(np.int8).reshape(w.shape)
    packed = ((q[:, 0::2] & 0xF) | ((q[:, 1::2] & 0xF) << 4)).astype(np.uint8)
    return packed, scale.astype(np.float32)


def dequantise(w: np.ndarray, weights: str) -> np.ndarray:
    if weights == "i8":
        q, s = quantise_rows_int8(w)
        return q.astype(np.float32) * s[:, None]
    packed, s = quantise_groups_int4(w)
    low, high = (packed & 0xF).astype(np.int8), (packed >> 4).astype(np.int8)
    q = np.empty(w.shape, dtype=np.int8)
    q[:, 0::2], q[:, 1::2] = (
        np.where(low > 7, low - 16, low),
        np.where(high > 7, high - 16, high),
    )
    return (q.reshape(w.shape[0], -1, 32).astype(np.float32) * s[..., None]).reshape(w.shape)


def dequantised_copy(model: gpt.GPT, weights: str) -> gpt.GPT:
    """The model as the engine computes it: every matrix but the embedding quantised and dequantised."""
    import copy

    out = copy.deepcopy(model)
    device = model.head.weight.device
    out.head = torch.nn.Linear(out.config.d_model, out.config.vocab_size, bias=False).to(
        device
    )
    out.head.weight.data = model.head.weight.detach().clone()
    for layer in [out.head] + [
        m
        for b in out.blocks
        for m in (b.attn.q, b.attn.k, b.attn.v, b.attn.o, b.mlp.gate, b.mlp.up, b.mlp.down)
    ]:
        w = layer.weight.detach().float().cpu().numpy()
        layer.weight.data = torch.from_numpy(dequantise(w, weights)).to(device)
    return out


# snippet:begin export
def export(
    model: gpt.GPT, tok: bpe.BPE, path: Path, prompt: str, weights: str = "f32"
) -> None:
    c = model.config
    tensors = {"embed": model.embed.weight, "norm": model.norm.weight}
    for i, b in enumerate(model.blocks):
        tensors |= {
            f"{i}.attn_norm": b.attn_norm.weight,
            f"{i}.mlp_norm": b.mlp_norm.weight,
            f"{i}.q": b.attn.q.weight,
            f"{i}.k": b.attn.k.weight,
            f"{i}.v": b.attn.v.weight,
            f"{i}.o": b.attn.o.weight,
            f"{i}.gate": b.mlp.gate.weight,
            f"{i}.up": b.mlp.up.weight,
            f"{i}.down": b.mlp.down.weight,
        }
    if not c.tie_embeddings or weights != "f32":
        tensors["head"] = model.head.weight
    blobs, entries, offset = [], [], 0
    for name, t in tensors.items():
        array = t.detach().float().cpu().numpy()
        matrix = array.ndim == 2 and name != "embed"
        parts = {"f32": [("f32", array)]}
        if matrix and weights == "i8":
            q, s = quantise_rows_int8(array)
            parts = {"i8": [("i8", q), ("f32", s)]}
        elif matrix and weights == "q4":
            q, s = quantise_groups_int4(array)
            parts = {"q4": [("u8", q), ("f32", s)]}
        kind, pieces = next(iter(parts.items()))
        entry = {"name": name, "kind": kind, "shape": list(array.shape), "offsets": []}
        for _, piece in pieces:
            offset = (offset + ALIGN - 1) // ALIGN * ALIGN
            entry["offsets"].append(offset)
            blobs.append((offset, np.ascontiguousarray(piece).tobytes()))
            offset += piece.nbytes
        entries.append(entry)
    ids = tok.encode(prompt)
    reference_model = dequantised_copy(model, weights) if weights != "f32" else model
    with torch.no_grad():
        reference = (
            reference_model(torch.tensor([ids], device=next(model.parameters()).device))[0, -1]
            .float()
            .cpu()
        )
    header = {
        "config": {
            "vocab": c.vocab_size,
            "d_model": c.d_model,
            "layers": c.n_layers,
            "heads": c.n_heads,
            "kv_heads": c.n_kv_heads,
            "d_ff": c.d_ff,
            "max_seq": c.max_seq,
            "rope_theta": c.rope_theta,
            "norm_eps": c.norm_eps,
            "tied": c.tie_embeddings,
        },
        "tensors": entries,
        "tokenizer": {
            "tokens": [t.hex() for t in tok.token_bytes],
            "merges": [
                [a, b, m]
                for (a, b), m in sorted(tok.merged.items(), key=lambda kv: tok.rank[kv[0]])
            ],
            "special": tok.special,
            "split_digits": tok.split_digits,
        },
        "check": {"prompt": prompt, "ids": ids, "logits": reference.tolist()},
    }
    raw = json.dumps(header).encode()
    start = (8 + len(raw) + ALIGN - 1) // ALIGN * ALIGN
    with open(path, "wb") as f:
        f.write(b"AIF1" + struct.pack("<I", len(raw)) + raw)
        for at, blob in blobs:
            f.seek(start + at)
            f.write(blob)


# snippet:end export


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        default="tinystories-28m",
        help="a run under runs/, or a Hugging Face model such as HuggingFaceTB/SmolLM2-135M",
    )
    parser.add_argument("--weights", choices=["f32", "i8", "q4"], default="f32")
    parser.add_argument("--prompt", default="Once upon a time, there was a little dog named")
    args = parser.parse_args()
    if args.model.startswith("HuggingFaceTB/"):
        folder = data.model_files(args.model)
        model, tok = (
            gpt.from_huggingface(folder),
            bpe.BPE.from_huggingface(folder / "tokenizer.json"),
        )
        stem = args.model.split("/")[1]
    else:
        model = gpt.load(data.RUNS / args.model / "model.pt")
        tok = bpe.BPE.load(data.DATA / "tinystories" / "bpe8192.json")
        stem = args.model
    out = data.RUNS / "engine" / f"{stem}-{args.weights}.bin"
    out.parent.mkdir(parents=True, exist_ok=True)
    export(model.eval(), tok, out, args.prompt, args.weights)
    print(f"wrote {out} ({out.stat().st_size / 2**20:,.1f} MiB)")
    check.expect("file written", out.stat().st_size > 1000)


if __name__ == "__main__":
    check.main(main)
