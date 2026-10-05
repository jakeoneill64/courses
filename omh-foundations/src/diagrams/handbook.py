import re
from pathlib import Path

from omhfig import C, Diagram

ROOT = Path(__file__).resolve().parents[1]

UNITS = [
    ("1", "Circuits, Sensors\nand Signals", C["amber"], "amber_t",
     ["Electricity and components", "Analogue signal chain", "Sensors with TI silicon", "Power and batteries",
      "Wires and RF basics"]),
    ("2", "Logic, Processors\nand Firmware", C["coral"], "coral_t",
     ["Digital logic", "HDL and FPGA", "Build a CPU", "Memory, interconnect", "Privilege, platform",
      "Bare-metal firmware", "Boot, platform firmware"]),
    ("3", "Control, Radio\nand Boards", C["magenta"], "magenta_t",
     ["Motors and control", "Radio links", "Synthesis and radar", "Boards: P, F, A, B", "The drone"]),
    ("4", "Systems Software\nand the Product", C["purple"], "purple_t",
     ["Write a kernel", "Linux internals", "Device drivers", "Virtualisation", "Data paths",
      "Product engineering", "Module Zero"]),
]

FALLBACK_WEEKS = {"4.3": 4.0, "4.4": 5.0, "4.6": 2.0, "4.7": 6.0}


def chapter_weeks():
    weeks = {}
    for u, *_ in UNITS:
        for p in (ROOT / f"u{u}").glob("ch*.typ"):
            n = int(re.match(r"ch(\d+)", p.name).group(1))
            m = re.search(r"weeks:\s*\[([\d.]+)", p.read_text())
            if m:
                weeks[f"{u}.{n}"] = float(m.group(1))
    for k, v in FALLBACK_WEEKS.items():
        weeks.setdefault(k, v)
    return weeks


def course_map():
    d = Diagram(168, 112)
    col_w, gap = 38.5, 4.0
    nodes = {}
    for i, (u, title, col, tint, chapters) in enumerate(UNITS):
        x = 2 + i * (col_w + gap)
        d.box(x, 99, col_w, 11, f"Unit {u}", sub=title.replace("\n", " "), kind="navy", size=8.0, sub_size=5.6)
        d.rect(x, 97.2, col_w, 1.2, fill=col, edge=None, z=4)
        for j, name in enumerate(chapters):
            y = 86 - j * 12.2
            final = (u, j) in (("3", 4), ("4", 6))
            node = d.box(x, y, col_w, 9, f"{u}.{j + 1}  {name}", kind=("magenta" if u == "3" else "purple") if final else tint,
                         size=6.8, weight="semibold" if final else "normal", align="left")
            nodes[f"{u}.{j + 1}"] = node
    d.badge(nodes["3.5"].cx, nodes["3.5"].y - 3.6, "it flies", kind="amber", size=6.4)
    d.badge(nodes["4.7"].cx, nodes["4.7"].y - 3.6, "it serves", kind="amber", size=6.4)
    d.save("h-map")


def timeline():
    weeks = chapter_weeks()
    d = Diagram(168, 62)
    x0, scale = 16, 146 / 84
    rows = {"1": 48, "2": 38, "3": 28, "4": 13}
    t = 0.0
    starts = {}
    for u, _, col, tint, chapters in UNITS:
        y = rows[u]
        d.text(x0 - 2, y + 3.5, f"Unit {u}", size=7.0, weight="bold", ha="right")
        for j in range(len(chapters)):
            key = f"{u}.{j + 1}"
            w = weeks.get(key, 3.0)
            starts[key] = t
            x = x0 + t * scale
            d.box(x + 0.2, y, w * scale - 0.4, 7, key if w * scale > 6 else "", kind=tint, size=6.2, radius=0.6, lw=0.6)
            t += w
    s34 = starts["3.4"]
    d.text(x0 - 2, 23.2, "fabrication", size=6.0, color=C["muted"], ha="right")
    for label, off, y in (("P and F", 2.0, 21.4), ("A and B", 4.0, 21.4)):
        x = x0 + (s34 + off) * scale
        d.box(x, y, 3 * scale, 3.6, "", kind="ghost", dashed=True, radius=0.5, lw=0.6)
    d.text(x0 + (s34 + 2.0) * scale - 1, 23.2, "P, F", size=5.6, color=C["muted"], ha="right")
    d.text(x0 + (s34 + 7.0) * scale + 1, 23.2, "A, B", size=5.6, color=C["muted"], ha="left")
    for wk in range(0, 85, 12):
        x = x0 + wk * scale
        d.line((x, 11.5), (x, 56.5), color=C["light"], lw=0.5, z=1)
        d.text(x, 58.8, f"{wk}", size=6.2, color=C["muted"])
    d.text(x0 - 2, 58.8, "week", size=6.2, color=C["muted"], ha="right")
    for key, label in (("3.5", "first hover"), ("4.7", "Module Zero demo")):
        x = x0 + (starts[key] + weeks[key] * 0.8) * scale
        y = rows[key[0]] + 7.0
        d.poly([(x - 1.4, y + 2.4), (x + 1.4, y + 2.4), (x, y)], fill=C["coral"], edge=None, z=6)
        d.text(x, y + 4.2, label, size=6.0, color=C["coral"], weight="semibold")
    d.text(x0 + t * scale + 1.5, rows["4"] + 3.5, f"{t:.0f}\nweeks", size=6.0, color=C["ink"], weight="bold", ha="left")
    d.save("h-timeline")


ALL = [course_map, timeline]

if __name__ == "__main__":
    for fn in ALL:
        fn()
        print("drew", fn.__name__)
