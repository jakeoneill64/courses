import argparse
import os
import sys
import time

import torch
import torch.distributed as dist
import torch.multiprocessing as mp
import torch.nn.functional as F

from aif import check, gpt, results

TINY = gpt.Config(
    vocab_size=512, d_model=128, n_layers=4, n_heads=4, n_kv_heads=2, d_ff=384, max_seq=64
)


# snippet:begin ring
def ring_all_reduce(t: torch.Tensor) -> None:
    world, rank = dist.get_world_size(), dist.get_rank()
    chunks = list(t.view(-1).tensor_split(world))
    right, left = (rank + 1) % world, (rank - 1) % world
    for step in range(world - 1):
        send, receive = (rank - step) % world, (rank - step - 1) % world
        incoming = torch.empty_like(chunks[receive])
        request = dist.isend(chunks[send].clone(), right)
        dist.recv(incoming, left)
        request.wait()
        chunks[receive] += incoming
    for step in range(world - 1):
        send, receive = (rank - step + 1) % world, (rank - step) % world
        incoming = torch.empty_like(chunks[receive])
        request = dist.isend(chunks[send].clone(), right)
        dist.recv(incoming, left)
        request.wait()
        chunks[receive].copy_(incoming)


# snippet:end ring


def batch(step: int, rows: int, seed: int = 0) -> torch.Tensor:
    g = torch.Generator().manual_seed(seed * 1000 + step)
    return torch.randint(0, TINY.vocab_size, (rows, TINY.max_seq + 1), generator=g)


def train_reference(steps: int, rows: int) -> list[torch.Tensor]:
    torch.manual_seed(0)
    model = gpt.GPT(TINY)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3)
    for step in range(steps):
        x = batch(step, rows)
        _, loss = model(x[:, :-1], x[:, 1:])
        opt.zero_grad()
        loss.backward()
        opt.step()
    return [p.detach().clone() for p in model.parameters()]


def experiment_allreduce(rank: int, world: int, out: dict) -> None:
    for n in (1 << 20, 1 << 24):
        t = torch.randn(n, generator=torch.Generator().manual_seed(rank))
        u = t.clone()
        start = time.perf_counter()
        ring_all_reduce(t)
        ring = time.perf_counter() - start
        start = time.perf_counter()
        dist.all_reduce(u)
        library = time.perf_counter() - start
        if rank == 0:
            out[f"allreduce {n}"] = (ring, library, (t - u).abs().max().item())


# snippet:begin data-parallel
def experiment_data_parallel(
    rank: int, world: int, out: dict, steps: int = 20, rows: int = 32
) -> None:
    torch.manual_seed(0)
    model = gpt.GPT(TINY)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3)
    share = rows // world
    start = time.perf_counter()
    for step in range(steps):
        x = batch(step, rows)[rank * share : (rank + 1) * share]
        _, loss = model(x[:, :-1], x[:, 1:])
        opt.zero_grad()
        loss.backward()
        flat = torch.cat([p.grad.view(-1) for p in model.parameters()])
        ring_all_reduce(flat)
        flat /= world
        offset = 0
        for p in model.parameters():
            p.grad.copy_(flat[offset : offset + p.numel()].view_as(p))
            offset += p.numel()
        opt.step()
    # snippet:end data-parallel
    if rank == 0:
        reference = train_reference(steps, rows)
        worst = max(
            (p.detach() - r).abs().max().item() for p, r in zip(model.parameters(), reference)
        )
        out["data parallel"] = (worst, time.perf_counter() - start)


# snippet:begin zero
def experiment_zero(rank: int, world: int, out: dict, steps: int = 20, rows: int = 32) -> None:
    torch.manual_seed(0)
    model = gpt.GPT(TINY)
    params = list(model.parameters())
    flat = torch.cat([p.detach().view(-1) for p in params])
    shard = flat.tensor_split(world)[rank].clone().requires_grad_()
    opt = torch.optim.AdamW([shard], lr=1e-3)
    sizes = [len(s) for s in flat.tensor_split(world)]
    share = rows // world
    for step in range(steps):
        x = batch(step, rows)[rank * share : (rank + 1) * share]
        _, loss = model(x[:, :-1], x[:, 1:])
        model.zero_grad()
        loss.backward()
        grads = torch.cat([p.grad.view(-1) for p in params])
        dist.all_reduce(grads)
        shard.grad = grads.tensor_split(world)[rank] / world
        opt.step()
        pieces = [torch.empty(n) for n in sizes]
        dist.all_gather(pieces, shard.detach())
        new = torch.cat(pieces)
        offset = 0
        with torch.no_grad():
            for p in params:
                p.copy_(new[offset : offset + p.numel()].view_as(p))
                offset += p.numel()
    # snippet:end zero
    state = sum(
        v.numel() * v.element_size()
        for s in opt.state.values()
        for v in s.values()
        if torch.is_tensor(v)
    )
    if rank == 0:
        reference = train_reference(steps, rows)
        worst = max((p.detach() - r).abs().max().item() for p, r in zip(params, reference))
        out["zero"] = (worst, state, flat.numel() * 8)


