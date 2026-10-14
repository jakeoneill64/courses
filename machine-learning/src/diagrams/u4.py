import json
import sys
from pathlib import Path

import numpy as np

from aifig import C, plot, save

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
sys.path.insert(0, str(ROOT.parent / "code"))


def load(name):
    return json.loads((DATA / f"{name}.json").read_text())


def roofline():
    d = load("u4-roofline")
    peak, bandwidth = d["peak"], d["bandwidth"]
    ops = d["ops"]
    fig, ax = plot(h=78)
    lo = min(o["intensity"] for o in ops) / 3
    hi = max(o["intensity"] for o in ops) * 3
    ridge = peak / bandwidth
    ax.plot([lo, ridge, hi], [lo * bandwidth, peak, peak], color=C["ink"], lw=1.4, snap=False)
    ax.axvline(ridge, color=C["muted"], lw=0.7, ls=(0, (3, 2)))
    ax.text(ridge * 1.08, peak / 12, f"ridge point\n{ridge:.0f} FLOP/byte", fontsize=7, color=C["muted"])
    ax.text(lo * 1.6, lo * 1.6 * bandwidth * 2.4, f"{bandwidth:.0f} GB/s", fontsize=7.4, color=C["muted"])
    ax.text(hi / 1.2, peak * 1.15, f"{peak / 1e3:.1f} TFLOP/s", fontsize=7.4, color=C["muted"], ha="right")
    for k, op in enumerate(ops, 1):
        colour = C["navy"] if op["intensity"] * bandwidth >= peak else C["coral"]
        ax.plot(op["intensity"], op["gflops"], "o", ms=4.2, color=colour)
        ax.annotate(str(k), (op["intensity"], op["gflops"]), xytext=(3.5, -8), textcoords="offset points",
                    fontsize=6.8, color=colour, weight="semibold")
        ax.text(0.7, 0.05 + (len(ops) - k) * 0.052, f"{k}  {op['name']}", transform=ax.transAxes, fontsize=6.8,
                color=C["ink"])
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(lo, hi)
    ax.set_ylim(min(o["gflops"] for o in ops) / 3, peak * 1.8)
    ax.set_xlabel("arithmetic intensity (FLOP per byte)")
    ax.set_ylabel("GFLOP/s")
    save(fig, "u4-roofline")


def pipeline():
    times = load("u4-parallel")["pipeline"]
    m = np.array(sorted(int(k) for k in times))
    measured = np.array([times[str(k)] for k in m]) * 1e3
    ideal = measured[0] * (m + 1) / (2 * m)
    fig, ax = plot(h=54)
    ax.plot(m, measured, marker="o", ms=3.5, color=C["navy"], label="measured, two stages")
    ax.plot(m, ideal, color=C["muted"], lw=1.0, ls=(0, (4, 2)), label="ideal: (m + 1) / 2m of the time at m = 1")
    ax.set_xscale("log", base=2)
    ax.set_xticks(m, [str(k) for k in m])
    ax.set_xlabel("micro-batches per batch, m")
    ax.set_ylabel("time per batch (ms)")
    ax.set_ylim(0, None)
    ax.legend(loc="lower left")
    save(fig, "u4-pipeline")


if __name__ == "__main__":
    for fn in (roofline, pipeline):
        fn()
