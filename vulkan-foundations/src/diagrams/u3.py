from pathlib import Path

from vkfig import C, Diagram

CONSOLE = Path(__file__).resolve().parents[1] / "console"


def overlap():
    d = Diagram(168, 82)
    rows = ["unit 0", "unit 1", "unit 2", "unit 3"]
    for panel, (title, with_barrier) in enumerate([("Without a barrier: B starts while A is still running", False),
                                                   ("With a barrier: B waits for A, and A's writes reach B", True)]):
        y0 = 46 - panel * 38
        d.text(2, y0 + 31, title, size=7.2, weight="bold", ha="left", color=C["navy"])
        for r, name in enumerate(rows):
            y = y0 + 22 - r * 6.2
            d.text(16, y + 2, name, size=6.2, ha="right", color=C["muted"])
            d.line((18, y + 2), (164, y + 2), color=C["rule"], lw=0.4)
            a_end = [62, 70, 58, 76][r]
            d.rect(18 + r * 1.5, y, a_end - 18 - r * 1.5, 4, fill=C["navy"], edge=C["navy"], lw=0.3)
            if with_barrier:
                b0 = 86
                d.rect(b0 + 4, y, 46 + r * 2, 4, fill=C["coral"], edge=C["coral"], lw=0.3)
            else:
                b0 = a_end + 1
                d.rect(b0, y, 48, 4, fill=C["coral"], edge=C["coral"], lw=0.3)
        if with_barrier:
            d.rect(77, y0 + 2.5, 12, 22, fill=C["amber_t"], edge=C["amber"], lw=0.5)
            d.text(83, y0 + 13.5, "wait,\nflush,\nmake\nvisible", size=5.6, color=C["ink"])
    d.box(18, 0.5, 22, 4.6, "dispatch A writes", kind="navy", size=5.8, weight="normal", radius=0.6)
    d.box(44, 0.5, 22, 4.6, "dispatch B reads", kind="coral", size=5.8, weight="normal", radius=0.6)
    d.box(70, 0.5, 22, 4.6, "barrier", kind="amber_t", size=5.8, weight="normal", radius=0.6)
    d.save("u3-overlap")


def hazard_kinds():
    d = Diagram(168, 40)
    kinds = [
        ("Read after write", "RAW", "write", "read", "the read must see the write:\nexecution and memory dependency"),
        ("Write after read", "WAR", "read", "write", "the read must finish first:\nexecution dependency only"),
        ("Write after write", "WAW", "write", "write", "the second write must land last:\nexecution and memory dependency"),
    ]
    for k, (title, short, first, second, note) in enumerate(kinds):
        x = 2 + k * 56
        d.text(x, 36, f"{title} ({short})", size=7.2, weight="bold", ha="left", color=C["navy"])
        d.box(x, 20, 20, 8, first, kind="navy" if first == "write" else "navy_t", size=7, radius=0.8)
        d.box(x + 30, 20, 20, 8, second, kind="coral" if second == "write" else "coral_t", size=7, radius=0.8)
        d.arrow((x + 20.5, 24), (x + 29.5, 24), color=C["ink"], lw=0.8, mutation=6)
        d.text(x + 25, 12, note, size=6.0, color=C["muted"])
    d.save("u3-hazard-kinds")


def scopes():
    d = Diagram(168, 62)
    d.group(2, 14, 50, 42, "first synchronisation scope", color=C["navy"], dashed=False, size=6.6)
    d.box(6, 36, 42, 9, "commands before the barrier", sub="in submission order", kind="navy_t", size=6.8,
          sub_size=5.8)
    d.box(6, 24, 42, 8, "srcStageMask: COMPUTE_SHADER", kind="navy", size=6.2, weight="normal", mono=False)
    d.box(6, 16, 42, 6.5, "srcAccessMask: SHADER_STORAGE_WRITE", kind="plain", size=5.8, weight="normal")
    d.group(116, 14, 50, 42, "second synchronisation scope", color=C["coral"], dashed=False, size=6.6)
    d.box(120, 36, 42, 9, "commands after the barrier", sub="in submission order", kind="coral_t", size=6.8,
          sub_size=5.8)
    d.box(120, 24, 42, 8, "dstStageMask: COMPUTE_SHADER", kind="coral", size=6.2, weight="normal")
    d.box(120, 16, 42, 6.5, "dstAccessMask: SHADER_STORAGE_READ", kind="plain", size=5.8, weight="normal")
    d.box(60, 22, 48, 26, "", kind="amber_t")
    d.text(84, 44.5, "vkCmdPipelineBarrier2", size=6.8, mono=True, color=C["ink"])
    steps = ["1  wait for the source stages", "2  make the source writes available",
             "3  make them visible to the", "    destination accesses",
             "4  then let the destination", "    stages start"]
    for i, t in enumerate(steps):
        d.text(63, 39.5 - i * 3.3, t, size=5.9, ha="left", color=C["ink"])
    d.arrow((52.5, 35), (59.5, 35), color=C["ink"], lw=0.8, mutation=6)
    d.arrow((108.5, 35), (115.5, 35), color=C["ink"], lw=0.8, mutation=6)
    d.text(84, 8, "Stage masks also cover logically earlier (source) or later (destination) stages;\n"
                  "access masks apply only to the stages named.", size=6.2, color=C["muted"])
    d.save("u3-scopes")


