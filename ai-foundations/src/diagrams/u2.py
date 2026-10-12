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


def compression():
    d = load("u2-bpe-sweep")
    rows = d["rows"]
    fig, ax = plot(h=56)
    vocab = [r["vocab"] for r in rows]
    ax.plot(vocab, [r["stories"] for r in rows], marker="o", ms=3.5, color=C["navy"], label="TinyStories tokeniser on stories")
    ax.plot(vocab, [r["code"] for r in rows], marker="o", ms=3.5, color=C["coral"], label="TinyStories tokeniser on Python code")
    s = d["smollm2"]
    ax.plot([s["vocab"]], [s["stories"]], marker="s", ms=5, color=C["navy"], ls="none", label="SmolLM2's tokeniser on stories")
    ax.plot([s["vocab"]], [s["code"]], marker="s", ms=5, color=C["coral"], ls="none", label="SmolLM2's tokeniser on code")
    ax.set_xscale("log", base=2)
    ax.set_xlabel("vocabulary size")
    ax.set_ylabel("bytes per token")
    ax.set_ylim(0, 4.6)
    ax.legend(loc="lower right", fontsize=7)
    save(fig, "u2-compression")


def transformer():
    d = Diagram(168, 118)
    x, w = 54, 60
    cx = x + w / 2

    def stage(y, label, kind="navy_t", h=8):
        return d.box(x, y, w, h, label, kind=kind, size=7.6, weight="normal", radius=1.2)

    tokens = stage(2, "token ids", kind="grey")
    embed = stage(14, "embedding  (V × d)", kind="amber_t")
    d.arrow(tokens.n, embed.s, color=C["muted"], lw=0.8)
    by = 28
    d.group(x - 9, by - 1, w + 15, 58, "", color=C["purple"], dashed=True)
    d.text(x + w + 9, by + 53, "× 8 blocks", size=7.6, color=C["purple"], ha="left", weight="semibold")
    n1 = stage(by + 4, "RMSNorm", kind="plain", h=6.5)
    at = stage(by + 13, "attention: RoPE, 8 query and 4 KV heads", kind="coral_t")
    n2 = stage(by + 31, "RMSNorm", kind="plain", h=6.5)
    ff = stage(by + 40, "SwiGLU feed-forward, d → 1,408 → d", kind="magenta_t")
    d.line(embed.n, (cx, by + 4), color=C["muted"], lw=0.8)
    d.arrow((cx, by + 2), n1.s, color=C["muted"], lw=0.8)
    d.arrow(n1.n, at.s, color=C["muted"], lw=0.8)
    plus1 = (cx, by + 26)
    plus2 = (cx, by + 53)
    d.arrow(at.n, (cx, plus1[1] - 2.2), color=C["muted"], lw=0.8)
    d.arrow((cx, plus1[1] + 2.2), n2.s, color=C["muted"], lw=0.8)
    d.arrow(n2.n, ff.s, color=C["muted"], lw=0.8)
    d.arrow(ff.n, (cx, plus2[1] - 2.2), color=C["muted"], lw=0.8)
    for y in (plus1[1], plus2[1]):
        d.circle(cx, y, 2.2, kind="coral_t", label="+", size=7.2)
    rx = x - 5
    d.path([(cx, by + 2), (rx, by + 2), (rx, plus1[1]), (cx - 2.2, plus1[1])], color=C["coral"], lw=1.1)
    d.path([(cx, by + 29), (rx, by + 29), (rx, plus2[1]), (cx - 2.2, plus2[1])], color=C["coral"], lw=1.1)
    d.text(rx - 2, by + 14, "residual", size=6.6, color=C["coral"], ha="right")
    d.text(rx - 2, by + 41, "residual", size=6.6, color=C["coral"], ha="right")
    fn = stage(by + 63, "RMSNorm", kind="plain", h=6.5)
    head = stage(by + 73, "output layer, tied to the embedding", kind="amber_t")
    d.arrow((cx, plus2[1] + 2.2), fn.s, color=C["muted"], lw=0.8)
    d.arrow(fn.n, head.s, color=C["muted"], lw=0.8)
    d.text(cx, by + 86, "logits for the next token, one row per position", size=7.2, color=C["ink"])
    d.text(x + w + 12, 18, "d = 512, V = 8,192\n28M parameters", size=7.2, color=C["muted"], ha="left")
    d.save("u2-transformer")


def copy_attention():
    import matplotlib.pyplot as plt
    d = load("u2-copy")
    w = np.array(d["weights"])
    fig, axes = plot(w=150, h=72, ncols=len(w))
    for h, ax in enumerate(np.atleast_1d(axes)):
        ax.imshow(w[h], cmap="Blues", vmin=0, vmax=1)
        ax.set_title(f"head {h}", fontsize=8)
        ax.set_xlabel("attended position")
        if h == 0:
            ax.set_ylabel("query position")
        ax.axhline(d["half"] - 1.5, color=C["coral"], lw=0.6, ls="--")
        ax.grid(False)
    save(fig, "u2-copy")


