# Figures are drawn at printed size in millimetres (168 mm is the full text width) so their type matches the body text.

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("svg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import font_manager as fm  # noqa: E402
from matplotlib.patches import (  # noqa: E402
    Circle,
    FancyArrowPatch,
    FancyBboxPatch,
    Polygon,
    Rectangle,
)

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / "fonts"
OUT = ROOT / "figures"
MM = 1 / 25.4
TEXT_WIDTH = 168.0

C = dict(
    navy="#003F5C", purple="#58508D", magenta="#BC5090", coral="#FF6361", amber="#FFA600",
    ink="#1B2430", muted="#5A6472", rule="#C9D0D8", light="#E3E7EC", grey="#F4F6F8",
    navy_t="#E8EFF3", purple_t="#EFEEF6", magenta_t="#F8EEF4", coral_t="#FFF0EF",
    amber_t="#FFF5E0", green="#2E7D5B", green_t="#E9F4EE", white="#FFFFFF",
)

KIND = {
    "navy": (C["navy"], C["navy"], C["white"]),
    "purple": (C["purple"], C["purple"], C["white"]),
    "magenta": (C["magenta"], C["magenta"], C["white"]),
    "coral": (C["coral"], C["coral"], C["white"]),
    "amber": (C["amber"], C["amber"], C["ink"]),
    "green": (C["green"], C["green"], C["white"]),
    "navy_t": (C["navy"], C["navy_t"], C["ink"]),
    "purple_t": (C["purple"], C["purple_t"], C["ink"]),
    "magenta_t": (C["magenta"], C["magenta_t"], C["ink"]),
    "coral_t": (C["coral"], C["coral_t"], C["ink"]),
    "amber_t": (C["amber"], C["amber_t"], C["ink"]),
    "green_t": (C["green"], C["green_t"], C["ink"]),
    "plain": (C["muted"], C["white"], C["ink"]),
    "grey": (C["rule"], C["grey"], C["ink"]),
    "ghost": (C["rule"], "none", C["muted"]),
}

SANS = "Source Sans 3"
MONO = "JetBrains Mono"
SERIF = "Source Serif 4"

_ready = False


def setup() -> None:
    global _ready
    if _ready:
        return
    for f in sorted(FONTS.glob("*.otf")) + sorted(FONTS.glob("*.ttf")):
        fm.fontManager.addfont(str(f))
    plt.rcParams.update({
        "font.family": SANS,
        "font.size": 8.5,
        "svg.fonttype": "none",
        "svg.hashsalt": "omh-foundations",
        "mathtext.fontset": "custom",
        "mathtext.rm": SERIF,
        "mathtext.it": f"{SERIF}:italic",
        "mathtext.bf": f"{SERIF}:bold",
        "mathtext.cal": f"{SERIF}:italic",
        "mathtext.sf": SANS,
        "axes.edgecolor": C["muted"],
        "axes.labelcolor": C["ink"],
        "axes.linewidth": 0.7,
        "axes.titlesize": 9,
        "axes.titleweight": "semibold",
        "axes.labelsize": 8.5,
        "xtick.color": C["muted"],
        "ytick.color": C["muted"],
        "xtick.labelsize": 7.8,
        "ytick.labelsize": 7.8,
        "xtick.major.width": 0.6,
        "ytick.major.width": 0.6,
        "grid.color": C["light"],
        "grid.linewidth": 0.6,
        "legend.fontsize": 7.8,
        "legend.frameon": False,
        "lines.linewidth": 1.5,
        "figure.dpi": 100,
    })
    OUT.mkdir(parents=True, exist_ok=True)
    _ready = True


def save(fig, name: str, pad: float = 0.02) -> Path:
    path = OUT / f"{name}.svg"
    fig.savefig(path, bbox_inches="tight", pad_inches=pad, metadata={"Date": None}, transparent=True)
    plt.close(fig)
    return path


@dataclass
class Node:
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2

    @property
    def c(self):
        return (self.cx, self.cy)

    @property
    def n(self):
        return (self.cx, self.y + self.h)

    @property
    def s(self):
        return (self.cx, self.y)

    @property
    def e(self):
        return (self.x + self.w, self.cy)

    @property
    def w_(self):
        return (self.x, self.cy)

    def at(self, fx: float, fy: float):
        return (self.x + fx * self.w, self.y + fy * self.h)

    def top(self, f=0.5):
        return self.at(f, 1)

    def bottom(self, f=0.5):
        return self.at(f, 0)

    def left(self, f=0.5):
        return self.at(0, f)

    def right(self, f=0.5):
        return self.at(1, f)


class Diagram:

    def __init__(self, w: float = TEXT_WIDTH, h: float = 80.0):
        setup()
        self.w, self.h = w, h
        self.fig = plt.figure(figsize=(w * MM, h * MM))
        self.ax = self.fig.add_axes((0, 0, 1, 1))
        self.ax.set_xlim(0, w)
        self.ax.set_ylim(0, h)
        self.ax.set_aspect("equal")
        self.ax.axis("off")

    def text(self, x, y, s, size=8.5, color=None, weight="normal", ha="center", va="center",
             mono=False, style="normal", rotation=0, family=None, z=6, linespacing=1.15):
        fam = family or (MONO if mono else SANS)
        self.ax.text(x, y, s, fontsize=size, color=color or C["ink"], weight=weight, ha=ha, va=va,
                     family=fam, style=style, rotation=rotation, zorder=z, linespacing=linespacing)

    def box(self, x, y, w, h, label="", sub=None, kind="navy_t", size=8.5, weight="semibold",
            radius=1.6, mono=False, lw=0.9, sub_size=None, z=3, align="center", dashed=False,
            label_color=None, sub_color=None) -> Node:
        edge, fill, fg = KIND[kind]
        patch = FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={radius}",
                               linewidth=lw, edgecolor=edge, facecolor=fill, zorder=z,
                               linestyle=(0, (3, 2)) if dashed else "solid")
        self.ax.add_patch(patch)
        node = Node(x, y, w, h)
        tx = x + w / 2 if align == "center" else x + 2.2
        ha = "center" if align == "center" else "left"
        if sub:
            self.text(tx, y + h * 0.62, label, size=size, color=label_color or fg, weight=weight, mono=mono, ha=ha, z=z + 1)
            self.text(tx, y + h * 0.30, sub, size=sub_size or size - 1.4, color=sub_color or fg, ha=ha, z=z + 1,
                      mono=False)
        elif label:
            self.text(tx, y + h / 2, label, size=size, color=label_color or fg, weight=weight, mono=mono, ha=ha, z=z + 1)
        return node

    def group(self, x, y, w, h, label="", color=None, fill="none", dashed=True, size=8, z=1,
              label_pos="tl", lw=0.8) -> Node:
        col = color or C["muted"]
        patch = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=2.2", linewidth=lw,
                               edgecolor=col, facecolor=fill, zorder=z,
                               linestyle=(0, (4, 2.5)) if dashed else "solid")
        self.ax.add_patch(patch)
        if label:
            if label_pos == "tl":
                self.text(x + 2.2, y + h - 2.6, label, size=size, color=col, weight="bold", ha="left", va="center", z=z + 1)
            elif label_pos == "tr":
                self.text(x + w - 2.2, y + h - 2.6, label, size=size, color=col, weight="bold", ha="right", va="center", z=z + 1)
            elif label_pos == "bl":
                self.text(x + 2.2, y + 2.6, label, size=size, color=col, weight="bold", ha="left", va="center", z=z + 1)
            elif label_pos == "top":
                self.text(x + w / 2, y + h + 2.4, label, size=size, color=col, weight="bold", ha="center", va="center", z=z + 1)
        return Node(x, y, w, h)

    def arrow(self, p1, p2, label=None, color=None, lw=1.0, style="-|>", rad=0.0, dashed=False,
              label_at=0.5, label_dx=0.0, label_dy=1.8, size=7.6, label_color=None, shrink=0.0,
              both=False, mono=False, ha="center", z=4, mutation=7.5, label_bg=False):
        col = color or C["ink"]
        arrowstyle = "<|-|>" if both else style
        patch = FancyArrowPatch(p1, p2, arrowstyle=arrowstyle, mutation_scale=mutation, color=col,
                                linewidth=lw, connectionstyle=f"arc3,rad={rad}", shrinkA=shrink,
                                shrinkB=shrink, zorder=z, linestyle=(0, (3, 2)) if dashed else "solid")
        self.ax.add_patch(patch)
        if label:
            mx = p1[0] + (p2[0] - p1[0]) * label_at + label_dx
            my = p1[1] + (p2[1] - p1[1]) * label_at + label_dy
            if rad:
                dx, dy = p2[0] - p1[0], p2[1] - p1[1]
                mx += -dy * rad * 0.5
                my += dx * rad * 0.5
            kw = {}
            self.text(mx, my, label, size=size, color=label_color or C["muted"], mono=mono, ha=ha, z=z + 1)
        return patch

    def path(self, pts, color=None, lw=1.0, arrow_end=True, arrow_start=False, dashed=False, z=4,
             mutation=7.5):
        col = color or C["ink"]
        xs, ys = zip(*pts)
        self.ax.plot(xs[:-1] + (xs[-1],) if not arrow_end else xs[:-1], ys[:-1] + (ys[-1],) if not arrow_end else ys[:-1],
                     color=col, lw=lw, zorder=z, solid_capstyle="butt",
                     linestyle=(0, (3, 2)) if dashed else "solid")
        if arrow_end:
            self.arrow(pts[-2], pts[-1], color=col, lw=lw, dashed=dashed, z=z, mutation=mutation)
        else:
            self.ax.plot([pts[-2][0], pts[-1][0]], [pts[-2][1], pts[-1][1]], color=col, lw=lw, zorder=z,
                         linestyle=(0, (3, 2)) if dashed else "solid")
        if arrow_start:
            self.arrow(pts[1], pts[0], color=col, lw=lw, z=z, mutation=mutation)

    def line(self, p1, p2, color=None, lw=0.9, dashed=False, z=2):
        self.ax.plot([p1[0], p2[0]], [p1[1], p2[1]], color=color or C["muted"], lw=lw, zorder=z,
                     linestyle=(0, (3, 2)) if dashed else "solid", solid_capstyle="butt")

    def circle(self, x, y, r, kind="navy_t", label="", size=8.5, weight="semibold", lw=0.9, z=3,
               double=False):
        edge, fill, fg = KIND[kind]
        self.ax.add_patch(Circle((x, y), r, facecolor=fill, edgecolor=edge, linewidth=lw, zorder=z))
        if double:
            self.ax.add_patch(Circle((x, y), r - 1.0, facecolor="none", edgecolor=edge, linewidth=lw * 0.8, zorder=z))
        if label:
            self.text(x, y, label, size=size, color=fg, weight=weight, z=z + 1)
        return Node(x - r, y - r, 2 * r, 2 * r)

    def rect(self, x, y, w, h, fill="none", edge=None, lw=0.8, z=2, dashed=False, alpha=1.0):
        self.ax.add_patch(Rectangle((x, y), w, h, facecolor=fill, edgecolor=edge or "none", linewidth=lw,
                                    zorder=z, linestyle=(0, (3, 2)) if dashed else "solid", alpha=alpha))

    def poly(self, pts, fill="none", edge=None, lw=0.8, z=2, alpha=1.0):
        self.ax.add_patch(Polygon(pts, closed=True, facecolor=fill, edgecolor=edge or "none", linewidth=lw,
                                  zorder=z, alpha=alpha))

    def wire(self, pts, color=None, lw=1.0, z=3):
        xs, ys = zip(*pts)
        self.ax.plot(xs, ys, color=color or C["ink"], lw=lw, zorder=z, solid_capstyle="round",
                     solid_joinstyle="miter")

    def dot(self, x, y, r=0.8, color=None, open_=False):
        self.ax.add_patch(Circle((x, y), r, facecolor="white" if open_ else (color or C["ink"]),
                                 edgecolor=color or C["ink"], linewidth=0.9, zorder=6))

    def resistor(self, p1, p2, label="", body=9.0, width=3.0, color=None, side=1, size=7.4, label_off=3.6):
        col = color or C["ink"]
        (x1, y1), (x2, y2) = p1, p2
        L = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / L, (y2 - y1) / L
        nx, ny = -uy, ux
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        a = (mx - ux * body / 2, my - uy * body / 2)
        b = (mx + ux * body / 2, my + uy * body / 2)
        self.wire([p1, a], color=col)
        self.wire([b, p2], color=col)
        corners = [(a[0] + nx * width / 2, a[1] + ny * width / 2), (b[0] + nx * width / 2, b[1] + ny * width / 2),
                   (b[0] - nx * width / 2, b[1] - ny * width / 2), (a[0] - nx * width / 2, a[1] - ny * width / 2)]
        self.poly(corners, fill="white", edge=col, lw=1.0, z=4)
        if label:
            self.text(mx + nx * label_off * side, my + ny * label_off * side, label, size=size, color=col, z=7)

    def ground(self, x, y, color=None):
        col = color or C["ink"]
        self.wire([(x, y), (x, y - 2.2)], color=col)
        for i, half in enumerate((2.6, 1.7, 0.8)):
            yy = y - 2.2 - i * 0.9
            self.wire([(x - half, yy), (x + half, yy)], color=col)

    def vsource(self, x, y, r=4.5, label="", color=None, size=7.6):
        col = color or C["ink"]
        self.ax.add_patch(Circle((x, y), r, facecolor="white", edgecolor=col, linewidth=1.0, zorder=4))
        self.text(x, y + r * 0.42, "+", size=8, color=col, weight="bold", z=7)
        self.text(x, y - r * 0.45, "−", size=8, color=col, weight="bold", z=7)
        if label:
            self.text(x - r - 1.5, y, label, size=size, color=col, ha="right", z=7)

    def mosfet(self, x, y, kind="n", gate_side="left", color=None, h=8.0):
        col = color or C["ink"]
        top, bot = (x, y + h / 2), (x, y - h / 2)
        self.wire([(x, y + h * 0.32), (x, y - h * 0.32)], color=col, lw=1.4)
        sgn = 1 if gate_side == "left" else -1
        self.wire([(x, y + h * 0.26), (x + sgn * 2.4, y + h * 0.26), (x + sgn * 2.4, y + h / 2 + 2.5)], color=col)
        self.wire([(x, y - h * 0.26), (x + sgn * 2.4, y - h * 0.26), (x + sgn * 2.4, y - h / 2 - 2.5)], color=col)
        gx = x - sgn * 1.3
        self.wire([(gx, y + h * 0.3), (gx, y - h * 0.3)], color=col, lw=1.2)
        if kind == "p":
            bx = gx - sgn * 0.9
            self.ax.add_patch(Circle((bx, y), 0.75, facecolor="white", edgecolor=col, linewidth=1.0, zorder=5))
            gate = (bx - sgn * 0.75 - sgn * 3.0, y)
            self.wire([(bx - sgn * 0.75, y), gate], color=col)
        else:
            gate = (gx - sgn * 3.6, y)
            self.wire([(gx, y), gate], color=col)
        return (x + sgn * 2.4, y + h / 2 + 2.5), gate, (x + sgn * 2.4, y - h / 2 - 2.5)

    def state(self, x, y, label, r=6.0, kind="navy_t", sub=None, double=False, size=8.5):
        node = self.circle(x, y, r, kind=kind, label="" if sub else label, size=size, double=double)
        if sub:
            self.text(x, y + 1.6, label, size=size, weight="semibold", color=KIND[kind][2], z=5)
            self.text(x, y - 2.2, sub, size=6.8, color=KIND[kind][2], z=5)
        return (x, y, r)

    def transition(self, s1, s2, label="", rad=0.25, color=None, size=7.2, label_dx=0.0, label_dy=0.0):
        (x1, y1, r1), (x2, y2, r2) = s1, s2
        ang = math.atan2(y2 - y1, x2 - x1)
        off = 0.35 * (1 if rad >= 0 else -1) * min(abs(rad) * 2.2, 1.0)
        p1 = (x1 + r1 * math.cos(ang + off), y1 + r1 * math.sin(ang + off))
        p2 = (x2 - r2 * math.cos(ang - off), y2 - r2 * math.sin(ang - off))
        self.arrow(p1, p2, rad=rad, color=color or C["ink"], lw=0.9, mutation=7, label=None)
        if label:
            mx, my = (p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2
            dx, dy = p2[0] - p1[0], p2[1] - p1[1]
            mx += -dy * rad * 0.62 + label_dx
            my += dx * rad * 0.62 + label_dy
            self.text(mx, my, label, size=size, color=color or C["ink"], z=7)

    def curve(self, p1, p2, bulge, color=None, lw=0.9, label="", size=7.0, label_pad=1.8, dashed=False,
              mutation=7, label_color=None, ha="center"):
        from matplotlib.path import Path as MPath
        (x1, y1), (x2, y2) = p1, p2
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        cx, cy = mx + nx * 2 * bulge, my + ny * 2 * bulge
        path = MPath([p1, (cx, cy), p2], [MPath.MOVETO, MPath.CURVE3, MPath.CURVE3])
        col = color or C["ink"]
        self.ax.add_patch(FancyArrowPatch(path=path, arrowstyle="-|>", mutation_scale=mutation, color=col,
                                          linewidth=lw, zorder=4, linestyle=(0, (3, 2)) if dashed else "solid"))
        if label:
            ax_, ay_ = mx + nx * bulge, my + ny * bulge
            sgn = 1 if bulge >= 0 else -1
            self.text(ax_ + nx * label_pad * sgn, ay_ + ny * label_pad * sgn, label, size=size,
                      color=label_color or col, z=7, ha=ha)

    def loop(self, s, label="", angle=90, color=None, size=7.0, r_loop=4.0, label_pad=2.2):
        from matplotlib.patches import Arc
        x, y, r = s
        col = color or C["ink"]
        a = math.radians(angle)
        cx, cy = x + (r + r_loop * 0.55) * math.cos(a), y + (r + r_loop * 0.55) * math.sin(a)
        start = angle - 150
        self.ax.add_patch(Arc((cx, cy), 2 * r_loop, 2 * r_loop, angle=0, theta1=start, theta2=start + 300,
                              color=col, linewidth=0.9, zorder=4))
        end = math.radians(start + 300)
        ex, ey = cx + r_loop * math.cos(end), cy + r_loop * math.sin(end)
        tx, ty = -math.sin(end), math.cos(end)
        self.arrow((ex - tx * 0.8, ey - ty * 0.8), (ex + tx * 0.4, ey + ty * 0.4), color=col, lw=0.9, mutation=6)
        if label:
            lx = cx + (r_loop + label_pad) * math.cos(a)
            ly = cy + (r_loop + label_pad) * math.sin(a)
            self.text(lx, ly, label, size=size, color=col, z=7)

    def self_loop(self, s, label="", side="top", color=None, size=7.2):
        x, y, r = s
        col = color or C["ink"]
        dirs = {"top": 90, "bottom": -90, "left": 180, "right": 0}
        a = math.radians(dirs[side])
        p1 = (x + r * math.cos(a - 0.45), y + r * math.sin(a - 0.45))
        p2 = (x + r * math.cos(a + 0.45), y + r * math.sin(a + 0.45))
        self.ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=7, color=col, linewidth=0.9,
                                          connectionstyle="arc3,rad=-1.9", zorder=4))
        if label:
            lx = x + (r + 6.2) * math.cos(a)
            ly = y + (r + 6.2) * math.sin(a)
            self.text(lx, ly, label, size=size, color=col, z=7)

    def bitfield(self, x, y, fields, bit_w=4.6, h=7.0, size=7.0, show_bits=False):
        # fields: (label, msb, lsb, kind), drawn with bit 31 leftmost.
        for lab, msb, lsb, kind in fields:
            n = msb - lsb + 1
            xx = x + (31 - msb) * bit_w
            self.box(xx, y, n * bit_w, h, lab, kind=kind, size=size, radius=0.6, weight="semibold", lw=0.7)
            if show_bits:
                self.text(xx + 0.6, y + h + 1.6, str(msb), size=5.8, color=C["muted"], ha="left")
                if n > 1:
                    self.text(xx + n * bit_w - 0.6, y + h + 1.6, str(lsb), size=5.8, color=C["muted"], ha="right")

    def badge(self, x, y, s, kind="amber", size=7.2, w=None, h=4.2):
        w = w or (len(s) * size * 0.19 + 3.2)
        return self.box(x - w / 2, y - h / 2, w, h, s, kind=kind, size=size, radius=2.0, weight="bold")

    def save(self, name: str) -> Path:
        return save(self.fig, name, pad=0.0)


