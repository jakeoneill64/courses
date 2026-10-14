import torch
import torch.nn.functional as F

from aif import check, device, gpt, results
from aif.timing import median_time


def main() -> None:
    dev = device.device()
    device.seed(0)
    # snippet:begin peaks
    a = torch.empty(64 * 2**20, device=dev)
    b = torch.empty_like(a)
    seconds = median_time(lambda: b.copy_(a), runs=20, dev=dev)
    bandwidth = 2 * a.numel() * 4 / seconds / 1e9
    x, y = torch.randn(4096, 4096, device=dev), torch.randn(4096, 4096, device=dev)
    peak = 2 * 4096**3 / median_time(lambda: x @ y, runs=20, dev=dev) / 1e9
    # snippet:end peaks
    print(
        f"{dev.type}: copying 256 MiB runs at {bandwidth:.0f} GB/s; a 4096 x 4096 product at {peak:,.0f} GFLOP/s"
    )
    print(f"ridge point: {peak / bandwidth:.0f} FLOP per byte")

    c = gpt.Config()
    B, T, d, H, hd, ff, V = 32, 512, c.d_model, c.n_heads, c.head_dim, c.d_ff, c.vocab_size
    N = B * T
    h = torch.randn(N, d, device=dev)
    w_qkv = torch.randn(d, (H + 2 * c.n_kv_heads) * hd, device=dev)
    w_o, w_up, w_down = (
        torch.randn(d, d, device=dev),
        torch.randn(d, 2 * ff, device=dev),
        torch.randn(ff, d, device=dev),
    )
    w_head = torch.randn(d, V, device=dev)
    q, k, v = (torch.randn(B, H, T, hd, device=dev) for _ in range(3))
    gate, up = torch.randn(N, ff, device=dev), torch.randn(N, ff, device=dev)
    weight = torch.ones(d, device=dev)
    logits = torch.randn(N, V, device=dev)
    targets = torch.randint(0, V, (N,), device=dev)
    # snippet:begin ops
    ops = {
        "q, k, v projection": (
            lambda: h @ w_qkv,
            2 * N * d * w_qkv.shape[1],
            4 * (N * d + w_qkv.numel() + N * w_qkv.shape[1]),
        ),
        "attention (SDPA)": (
            lambda: F.scaled_dot_product_attention(q, k, v, is_causal=True),
            2 * B * H * T * T * hd,
            4 * 4 * B * H * T * hd,
        ),
        "output projection": (lambda: h @ w_o, 2 * N * d * d, 4 * (2 * N * d + d * d)),
        "gate and up": (
            lambda: h @ w_up,
            2 * N * d * 2 * ff,
            4 * (N * d + d * 2 * ff + N * 2 * ff),
        ),
        "SiLU(gate) * up": (lambda: F.silu(gate) * up, 6 * N * ff, 4 * 3 * N * ff),
        "down projection": (
            lambda: gate @ w_down,
            2 * N * ff * d,
            4 * (N * ff + ff * d + N * d),
        ),
        "RMSNorm": (lambda: F.rms_norm(h, (d,), weight), 4 * N * d, 4 * 2 * N * d),
        "residual add": (lambda: h + h, N * d, 4 * 3 * N * d),
        "logits": (lambda: h @ w_head, 2 * N * d * V, 4 * (N * d + d * V + N * V)),
        "cross-entropy": (lambda: F.cross_entropy(logits, targets), 5 * N * V, 4 * N * V),
    }
    # snippet:end ops
    print(f"one layer of the Chapter 2.5 model, batch {B} x {T} tokens, float32:")
    print(
        f"{'operation':<20}{'GFLOP':>8}{'MB':>8}{'FLOP/B':>8}{'ms':>8}{'GFLOP/s':>9}{'GB/s':>7}   bound"
    )
    rows = []
    for name, (fn, flops, bytes_) in ops.items():
        seconds = median_time(fn, runs=10, dev=dev)
        intensity = flops / bytes_
        limit = min(peak, intensity * bandwidth)
        achieved = flops / seconds / 1e9
        rows.append(
            {"name": name, "intensity": intensity, "gflops": achieved, "ms": seconds * 1e3}
        )
        kind = "memory" if intensity * bandwidth < peak else "compute"
        print(
            f"{name:<20}{flops / 1e9:8.2f}{bytes_ / 1e6:8.0f}{intensity:8.1f}{seconds * 1e3:8.2f}"
            f"{achieved:9.0f}{bytes_ / seconds / 1e9:7.0f}   {kind}, {achieved / limit:4.0%} of it"
        )
    results.save("u4-roofline", {"bandwidth": bandwidth, "peak": peak, "ops": rows})
    check.expect("measurements are positive", bandwidth > 0 and peak > 0)


if __name__ == "__main__":
    check.main(main)
