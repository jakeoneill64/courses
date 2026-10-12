import argparse
import asyncio
import json
import time

import numpy as np
import pyarrow.parquet as pq
import torch

from aif import bpe, chat, check, data, device, gpt, results, sample, serving

TARGET = "HuggingFaceTB/SmolLM2-360M-Instruct"


def prompts(tok, count: int) -> list[list[int]]:
    rows = pq.read_table(
        data.fetch("HuggingFaceTB/smol-smoltalk", "data/test-00000-of-00001.parquet"),
        columns=["messages"],
    ).to_pylist()
    out = []
    for r in rows:
        first = next(m for m in r["messages"] if m["role"] == "user")
        ids = tok.encode(chat.render([first]))
        if len(ids) <= 384:
            out.append(ids)
        if len(out) == count:
            return out
    return out


def load(name: str, dev, half: bool = True):
    folder = data.model_files(name)
    dtype = torch.float16 if half and dev.type != "cpu" else torch.float32
    return gpt.from_huggingface(folder, dtype=dtype).to(dev).eval(), bpe.BPE.from_huggingface(
        folder / "tokenizer.json"
    )


# snippet:begin load-test
def benchmark(
    model, tok, ids, rate: float, max_batch: int, continuous: bool, max_new: int
) -> dict:
    arrivals = np.cumsum(np.random.default_rng(0).exponential(1 / rate, len(ids)))
    requests = [
        serving.Sequence(prompt=p, max_new=max_new, arrival=float(a))
        for p, a in zip(ids, arrivals)
    ]
    cache = serving.PagedCache(model, blocks=2048, block_size=16)
    makespan = serving.run(
        model, cache, requests, tok.special[chat.END], max_batch, continuous
    )
    ttft = np.array([r.first - r.arrival for r in requests])
    per_token = np.array([(r.finish - r.first) / max(1, len(r.out) - 1) for r in requests])
    generated = sum(len(r.out) for r in requests)
    return {
        "throughput": generated / makespan,
        "ttft": float(ttft.mean()),
        "ttft90": float(np.percentile(ttft, 90)),
        "itl": float(per_token.mean()),
        "makespan": makespan,
    }


# snippet:end load-test


async def handle(reader, writer, model, tok, queue) -> None:
    request = (await reader.readuntil(b"\r\n\r\n")).decode()
    length = int(
        next(
            (
                line.split(":")[1]
                for line in request.split("\r\n")
                if line.lower().startswith("content-length")
            ),
            0,
        )
    )
    body = json.loads((await reader.readexactly(length)).decode() or "{}")
    seq = serving.Sequence(
        prompt=tok.encode(chat.render([{"role": "user", "content": body.get("prompt", "")}])),
        max_new=int(body.get("max_tokens", 128)),
    )
    seq.sink = asyncio.Queue()
    await queue.put(seq)
    writer.write(
        b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n\r\n"
    )
    while (token := await seq.sink.get()) is not None:
        writer.write(f"data: {json.dumps({'text': tok.decode([token])})}\n\n".encode())
        await writer.drain()
    writer.write(b"data: [DONE]\n\n")
    await writer.drain()
    writer.close()


def agreement(model, tok, ids, max_new: int) -> int:
    stop = tok.special[chat.END]
    seqs = [serving.Sequence(prompt=p, max_new=max_new) for p in ids]
    serving.run(model, serving.PagedCache(model, blocks=512), seqs, stop, len(seqs))
    alone = [sample.generate(model, p, max_new, stop=stop, temperature=0.0) for p in ids]
    return sum(s.out == a for s, a in zip(seqs, alone))


# snippet:begin http
async def scheduler(model, tok, queue, max_batch: int = 16) -> None:
    cache = serving.PagedCache(model, blocks=2048)
    stop, running = tok.special[chat.END], []
    dev = next(model.parameters()).device
    while True:
        while not queue.empty() and len(running) < max_batch:
            seq = queue.get_nowait()
            seq.blocks = [
                cache.free.pop()
                for _ in range(cache.blocks_for(len(seq.prompt) + seq.max_new))
            ]
            seq.out.append(int(serving.prefill(model, cache, seq).argmax()))
            seq.sink.put_nowait(seq.out[-1])
            running.append(seq)
        if not running:
            seq = await queue.get()
            await queue.put(seq)
            continue
        logits = serving.decode_step(
            model, cache, running, torch.tensor([s.out[-1] for s in running], device=dev)
        )
        for s, t in zip(running, logits.argmax(-1).tolist()):
            s.out.append(t)
            if t != stop:
                s.sink.put_nowait(t)
        for s in [s for s in running if s.out[-1] == stop or len(s.out) >= s.max_new]:
            s.sink.put_nowait(None)
            cache.free += s.blocks
            running.remove(s)
        await asyncio.sleep(0)