def ortho(p1, p2, mid=None, first="h"):
    if first == "h":
        mx = mid if mid is not None else (p1[0] + p2[0]) / 2
        return [p1, (mx, p1[1]), (mx, p2[1]), p2]
    my = mid if mid is not None else (p1[1] + p2[1]) / 2
    return [p1, (p1[0], my), (p2[0], my), p2]


class Sequence(Diagram):
    def __init__(self, actors, w=TEXT_WIDTH, h=100.0, top_pad=12.0, box_w=30.0, kinds=None):
        super().__init__(w, h)
        n = len(actors)
        self.xs = [box_w / 2 + 2 + i * (w - box_w - 4) / (n - 1) for i in range(n)]
        self.top = h - top_pad
        kinds = kinds or ["navy"] * n
        for x, a, k in zip(self.xs, actors, kinds):
            self.box(x - box_w / 2, h - top_pad + 2, box_w, 8.5, a, kind=k, size=8.2)
            self.line((x, h - top_pad + 2), (x, 3), color=C["rule"], lw=0.9, dashed=True)
        self.y = self.top - 4

    def msg(self, i, j, label, step=8.5, dashed=False, color=None, size=7.6, note=None):
        y = self.y
        x1, x2 = self.xs[i], self.xs[j]
        if i == j:
            self.path([(x1, y), (x1 + 8, y), (x1 + 8, y - 4), (x1 + 0.6, y - 4)], color=color or C["ink"], lw=0.9)
            self.text(x1 + 9.5, y - 2, label, size=size, color=C["ink"], ha="left")
            self.y -= step + 2
            return
        self.arrow((x1, y), (x2, y), color=color or (C["purple"] if dashed else C["ink"]), lw=0.9,
                   dashed=dashed, mutation=7)
        self.text((x1 + x2) / 2, y + 1.7, label, size=size, color=C["ink"])
        if note:
            self.text((x1 + x2) / 2, y - 1.9, note, size=6.8, color=C["muted"], style="italic")
        self.y -= step

    def divider(self, label, step=7.0):
        y = self.y + 1.5
        self.line((2, y), (self.w - 2, y), color=C["amber"], lw=0.8, dashed=True)
        self.text(4, y + 1.8, label, size=7.2, color=C["amber"], weight="bold", ha="left")
        self.y -= step - 1.0


