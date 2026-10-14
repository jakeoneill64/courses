import re
from pathlib import Path

from vkfig import C, Diagram, plot, save

CONSOLE = Path(__file__).resolve().parents[1] / "console"


def table_rows(name, first_column="local size"):
    lines = (CONSOLE / name).read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(first_column))
    rows = []
    for line in lines[start + 1:]:
        cells = line.split()
        if not cells or not re.match(r"^[\d.]+$", cells[0]):
            break
        rows.append(cells)
    return rows


def hierarchy():
    d = Diagram(168, 70)
    d.text(2, 66, "vkCmdDispatch(cmd, 4, 2, 1)", size=7.4, mono=True, ha="left", color=C["navy"])
    gx, gy, gw, gh = 2, 18, 58, 42
    for j in range(2):
        for i in range(4):
            x = gx + i * (gw / 4)
            y = gy + (1 - j) * (gh / 2)
            hot = (i, j) == (3, 0)
            d.rect(x + 0.6, y + 0.6, gw / 4 - 1.2, gh / 2 - 1.2, fill=C["coral_t"] if hot else C["navy_t"],
                   edge=C["coral"] if hot else C["navy"], lw=0.8 if hot else 0.5)
            d.text(x + gw / 8, y + gh / 4, f"({i}, {j})", size=6.4, mono=True, color=C["ink"])
    d.text(gx + gw / 2, 13.5, "a dispatch: a grid of workgroups,\nindexed by gl_WorkGroupID", size=6.4,
           color=C["muted"])
    d.line((gx + gw, gy + gh), (78, 62), color=C["coral"], lw=0.6, dashed=True)
    d.line((gx + gw, gy + gh / 2), (78, 18), color=C["coral"], lw=0.6, dashed=True)
    wx, wy, ww, wh = 78, 18, 84, 44
    d.rect(wx, wy, ww, wh, fill="none", edge=C["coral"], lw=0.9)
    d.text(wx + 2, wy + wh + 2.8, "one workgroup of 8 × 8 invocations (gl_LocalInvocationID)", size=6.6,
           color=C["coral"], ha="left", weight="semibold")
    cell = ww / 8
    for r in range(8):
        for c in range(8):
            sub = 0 if r < 4 else 1
            x = wx + c * cell
            y = wy + wh - (r + 1) * (wh / 8)
            d.rect(x + 0.5, y + 0.5, cell - 1, wh / 8 - 1, fill=C["purple_t"] if sub == 0 else C["amber_t"],
                   edge=C["purple"] if sub == 0 else C["amber"], lw=0.4)
            if r in (0, 4) and c < 3 or (r, c) == (7, 7):
                d.text(x + cell / 2, y + wh / 16, f"{r * 8 + c}", size=5.6, mono=True, color=C["ink"])
    d.text(wx + ww / 2, 13.5, "gl_LocalInvocationIndex in each cell; two subgroups of 32 on this GPU",
           size=6.4, color=C["muted"])
    d.box(wx, 2, 40, 6.5, "subgroup 0", kind="purple_t", size=6.4, weight="normal", radius=0.8)
    d.box(wx + 44, 2, 40, 6.5, "subgroup 1", kind="amber_t", size=6.4, weight="normal", radius=0.8)
    d.save("u2-hierarchy")


def localsize():
    rows = table_rows("u2-localsize.txt")
    sizes = [int(r[0]) for r in rows]
    gbs = [float(r[2]) for r in rows]
    gflops = [float(r[4]) for r in rows]
    fig, (left, right) = plot(h=52, ncols=2)
    left.plot(sizes, gbs, "o-", color=C["navy"], lw=1.2, ms=3.5)
    left.set_xscale("log", base=2)
    left.set_xticks(sizes, [str(s) for s in sizes])
    left.set_ylim(0, max(gbs) * 1.2)
    left.set_xlabel("local size")
    left.set_ylabel("SAXPY, GB/s")
    right.plot(sizes, [g / 1000 for g in gflops], "o-", color=C["coral"], lw=1.2, ms=3.5)
    right.set_xscale("log", base=2)
    right.set_xticks(sizes, [str(s) for s in sizes])
    right.set_ylim(0, max(gflops) / 1000 * 1.2)
    right.set_xlabel("local size")
    right.set_ylabel("FMA chain, TFLOP/s")
    fig.tight_layout(pad=0.4, w_pad=2.0)
    save(fig, "u2-localsize")