# snippet:end http


async def serve_http(port: int, dev) -> None:
    model, tok = load(TARGET, dev)
    queue = asyncio.Queue()
    asyncio.get_running_loop().create_task(scheduler(model, tok, queue))
    server = await asyncio.start_server(
        lambda r, w: handle(r, w, model, tok, queue), "127.0.0.1", port
    )
    print(f"serving {TARGET} on http://127.0.0.1:{port}/generate", flush=True)
    async with server:
        await server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--http", type=int, help="serve on this port instead of running the benchmarks"
    )
    parser.add_argument("--requests", type=int, default=48)
    parser.add_argument("--rate", type=float, default=2.0, help="requests per second")
    parser.add_argument("--max-new", type=int, default=128)
    args = parser.parse_args()
    dev = device.device()
    if args.http:
        asyncio.run(serve_http(args.http, dev))
        return
    model, tok = load(TARGET, dev)
    ids = prompts(tok, args.requests)
    record = {}
    print(
        f"{args.requests} chat requests at {args.rate:g} per second, up to {args.max_new} tokens each, "
        f"{TARGET.split('/')[1]} in float16:"
    )
    print(
        f"{'policy':<28}{'tokens/s':>9}{'TTFT mean':>11}{'TTFT p90':>10}{'ms/token':>10}{'makespan':>10}"
    )
    for name, batch, continuous in (
        ("one at a time", 1, True),
        ("static batches of 16", 16, False),
        ("continuous batching, 16", 16, True),
    ):
        r = benchmark(model, tok, ids, args.rate, batch, continuous, args.max_new)
        record[name] = r
        print(
            f"{name:<28}{r['throughput']:9.0f}{r['ttft']:10.2f}s{r['ttft90']:9.2f}s{r['itl'] * 1e3:10.1f}"
            f"{r['makespan']:9.1f}s",
            flush=True,
        )

    same16 = agreement(model, tok, ids[:8], args.max_new)
    del model
    model, _ = load(TARGET, dev, half=False)
    same32 = agreement(model, tok, ids[:8], args.max_new)
    del model
    print(
        f"batched and one-at-a-time greedy decoding agree on {same16}/8 prompts in float16, "
        f"{same32}/8 in float32"
    )
    record["agreement"] = {"float16": same16, "float32": same32}
    check.expect(
        "batched decoding in float32 matches one at a time", same32 == 8, f"{same32}/8"
    )
    target, tok = load("HuggingFaceTB/SmolLM2-1.7B-Instruct", dev, half=False)
    draft, _ = load("HuggingFaceTB/SmolLM2-135M-Instruct", dev, half=False)
    stop = tok.special[chat.END]
    tests = ids[:8]
    start = time.perf_counter()
    plain = [
        sample.generate(target, p, args.max_new, stop=stop, temperature=0.0) for p in tests
    ]
    device.sync(dev)
    base = sum(len(o) for o in plain) / (time.perf_counter() - start)
    print(
        "speculative decoding in float32: SmolLM2-1.7B-Instruct drafted by SmolLM2-135M-Instruct"
    )
    print(f"  target alone: {base:5.1f} tokens/s")
    for k in (2, 4, 6):
        start, rounds, accepted = time.perf_counter(), 0, 0
        for p, want in zip(tests, plain):
            got, r = serving.speculative(target, draft, p, args.max_new, k, stop)
            check.expect(
                f"speculative output with k = {k}",
                got == want,
                "differs from the target's own output",
            )
            rounds += r
            accepted += len(got) - r
        rate = sum(len(o) for o in plain) / (time.perf_counter() - start)
        print(
            f"  k = {k}: {rate:5.1f} tokens/s ({rate / base:.2f}x), "
            f"{accepted / (rounds * k):.0%} of drafted tokens accepted, output identical"
        )
        record[f"speculative {k}"] = {"rate": rate, "accepted": accepted / (rounds * k)}
    results.save("u4-serve", record)


if __name__ == "__main__":
    check.main(main)
