import json
import math
import time
from pathlib import Path

import numpy as np
import torch


# snippet:begin batches
class TokenFile:
    def __init__(self, path: Path, seq: int):
        self.ids = np.memmap(path, dtype=np.uint16, mode="r")
        self.seq = seq

    def batch(
        self, size: int, rng: np.random.Generator, device
    ) -> tuple[torch.Tensor, torch.Tensor]:
        starts = rng.integers(0, len(self.ids) - self.seq - 1, size)
        rows = np.stack([self.ids[s : s + self.seq + 1] for s in starts]).astype(np.int64)
        rows = torch.from_numpy(rows).to(device, non_blocking=True)
        return rows[:, :-1], rows[:, 1:]

    def fixed(self, count: int, device) -> list[tuple[torch.Tensor, torch.Tensor]]:
        step = (len(self.ids) - self.seq - 1) // count
        rows = np.stack(
            [self.ids[i * step : i * step + self.seq + 1] for i in range(count)]
        ).astype(np.int64)
        rows = torch.from_numpy(rows).to(device)
        return [(rows[i : i + 16, :-1], rows[i : i + 16, 1:]) for i in range(0, count, 16)]


# snippet:end batches


# snippet:begin schedule
def lr_at(step: int, total: int, peak: float, warmup: int, floor: float = 0.1) -> float:
    if step < warmup:
        return peak * (step + 1) / warmup
    progress = min(1.0, (step - warmup) / max(1, total - warmup))
    return peak * (floor + (1 - floor) * 0.5 * (1 + math.cos(math.pi * progress)))


# snippet:end schedule


# snippet:begin evaluate
@torch.no_grad()
def evaluate(model, batches, dtype=None) -> float:
    model.eval()
    total, count = 0.0, 0
    for x, y in batches:
        with torch.autocast(x.device.type, dtype=dtype, enabled=dtype is not None):
            _, loss = model(x, y)
        total += loss.item() * y.numel()
        count += y.numel()
    model.train()
    return total / count


# snippet:end evaluate


def param_groups(model: torch.nn.Module, weight_decay: float) -> list[dict]:
    decay = [p for n, p in model.named_parameters() if p.dim() >= 2]
    rest = [p for n, p in model.named_parameters() if p.dim() < 2]
    return [
        {"params": decay, "weight_decay": weight_decay},
        {"params": rest, "weight_decay": 0.0},
    ]


class Log:
    def __init__(self, path: Path, resume: bool = False):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.file = open(path, "a" if resume else "w")
        self.start = time.perf_counter()

    def write(self, **record) -> None:
        record["time"] = round(time.perf_counter() - self.start, 2)
        self.file.write(json.dumps(record) + "\n")
        self.file.flush()


def read_log(path: Path) -> list[dict]:
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line]