# snippet:begin tensor-parallel
def experiment_tensor_parallel(rank: int, world: int, out: dict) -> None:
    torch.manual_seed(0)
    full = gpt.SwiGLU(TINY)
    x = torch.randn(8, TINY.d_model, requires_grad=True)
    columns = torch.arange(TINY.d_ff).tensor_split(world)[rank]
    gate, up = full.gate.weight[columns], full.up.weight[columns]
    down = full.down.weight[:, columns]
    partial = F.linear(F.silu(F.linear(x, gate)) * F.linear(x, up), down)
    total = partial.clone()
    dist.all_reduce(total)
    # snippet:end tensor-parallel
    if rank == 0:
        out["tensor parallel"] = (total - full(x)).abs().max().item()


def experiment_pipeline(rank: int, world: int, out: dict, rows: int = 64) -> None:
    torch.manual_seed(0)
    model = gpt.GPT(
        gpt.Config(
            vocab_size=512,
            d_model=256,
            n_layers=8,
            n_heads=4,
            n_kv_heads=2,
            d_ff=768,
            max_seq=64,
        )
    )
    layers = model.blocks[rank * 4 : (rank + 1) * 4]
    cos, sin = model.cos, model.sin
    x = batch(0, rows)[:, :-1]
    timings = {}
    # snippet:begin pipeline
    for micro in (1, 2, 4, 8, 16):
        dist.barrier()
        start = time.perf_counter()
        for chunk in x.tensor_split(micro):
            if rank == 0:
                h = model.embed(chunk)
                for block in layers:
                    h = block(h, cos, sin)
                dist.send(h.detach(), 1)
            else:
                h = torch.empty(len(chunk), x.shape[1], 256)
                dist.recv(h, 0)
                for block in layers:
                    h = block(h, cos, sin)
        dist.barrier()
        timings[micro] = time.perf_counter() - start
    # snippet:end pipeline
    if rank == 0:
        out["pipeline"] = timings


def worker(rank: int, world: int, name: str, queue) -> None:
    os.environ.setdefault("MASTER_ADDR", "127.0.0.1")
    os.environ.setdefault("MASTER_PORT", "29517")
    os.environ.setdefault("GLOO_SOCKET_IFNAME", "lo0" if sys.platform == "darwin" else "lo")
    torch.set_num_threads(1)
    dist.init_process_group("gloo", rank=rank, world_size=world)
    out = {}
    {
        "allreduce": experiment_allreduce,
        "dp": experiment_data_parallel,
        "zero": experiment_zero,
        "tp": experiment_tensor_parallel,
        "pp": experiment_pipeline,
    }[name](rank, world, out)
    if rank == 0:
        queue.put(out)
    dist.destroy_process_group()


def run(name: str, world: int) -> dict:
    ctx = mp.get_context("spawn")
    queue = ctx.Queue()
    mp.start_processes(worker, args=(world, name, queue), nprocs=world, start_method="spawn")
    return queue.get()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--world", type=int, default=4)
    args = parser.parse_args()
    w = args.world
    r = run("allreduce", w)
    for n in (1 << 20, 1 << 24):
        ring, library, difference = r[f"allreduce {n}"]
        print(
            f"all-reduce of {n * 4 / 2**20:.0f} MiB, {w} processes: ring {ring * 1e3:6.1f} ms, "
            f"gloo {library * 1e3:6.1f} ms, difference {difference:.1e}"
        )
        check.expect("the ring matches gloo", difference < 1e-5, f"{difference:.1e}")
    dp_worst, seconds = run("dp", w)["data parallel"]
    print(
        f"data parallel, {w} processes, 20 steps: parameters within {dp_worst:.1e} of one process"
    )
    zero_worst, state, unsharded = run("zero", w)["zero"]
    print(
        f"ZeRO stage 1: Adam's state {state / 2**10:,.0f} KiB per process, not "
        f"{unsharded / 2**10:,.0f} KiB; parameters within {zero_worst:.1e}"
    )
    print(
        f"tensor-parallel SwiGLU across {w} processes: largest difference from the whole layer "
        f"{run('tp', w)['tensor parallel']:.1e}"
    )
    timings = run("pp", 2)["pipeline"]
    base = timings[1]
    print("pipeline of two stages, 64 sequences split into micro-batches:")
    print(f"{'micro-batches':>15}{'ms':>8}{'speed-up':>10}{'idle in theory':>16}")
    for micro, t in timings.items():
        print(f"{micro:15d}{t * 1e3:8.0f}{base / t:9.2f}x{1 / (micro + 1):16.0%}")
    results.save("u4-parallel", {"pipeline": timings})
    check.expect("data parallel matches", dp_worst < 1e-4, f"{dp_worst:.1e}")
    check.expect("ZeRO matches", zero_worst < 1e-4, f"{zero_worst:.1e}")


if __name__ == "__main__":
    check.main(main)
