import argparse
import os
import platform
import subprocess
import sys
import time

import numpy as np
import torch

from . import check, data, device


def processor() -> str:
    if sys.platform == "darwin":
        out = subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True
        )
        return out.stdout.strip() or platform.machine()
    if os.path.exists("/proc/cpuinfo"):
        for line in open("/proc/cpuinfo"):
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor() or platform.machine()


def memory_gib() -> float:
    return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 2**30


def throughput(dev: torch.device, n: int = 2048) -> float:
    a = torch.randn(n, n, device=dev)
    b = torch.randn(n, n, device=dev)
    for _ in range(3):
        a @ b
    device.sync(dev)
    start = time.perf_counter()
    for _ in range(10):
        a @ b
    device.sync(dev)
    return 2 * n**3 * 10 / (time.perf_counter() - start) / 1e12


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check that the course's tools work on this machine."
    )
    parser.add_argument(
        "--download", action="store_true", help="also download MNIST and CIFAR-10"
    )
    args = parser.parse_args()
    # snippet:begin report
    print(
        f"Python {sys.version.split()[0]}, NumPy {np.__version__}, PyTorch {torch.__version__}"
    )
    print(
        f"machine: {processor()}, {memory_gib():.0f} GiB of memory, "
        f"{platform.system()} {platform.release()} on {platform.machine()}"
    )
    dev = device.device()
    if dev.type == "cuda":
        name = torch.cuda.get_device_name()
    elif dev.type == "mps":
        name = f"the GPU of the {processor()}, through Metal"
    else:
        name = "no GPU found: the course runs, slowly, on the CPU"
    print(f"device: {dev.type} ({name})")
    # snippet:end report

    a = np.random.default_rng(0).normal(size=(256, 256)).astype(np.float32)
    want = a.astype(np.float64) @ a.astype(np.float64)
    for d in dict.fromkeys([torch.device("cpu"), dev]):
        got = (torch.from_numpy(a).to(d) @ torch.from_numpy(a).to(d)).cpu().numpy()
        check.close(f"matrix product on {d.type}", got, want, rtol=1e-3, atol=1e-3)
        print(
            f"matrix product on {d.type}: correct, {throughput(d):.2f} TFLOP/s at 2048 x 2048"
        )

    x = torch.tensor([1.0, 2.0, 3.0], requires_grad=True, device=dev)
    (x**2).sum().backward()
    check.close("autograd", x.grad.cpu(), [2.0, 4.0, 6.0])
    print("autograd: correct")

    for label, folder in (("data", data.DATA), ("runs", data.RUNS)):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ".write-test").write_text("ok")
        (folder / ".write-test").unlink()
        print(f"{label} folder: {os.path.relpath(folder)} (writable)")
    if args.download:
        for name, fn in (("MNIST", data.mnist), ("CIFAR-10", data.cifar10)):
            arrays = fn()
            print(
                f"{name}: {len(arrays['x_train']):,} training and {len(arrays['x_test']):,} test images"
            )
    print("self-test passed")


if __name__ == "__main__":
    check.main(main)