def grid(d, x, y, size, n, fill, edge, lw=0.4):
    cell = size / n
    for r in range(n):
        for c in range(n):
            d.rect(x + c * cell, y + size - (r + 1) * cell, cell, cell, fill=fill, edge=edge, lw=lw)
    return cell


def transpose():
    d = Diagram(168, 66)
    d.text(2, 62, "Naive: rows in, columns out", size=7.4, weight="bold", ha="left", color=C["navy"])
    sx, dx_, y0, size = 4, 44, 22, 30
    grid(d, sx, y0, size, 6, C["navy_t"], C["navy"])
    grid(d, dx_, y0, size, 6, C["navy_t"], C["navy"])
    cell = size / 6
    d.rect(sx, y0 + size - cell, size, cell, fill=C["amber_t"], edge=C["amber"], lw=0.8)
    d.rect(dx_, y0, cell, size, fill=C["coral_t"], edge=C["coral"], lw=0.8)
    d.text(sx + size / 2, y0 - 4, "src: a subgroup reads\none row (coalesced)", size=6.2, color=C["muted"])
    d.text(dx_ + size / 2, y0 - 4, "dst: it writes one column,\na transaction per element", size=6.2,
           color=C["muted"])
    d.arrow((sx + size + 1, y0 + size / 2), (dx_ - 1, y0 + size / 2), color=C["muted"], lw=0.7, mutation=6)
    d.line((82, 6), (82, 60), color=C["rule"], lw=0.6)
    d.text(86, 62, "Tiled: through shared memory", size=7.4, weight="bold", ha="left", color=C["navy"])
    tx, ts = 86, 24
    grid(d, tx, y0 + 3, ts, 6, C["navy_t"], C["navy"])
    tc = ts / 6
    d.rect(tx, y0 + 3 + ts - tc, ts, tc, fill=C["amber_t"], edge=C["amber"], lw=0.8)
    mx, ms = tx + ts + 6, 16
    grid(d, mx, y0 + 7, ms, 6, C["purple_t"], C["purple"], lw=0.3)
    d.text(mx + ms / 2, y0 + 3.5, "shared tile", size=6.2, color=C["purple"])
    ox = mx + ms + 6
    grid(d, ox, y0 + 3, ts, 6, C["navy_t"], C["navy"])
    d.rect(ox, y0 + 3 + ts - tc, ts, tc, fill=C["coral_t"], edge=C["coral"], lw=0.8)
    d.arrow((tx + ts + 0.5, y0 + 3 + ts / 2), (mx - 0.5, y0 + 3 + ts / 2), color=C["muted"], lw=0.7, mutation=6)
    d.arrow((mx + ms + 0.5, y0 + 3 + ts / 2), (ox - 0.5, y0 + 3 + ts / 2), color=C["muted"], lw=0.7,
            mutation=6)
    d.text(tx + ts / 2, y0 - 2, "read a row\nof the tile", size=6.2, color=C["muted"])
    d.text(ox + ts / 2, y0 - 2, "write a row of the\ntransposed tile", size=6.2, color=C["muted"])
    d.text(125, 8, "barrier() between the phases: every invocation\nfinishes writing the tile before any reads it",
           size=6.2, color=C["ink"])
    d.save("u2-transpose")


