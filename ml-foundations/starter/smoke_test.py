"""Checks the environment can train on the CPU and on MPS, and measures the speedup."""

import platform
import time

import numpy as np
import sklearn
import torch
import torch.nn as nn
import torch.nn.functional as F


def make_data(n: int = 8192, seed: int = 0) -> tuple[torch.Tensor, torch.Tensor]:
    g = torch.Generator().manual_seed(seed)
    x = torch.rand(n, 2, generator=g) * 4 - 2
    y = ((x[:, 0] ** 2 + x[:, 1] ** 2) < 2.0).long()
    return x, y


def train_mlp(device: str, steps: int = 300, width: int = 512) -> tuple[float, float, float]:
    torch.manual_seed(0)
    x, y = make_data()
    x, y = x.to(device), y.to(device)
    model = nn.Sequential(
        nn.Linear(2, width), nn.ReLU(), nn.Linear(width, width), nn.ReLU(), nn.Linear(width, 2)
    ).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    with torch.no_grad():
        first = F.cross_entropy(model(x), y).item()
    if device == "mps":
        torch.mps.synchronize()
    t0 = time.perf_counter()
    for _ in range(steps):
        loss = F.cross_entropy(model(x), y)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
    if device == "mps":
        torch.mps.synchronize()
    elapsed = time.perf_counter() - t0
    return first, loss.item(), elapsed


def conv_forward(device: str, dtype: torch.dtype | None) -> float:
    torch.manual_seed(0)
    net = nn.Sequential(
        nn.Conv2d(3, 64, 3, padding=1), nn.ReLU(),
        nn.Conv2d(64, 128, 3, padding=1), nn.ReLU(),
        nn.AdaptiveAvgPool2d(1), nn.Flatten(), nn.Linear(128, 10),
    ).to(device)
    x = torch.randn(256, 3, 32, 32, device=device)
    if device == "mps":
        torch.mps.synchronize()
    t0 = time.perf_counter()
    with torch.no_grad():
        for _ in range(20):
            if dtype is None:
                net(x)
            else:
                with torch.autocast(device_type=device, dtype=dtype):
                    net(x)
    if device == "mps":
        torch.mps.synchronize()
    return (time.perf_counter() - t0) / 20


def main() -> None:
    print(f"python      {platform.python_version()}  ({platform.machine()})")
    print(f"numpy       {np.__version__}")
    print(f"scikit-learn {sklearn.__version__}")
    print(f"torch       {torch.__version__}")
    has_mps = torch.backends.mps.is_available()
    print(f"mps available: {has_mps}")

    results = {}
    for device in ["cpu"] + (["mps"] if has_mps else []):
        first, last, secs = train_mlp(device)
        results[device] = secs
        ok = last < 0.3 * first
        print(f"[{device}] MLP loss {first:.3f} -> {last:.3f} in {secs:.2f}s  {'OK' if ok else 'FAILED to learn'}")
        assert ok, f"loss did not fall on {device}"

    if has_mps:
        print(f"MLP speedup mps/cpu: {results['cpu'] / results['mps']:.1f}x")
        fp32 = conv_forward("mps", None)
        fp16 = conv_forward("mps", torch.float16)
        print(f"[mps] conv forward fp32 {fp32 * 1000:.1f} ms, fp16 autocast {fp16 * 1000:.1f} ms")
        try:
            conv_forward("mps", torch.bfloat16)
            print("[mps] bfloat16 autocast: available")
        except (RuntimeError, TypeError) as e:
            print(f"[mps] bfloat16 autocast: not available ({type(e).__name__})")
        try:
            torch.zeros(1, dtype=torch.float64, device="mps")
            print("[mps] float64: available")
        except TypeError:
            print("[mps] float64: not supported (expected; keep tensors float32)")

    try:
        import mlflow

        mlflow.set_tracking_uri("file:./mlruns")
        mlflow.set_experiment("00-setup")
        with mlflow.start_run(run_name="smoke-test"):
            mlflow.log_params({"steps": 300, "width": 512})
            for device, secs in results.items():
                mlflow.log_metric(f"seconds_{device}", secs)
        print("mlflow run logged to ./mlruns")
    except ImportError:
        print("mlflow not installed; skipping tracking check")

    print("smoke test passed")


if __name__ == "__main__":
    main()
