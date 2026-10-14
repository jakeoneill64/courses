import argparse
import math
import subprocess
import sys

import numpy as np

from aif import check, data, gpt, results, train
from u2.pretrain import ffn_width, kv_heads

SEQ, BATCH, HEAD_DIM = 256, 32, 32

# snippet:begin shapes
SHAPES = [
    (64, 2),
    (96, 2),
    (128, 3),
    (160, 4),
    (192, 4),
    (256, 4),
    (320, 5),
    (384, 6),
    (448, 7),
]
BUDGETS = {1e14: SHAPES[0:5], 4e14: SHAPES[1:6], 1.6e15: SHAPES[2:7]}
# snippet:end shapes


def config(d: int, layers: int) -> gpt.Config:
    heads = d // HEAD_DIM
    return gpt.Config(
        vocab_size=8192,
        d_model=d,
        n_layers=layers,
        n_heads=heads,
        n_kv_heads=kv_heads(heads),
        d_ff=ffn_width(d),
        max_seq=SEQ,
    )


def run_name(d: int, layers: int, budget: float) -> str:
    return f"scale-d{d}-l{layers}-c{budget:.1e}"


# snippet:begin run
def run(d: int, layers: int, budget: float) -> float:
    name = run_name(d, layers, budget)
    log = data.RUNS / name / "log.jsonl"
    if not (data.RUNS / name / "model.pt").exists():
        tokens = budget / gpt.train_flops_per_token(config(d, layers), SEQ)
        done = subprocess.run(
            [
                sys.executable,
                "-m",
                "u2.pretrain",
                "--name",
                name,
                "--d-model",
                str(d),
                "--layers",
                str(layers),
                "--head-dim",
                str(HEAD_DIM),
                "--seq",
                str(SEQ),
                "--batch",
                str(BATCH),
                "--tokens",
                str(tokens),
                "--lr",
                "3e-3",
                "--warmup",
                "200",
                "--eval-every",
                "100000",
                "--eval-windows",
                "512",
                "--ckpt-every",
                "100000",
            ],
            capture_output=True,
            text=True,
        )
        check.expect(f"{name} trained", done.returncode == 0, done.stderr[-500:])
    return [r for r in train.read_log(log) if "val_loss" in r][-1]["val_loss"]


# snippet:end run


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        type=float,
        default=6.4e15,
        help="the larger budget to predict and then train",
    )
    args = parser.parse_args()
    points = []
    print(
        f"{'budget (FLOPs)':>15}{'d_model':>9}{'layers':>8}{'parameters':>12}{'tokens':>10}{'val loss':>10}"
    )
    for budget, shapes in BUDGETS.items():
        for d, layers in shapes:
            c = config(d, layers)
            n = gpt.param_count(c)
            tokens = budget / gpt.train_flops_per_token(c, SEQ)
            loss = run(d, layers, budget)
            points.append((budget, n, tokens, loss))
            print(
                f"{budget:15.1e}{d:9d}{layers:8d}{n / 1e6:11.2f}M{tokens / 1e6:9.1f}M{loss:10.3f}",
                flush=True,
            )
    # snippet:begin isoflop
    optima = []
    for budget in BUDGETS:
        rows = np.array([(math.log(n), loss) for b, n, _, loss in points if b == budget])
        a, b, c0 = np.polyfit(rows[:, 0], rows[:, 1], 2)
        best_log_n = -b / (2 * a)
        optima.append((budget, math.exp(best_log_n), c0 - b * b / (4 * a)))
    logs = np.log([[c, n, loss] for c, n, loss in optima])
    n_slope, n_icept = np.polyfit(logs[:, 0], logs[:, 1], 1)
    l_slope, l_icept = np.polyfit(logs[:, 0], logs[:, 2], 1)
    predicted_n = math.exp(n_icept + n_slope * math.log(args.check))
    predicted_loss = math.exp(l_icept + l_slope * math.log(args.check))
    # snippet:end isoflop
    for budget, n, loss in optima:
        print(
            f"budget {budget:.1e}: the best size is about {n / 1e6:.2f}M parameters, loss {loss:.3f}"
        )
    print(f"fits: best size grows as C^{n_slope:.2f}, best loss falls as C^{l_slope:.3f}")
    print(
        f"prediction for {args.check:.1e} FLOPs: about {predicted_n / 1e6:.1f}M parameters, loss {predicted_loss:.3f}"
    )
    shape = min(SHAPES, key=lambda s: abs(math.log(gpt.param_count(config(*s)) / predicted_n)))
    measured = run(*shape, args.check)
    error = (measured - predicted_loss) / predicted_loss
    print(
        f"trained d_model {shape[0]}, {shape[1]} layers at {args.check:.1e} FLOPs: loss {measured:.3f}, "
        f"{abs(error):.1%} {'above' if error > 0 else 'below'} the prediction"
    )
    results.save(
        "u2-scaling",
        {
            "points": points,
            "optima": optima,
            "n_slope": n_slope,
            "l_slope": l_slope,
            "check": [args.check, predicted_loss, measured, gpt.param_count(config(*shape))],
        },
    )
    for budget, n, loss in optima:
        rows = [(p[1], p[3]) for p in points if p[0] == budget]
        check.expect(
            f"the valley at {budget:.1e} FLOPs has its bottom among the sizes trained",
            min(r[0] for r in rows) < n < max(r[0] for r in rows)
            and loss < max(r[1] for r in rows),
            f"{n / 1e6:.2f}M parameters",
        )


if __name__ == "__main__":
    check.main(main)
