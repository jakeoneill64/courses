import time

import torch
import torch.utils.checkpoint as ckpt

from aif import check, device, gpt, results


def step_parts(model, opt, x, y, dev) -> tuple[float, float, float]:
    device.sync(dev)
    t0 = time.perf_counter()
    _, loss = model(x, y)
    device.sync(dev)
    t1 = time.perf_counter()
    loss.backward()
    device.sync(dev)
    t2 = time.perf_counter()
    opt.step()
    opt.zero_grad(set_to_none=True)
    device.sync(dev)
    return t1 - t0, t2 - t1, time.perf_counter() - t2


# snippet:begin hooks
def module_times(model, x, dev, runs: int = 5) -> dict[str, float]:
    times, starts = {}, {}

    def before(name):
        def hook(module, args):
            device.sync(dev)
            starts[name] = time.perf_counter()

        return hook

    def after(name):
        def hook(module, args, out):
            device.sync(dev)
            times[name] = times.get(name, 0.0) + time.perf_counter() - starts[name]

        return hook

    handles = []
    for name, module in (
        ("embedding", model.embed),
        ("final norm", model.norm),
        ("logits", model.head),
    ):
        handles += [
            module.register_forward_pre_hook(before(name)),
            module.register_forward_hook(after(name)),
        ]
    for block in model.blocks:
        for name, module in (
            ("attention", block.attn),
            ("feed-forward", block.mlp),
            ("norms", block.attn_norm),
            ("norms", block.mlp_norm),
        ):
            handles += [
                module.register_forward_pre_hook(before(name)),
                module.register_forward_hook(after(name)),
            ]
    with torch.no_grad():
        for _ in range(runs):
            model(x)
    for h in handles:
        h.remove()
    return {k: v / runs for k, v in times.items()}


# snippet:end hooks


# snippet:begin checkpointing
class Checkpointed(torch.nn.Module):
    def __init__(self, block):
        super().__init__()
        self.block = block

    def forward(self, x, cos, sin, cache=None, layer=0):
        return ckpt.checkpoint(self.block, x, cos, sin, use_reentrant=False)


# snippet:end checkpointing


def memory_and_time(make, batch: int, dev, checkpoint: bool = False) -> tuple[float, float]:
    torch.manual_seed(0)
    model = make().to(dev)
    if checkpoint:
        model.blocks = torch.nn.ModuleList(Checkpointed(b) for b in model.blocks)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-4)
    x = torch.randint(0, model.config.vocab_size, (batch, 513), device=dev)
    _, loss = model(x[:, :-1], x[:, 1:])
    loss.backward()
    opt.step()
    opt.zero_grad(set_to_none=False)
    device.sync(dev)
    resting = device.allocated(dev)
    _, loss = model(x[:, :-1], x[:, 1:])
    peak = device.allocated(dev)
    loss.backward()
    opt.step()
    device.sync(dev)
    start = time.perf_counter()
    for _ in range(3):
        _, loss = model(x[:, :-1], x[:, 1:])
        loss.backward()
        opt.step()
    device.sync(dev)
    seconds = (time.perf_counter() - start) / 3
    del model, opt, loss
    if dev.type == "mps":
        torch.mps.empty_cache()
    return resting, peak - resting, seconds


def main() -> None:
    dev = device.device()
    c = gpt.Config()
    make = lambda: gpt.GPT(c)
    torch.manual_seed(0)
    model = make().to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-4)
    x = torch.randint(0, c.vocab_size, (16, 513), device=dev)
    for _ in range(3):
        step_parts(model, opt, x[:, :-1], x[:, 1:], dev)
    parts = [step_parts(model, opt, x[:, :-1], x[:, 1:], dev) for _ in range(5)]
    forward, backward, update = (sorted(p[i] for p in parts)[2] for i in range(3))
    total = forward + backward + update
    print(
        f"one training step of the Chapter 2.5 model, 16 x 512 tokens, eager mode: {total * 1e3:.0f} ms"
    )
    for name, t in (("forward", forward), ("backward", backward), ("optimiser", update)):
        print(f"  {name:<10}{t * 1e3:7.1f} ms  {t / total:5.1%}")
    print("forward time by module (synchronised after each, which adds overhead):")
    times = module_times(model, x[:, :-1], dev)
    whole = sum(times.values())
    for name, t in sorted(times.items(), key=lambda kv: -kv[1]):
        print(f"  {name:<14}{t * 1e3:7.1f} ms  {t / whole:5.1%}")
    del model, opt

    # snippet:begin equation
    params = gpt.param_count(c)
    state = params * (4 + 4 + 8)
    # snippet:end equation
    print(
        f"memory: {params / 1e6:.1f}M parameters x 16 bytes for weights, gradients and Adam's two moments "
        f"= {state / 2**20:.0f} MiB before any activations"
    )
    print(
        f"{'batch':>6}{'resting MiB':>13}{'activations MiB':>17}{'per token KiB':>15}{'step ms':>9}"
    )
    rows = []
    for batch in (4, 8, 16):
        resting, act, seconds = memory_and_time(make, batch, dev)
        rows.append((batch, act))
        print(
            f"{batch:6d}{resting / 2**20:13.0f}{act / 2**20:17.0f}{act / (batch * 512) / 2**10:15.1f}"
            f"{seconds * 1e3:9.0f}"
        )
    resting, act, seconds = memory_and_time(make, 16, dev, checkpoint=True)
    print(
        f"batch 16 with activation checkpointing: activations {act / 2**20:.0f} MiB, step {seconds * 1e3:.0f} ms"
    )
    results.save(
        "u4-profile", {"parts": [forward, backward, update], "modules": times, "memory": rows}
    )
    check.expect("backward costs more than forward", backward > forward)


if __name__ == "__main__":
    check.main(main)