def banks():
    d = Diagram(168, 50)
    n = 8
    for k, (pad, title) in enumerate([(0, "tile[8][8]: a column falls in one bank"),
                                      (1, "tile[8][9]: a column spreads over every bank")]):
        x0 = 6 + k * 84
        d.text(x0, 46, title, size=7.2, weight="bold", ha="left", color=C["navy"])
        cell = 7.4
        for r in range(n):
            for c in range(n + pad):
                bank = (r * (n + pad) + c) % n
                x = x0 + c * cell
                y = 36 - r * 4.4
                in_col = c == 2
                fill = C["coral"] if in_col else (C["grey"] if c >= n else C["navy_t"])
                d.rect(x, y, cell - 0.6, 3.8, fill=fill, edge=C["coral"] if in_col else C["rule"], lw=0.4)
                d.text(x + (cell - 0.6) / 2, y + 1.9, str(bank), size=5.4, mono=True,
                       color=C["white"] if in_col else C["muted"])
        d.text(x0, 1.5, "numbers: the bank of each element; highlighted: column 2" if k == 0 else
               "the grey column is padding that is never used", size=6.2, color=C["muted"], ha="left")
    d.save("u2-banks")


def labelled_rows(name, header):
    lines = (CONSOLE / name).read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith(header))
    rows = []
    for line in lines[start + 1:]:
        if not line.strip() or line.startswith(("PASS", "FAIL")):
            break
        rows.append([c for c in re.split(r"\s{2,}", line.strip())])
    return rows


def transpose_results():
    big = labelled_rows("u2-transpose.txt", "kernel")
    small = labelled_rows("u2-transpose-cached.txt", "kernel")
    labels = ["copy", "naive", "tiled", "tiled, padded"]
    fig, ax = plot(h=52)
    import numpy as np
    x = np.arange(len(labels))
    w = 0.38
    ax.bar(x - w / 2, [float(r[-2]) for r in small], w, color=C["amber"], label="1024 × 1024 (4 MiB)")
    ax.bar(x + w / 2, [float(r[-2]) for r in big], w, color=C["navy"], label="4096 × 4096 (64 MiB)")
    ax.set_xticks(x, labels)
    ax.set_ylabel("GB/s, reads plus writes")
    ax.set_ylim(0, 540)
    ax.legend(frameon=False, fontsize=7, loc="upper right", ncol=2)
    save(fig, "u2-transpose-results")


def histogram_results():
    rows = labelled_rows("u2-histogram.txt", "input")
    fig, ax = plot(h=46)
    import numpy as np
    inputs = ["uniform", "all identical"]
    kernels = ["global atomics", "shared, then global"]
    x = np.arange(len(inputs))
    w = 0.38
    for k, (kernel, colour) in enumerate(zip(kernels, [C["coral"], C["navy"]])):
        values = [float(next(r for r in rows if r[0] == i and r[1] == kernel)[2]) for i in inputs]
        bars = ax.bar(x + (k - 0.5) * w, values, w, color=colour, label=kernel)
        for b, v in zip(bars, values):
            ax.text(b.get_x() + b.get_width() / 2, v * 1.15, f"{v:g} ms", ha="center", fontsize=6.6)
    ax.set_yscale("log")
    ax.set_ylim(0.1, 300)
    ax.set_xticks(x, ["uniform bytes", "every byte the same"])
    ax.set_ylabel("ms for 64 MiB (log scale)")
    ax.legend(frameon=False, fontsize=7, loc="upper left")
    save(fig, "u2-histogram")

def reduction_trees():
    d = Diagram(168, 66)
    values = [3, 1, 7, 0, 4, 1, 6, 3]
    for panel, (title, sequential) in enumerate([("Interleaved addressing: t % (2·stride) == 0", False),
                                                 ("Sequential addressing: t < stride", True)]):
        x0 = 4 + panel * 84
        d.text(x0, 62, title, size=7, weight="bold", ha="left", color=C["navy"])
        level = list(values)
        cell = 8.6
        y = 50
        for step in range(4):
            for i, v in enumerate(level):
                active = v is not None
                d.rect(x0 + i * (cell + 0.6), y, cell, 6, fill=C["navy_t"] if active else C["grey"],
                       edge=C["navy"] if active else C["rule"], lw=0.4)
                if active:
                    d.text(x0 + i * (cell + 0.6) + cell / 2, y + 3, str(v), size=6.2, mono=True)
            if step == 3:
                break
            stride = (1 << step) if not sequential else (4 >> step)
            new_level = [None] * 8
            for i in range(8):
                if not sequential:
                    if i % (2 * stride) == 0:
                        new_level[i] = level[i] + level[i + stride]
                        d.arrow((x0 + (i + stride) * (cell + 0.6) + cell / 2, y - 0.3),
                                (x0 + i * (cell + 0.6) + cell / 2, y - 6.7), color=C["coral"], lw=0.5, mutation=4)
                else:
                    if i < stride:
                        new_level[i] = level[i] + level[i + stride]
                        d.arrow((x0 + (i + stride) * (cell + 0.6) + cell / 2, y - 0.3),
                                (x0 + i * (cell + 0.6) + cell / 2, y - 6.7), color=C["coral"], lw=0.5, mutation=4)
            level = new_level
            y -= 13
        note = ("the active invocations spread out: every subgroup\nstays busy until the last step"
                if not sequential else "the active invocations stay together: whole\nsubgroups finish early")
        d.text(x0 + 38, 6, note, size=6.2, color=C["muted"])
    d.save("u2-reduction-trees")


