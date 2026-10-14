import json
import sys
from pathlib import Path

import numpy as np

from aifig import C, SERIES, Diagram, plot, save

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
sys.path.insert(0, str(ROOT.parent / "code"))


def load(name):
    return json.loads((DATA / f"{name}.json").read_text())


def graph():
    from aif.tiny.scalar import Value

    a, b = Value(2.0), Value(-3.0)
    ab = a * b
    ea = a.exp()
    c = ab + ea
    t = c.tanh()
    d = t * b
    d.backward()
    dg = Diagram(168, 62)
    nodes = {
        "a": (8, 40, a, "a", "leaf"), "b": (8, 12, b, "b", "leaf"),
        "ab": (44, 26, ab, "×", "op"), "ea": (44, 48, ea, "exp", "op"),
        "c": (80, 37, c, "+", "op"), "t": (112, 37, t, "tanh", "op"), "d": (148, 26, d, "×", "op"),
    }
    boxes = {}
    for key, (x, y, v, label, kind) in nodes.items():
        box = dg.box(x - 7, y - 4.5, 14, 9, label, kind="amber_t" if kind == "leaf" else "navy_t", size=8.4,
                     mono=label in ("exp", "tanh"))
        boxes[key] = box
        dg.text(x, y + 7.6, f"{v.data:.3f}", size=6.8, color=C["ink"], mono=True)
        dg.text(x, y - 7.6, f"{v.grad:.3f}", size=6.8, color=C["coral"], mono=True, weight="bold")
    edges = [("a", "ab"), ("b", "ab"), ("a", "ea"), ("ab", "c"), ("ea", "c"), ("c", "t"), ("t", "d")]
    for u, v in edges:
        dg.arrow(boxes[u].e, boxes[v].w_, color=C["muted"], lw=0.8)
    dg.path([boxes["b"].e, (130, 12), (138, 21.5), boxes["d"].w_], color=C["muted"], lw=0.8)
    dg.text(4, 58, "forward value", size=6.8, ha="left", color=C["ink"])
    dg.text(4, 54, "adjoint ∂d/∂v", size=6.8, ha="left", color=C["coral"], weight="bold")
    dg.save("u1-graph")


def matmul():
    rows = load("u1-matmul")
    fig, ax = plot(h=60)
    methods = list(dict.fromkeys(r["method"] for r in rows))
    for colour, method in zip(SERIES, methods):
        pts = sorted((r["n"], r["gflops"]) for r in rows if r["method"] == method)
        ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", ms=3.5, color=colour, label=method)
    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xlabel("matrix size n")
    ax.set_ylabel("GFLOP/s")
    ax.legend(loc="center right")
    save(fig, "u1-matmul")


def templates():
    from matplotlib.colors import LinearSegmentedColormap

    w = np.load(DATA / "u1-logistic-weights.npy")
    cmap = LinearSegmentedColormap.from_list("ai", [C["coral"], "#FFFFFF", C["navy"]])
    fig, axes = plot(w=120, h=54, nrows=2, ncols=5)
    for k, ax in enumerate(axes.flat):
        lim = np.abs(w[k]).max()
        ax.imshow(w[k], cmap=cmap, vmin=-lim, vmax=lim)
        ax.set_title(str(k), fontsize=8, pad=2)
        ax.axis("off")
    fig.subplots_adjust(wspace=0.06, hspace=0.18, left=0, right=1, top=0.93, bottom=0)
    save(fig, "u1-templates")


def valley():
    d = load("u1-valley")
    H = np.array(d["H"])
    paths = {name: np.array(path[:80]) for name, path in d["paths"].items()}
    pts = np.vstack(list(paths.values()))
    x0, x1 = pts[:, 0].min() - 0.3, pts[:, 0].max() + 0.3
    y0, y1 = pts[:, 1].min() - 0.3, pts[:, 1].max() + 0.3
    fig, axes = plot(w=168, h=84, ncols=2)
    xs, ys = np.meshgrid(np.linspace(x0, x1, 300), np.linspace(y0, y1, 200))
    f = 0.5 * (H[0, 0] * xs ** 2 + 2 * H[0, 1] * xs * ys + H[1, 1] * ys ** 2)
    names = list(paths)
    for ax, group, colours in ((axes[0], names[:2], SERIES[:2]), (axes[1], names[2:], SERIES[2:4])):
        ax.contour(xs, ys, f, levels=np.geomspace(0.02, 300, 16), colors=C["rule"], linewidths=0.6)
        for colour, name in zip(colours, group):
            p = paths[name]
            ax.plot(p[:, 0], p[:, 1], marker="o", ms=1.5, lw=0.7, color=colour, label=name)
        ax.plot([0], [0], marker="*", ms=7, color=C["ink"])
        ax.set_xlim(x0, x1)
        ax.set_ylim(y0, y1)
        ax.set_aspect("equal")
        ax.grid(False)
        ax.legend(loc="lower right", fontsize=6.8)
    fig.subplots_adjust(wspace=0.12)
    save(fig, "u1-valley")