def stages():
    d = Diagram(168, 58)
    graphics = ["DRAW_INDIRECT", "INDEX_INPUT", "VERTEX_ATTRIBUTE_INPUT", "VERTEX_SHADER",
                "EARLY_FRAGMENT_TESTS", "FRAGMENT_SHADER", "LATE_FRAGMENT_TESTS", "COLOR_ATTACHMENT_OUTPUT"]
    d.text(2, 54, "Graphics, in logical order", size=7, weight="bold", ha="left", color=C["purple"])
    w = 20.2
    for i, name in enumerate(graphics):
        x = 2 + i * (w + 0.6)
        d.box(x, 40, w, 9, name.replace("_", "_\n", 1) if len(name) > 13 else name, kind="purple_t", size=4.9,
              weight="normal", mono=True, radius=0.8)
    d.text(2, 34, "Compute", size=7, weight="bold", ha="left", color=C["coral"])
    d.box(2, 20, w, 9, "DRAW_INDIRECT", kind="coral_t", size=4.9, weight="normal", mono=True, radius=0.8)
    d.box(2 + w + 0.6, 20, w, 9, "COMPUTE_SHADER", kind="coral_t", size=4.9, weight="normal", mono=True, radius=0.8)
    d.text(52, 34, "Transfer", size=7, weight="bold", ha="left", color=C["navy"])
    for i, name in enumerate(["COPY", "BLIT", "RESOLVE", "CLEAR"]):
        d.box(52 + i * 15.5, 20, 15, 9, name, kind="navy_t", size=5.2, weight="normal", mono=True, radius=0.8)
    d.text(52 + 31, 16, "TRANSFER = all four", size=5.8, color=C["muted"])
    d.text(118, 34, "Host", size=7, weight="bold", ha="left", color=C["green"])
    d.box(118, 20, 20, 9, "HOST", kind="green_t", size=5.2, weight="normal", mono=True, radius=0.8)
    d.text(2, 8, "NONE: no stage.   ALL_COMMANDS: every stage of every command.   ALL_GRAPHICS: every graphics stage.",
           size=6.2, ha="left", color=C["ink"])
    d.text(2, 3, "Names are shown without their prefix VK_PIPELINE_STAGE_2_ and suffix _BIT.", size=5.8,
           ha="left", color=C["muted"])
    d.save("u3-stages")


def chain():
    d = Diagram(168, 30)
    xs = [2, 60, 118]
    names = ["dispatch A\nwrites x", "dispatch B\nreads x, writes y", "copy C\nreads y"]
    for x, n in zip(xs, names):
        d.box(x, 10, 40, 12, n, kind="navy_t", size=6.6, weight="normal")
    for k, (x, label) in enumerate([(44, "barrier 1"), (102, "barrier 2")]):
        d.box(x, 11, 12, 10, label, kind="amber_t", size=5.6, weight="normal", radius=0.8)
        d.arrow((x - 1.5, 16), (x - 0.5, 16), color=C["ink"], lw=0.6, mutation=5)
        d.arrow((x + 12.5, 16), (x + 13.5, 16), color=C["ink"], lw=0.6, mutation=5)
    d.path([(22, 22.5), (22, 27), (138, 27), (138, 22.5)], color=C["coral"], lw=0.7, dashed=True)
    d.text(80, 28.8, "A happens before C: barrier 1's destination and barrier 2's source both include COMPUTE_SHADER",
           size=6.0, color=C["coral"])
    d.text(80, 4, "Each barrier orders its neighbours; together they form an execution dependency chain.", size=6.2,
           color=C["muted"])
    d.save("u3-chain")