def reduce_results():
    rows = labelled_rows("u2-reduce.txt", "variant")
    fig, ax = plot(h=46)
    labels = [r[0].replace("subgroupAdd, ", "subgroupAdd,\n").replace(" addressing", "\naddressing")
              .replace(" elements per invocation", "\nper invocation") for r in rows]
    values = [float(r[3]) for r in rows]
    colours = [C["navy"], C["navy"], C["purple"], C["coral"], C["purple"]]
    bars = ax.bar(range(len(rows)), values, color=colours, width=0.6)
    for b, v in zip(bars, values):
        ax.text(b.get_x() + b.get_width() / 2, v + 3, f"{v:.0f}", ha="center", fontsize=6.6)
    ax.set_xticks(range(len(rows)), labels, fontsize=6.4)
    ax.set_ylabel("GB/s")
    ax.set_ylim(0, max(values) * 1.18)
    save(fig, "u2-reduce")


def blelloch():
    d = Diagram(168, 70)
    vals = [3, 1, 7, 0, 4, 1, 6, 3]
    cell = 9.0
    x0 = 30
    def row(y, values, label, colour_idx=None):
        d.text(x0 - 3, y + 3, label, size=6.2, ha="right", color=C["muted"])
        for i, v in enumerate(values):
            hot = colour_idx is not None and i in colour_idx
            d.rect(x0 + i * (cell + 0.8), y, cell, 6, fill=C["coral_t"] if hot else C["navy_t"],
                   edge=C["coral"] if hot else C["navy"], lw=0.4)
            d.text(x0 + i * (cell + 0.8) + cell / 2, y + 3, str(v), size=6.2, mono=True)
    up1 = [3, 4, 7, 7, 4, 5, 6, 9]
    up2 = [3, 4, 7, 11, 4, 5, 6, 14]
    up3 = [3, 4, 7, 11, 4, 5, 6, 25]
    clear = [3, 4, 7, 11, 4, 5, 6, 0]
    dn1 = [3, 4, 7, 0, 4, 5, 6, 11]
    dn2 = [3, 0, 7, 4, 4, 11, 6, 16]
    dn3 = [0, 3, 4, 11, 11, 15, 16, 22]
    rows = [("input", vals, None), ("up-sweep 1", up1, {1, 3, 5, 7}), ("up-sweep 2", up2, {3, 7}),
            ("up-sweep 3", up3, {7}), ("clear the root", clear, {7}), ("down-sweep 1", dn1, {3, 7}),
            ("down-sweep 2", dn2, {1, 3, 5, 7}), ("down-sweep 3", dn3, set(range(8)))]
    for k, (label, values, hot) in enumerate(rows):
        row(62 - k * 8.2, values, label, hot)
    d.text(x0 + 8 * (cell + 0.8) + 6, 62 - 3 * 8.2 + 3, "the root holds the total, 25", size=6.2, ha="left",
           color=C["muted"])
    d.text(x0 + 8 * (cell + 0.8) + 6, 62 - 7 * 8.2 + 3, "the exclusive prefix sums", size=6.2, ha="left",
           color=C["muted"])
    d.text(84, 1.5, "highlighted: elements written in that step; each step is one loop iteration between barriers",
           size=6.0, color=C["muted"])
    d.save("u2-blelloch")