class Timing(Diagram):
    # One character per time unit: 0, 1 and z are levels; "=" starts a bus value that "." continues; "x" is don't-care.

    def __init__(self, rows, unit=6.0, row_h=9.0, name_w=24.0, w=None, h=None, slope=0.8):
        steps = max(len(r[1]) for r in rows)
        w = w or name_w + steps * unit + 4
        h = h or len(rows) * row_h + 8
        super().__init__(w, h)
        self.unit, self.row_h, self.name_w, self.slope = unit, row_h, name_w, slope
        self.rows = rows
        for i, row in enumerate(rows):
            name, levels = row[0], row[1]
            labels = row[2] if len(row) > 2 else []
            color = row[3] if len(row) > 3 else C["navy"]
            y0 = h - 6 - (i + 1) * row_h + 2.0
            self.text(name_w - 2.5, y0 + (row_h - 4) / 2, name, size=8, color=C["ink"], weight="semibold",
                      ha="right", mono=True)
            self._draw(levels, labels, y0, row_h - 4, color)

    def x(self, t):
        return self.name_w + t * self.unit

    def _draw(self, levels, labels, y0, hh, color):
        s = self.slope
        lab_iter = iter(labels)
        t = 0
        while t < len(levels):
            ch = levels[t]
            run = 1
            while t + run < len(levels) and levels[t + run] == ch and ch not in "=":
                run += 1
            if ch == "=":
                run = 1
                while t + run < len(levels) and levels[t + run] == ".":
                    run += 1
                x0, x1 = self.x(t), self.x(t + run)
                pts = [(x0, y0 + hh / 2), (x0 + s, y0 + hh), (x1 - s, y0 + hh), (x1, y0 + hh / 2),
                       (x1 - s, y0), (x0 + s, y0)]
                self.poly(pts, fill=C["navy_t"], edge=color, lw=0.9, z=3)
                lab = next(lab_iter, "")
                if lab:
                    self.text((x0 + x1) / 2, y0 + hh / 2, lab, size=7, mono=True, color=C["ink"])
            elif ch == "x":
                x0, x1 = self.x(t), self.x(t + run)
                self.rect(x0, y0, x1 - x0, hh, fill=C["light"], edge=None, z=2)
                for k in range(int((x1 - x0) / 1.6)):
                    xx = x0 + k * 1.6
                    self.line((xx, y0), (min(xx + hh * 0.5, x1), y0 + hh), color=C["rule"], lw=0.5)
            elif ch in "01zZ":
                yy = y0 + (hh if ch == "1" else 0 if ch == "0" else hh / 2)
                col = color if ch in "01" else C["muted"]
                self.line((self.x(t) + (s if t > 0 else 0), yy), (self.x(t + run), yy), color=col, lw=1.2, z=4)
                if t > 0 and levels[t - 1] in "01zZ" and levels[t - 1] != ch:
                    pv = levels[t - 1]
                    py = y0 + (hh if pv == "1" else 0 if pv == "0" else hh / 2)
                    self.line((self.x(t), py), (self.x(t) + s, yy), color=col, lw=1.2, z=4)
            elif ch == ".":
                pass
            t += run

    def mark(self, t, label="", color=None, dashed=True):
        x = self.x(t)
        self.line((x, 3), (x, self.h - 4), color=color or C["amber"], lw=0.8, dashed=dashed, z=1)
        if label:
            self.text(x, self.h - 2.4, label, size=7, color=color or C["amber"], weight="bold")

    def span(self, t0, t1, y, label, color=None):
        col = color or C["coral"]
        self.arrow((self.x(t0), y), (self.x(t1), y), color=col, lw=0.8, both=True, mutation=6)
        self.text((self.x(t0) + self.x(t1)) / 2, y + 2.0, label, size=7, color=col, weight="semibold")


def plot(w=TEXT_WIDTH, h=62.0, nrows=1, ncols=1, sharex=False, **kw):
    setup()
    fig, axes = plt.subplots(nrows, ncols, figsize=(w * MM, h * MM), sharex=sharex, **kw)
    for ax in (axes.flat if hasattr(axes, "flat") else [axes]):
        style_axes(ax)
    return fig, axes


def style_axes(ax):
    ax.grid(True, which="major")
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.tick_params(length=2.5)


SERIES = [C["navy"], C["coral"], C["amber"], C["purple"], C["magenta"], C["green"]]
