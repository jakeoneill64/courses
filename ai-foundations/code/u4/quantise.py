import argparse
import copy

import torch
import torch.nn.functional as F

from aif import bpe, check, data, device, gpt, results, train


def linears(model):
    for block in model.blocks:
        for layer in (
            block.attn.q,
            block.attn.k,
            block.attn.v,
            block.attn.o,
            block.mlp.gate,
            block.mlp.up,
            block.mlp.down,
        ):
            yield layer


# snippet:begin rtn
def round_to_nearest(w: torch.Tensor, bits: int, group: int) -> torch.Tensor:
    top = 2 ** (bits - 1) - 1
    rows, cols = w.shape
    g = F.pad(w, (0, -cols % group)).view(rows, -1, group)
    scale = g.abs().amax(-1, keepdim=True).clamp(min=1e-8) / top
    q = torch.clamp(torch.round(g / scale), -top - 1, top) * scale
    return q.view(rows, -1)[:, :cols]


# snippet:end rtn


# snippet:begin gptq
def gptq(
    w: torch.Tensor, x: torch.Tensor, bits: int, group: int, damp: float = 0.01
) -> torch.Tensor:
    """Quantise columns in turn, pushing each one's error onto those not yet done."""
    device = w.device
    w, x = w.cpu().double().clone(), x.cpu().double()  # MPS has no float64
    h = 2 * x.T @ x / len(x)
    h += damp * h.diagonal().mean() * torch.eye(len(h), dtype=h.dtype, device=h.device)
    inverse = torch.linalg.cholesky(
        torch.cholesky_inverse(torch.linalg.cholesky(h)), upper=True
    )
    top = 2 ** (bits - 1) - 1
    out = torch.zeros_like(w)
    for j in range(w.shape[1]):
        if j % group == 0:
            scale = w[:, j : j + group].abs().amax(1).clamp(min=1e-8) / top
        q = torch.clamp(torch.round(w[:, j] / scale), -top - 1, top) * scale
        out[:, j] = q
        error = (w[:, j] - q) / inverse[j, j]
        w[:, j + 1 :] -= error[:, None] * inverse[j, j + 1 :][None, :]
    return out.to(device, torch.float32)


# snippet:end gptq


def calibrate_and_quantise(model, batches, bits: int, group: int) -> None:
    for layer in list(linears(model)):
        seen = []
        handle = layer.register_forward_hook(
            lambda m, a, o: seen.append(a[0].reshape(-1, a[0].shape[-1]))
        )
        with torch.no_grad():
            for x, _ in batches:
                model(x)
        handle.remove()
        inputs = torch.cat(seen).float()
        layer.weight.data = gptq(layer.weight.data.float(), inputs, bits, group).to(
            layer.weight.dtype
        )


# snippet:begin kv
def quantised_kv(cache_update):
    def update(self, layer, k, v):
        def roundtrip(t):
            scale = t.abs().amax(-1, keepdim=True).clamp(min=1e-8) / 127
            return torch.round(t / scale).clamp(-127, 127) * scale

        return cache_update(self, layer, roundtrip(k), roundtrip(v))

    return update


# snippet:end kv


def kv_loss(model, batches) -> float:
    total, count = 0.0, 0
    with torch.no_grad():
        for x, y in batches:
            for row in range(len(x)):
                cache = gpt.KVCache(model.config, 1, x.shape[1], x.device)
                half = x.shape[1] // 2
                model(x[row : row + 1, :half], cache=cache)
                logits = model(x[row : row + 1, half:], cache=cache)
                loss = torch.nn.functional.cross_entropy(
                    logits[0].float(), y[row, half:], reduction="sum"
                )
                total += loss.item()
                count += y.shape[1] - half
    return total / count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    args = parser.parse_args()
    dev = device.device()
    if args.model.startswith("HuggingFaceTB/"):
        folder = data.model_files(args.model)
        model, tok = (
            gpt.from_huggingface(folder).to(dev).eval(),
            bpe.BPE.from_huggingface(folder / "tokenizer.json"),
        )

        def windows(text: str, count: int) -> list[tuple[torch.Tensor, torch.Tensor]]:
            ids = torch.tensor(tok.encode(text)[: count * 513], device=dev).view(count, 513)
            return [(ids[i : i + 8, :-1], ids[i : i + 8, 1:]) for i in range(0, count, 8)]

        valid = windows(data.tinystories("valid").read_text()[:400_000], 64)
        with data.tinystories("train").open() as f:
            calib = windows(f.read(200_000), 32)
    else:
        model = gpt.load(data.RUNS / args.model / "model.pt", dev).eval()
        folder = data.DATA / "tinystories"
        valid = train.TokenFile(folder / "valid-8192.bin", 512).fixed(64, dev)
        calib = train.TokenFile(folder / "train-8192.bin", 512).fixed(32, dev)
    base = train.evaluate(model, valid)
    params = sum(layer.weight.numel() for layer in linears(model))
    print(
        f"{args.model}: {params / 1e6:.1f}M parameters in its block matrices; validation loss {base:.4f} in float32"
    )
    print(f"{'weights':<30}{'bits/weight':>12}{'block MiB':>11}{'loss':>9}{'change':>9}")
    rows = [("float32", 32, base)]
    # snippet:begin variants
    variants = [
        ("int8, one scale per row", 8, None),
        ("int4, groups of 128", 4, 128),
        ("int4, groups of 32", 4, 32),
        ("int3, groups of 32", 3, 32),
        ("int4 GPTQ, groups of 128", 4, 128),
    ]
    for name, bits, group in variants:
        q = copy.deepcopy(model)
        if "GPTQ" in name:
            calibrate_and_quantise(q, calib, bits, group)
        else:
            for layer in linears(q):
                w = layer.weight.data
                layer.weight.data = round_to_nearest(w, bits, group or w.shape[1])
        loss = train.evaluate(q, valid)
        # snippet:end variants
        scales = sum(
            layer.weight.shape[0]
            * -(-layer.weight.shape[1] // (group or layer.weight.shape[1]))
            for layer in linears(model)
        )
        rows.append((name, bits + 32 * scales / params, loss))
        del q
    for name, per_weight, loss in rows:
        print(
            f"{name:<30}{per_weight:12.2f}{params * per_weight / 8 / 2**20:11.1f}{loss:9.4f}{loss - base:+9.4f}"
        )
    plain = kv_loss(model, valid[:2])
    original = gpt.KVCache.update
    gpt.KVCache.update = quantised_kv(original)
    quantised = kv_loss(model, valid[:2])
    gpt.KVCache.update = original
    print(
        f"KV cache in int8, one scale per head and position: second-half loss {plain:.4f} -> {quantised:.4f}"
    )
    results.save(
        f"u4-quantise-{args.model.split('/')[-1]}", {"rows": rows, "kv": [plain, quantised]}
    )
    gptq_loss = rows[-1][2]
    rtn_loss = rows[2][2]
    check.expect(
        "GPTQ beats rounding",
        gptq_loss <= rtn_loss + 1e-3,
        f"{gptq_loss:.4f} vs {rtn_loss:.4f}",
    )


if __name__ == "__main__":
    check.main(main)