def multilevel():
    d = Diagram(168, 56)
    for b in range(4):
        x = 4 + b * 30
        d.box(x, 40, 27, 8, f"block {b}", kind="navy_t", size=6.6, weight="normal", radius=0.8)
    d.text(130, 44, "1  scan each block of the input,\n    writing each block's total", size=6.2, ha="left")
    d.box(34, 24, 60, 8, "block totals, scanned the same way", kind="purple_t", size=6.4, weight="normal",
          radius=0.8)
    d.text(130, 28, "2  scan the totals: block b's offset\n    is the sum of blocks 0 to b − 1", size=6.2,
           ha="left")
    for b in range(4):
        x = 4 + b * 30
        d.box(x, 8, 27, 8, f"block {b} + offset {b}", kind="coral_t", size=6.2, weight="normal", radius=0.8)
        d.arrow((x + 13.5, 39.6), (64, 32.4), color=C["muted"], lw=0.5, mutation=4)
        d.arrow((64, 23.6), (x + 13.5, 16.4), color=C["muted"], lw=0.5, mutation=4)
    d.text(130, 12, "3  add each block's offset to\n    every element of the block", size=6.2, ha="left")
    d.text(4, 2, "When the totals are more than one block, step 2 is the same algorithm again, one level up.", size=6.2,
           ha="left", color=C["muted"])
    d.save("u2-multilevel")


def radix():
    d = Diagram(168, 72)
    d.text(2, 68, "One pass of the LSD radix sort, for a 4-bit digit", size=7.2, weight="bold", ha="left",
           color=C["navy"])
    for b in range(3):
        x = 4 + b * 34
        d.box(x, 50, 30, 10, f"block {b} of keys", kind="navy_t", size=6.6, weight="normal", radius=0.8)
    d.text(110, 55, "count: each workgroup counts its block's\nkeys by digit, into shared memory", size=6.2,
           ha="left")
    labels = []
    for dgt in range(3):
        for b in range(3):
            labels.append(f"d{dgt}b{b}")
    for i, lab in enumerate(labels):
        d.rect(4 + i * 10.6, 34, 10, 6, fill=C["purple_t"], edge=C["purple"], lw=0.4)
        d.text(4 + i * 10.6 + 5, 37, lab, size=5.4, mono=True)
    d.text(4 + 9 * 10.6 + 1, 37, "...", size=7, ha="left")
    d.text(110, 37, "counts, digit-major: every block's count\nof digit 0, then of digit 1, and so on", size=6.2,
           ha="left")
    d.box(4, 18, 96, 8, "exclusive scan of the counts: where each block's keys of each digit start",
          kind="purple", size=6.2, weight="normal", radius=0.8)
    d.text(110, 22, "a multi-level scan, as for any other array", size=6.2, ha="left")
    d.box(4, 2, 96, 9, "scatter: sort the block by digit in shared memory, stably, then write each key to\n"
                       "its digit's start plus its rank among that digit's keys in the block", kind="coral_t",
          size=6.0, weight="normal", radius=0.8)
    d.text(110, 6.5, "stable within a block, blocks in order:\nthe whole pass is stable", size=6.2, ha="left")
    d.save("u2-radix")


def apron():
    d = Diagram(168, 54)
    for panel, (title, horizontal) in enumerate([("rows pass: tile plus left and right aprons", True),
                                                 ("columns pass: tile plus top and bottom aprons", False)]):
        x0 = 6 + panel * 84
        d.text(x0, 50, title, size=7, weight="bold", ha="left", color=C["navy"])
        cell = 2.2
        tile, r = 8, 4
        cols = tile + 2 * r if horizontal else tile
        rows = tile if horizontal else tile + 2 * r
        oy = 9 if horizontal else 8
        for j in range(rows):
            for i in range(cols):
                in_tile = (r <= i < r + tile) if horizontal else (r <= j < r + tile)
                d.rect(x0 + i * cell, oy + (rows - 1 - j) * cell + (8 if horizontal else 0), cell - 0.25, cell - 0.25,
                       fill=C["navy_t"] if in_tile else C["amber_t"], edge=C["navy"] if in_tile else C["amber"],
                       lw=0.25)
        tx = x0 + cols * cell + 4
        d.text(tx, 30, "tile: one pixel per invocation", size=6.2, ha="left", color=C["navy"])
        d.text(tx, 25, "apron: RADIUS pixels each side,\nloaded into shared memory too", size=6.2, ha="left",
               color=C["amber"])
    d.text(84, 1.5, "drawn with a tile of 8 and a radius of 4; the program uses 16 and 8", size=6.0,
           color=C["muted"])
    d.save("u2-apron")


