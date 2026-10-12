import argparse
import time

import torch

from aif import check, device, gpt, results
from u2.common import tinystories_model


# snippet:begin bytes
def cache_bytes(
    layers: int, kv_heads: int, head_dim: int, tokens: int, bytes_per_value: int
) -> int:
    return 2 * layers * kv_heads * head_dim * tokens * bytes_per_value


# snippet:end bytes


@torch.no_grad()
def timed_generation(
    model, prompt: list[int], new: int, use_cache: bool, dev
) -> tuple[list[int], list[float]]:
    ids = torch.tensor([prompt], device=dev)
    cache = gpt.KVCache(model.config, 1, len(prompt) + new, dev) if use_cache else None
    times, out = [], []
    logits = model(ids, cache=cache)[:, -1]
    for _ in range(new):
        start = time.perf_counter()
        token = logits.argmax(-1, keepdim=True)
        out.append(int(token))
        if use_cache:
            logits = model(token, cache=cache)[:, -1]
        else:
            ids = torch.cat([ids, token], dim=1)
            logits = model(ids)[:, -1]
        device.sync(dev)
        times.append(time.perf_counter() - start)
    return out, times


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="tinystories-28m")
    args = parser.parse_args()
    dev = device.device()
    devices = [dev] + ([torch.device("cpu")] if dev.type != "cpu" else [])
    record = {}
    for d in devices:
        model, tok = tinystories_model(d, args.model)
        prompt = tok.encode("Once upon a time")
        new = model.config.max_seq - len(prompt)
        for use_cache in (True, False):
            timed_generation(model, prompt, 16, use_cache, d)
        # snippet:begin compare
        with_cache, t_cache = timed_generation(model, prompt, new, True, d)
        without, t_plain = timed_generation(model, prompt, new, False, d)
        # snippet:end compare
        check.expect(f"identical greedy output on {d.type}", with_cache == without)
        if not record:
            print(
                f"greedy generation of {new} tokens; identical output with and without the cache"
            )
        for label, times in (("without the cache", t_plain), ("with the cache", t_cache)):
            print(
                f"  {d.type:<4} {label:<18} {sum(times):6.2f} s; first 50 tokens "
                f"{1e3 * sum(times[:50]) / 50:5.1f} ms each, last 50 {1e3 * sum(times[-50:]) / 50:5.1f} ms"
            )
        record[d.type] = {"cache": t_cache, "plain": t_plain}
    c = model.config
    print("KV-cache size for one sequence:")
    for name, layers, kv, hd, tokens, size in (
        ("this model, 512 tokens, float32", c.n_layers, c.n_kv_heads, c.head_dim, 512, 4),
        ("SmolLM2-1.7B, 8,192 tokens, bfloat16", 24, 32, 64, 8192, 2),
        ("a 70B model with 8 KV heads, 128K tokens, bfloat16", 80, 8, 128, 131072, 2),
    ):
        print(f"  {name:<52} {cache_bytes(layers, kv, hd, tokens, size) / 2**20:10,.1f} MiB")
    results.save("u2-kvcache", record)


if __name__ == "__main__":
    check.main(main)