def schedule():
    from aif.train import lr_at

    steps = np.arange(18310)
    lr = [lr_at(int(s), 18310, 2e-3, 500) for s in steps]
    fig, ax = plot(h=44)
    ax.plot(steps, lr, color=C["navy"])
    ax.axvline(500, color=C["coral"], lw=0.8, ls="--")
    ax.text(650, 1.9e-3, "end of warm-up", color=C["coral"], fontsize=7.4, va="top")
    ax.set_xlabel("step")
    ax.set_ylabel("learning rate")
    ax.ticklabel_format(axis="y", style="sci", scilimits=(-3, -3))
    save(fig, "u1-schedule")


def lr_range():
    d = load("u1-lr-range")
    fig, ax = plot(h=52)
    ax.plot(d["lr"], d["loss"], color=C["navy"])
    best = int(np.argmin(d["loss"]))
    ax.plot([d["lr"][best]], [d["loss"][best]], marker="o", color=C["coral"])
    ax.axvline(d["lr"][best] / 10, color=C["green"], lw=0.8, ls="--")
    ax.text(d["lr"][best] / 10 * 0.8, 2.6, "a tenth of the minimum", color=C["green"], fontsize=7.4, ha="right")
    ax.set_xscale("log")
    ax.set_xlabel("learning rate")
    ax.set_ylabel("smoothed training loss")
    save(fig, "u1-lr-range")


def init():
    d = load("u1-init")
    fig, ax = plot(h=56)
    for colour, (name, scales) in zip(SERIES, d.items()):
        ax.plot(range(1, len(scales) + 1), np.clip(scales, 1e-30, 1e30), color=colour, label=name, marker="o", ms=2)
    ax.set_yscale("log")
    ax.set_xlabel("layer")
    ax.set_ylabel("activation standard deviation")
    ax.legend(loc="lower left", fontsize=7)
    save(fig, "u1-init")


def overfit():
    d = load("u1-overfit")
    fig, ax = plot(h=58)
    for colour, (name, history) in zip(SERIES, d.items()):
        acc = [100 * h[1] for h in history]
        ax.plot(range(1, len(acc) + 1), acc, color=colour, label=name, lw=1.1)
    ax.set_ylim(80, 97)
    ax.set_xlabel("epoch")
    ax.set_ylabel("validation accuracy (%)")
    ax.legend(loc="lower right", fontsize=7)
    save(fig, "u1-overfit")


def double_descent():
    d = load("u1-double-descent")
    rows = np.array(d["rows"])
    fig, ax = plot(h=56)
    ax.plot(rows[:, 0], 100 * rows[:, 2], marker="o", ms=3, color=C["navy"], label="test error")
    ax.plot(rows[:, 0], 100 * rows[:, 1], marker="o", ms=3, color=C["amber"], label="training error (noisy labels)")
    ax.axvline(d["n"], color=C["coral"], lw=0.8, ls="--")
    ax.text(d["n"] * 1.08, 92, "features = training examples", color=C["coral"], fontsize=7.4)
    ax.set_xscale("log")
    ax.set_ylim(-2, 100)
    ax.set_xlabel("number of random features")
    ax.set_ylabel("error (%)")
    ax.legend(loc="center right", fontsize=7)
    save(fig, "u1-double-descent")


def deep():
    d = load("u1-deep")
    fig, ax = plot(h=56)
    for colour, (name, rec) in zip(SERIES, d.items()):
        g = rec["grad_norms"]
        ax.plot(range(1, len(g) + 1), g, color=colour, label=name, marker="o", ms=2)
    ax.set_yscale("log")
    ax.set_xlabel("layer")
    ax.set_ylabel("weight gradient norm")
    ax.legend(loc="lower right", fontsize=7)
    save(fig, "u1-deep")