def measured_roofline():
    import numpy as np
    lines = (CONSOLE / "u2-bandwidth.txt").read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith("k  FLOP/byte"))
    pts = []
    for l in lines[start + 1:]:
        c = l.split()
        if len(c) < 5 or not c[0].isdigit():
            break
        pts.append((float(c[1]), float(c[3])))
    peak_bw = max(float(l.split()[2]) for l in lines if l.startswith("vkCmdCopyBuffer"))
    peak_fl = max(g for _, g in pts)
    fig, ax = plot(h=60)
    ai = np.logspace(-1, 3, 300)
    ax.loglog(ai, np.minimum(peak_fl, ai * peak_bw), color=C["muted"], lw=1.0, ls="--",
              label=f"bounds: {peak_bw:.0f} GB/s and {peak_fl / 1000:.1f} TFLOP/s")
    ax.loglog([p[0] for p in pts], [p[1] for p in pts], "o-", color=C["navy"], ms=3.5, lw=1.2,
              label="measured: k fused multiply-adds per float")
    ridge = peak_fl / peak_bw
    ax.axvline(ridge, color=C["coral"], lw=0.7)
    ax.text(ridge * 1.1, 25, f"ridge point\n{ridge:.0f} FLOP/byte", fontsize=6.6, color=C["coral"])
    ax.set_xlabel("arithmetic intensity (FLOP per byte moved)")
    ax.set_ylabel("GFLOP/s")
    ax.set_xlim(0.1, 1000)
    ax.legend(frameon=False, fontsize=6.8, loc="upper left")
    save(fig, "u2-roofline")


def strided():
    lines = (CONSOLE / "u2-bandwidth.txt").read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.split()[:2] == ["stride", "ms"])
    rows = []
    for l in lines[start + 1:]:
        c = l.split()
        if len(c) < 3 or not c[0].isdigit():
            break
        rows.append((int(c[0]), float(c[2])))
    fig, ax = plot(h=44)
    ax.plot([r[0] for r in rows], [r[1] for r in rows], "o-", color=C["coral"], ms=3.5, lw=1.2)
    ax.set_xscale("log", base=2)
    ax.set_xticks([r[0] for r in rows], [str(r[0]) for r in rows])
    ax.set_ylim(0, max(r[1] for r in rows) * 1.15)
    ax.set_xlabel("stride between neighbouring invocations' reads, in floats")
    ax.set_ylabel("GB/s")
    save(fig, "u2-strided")


def tune_heatmap():
    import numpy as np
    lines = (CONSOLE / "u2-tune.txt").read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("GB/s by local size"))
    header = [int(x) for x in lines[start + 1].split()]
    rows, labels = [], []
    for l in lines[start + 2:]:
        c = l.split()
        if not c:
            break
        labels.append(int(c[0]))
        rows.append([float(x) for x in c[1:]])
    data = np.array(rows)
    fig, ax = plot(h=58)
    ax.grid(False)
    from matplotlib.colors import LinearSegmentedColormap
    cmap = LinearSegmentedColormap.from_list("course", [C["amber_t"], C["amber"], C["coral"], C["magenta"]])
    im = ax.imshow(data, cmap=cmap, aspect="auto")
    ax.set_xticks(range(len(header)), [str(h) for h in header])
    ax.set_yticks(range(len(labels)), [str(l) for l in labels])
    ax.set_xlabel("local size")
    ax.set_ylabel("elements per invocation")
    for i in range(data.shape[0]):
        for j in range(data.shape[1]):
            ax.text(j, i, f"{data[i, j]:.0f}", ha="center", va="center", fontsize=6.4,
                    color="white" if data[i, j] > 150 else C["ink"])
    fig.colorbar(im, ax=ax, label="GB/s", shrink=0.9)
    save(fig, "u2-tune")