def layouts():
    d = Diagram(168, 40)
    d.line((4, 20), (164, 20), color=C["rule"], lw=1.0)
    events = [
        (6, "UNDEFINED", "image created", "grey"),
        (46, "GENERAL", "dispatch writes\nthe image", "coral_t"),
        (96, "TRANSFER_SRC_OPTIMAL", "copy reads\nthe image", "navy_t"),
    ]
    for x, layout, what, kind in events:
        d.box(x, 23, 36 if len(layout) < 12 else 48, 7, layout, kind=kind, size=5.8, weight="normal", mono=True,
              radius=0.8)
        d.text(x + 2, 13, what, size=6.0, ha="left", color=C["ink"])
    for x, label in [(42.5, "transition 1"), (92.5, "transition 2")]:
        d.line((x, 16), (x, 33), color=C["amber"], lw=1.4)
        d.text(x, 35.5, label, size=6.0, color=C["amber"], weight="semibold")
    d.text(84, 3, "Each transition is part of a barrier: it happens after the barrier's source scope and before "
                  "its destination scope, and it both reads and writes the image.", size=6.0, color=C["muted"])
    d.save("u3-layouts")


def passes():
    d = Diagram(168, 62)
    nodes = [
        ("generate", "writes field", 2, 32),
        ("blur", "reads field", 36, 42),
        ("edges", "reads field", 36, 22),
        ("select", "writes stats, list", 70, 32),
        ("command", "writes indirect args", 104, 32),
        ("score", "indirect; reads list", 138, 32),
    ]
    boxes = {}
    for name, sub, x, y in nodes:
        boxes[name] = d.box(x, y, 26, 11, name, sub=sub, kind="navy_t", size=7, sub_size=5.6)
    for a, b in [("generate", "blur"), ("generate", "edges"), ("blur", "select"), ("edges", "select"),
                 ("select", "command"), ("command", "score")]:
        d.arrow(boxes[a].e, boxes[b].w_, color=C["muted"], lw=0.7, mutation=6, shrink=0.5)
    for x, label in [(31, "1"), (65, "2"), (99, "3"), (133, "4")]:
        d.line((x, 18), (x, 57), color=C["amber"], lw=1.6)
        d.text(x, 58.8, label, size=6.6, color=C["amber"], weight="bold")
    for i, t in enumerate(["1  the field's writes → shader reads",
                           "2  blur and edges' writes, and the clear of stats → shader reads and writes",
                           "3  select's writes → shader reads and writes",
                           "4  command's writes → DRAW_INDIRECT, INDIRECT_COMMAND_READ"]):
        d.text(4, 13 - i * 3.6, t, size=6.0, color=C["ink"], ha="left")
    d.save("u3-passes")


def cost():
    import re
    from vkfig import plot, save
    lines = (CONSOLE / "u3-passes-timing.txt").read_text().splitlines()
    rows = []
    for line in lines:
        m = re.match(r"\s+(chain|independent)\s+(.+?)\s{2,}(\d+)\s+([\d.]+)\s+([\d.]+)$", line)
        if m:
            rows.append((m.group(1), m.group(2), float(m.group(4))))
    labels = [f"{seq}\n{b.replace('COMPUTE write -> COMPUTE read/write', 'precise').replace('ALL_COMMANDS -> ALL_COMMANDS', 'ALL_COMMANDS')}"
              for seq, b, _ in rows]
    fig, ax = plot(h=50)
    colours = [C["navy"], C["coral"], C["green"], C["navy"], C["coral"]]
    bars = ax.bar(range(len(rows)), [ms for _, _, ms in rows], color=colours, width=0.6)
    for b, (_, _, ms) in zip(bars, rows):
        ax.text(b.get_x() + b.get_width() / 2, ms + 0.15, f"{ms:.2f}", ha="center", fontsize=6.6)
    ax.set_xticks(range(len(rows)), labels, fontsize=6.6)
    ax.set_ylabel("ms for 256 dispatches")
    save(fig, "u3-cost")


def frames():
    d = Diagram(168, 56)
    scale, x0 = 11.6, 30.0

    def block(t0, t1, y, label, kind):
        x = x0 + t0 * scale
        d.box(x, y, (t1 - t0) * scale - 0.4, 5, label, kind=kind, size=5.6, weight="normal", radius=0.4)

    def lanes(y, title):
        d.text(2, y + 14.5, title, size=7, weight="bold", ha="left", color=C["navy"])
        for name, dy in (("CPU", 6.5), ("GPU", 0)):
            d.text(x0 - 2, y + dy + 2.5, name, size=6.2, ha="right", color=C["muted"])
            d.line((x0, y + dy - 0.6), (x0 + 11.4 * scale, y + dy - 0.6), color=C["rule"], lw=0.4)

    y = 38
    lanes(y, "One frame in flight: the CPU waits for each frame before preparing the next")
    t = 0.0
    for f in range(3):
        block(t, t + 1.76, y + 6.5, f"prepare {f}", "purple_t")
        block(t + 1.76, t + 3.68, y + 6.5, "wait", "grey")
        block(t + 2.06, t + 3.19, y, f"run {f}", "navy_t")
        t += 3.68

    y = 8
    lanes(y, "Two frames in flight: the CPU prepares frame n + 1 while the GPU runs frame n")
    for f in range(6):
        t = f * 1.77
        block(t, t + 1.77, y + 6.5, f"prepare {f}", "purple_t")
        if f < 5:
            block(t + 2.07, t + 3.20, y, f"run {f}", "navy_t")
    for ms in range(0, 12, 2):
        x = x0 + ms * scale
        d.line((x, 4.6), (x, 5.6), color=C["muted"], lw=0.4)
        d.text(x, 2.6, f"{ms} ms", size=5.6, color=C["muted"])
    d.save("u3-frames")