def blocks():
    dg = Diagram(168, 66)
    cols = [(28, "plain"), (84, "post-norm residual"), (140, "pre-norm residual")]
    for x, title in cols:
        dg.text(x, 62, title, size=8.4, weight="semibold", color=C["navy"])
    x = 28
    dg.arrow((x, 6), (x, 14), color=C["muted"])
    lin = dg.box(x - 14, 14, 28, 8, "Linear", kind="navy_t", size=7.6)
    act = dg.box(x - 14, 30, 28, 8, "ReLU", kind="purple_t", size=7.6)
    dg.arrow(lin.n, act.s, color=C["muted"])
    dg.arrow(act.n, (x, 56), color=C["muted"])
    x = 84
    dg.line((x, 6), (x, 33.4), color=C["muted"], lw=1.4)
    dg.circle(x, 36, 2.6, kind="coral_t", label="+", size=7.6)
    nrm = dg.box(x - 10, 42, 20, 7, "Norm", kind="amber_t", size=7)
    dg.arrow((x, 38.6), nrm.s, color=C["muted"], lw=1.4)
    dg.arrow(nrm.n, (x, 56), color=C["muted"], lw=1.4)
    bx = x - 26
    dg.path([(x, 10), (bx + 7, 10), (bx + 7, 14)], color=C["muted"], lw=0.8)
    act = dg.box(bx, 14, 14, 7, "ReLU", kind="purple_t", size=7)
    lin = dg.box(bx, 24, 14, 7, "Linear", kind="navy_t", size=7)
    dg.arrow(act.n, lin.s, color=C["muted"], lw=0.8)
    dg.path([lin.n, (bx + 7, 36), (x - 2.6, 36)], color=C["muted"], lw=0.8)
    x = 140
    dg.line((x, 6), (x, 48), color=C["coral"], lw=1.4)
    dg.circle(x, 48, 2.6, kind="coral_t", label="+", size=7.6)
    dg.arrow((x, 50.6), (x, 56), color=C["coral"], lw=1.4)
    bx = x - 26
    dg.path([(x, 12), (bx + 7, 12), (bx + 7, 16)], color=C["muted"], lw=0.8)
    nrm = dg.box(bx, 16, 14, 7, "Norm", kind="amber_t", size=7)
    act = dg.box(bx, 26, 14, 7, "ReLU", kind="purple_t", size=7)
    lin = dg.box(bx, 36, 14, 7, "Linear", kind="navy_t", size=7)
    dg.arrow(nrm.n, act.s, color=C["muted"], lw=0.8)
    dg.arrow(act.n, lin.s, color=C["muted"], lw=0.8)
    dg.path([lin.n, (bx + 7, 48), (x - 2.6, 48)], color=C["muted"], lw=0.8)
    dg.text(x + 3, 30, "identity path", size=6.8, color=C["coral"], ha="left", rotation=90)
    dg.save("u1-blocks")


def conv():
    dg = Diagram(144, 47)
    cell = 5.0
    def grid(x0, y0, n, fill):
        for r in range(n):
            for c in range(n):
                dg.rect(x0 + c * cell, y0 + r * cell, cell, cell, fill=fill, edge=C["rule"], lw=0.5)
    grid(4, 8, 6, C["grey"])
    grid(102, 8, 6, C["grey"])
    def window(x0, y0, row, col, edge, fill, dashed=False):
        dg.rect(x0 + col * cell, y0 + row * cell, 3 * cell, 3 * cell, fill=fill, edge=edge, lw=1.1, z=3,
                dashed=dashed)
    window(4, 8, 2, 1, C["amber"], C["amber_t"])
    window(4, 8, 0, 3, C["purple"], "none", dashed=True)
    dg.rect(102 + 2 * cell, 8 + 3 * cell, cell, cell, fill=C["coral"], edge=C["coral"], lw=0.8, z=3)
    dg.rect(102 + 4 * cell, 8 + 1 * cell, cell, cell, fill=C["purple_t"], edge=C["purple"], lw=0.8, z=3,
            dashed=True)
    kx, ky = 57, 18.5
    weights = [[1, 0, -1], [2, 0, -2], [1, 0, -1]]
    for r in range(3):
        for c in range(3):
            dg.rect(kx + c * cell, ky + (2 - r) * cell, cell, cell, fill=C["purple_t"], edge=C["purple"], lw=0.6)
            dg.text(kx + c * cell + cell / 2, ky + (2 - r) * cell + cell / 2, str(weights[r][c]), size=6.6,
                    mono=True)
    dg.arrow((4 + 4 * cell + 1, 8 + 3.5 * cell), (kx - 2, ky + 1.5 * cell), color=C["amber"], lw=1.0)
    dg.arrow((kx + 3 * cell + 2, ky + 1.5 * cell), (102 + 2 * cell - 1, 8 + 3.5 * cell), color=C["coral"], lw=1.0)
    dg.text(kx + 1.5 * cell, ky + 3 * cell + 4, "kernel", size=7.6, weight="semibold", color=C["purple"])
    dg.text(kx + 1.5 * cell, ky - 4, "multiply and add", size=6.8, color=C["muted"])
    dg.text(4 + 3 * cell, 3.5, "input", size=7.6, weight="semibold")
    dg.text(102 + 3 * cell, 3.5, "output", size=7.6, weight="semibold")
    dg.text(4 + 3 * cell, 42.5, "the same kernel at every position", size=6.8, color=C["muted"])
    dg.text(102 + 3 * cell, 42.5, "one value per position", size=6.8, color=C["muted"])
    dg.save("u1-conv")