def nbody_tiles():
    d = Diagram(168, 56)
    d.text(2, 52, "Each workgroup computes the forces on its own particles, one tile of sources at a time",
           size=7, weight="bold", ha="left", color=C["navy"])
    tiles = 6
    for t in range(tiles):
        x = 4 + t * 18
        hot = t == 2
        d.box(x, 34, 16, 8, f"tile {t}", kind="coral" if hot else "coral_t", size=6.2, weight="normal", radius=0.6)
    d.text(4 + tiles * 18 + 2, 38, "all particles' positions, in global memory", size=6.0, ha="left",
           color=C["muted"])
    d.arrow((48, 33.6), (60, 25.4), color=C["coral"], lw=0.7, mutation=5)
    d.text(64, 30, "1  every invocation loads one position of the tile into shared memory; barrier", size=6.0,
           ha="left", color=C["ink"])
    d.box(40, 16, 40, 9, "shared tile of 256 positions", kind="purple_t", size=6.4, weight="normal", radius=0.6)
    for k in range(8):
        d.arrow((44 + k * 4.5, 15.6), (44 + k * 4.5, 10.4), color=C["purple"], lw=0.4, mutation=3)
    d.box(40, 2, 40, 8, "256 invocations, one particle each", kind="navy_t", size=6.4, weight="normal", radius=0.6)
    d.text(84, 8, "2  each invocation accumulates the pull of all 256 sources\n    from shared memory; barrier; "
                  "next tile", size=6.0, ha="left", color=C["ink"])
    d.save("u2-nbody-tiles")


def grid2d():
    d = Diagram(168, 40)
    d.text(2, 36, "64 workgroups of work, with at most 16 per dimension: a 16 × 4 grid", size=7, weight="bold",
           ha="left", color=C["navy"])
    for y in range(4):
        for x in range(16):
            n = y * 16 + x
            d.rect(4 + x * 6.2, 24 - y * 6, 5.6, 5.2, fill=C["navy_t"], edge=C["navy"], lw=0.4)
            if x < 3 or x == 15:
                d.text(4 + x * 6.2 + 2.8, 24 - y * 6 + 2.6, str(n), size=5.2, mono=True)
    d.text(110, 18, "group = gl_WorkGroupID.y × gl_NumWorkGroups.x\n          + gl_WorkGroupID.x\n"
                    "particle = group × 256 + gl_LocalInvocationIndex", size=6.0, ha="left", mono=True,
           color=C["purple"])
    d.save("u2-grid2d")


