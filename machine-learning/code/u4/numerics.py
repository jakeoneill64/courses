import math

import torch

from aif import check, device
from aif.timing import median_time

FORMATS = (
    ("float32", torch.float32),
    ("float16", torch.float16),
    ("bfloat16", torch.bfloat16),
)


def main() -> None:
    device.seed(0)
    # snippet:begin formats
    print(
        f"{'format':<10}{'bits':>5}{'mantissa':>10}{'largest':>12}"
        f"{'smallest normal':>17}{'epsilon':>11}"
    )
    for name, dtype in FORMATS + (
        ("fp8 e4m3", torch.float8_e4m3fn),
        ("fp8 e5m2", torch.float8_e5m2),
    ):
        info = torch.finfo(dtype)
        mantissa = round(-math.log2(info.eps))
        print(
            f"{name:<10}{info.bits:5d}{mantissa:10d}{info.max:12.3g}"
            f"{info.tiny:17.3g}{info.eps:11.3g}"
        )
    # snippet:end formats

    # snippet:begin summation
    print("adding 0.0001 to a running total 100,000 times (exact answer 10):")
    for name, dtype in FORMATS:
        total, step = torch.zeros((), dtype=dtype), torch.tensor(1e-4, dtype=dtype)
        for _ in range(100_000):
            total = total + step
        wide = torch.full((100_000,), 1e-4, dtype=dtype).sum(dtype=torch.float32)
        print(
            f"  {name:<9} total kept in {name}: {float(total):8.4f}; "
            f"accumulated in float32: {float(wide):8.4f}"
        )
    # snippet:end summation

    # snippet:begin overflow
    half = torch.finfo(torch.float16).max
    print(
        f"float16 overflows above {half:,.0f}: "
        f"exp(11) = {float(torch.tensor(11.0).half().exp()):,.0f}, "
        f"exp(12) = {float(torch.tensor(12.0).half().exp())}"
    )
    x = torch.randn(4096) * 300
    print(
        f"mean square of 4,096 activations of size about 300: "
        f"{float((x**2).mean()):,.0f} in float32, "
        f"{float((x.half() ** 2).mean())} in float16"
    )
    # snippet:end overflow

    # snippet:begin underflow
    grads = torch.tensor([3e-4, 2e-6, 4e-8, 1e-9])
    print(
        "gradients 3e-4, 2e-6, 4e-8, 1e-9 stored in float16:   ",
        ", ".join(f"{float(g):.1e}" for g in grads.half()),
    )
    print(
        "the same gradients scaled by 1024, stored, unscaled:",
        ", ".join(f"{float(g) / 1024:.1e}" for g in (grads * 1024).half()),
    )
    # snippet:end underflow

    torch.manual_seed(0)
    a, b = torch.randn(512, 512), torch.randn(512, 512)
    exact = a.double() @ b.double()
    print("relative error of a 512 x 512 matrix product against float64:")
    for name, dtype in FORMATS:
        err = ((a.to(dtype) @ b.to(dtype)).double() - exact).norm() / exact.norm()
        print(f"  {name:<9} {float(err):.1e}")
    # snippet:begin fp8
    scale_a, scale_b = a.abs().max() / 448, b.abs().max() / 448
    a8 = (a / scale_a).to(torch.float8_e4m3fn)
    b8 = (b / scale_b).to(torch.float8_e4m3fn)
    product = (a8.float() @ b8.float()) * scale_a * scale_b
    # snippet:end fp8
    fp8 = float((product.double() - exact).norm() / exact.norm())
    print(
        f"  {'fp8 e4m3':<9} {fp8:.1e} (inputs scaled into range, products accumulated in float32)"
    )

    dev = device.device()
    if dev.type != "cpu":
        n = 4096
        print(f"matrix product of {n} x {n} on the {dev.type} device:")
        for name, dtype in FORMATS:
            x, y = (
                torch.randn(n, n, device=dev, dtype=dtype),
                torch.randn(n, n, device=dev, dtype=dtype),
            )
            seconds = median_time(lambda: x @ y, runs=20, dev=dev)
            print(f"  {name:<9} {2 * n**3 / seconds / 1e12:5.2f} TFLOP/s")
    check.expect("fp8 is coarser than bfloat16", fp8 > 1e-3)


if __name__ == "__main__":
    check.main(main)