def views():
    import matplotlib.pyplot as plt
    import torch

    from u1.vision import MEAN, STD, cifar_tensors, random_view

    d = cifar_tensors("cpu")
    labels = d["y_train"].numpy()
    picks = [int(np.argmax(labels == k)) for k in (3, 8, 7)]
    torch.manual_seed(4)
    fig = plt.figure(figsize=(141 / 25.4, 63 / 25.4))
    gs = fig.add_gridspec(3, 8, width_ratios=[1, 0.18, 1, 1, 1, 1, 1, 1], wspace=0.06, hspace=0.08,
                          left=0, right=1, top=0.92, bottom=0)
    for row, i in enumerate(picks):
        x = d["x_train"][i : i + 1]
        images = [x] + [random_view(x) for _ in range(6)]
        for col, img in enumerate(images):
            ax = fig.add_subplot(gs[row, 0 if col == 0 else col + 1])
            pixels = (img * STD + MEAN).clamp(0, 1)[0].permute(1, 2, 0).numpy()
            ax.imshow(pixels, interpolation="none")
            ax.axis("off")
            if row == 0:
                ax.set_title("image" if col == 0 else f"view {col}", fontsize=7.6, pad=2,
                             color=C["ink"] if col == 0 else C["muted"])
    save(fig, "u1-views")


def neighbours():
    import matplotlib.pyplot as plt

    from aif import data

    rec = load("u1-cifar")
    d = data.cifar10()
    images, labels = d["x_test"], d["y_test"]
    british = {"airplane": "aeroplane", "automobile": "car", "truck": "lorry"}
    names = [british.get(n, n) for n in data.CIFAR10_CLASSES]
    fig = plt.figure(figsize=(168 / 25.4, 50 / 25.4))
    ratios = [1, 0.12, 1, 1, 1, 1, 1, 0.45, 1, 0.12, 1, 1, 1, 1, 1]
    gs = fig.add_gridspec(3, len(ratios), width_ratios=ratios, wspace=0.05, hspace=0.42,
                          left=0, right=1, top=0.93, bottom=0.06)
    for n, (q, nbrs) in enumerate(zip(rec["queries"], rec["neighbours"])):
        row, base = n % 3, 0 if n < 3 else 8
        for k, i in enumerate([q] + list(nbrs)):
            ax = fig.add_subplot(gs[row, base + (0 if k == 0 else k + 1)])
            ax.imshow(images[i], interpolation="none")
            ax.set_xticks([])
            ax.set_yticks([])
            same = labels[i] == labels[q]
            edge = C["navy"] if k == 0 else (C["green"] if same else C["coral"])
            for side in ax.spines.values():
                side.set_edgecolor(edge)
                side.set_linewidth(1.4 if k == 0 else 1.0)
            ax.set_xlabel(names[labels[i]], fontsize=6.4, labelpad=1.5,
                          color=C["ink"] if k == 0 or same else C["coral"])
            if row == 0 and k <= 1:
                ax.set_title("query" if k == 0 else "nearest neighbours", fontsize=7.6, pad=2.5,
                             loc="left", color=C["ink"] if k == 0 else C["muted"])
    save(fig, "u1-neighbours")


if __name__ == "__main__":
    for fn in (graph, matmul, templates, valley, schedule, lr_range, init, overfit, double_descent, deep, blocks,
               conv, views, neighbours):
        fn()