def bvh():
    d = Diagram(168, 64)
    d.text(2, 61, "A bounding volume hierarchy: boxes around the scene, and nodes in a buffer", size=7,
           weight="bold", ha="left", color=C["navy"])
    tris = [((8, 10), (15, 8), (11, 16)), ((14, 16), (21, 13), (19, 21)),
            ((9, 30), (16, 27), (12, 36)), ((17, 34), (24, 31), (21, 40)),
            ((44, 12), (51, 9), (48, 18)), ((52, 16), (60, 14), (56, 22)),
            ((46, 34), (53, 31), (50, 40)), ((55, 40), (63, 37), (60, 46))]

    def bounds(points, pad):
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad

    def corners(b):
        return [(b[0], b[1]), (b[2], b[3])]

    leaves = [bounds([v for t in tris[2 * i:2 * i + 2] for v in t], 1.2) for i in range(4)]
    inner = [bounds(corners(leaves[0]) + corners(leaves[1]), 1.5),
             bounds(corners(leaves[2]) + corners(leaves[3]), 1.5)]
    root = bounds(corners(inner[0]) + corners(inner[1]), 2.0)
    colours = [C["purple"], C["coral"]]

    def outline(b, colour, dashed=False, lw=0.6):
        d.rect(b[0], b[1], b[2] - b[0], b[3] - b[1], edge=colour, lw=lw, dashed=dashed, z=2)

    outline(root, C["navy"], lw=0.7)
    d.text(root[0], root[3] + 2.2, "A", size=6.4, weight="bold", color=C["navy"], ha="left")
    for i, b in enumerate(inner):
        outline(b, colours[i], lw=0.6)
        d.text(b[2] - 1.4, b[3] - 2.2, "BC"[i], size=6.4, weight="bold", color=colours[i], ha="right")
    for i, b in enumerate(leaves):
        outline(b, colours[i // 2], dashed=True, lw=0.45)
    for i, t in enumerate(tris):
        d.poly(list(t), fill=C["navy_t"], edge=C["navy"], lw=0.45, z=3)
    hit = (18.9, 36.85)
    d.arrow((0.5, 44.6), hit, color=C["amber"], lw=0.9, mutation=5, z=5)
    d.line(hit, (40, 28.0), color=C["amber"], lw=0.6, dashed=True, z=5)
    d.dot(hit[0], hit[1], r=0.9, color=C["amber"])
    d.text(0.8, 41.6, "ray", size=6.0, color=C["muted"], ha="left")
    d.text(35, 1.4, "C is visited after B, but its children's boxes lie beyond the hit, so none of its"
                    " triangles is tested", size=5.6, color=C["muted"])

    nodes = {0: (118, 46), 1: (100, 36), 2: (136, 36), 3: (92, 26), 4: (108, 26), 5: (128, 26), 6: (144, 26)}
    labels = {0: "0  A", 1: "1  B", 2: "2  C", 3: "3", 4: "4", 5: "5", 6: "6"}
    kinds = {0: "navy_t", 1: "purple_t", 2: "coral_t", 3: "purple_t", 4: "purple_t", 5: "coral_t", 6: "coral_t"}
    for child, parent in ((1, 0), (2, 0), (3, 1), (4, 1), (5, 2), (6, 2)):
        (cx, cy), (px, py) = nodes[child], nodes[parent]
        d.line((px + 6, py), (cx + 6, cy + 6), color=C["muted"], lw=0.5, z=1)
    for n, (x, y) in nodes.items():
        d.box(x, y, 12, 6, labels[n], kind=kinds[n], size=6.0, weight="normal", radius=0.6,
              dashed=n in (5, 6))
    d.text(84, 56, "The nodes, in the order the builder writes them", size=6.2, weight="bold",
           ha="left", color=C["ink"])
    rows = [("0", "1", "0"), ("1", "3", "0"), ("2", "5", "0"), ("3", "0", "2"), ("4", "2", "2"),
            ("5", "4", "2"), ("6", "6", "2")]
    d.text(84, 20, "node", size=5.6, color=C["muted"], ha="left")
    d.text(84, 16.5, "leftOrFirst", size=5.6, color=C["muted"], ha="left")
    d.text(84, 13, "count", size=5.6, color=C["muted"], ha="left")
    for i, (n, first, count) in enumerate(rows):
        x = 104 + i * 9
        d.rect(x, 11, 8.4, 11, fill=C["grey"], edge=C["rule"], lw=0.4)
        d.text(x + 4.2, 20, n, size=5.8, mono=True, weight="bold")
        d.text(x + 4.2, 16.5, first, size=5.8, mono=True)
        d.text(x + 4.2, 13, count, size=5.8, mono=True)
    d.text(104, 2.4, "inner node: children at leftOrFirst and leftOrFirst + 1, count 0\n"
                     "leaf: count triangles from leftOrFirst", size=5.4, color=C["muted"], ha="left",
           va="bottom")
    d.save("u2-bvh")


if __name__ == "__main__":
    for f in (hierarchy, localsize, transpose, banks, transpose_results, histogram_results, reduction_trees,
              reduce_results, blelloch, multilevel, radix, apron, measured_roofline, strided, tune_heatmap,
              nbody_tiles, grid2d, bvh):
        f()
        print("drew", f.__name__)