def pretrain():
    rows = [json.loads(line) for line in (DATA / "u2-pretrain-log.jsonl").read_text().splitlines()]
    steps = [r for r in rows if "loss" in r]
    evals = [r for r in rows if "val_loss" in r]
    fig, (ax, lr) = plot(h=74, nrows=2, sharex=True, gridspec_kw={"height_ratios": [3.2, 1]})
    ax.plot([r["tokens"] / 1e6 for r in steps], [r["loss"] for r in steps], color=C["navy"], lw=0.9,
            alpha=0.75, label="training loss, one batch every 50 steps")
    ax.plot([r["tokens"] / 1e6 for r in evals], [r["val_loss"] for r in evals], color=C["coral"], lw=0,
            marker="o", ms=3, label="validation loss")
    ax.set_ylim(1.0, 3.2)
    ax.set_ylabel("nats per token")
    ax.legend(loc="upper right", fontsize=7.4)
    lr.plot([r["tokens"] / 1e6 for r in steps], [r["lr"] * 1e3 for r in steps], color=C["amber"], lw=1.2)
    lr.set_ylabel("lr (×10⁻³)")
    lr.set_xlabel("tokens seen (millions)")
    lr.set_ylim(0, 2.3)
    fig.subplots_adjust(hspace=0.12)
    save(fig, "u2-pretrain")


def scaling():
    from matplotlib.ticker import FixedLocator, FormatStrFormatter, NullFormatter, NullLocator

    d = load("u2-scaling")
    points = np.array(d["points"])
    fig, (left, right) = plot(h=62, ncols=2, gridspec_kw={"wspace": 0.32})
    for colour, budget in zip(SERIES, sorted(set(points[:, 0]))):
        rows = points[points[:, 0] == budget]
        a, b, c0 = np.polyfit(np.log(rows[:, 1]), rows[:, 3], 2)
        xs = np.linspace(np.log(rows[:, 1]).min() - 0.15, np.log(rows[:, 1]).max() + 0.15, 60)
        left.plot(rows[:, 1] / 1e6, rows[:, 3], "o", ms=3.5, color=colour, label=f"{budget:.2g} FLOPs".replace("e+", "e"))
        left.plot(np.exp(xs) / 1e6, a * xs**2 + b * xs + c0, color=colour, lw=1.0)
        best = -b / (2 * a)
        left.plot(np.exp(best) / 1e6, c0 - b * b / (4 * a), "D", ms=4.5, color=colour, mec=C["ink"], mew=0.6)
    left.set_xscale("log")
    left.xaxis.set_major_locator(FixedLocator([0.5, 1, 2, 5, 10, 20]))
    left.xaxis.set_major_formatter(FormatStrFormatter("%g"))
    left.xaxis.set_minor_locator(NullLocator())
    left.set_xlabel("parameters (millions)")
    left.set_ylabel("validation loss (nats per token)")
    left.legend(fontsize=7, loc="best")
    optima = np.array(d["optima"])
    check_c, predicted, measured, _ = d["check"]
    slope, icept = np.polyfit(np.log(optima[:, 0]), np.log(optima[:, 2]), 1)
    cs = np.geomspace(optima[:, 0].min() / 1.5, check_c * 1.5, 50)
    right.plot(cs, np.exp(icept) * cs**slope, color=C["muted"], lw=1.0, ls=(0, (4, 2)),
               label=f"power law, exponent {slope:.3f}".replace("-", "\u2212"))
    right.plot(optima[:, 0], optima[:, 2], "D", ms=4.5, color=C["navy"], label="best loss at each budget")
    right.plot(check_c, predicted, "o", ms=6, mfc="none", mec=C["coral"], mew=1.2, label="predicted")
    right.plot(check_c, measured, "*", ms=8, color=C["coral"], label="measured")
    right.set_xscale("log")
    right.set_yscale("log")
    lo, hi = right.get_ylim()
    right.yaxis.set_major_locator(FixedLocator(np.round(np.geomspace(lo * 1.02, hi / 1.02, 5), 2)))
    right.yaxis.set_major_formatter(FormatStrFormatter("%.2f"))
    right.yaxis.set_minor_formatter(NullFormatter())
    right.yaxis.set_minor_locator(NullLocator())
    right.set_xlabel("training compute (FLOPs)")
    right.set_ylabel("best loss (nats per token)")
    right.legend(fontsize=7, loc="upper right")
    save(fig, "u2-scaling")


