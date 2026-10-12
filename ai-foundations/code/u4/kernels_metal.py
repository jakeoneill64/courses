import argparse
import math
from pathlib import Path

import torch
import torch.nn.functional as F

from aif import check, device, results
from aif.timing import median_time


def up(x: int, multiple: int) -> int:
    return (x + multiple - 1) // multiple * multiple


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sizes", type=int, nargs="+", default=[1024, 2048, 4096])
    parser.add_argument("--lengths", type=int, nargs="+", default=[512, 1024, 2048, 4096])
    args = parser.parse_args()
    dev = device.device()
    device.seed(0)
    check.expect(
        "a Metal device",
        dev.type == "mps",
        "this track needs Apple's GPU; see the Vulkan track",
    )
    # snippet:begin compile
    lib = torch.mps.compile_shader((Path(__file__).parent / "kernels.metal").read_text())
    # snippet:end compile
    record = {"matmul": [], "attention": []}
    print(
        f"{'matrix product':<20}"
        + "".join(f"{f'n = {n}':>13}" for n in args.sizes)
        + "   (GFLOP/s)"
    )
    rows = {"naive": [], "tiled": [], "register-blocked": [], "PyTorch (MPS)": []}
    for n in args.sizes:
        a = torch.randn(n, n, device=dev)
        b = torch.randn(n, n, device=dev)
        want = a @ b
        # snippet:begin launch
        c = torch.empty(n, n, device=dev)
        launches = {
            "naive": lambda: lib.matmul_naive(
                a, b, c, n, n, n, threads=(n, n), group_size=(16, 16)
            ),
            "tiled": lambda: lib.matmul_tiled(
                a, b, c, n, n, n, threads=(up(n, 16), up(n, 16)), group_size=(16, 16)
            ),
            "register-blocked": lambda: lib.matmul_blocked(
                a, b, c, n, n, n, threads=(up(n, 64) // 4, up(n, 64) // 4), group_size=(16, 16)
            ),
            "PyTorch (MPS)": lambda: torch.mm(a, b, out=c),
        }
        # snippet:end launch
        for name, launch in launches.items():
            c.zero_()
            launch()
            check.close(
                f"{name} at n = {n}",
                c.cpu().numpy()[:64, :64],
                want.cpu().numpy()[:64, :64],
                rtol=1e-3,
                atol=1e-2,
            )
            seconds = median_time(launch, runs=10, dev=dev)
            rows[name].append(2 * n**3 / seconds / 1e9)
    for name, rates in rows.items():
        print(f"{name:<20}" + "".join(f"{r:13,.0f}" for r in rates))
        record["matmul"].append({"name": name, "rates": rates})

    # snippet:begin softmax-launch
    x = torch.randn(4096, 8192, device=dev) * 4
    y = torch.empty_like(x)
    ours = lambda: lib.softmax_rows(x, y, x.shape[1], threads=x.shape[0] * 256, group_size=256)
    # snippet:end softmax-launch
    ours()
    check.close(
        "softmax",
        y.cpu()[:8].numpy(),
        torch.softmax(x, -1).cpu()[:8].numpy(),
        rtol=1e-4,
        atol=1e-7,
    )
    gb = 2 * x.numel() * 4 / 1e9
    print(
        f"softmax over 4,096 rows of 8,192: yours {gb / median_time(ours, dev=dev):.0f} GB/s, PyTorch's "
        f"{gb / median_time(lambda: torch.softmax(x, -1), dev=dev):.0f} GB/s"
    )

    heads, d = 8, 64
    print(f"causal attention, {heads} heads of {d}: milliseconds")
    print(
        f"{'length':>8}{'materialised':>14}{'flash, yours':>14}{'PyTorch SDPA':>14}{'scores held':>14}"
    )
    for length in args.lengths:
        q, k, v = (torch.randn(heads, length, d, device=dev) for _ in range(3))
        out = torch.empty_like(q)
        # snippet:begin attention
        mask = torch.ones(length, length, dtype=torch.bool, device=dev).tril()

        def materialised():
            scores = (q @ k.transpose(-1, -2)) / math.sqrt(d)
            return scores.masked_fill(~mask, float("-inf")).softmax(-1) @ v

        flash = lambda: lib.flash_attention(
            q,
            k,
            v,
            out,
            length,
            1 / math.sqrt(d),
            threads=(up(length, 64), heads),
            group_size=(64, 1),
        )
        sdpa = lambda: F.scaled_dot_product_attention(q, k, v, is_causal=True)
        # snippet:end attention
        flash()
        want = sdpa()
        check.close(
            f"flash attention at {length}",
            out.cpu().numpy(),
            want.cpu().numpy(),
            rtol=1e-3,
            atol=1e-4,
        )
        times = [median_time(f, runs=5, dev=dev) * 1e3 for f in (materialised, flash, sdpa)]
        held = heads * length * length * 4 / 2**20
        print(f"{length:8d}" + "".join(f"{t:14.1f}" for t in times) + f"{held:11.0f} MiB")
        record["attention"].append({"length": length, "times": times})
    results.save("u4-kernels-metal", record)


if __name__ == "__main__":
    check.main(main)