def declared():
    d = Diagram(168, 66)
    d.text(2, 63, "What each pass declares: R reads a resource's contents, W writes new contents",
           size=7, weight="bold", ha="left", color=C["navy"])
    resources = ["stats", "field", "blurred", "edges", "scratch", "list", "mask", "command",
                 "results"]
    passes = [("clear-stats", {"stats": "W"}),
              ("generate", {"field": "W"}),
              ("blur", {"field": "R", "blurred": "W"}),
              ("edges", {"field": "R", "edges": "W"}),
              ("debug-copy", {"blurred": "R", "scratch": "W"}),
              ("select", {"blurred": "R", "edges": "R", "stats": "RW", "list": "W", "mask": "W"}),
              ("command", {"stats": "R", "command": "W"}),
              ("score", {"command": "R", "list": "R", "blurred": "R", "stats": "RW"}),
              ("readback", {"stats": "R", "mask": "R", "results": "W"}),
              ("host", {"results": "R"})]
    x0, w, top, h = 40, 13.2, 52, 4.6
    for c, name in enumerate(resources):
        d.text(x0 + c * w + w / 2, top + 4.2, name, size=5.8, mono=True, color=C["ink"])
    kinds = {"R": "navy_t", "W": "coral_t", "RW": "purple_t"}
    for r, (name, uses) in enumerate(passes):
        y = top - (r + 1) * h
        culled = name == "debug-copy"
        label = name + ("  (culled)" if culled else "  (side effect)" if name == "host" else "")
        d.text(x0 - 2, y + h / 2, label, size=5.8, ha="right",
               color=C["muted"] if culled else C["ink"])
        for c, res in enumerate(resources):
            x = x0 + c * w
            d.rect(x, y, w, h, fill=C["white"], edge=C["rule"], lw=0.3)
            if res in uses:
                kind = "ghost" if culled else kinds[uses[res]]
                d.box(x + 0.8, y + 0.6, w - 1.6, h - 1.2, uses[res].replace("RW", "R W"),
                      kind=kind, size=5.6, weight="normal", radius=0.4)
    d.text(x0, 1.6, "Every resource but results is transient: the graph creates it and places it "
                    "in memory. results is imported.", size=5.6, ha="left", color=C["muted"])
    d.save("u3-declared")


def aliasing():
    d = Diagram(168, 56)
    d.text(2, 53, "Transient memory over the kept passes: resources whose lifetimes do not "
                  "overlap share memory", size=7, weight="bold", ha="left", color=C["navy"])
    passes = ["clear-stats", "generate", "blur", "edges", "select", "command", "score",
              "readback", "host"]
    x0, w = 30, 14.4
    lanes = [("about 3 MiB", [("list", 4, 6, "navy_t")]),
             ("about 2 MiB", [("edges", 3, 4, "navy_t"), ("command", 5, 6, "coral_t")]),
             ("about 1 MiB", [("blurred", 2, 6, "navy_t")]),
             ("128 bytes", [("field", 1, 3, "navy_t"), ("mask", 4, 7, "coral_t")]),
             ("0", [("stats", 0, 7, "purple_t")])]
    for i, (label, items) in enumerate(lanes):
        y = 40 - i * 7.2
        d.text(x0 - 2, y + 2.6, label, size=5.8, ha="right", color=C["muted"])
        d.line((x0, y - 0.6), (x0 + 9 * w, y - 0.6), color=C["rule"], lw=0.4)
        for name, first, last, kind in items:
            d.box(x0 + first * w + 0.4, y, (last - first + 1) * w - 0.8, 5.2, name, kind=kind,
                  size=5.8, weight="normal", radius=0.5, mono=True)
    for k, name in enumerate(passes):
        d.text(x0 + k * w + w / 2, 6.6, f"{k} {name}", size=5.4, color=C["muted"])
    d.text(x0, 1.8, "mask reuses field's memory and command reuses edges': 4 MiB in all, "
                    "against 5 MiB with every resource apart", size=5.6, ha="left",
           color=C["muted"])
    d.save("u3-aliasing")


if __name__ == "__main__":
    for f in (overlap, hazard_kinds, scopes, stages, chain, layouts, passes, cost, frames, declared, aliasing):
        f()
        print("drew", f.__name__)