def ngram():
    grams = load("u2-ngram")
    neural = load("u2-mlp-lm")
    log = [json.loads(line) for line in (DATA / "u2-pretrain-log.jsonl").read_text().splitlines()]
    final = [r for r in log if "val_loss" in r][-1]["val_loss"]
    names = [f"{g['order']}-gram" for g in grams] + [f"neural, {neural['context']} tokens", "transformer"]
    values = [g["nats"] for g in grams] + [neural["nats"], final]
    colours = [C["navy"]] * len(grams) + [C["purple"], C["coral"]]
    fig, ax = plot(h=52)
    y = np.arange(len(names))[::-1]
    ax.barh(y, values, color=colours, height=0.62)
    for yi, v in zip(y, values):
        ax.text(v + 0.06, yi, f"{v:.3f}", va="center", fontsize=7.6, color=C["ink"])
    ax.set_yticks(y, names)
    ax.set_xlabel("validation cross-entropy (nats per token)")
    ax.set_xlim(0, max(values) * 1.12)
    ax.grid(axis="y", visible=False)
    save(fig, "u2-ngram")


def kvcache():
    d = load("u2-kvcache")
    names = {"mps": "on the GPU", "cuda": "on the GPU", "cpu": "on the CPU"}
    fig, axes = plot(h=54, ncols=len(d), sharey=True, gridspec_kw={"wspace": 0.08})
    axes = axes if len(d) > 1 else [axes]
    for ax, (dev, runs) in zip(axes, d.items()):
        for colour, key, label in ((C["coral"], "plain", "without the cache"), (C["navy"], "cache", "with the cache")):
            times = np.array(runs[key]) * 1e3
            ax.plot(np.arange(len(times)) + 5, times, color=colour, lw=0.9, label=label)
        ax.set_title(names.get(dev, dev), fontsize=8.4)
        ax.set_xlabel("position of the generated token")
    axes[0].set_ylabel("time per token (ms)")
    axes[0].set_ylim(0, 60)
    axes[0].legend(loc="upper left")
    save(fig, "u2-kvcache")


def induction():
    from matplotlib.colors import LinearSegmentedColormap

    scores = np.array(load("u2-induction")["scores"])
    cmap = LinearSegmentedColormap.from_list("ai", ["#FFFFFF", C["navy"]])
    fig, ax = plot(w=134, h=66)
    ax.grid(False)
    im = ax.imshow(scores, cmap=cmap, vmin=0, vmax=max(0.5, scores.max()), aspect="auto")
    for (layer, head), v in np.ndenumerate(scores):
        if v >= 0.1:
            ax.text(head, layer, f"{v:.2f}", ha="center", va="center", fontsize=6.8,
                    color=C["white"] if v > 0.3 else C["ink"])
    ax.set_xticks(range(scores.shape[1]), [str(h) for h in range(scores.shape[1])])
    ax.set_yticks(range(scores.shape[0]), [str(l + 1) for l in range(scores.shape[0])])
    ax.set_xlabel("head")
    ax.set_ylabel("layer")
    for side in ax.spines.values():
        side.set_visible(False)
    bar = fig.colorbar(im, ax=ax, fraction=0.04, pad=0.03)
    bar.outline.set_visible(False)
    bar.ax.tick_params(labelsize=7, length=2)
    bar.set_label("induction score", fontsize=7.8)
    save(fig, "u2-induction")


def logit_lens():
    losses = load("u2-logit-lens")["losses"]
    fig, ax = plot(h=54)
    depth = np.arange(1, len(losses))
    ax.plot(depth, losses[1:], marker="o", ms=3.5, color=C["navy"])
    ax.set_xticks(depth, [f"after {d}" for d in depth])
    ax.set_xlabel("block")
    ax.set_ylabel("loss of the lens (nats per token)")
    ax.set_ylim(0, max(losses[1:]) * 1.12)
    save(fig, "u2-logit-lens")


def probe():
    d = load("u2-probe")
    fig, ax = plot(h=56)
    labels = ["embedding"] + [str(i) for i in range(1, len(d["trained"]))]
    x = np.arange(len(labels))
    ax.plot(x, np.array(d["trained"]) * 100, marker="o", ms=3.5, color=C["navy"], label="trained model")
    ax.plot(x, np.array(d["untrained"]) * 100, marker="o", ms=3.5, color=C["coral"], label="untrained model")
    ax.axhline((1 - d["base_rate"]) * 100, color=C["muted"], lw=0.9, ls=(0, (4, 2)),
               label="always \u201coutside\u201d")
    ax.set_xticks(x, labels)
    ax.set_xlabel("residual stream after layer")
    ax.set_ylabel("probe accuracy (%)")
    ax.legend(loc="center right")
    save(fig, "u2-probe")


if __name__ == "__main__":
    for fn in (compression, transformer, copy_attention, pretrain, scaling, ngram, kvcache, induction,
               logit_lens, probe):
        fn()
