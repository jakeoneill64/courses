
import numpy as np
import schemdraw
import schemdraw.elements as elm
from matplotlib.gridspec import GridSpec
import matplotlib.pyplot as plt

from omhfig import (C, MM, SERIES, SANS, MONO, Diagram, Timing, plot, save, setup, style_axes)


def schem(ax, unit=2.2, fontsize=8.2):
    ax.axis("off")
    d = schemdraw.Drawing(canvas=ax, show=False)
    d.config(unit=unit, fontsize=fontsize, font=SANS, lw=1.0, color=C["ink"])
    return d


def thevenin():
    setup()
    fig = plt.figure(figsize=(160 * MM, 50 * MM))
    gs = GridSpec(1, 3, width_ratios=[1.0, 0.85, 1.25], wspace=0.32)
    ax0, ax1, ax2 = fig.add_subplot(gs[0]), fig.add_subplot(gs[1]), fig.add_subplot(gs[2])

    d = schem(ax0, unit=2.0)
    d += (s := elm.SourceV().up().label("5 V", loc="top"))
    d += elm.Line().right(1.2)
    d += (r1 := elm.Resistor().down().label("$R_1$ 10 kΩ", loc="bottom"))
    d += (mid := elm.Dot())
    d += (r2 := elm.Resistor().down().label("$R_2$ 10 kΩ", loc="bottom"))
    d += elm.Line().left().tox(s.start)
    d += elm.Line().at(mid.center).right(1.8)
    d += elm.Dot(open=True).label("$V_{out}$", loc="right")
    d.draw(show=False)
    ax0.text(0.5, -0.04, "divider", transform=ax0.transAxes, ha="center", va="top", fontsize=8, color=C["muted"])

    d = schem(ax1, unit=2.0)
    d += (s := elm.SourceV().up().label("$V_{th}$ = 2.5 V", loc="bottom"))
    d += elm.Resistor().right().label("$R_{th}$ = 5 kΩ")
    d += elm.Dot(open=True).label("$V_{out}$", loc="right")
    d += elm.Line().down().toy(s.start).color(C["rule"])
    d += elm.Line().left().tox(s.start).color(C["rule"])
    d.draw(show=False)
    ax1.text(0.5, -0.04, "Thevenin equivalent", transform=ax1.transAxes, ha="center", va="top", fontsize=8,
             color=C["muted"])

    style_axes(ax2)
    rl = np.logspace(2, 6, 200)
    for rth, col, lab in [(5e3, C["navy"], "10 kΩ divider"), (50, C["amber"], "100 Ω divider")]:
        ax2.semilogx(rl, 2.5 * rl / (rl + rth), color=col, label=lab)
    for x in (1e3, 1e4):
        ax2.axvline(x, color=C["rule"], lw=0.8, ls="--")
    ax2.set_xlabel("Load $R_L$ on $V_{out}$ (Ω)")
    ax2.set_ylabel("$V_{out}$ (V)")
    ax2.set_ylim(0, 2.7)
    ax2.legend(loc="lower right")
    save(fig, "u1-thevenin")


def decoupling():
    setup()
    fig = plt.figure(figsize=(168 * MM, 58 * MM))
    gs = GridSpec(1, 2, width_ratios=[1.05, 1.2], wspace=0.32)
    ax0, ax1 = fig.add_subplot(gs[0]), fig.add_subplot(gs[1])

    d = schem(ax0, unit=2.0)
    d += (src := elm.SourceV().up().label("regulator", loc="top"))
    d += elm.Inductor2(loops=2).right(3).label("trace: ≈ 1 nH/mm", loc="top").color(C["coral"])
    d += (n1 := elm.Dot())
    d += elm.Line().right(2.6)
    d += (n2 := elm.Dot())
    d += elm.Line().right(2.0)
    d += (ld := elm.SourceI().down().label("load\nstep", loc="bottom").color(C["purple"]))
    d += elm.Line().left().tox(src.start)
    d += elm.Capacitor().at(n1.center).down().toy(ld.end).label("10 µF", loc="top").color(C["navy"])
    d += elm.Capacitor().at(n2.center).down().toy(ld.end).label("100 nF\nat pin", loc="top").color(C["navy"])
    d.draw(show=False)

    style_axes(ax1)
    f = np.logspace(4, 9, 600)
    w = 2 * np.pi * f

    def zcap(c, esl, esr, n=1):
        z = esr + 1j * (w * esl - 1 / (w * c))
        return np.abs(z / n)

    ax1.loglog(f, zcap(10e-6, 0.6e-9, 3e-3), color=C["navy"], label="one 10 µF (0805)")
    ax1.loglog(f, zcap(1e-6, 0.4e-9, 15e-3, n=10), color=C["coral"], label="ten 1 µF (0402)")
    ax1.axhline(0.01, color=C["amber"], lw=1, ls="--")
    ax1.text(1.4e4, 0.0125, "target 10 mΩ", color=C["amber"], fontsize=7.5)
    ax1.set_xlabel("Frequency (Hz)")
    ax1.set_ylabel("|Z| (Ω)")
    ax1.set_ylim(5e-4, 20)
    ax1.legend(loc="upper right")
    save(fig, "u1-decoupling")


def mosfet():
    setup()
    fig = plt.figure(figsize=(160 * MM, 58 * MM))
    gs = GridSpec(1, 2, width_ratios=[0.9, 1.3], wspace=0.15)
    ax0, ax1 = fig.add_subplot(gs[0]), fig.add_subplot(gs[1])

    d = schem(ax0, unit=2.0)
    d += (vdd := elm.Vdd().label("+12 V"))
    d += (fan := elm.Motor().down().label("fan", loc="bottom"))
    d += (dn := elm.Dot())
    d += (q := elm.NFet(bulk=False).left().flip().anchor("drain"))
    d += elm.Ground().at(q.source)
    d += elm.Line().at(q.gate).left(0.4)
    d += elm.Resistor().left().label("10 kΩ")
    d += elm.Dot(open=True).label("gate\ndrive", loc="left")
    d += elm.Line().at(vdd.start).right(2.0)
    d += elm.Diode().down().toy(dn.center).reverse().label("1N5819", loc="bottom").color(C["green"])
    d += elm.Line().left().tox(dn.center).color(C["green"])
    d.draw(show=False)

    style_axes(ax1)
    t = np.linspace(-2, 10, 1200)
    on = t < 0
    rise = np.clip(t / 0.25, 0, 1)
    v_nod = np.where(on, 0.15, np.where(t < 0.25, 12 + 48 * rise, 12 + 48 * np.exp(-(t - 0.25) / 0.6)))
    v_d = np.where(on, 0.15, 12 + 0.45 * (1 - np.exp(-np.maximum(t, 0) / 0.05)) * np.exp(-np.maximum(t, 0) / 4))
    ax1.plot(t, v_nod, color=C["coral"], label="no diode: clamped by avalanche")
    ax1.plot(t, v_d, color=C["navy"], label="with 1N5819: about 12.4 V")
    ax1.set_xlabel("Time from turn-off (µs, illustrative)")
    ax1.set_ylabel("$V_{DS}$ (V)")
    ax1.set_ylim(-3, 68)
    ax1.legend(loc="center right")
    save(fig, "u1-mosfet")


def signal_chain():
    d = Diagram(168, 46)
    stages = [
        ("Quantity", "force, heat,\nfield, RF", "grey"),
        ("Transducer", "bridge, diode,\nHall plate", "navy_t"),
        ("Conditioning", "gain, offset,\nbuffer", "navy_t"),
        ("Anti-alias\nfilter", "", "navy_t"),
        ("ADC", "sample and\nquantise", "navy"),
        ("Digital filter", "average,\ndecimate", "navy_t"),
        ("Value", "with units\nand error", "grey"),
    ]
    errs = ["", "nonlinearity,\ndrift", "offset, gain,\nnoise", "phase delay,\nresidual alias",
            "quantisation,\nreference, INL", "latency,\nrounding", ""]
    n = len(stages)
    bw, gap = 20.5, 3.6
    x0 = 1.0
    nodes = []
    for i, (lab, sub, k) in enumerate(stages):
        x = x0 + i * (bw + gap)
        node = d.box(x, 22, bw, 15, lab, kind=k, size=8, weight="semibold") if not sub else \
            d.box(x, 22, bw, 15, lab, sub=sub, kind=k, size=8, sub_size=6.6)
        nodes.append(node)
        if errs[i]:
            d.text(x + bw / 2, 13.5, errs[i], size=6.8, color=C["coral"], linespacing=1.1)
    for a, b in zip(nodes, nodes[1:]):
        d.arrow(a.e, b.w_, mutation=6.5)
    ref = d.box(nodes[4].x + 1.5, 2.0, bw - 3, 6.5, "reference", kind="amber_t", size=7.2)
    d.arrow(ref.n, nodes[4].s, mutation=6, color=C["amber"])
    d.text(1, 17.2, "dominant error added", size=6.8, color=C["coral"], ha="left", weight="bold")
    d.save("u1-signal-chain")


def opamps():
    setup()
    fig = plt.figure(figsize=(150 * MM, 48 * MM))
    gs = GridSpec(1, 2, wspace=0.3)
    ax0, ax1 = fig.add_subplot(gs[0]), fig.add_subplot(gs[1])

    d = schem(ax0, unit=2.0)
    d += (op := elm.Opamp(leads=True))
    d += elm.Line().at(op.in1).left(0.6)
    d += (j := elm.Dot())
    d += elm.Resistor().left().label("$R_{in}$")
    d += elm.Dot(open=True).label("$V_{in}$", loc="left")
    d += elm.Line().at(j.center).up(1.6)
    d += elm.Resistor().right().tox(op.out).label("$R_f$")
    d += elm.Line().down().toy(op.out)
    d += elm.Dot(open=True).at(op.out).label("$V_{out}$", loc="right")
    d += elm.Line().at(op.in2).left(0.5)
    d += elm.Ground()
    d.draw(show=False)
    ax0.text(0.5, -0.06, "Inverting:  $G = -R_f\\,/\\,R_{in}$", transform=ax0.transAxes, ha="center", va="top",
             fontsize=8.4)

    d = schem(ax1, unit=2.0)
    d += (op := elm.Opamp(leads=True).flip())
    d += elm.Line().at(op.in2).left(1.6)
    d += elm.Dot(open=True).label("$V_{in}$", loc="left")
    d += elm.Line().at(op.in1).left(0.6)
    d += (j := elm.Dot())
    d += elm.Resistor().left().label("$R_g$", loc="bottom")
    d += elm.Ground()
    d += elm.Line().at(j.center).down(1.4)
    d += elm.Resistor().right().tox(op.out).label("$R_f$", loc="bottom")
    d += elm.Line().up().toy(op.out)
    d += elm.Dot(open=True).at(op.out).label("$V_{out}$", loc="right")
    d.draw(show=False)
    ax1.text(0.5, -0.06, "Non-inverting:  $G = 1 + R_f\\,/\\,R_g$", transform=ax1.transAxes, ha="center",
             va="top", fontsize=8.4)
    save(fig, "u1-opamps")


def sallen_key():
    setup()
    fig = plt.figure(figsize=(168 * MM, 62 * MM))
    gs = GridSpec(2, 2, width_ratios=[1.05, 1.2], height_ratios=[1.4, 1], wspace=0.3, hspace=0.12)
    ax0 = fig.add_subplot(gs[:, 0])
    ax1 = fig.add_subplot(gs[0, 1])
    ax2 = fig.add_subplot(gs[1, 1], sharex=ax1)

    d = schem(ax0, unit=1.8)
    d += elm.Dot(open=True).label("$V_{in}$", loc="left")
    d += elm.Resistor().right().label("$R$")
    d += (a := elm.Dot())
    d += elm.Resistor().right().label("$R$")
    d += (b := elm.Dot())
    d += elm.Line().right(1.4)
    d += (op := elm.Opamp(leads=True).flip().anchor("in2"))
    d += elm.Capacitor().at(b.center).down().label("$C_2$ 10 nF", loc="top")
    d += elm.Ground()
    d += elm.Line().at(a.center).up(1.8)
    d += elm.Capacitor().right().tox(op.out).label("$C_1$ 22 nF")
    d += elm.Line().down().toy(op.out)
    d += elm.Dot()
    d += elm.Line().right(0.6)
    d += elm.Dot(open=True).label("$V_{out}$", loc="right")
    d += elm.Line().at(op.in1).left(0.4)
    d += elm.Line().down(1.6)
    d += elm.Line().right().tox(op.out)
    d += elm.Line().up().toy(op.out)
    d.draw(show=False)
    ax0.text(0.5, -0.04, "$R$ = 11 kΩ", transform=ax0.transAxes, ha="center", va="top", fontsize=8)

    f = np.logspace(2, 4.5, 400)
    f0 = 1000.0
    for q, col in [(0.5, C["amber"]), (0.707, C["navy"]), (1.2, C["coral"])]:
        s = 1j * f / f0
        h = 1 / (s ** 2 + s / q + 1)
        ax1.semilogx(f, 20 * np.log10(np.abs(h)), color=col, label=f"Q = {q:g}")
        ax2.semilogx(f, np.degrees(np.unwrap(np.angle(h))), color=col)
    for ax in (ax1, ax2):
        style_axes(ax)
        ax.axvline(f0, color=C["rule"], lw=0.8, ls="--")
    ax1.axhline(-3, color=C["rule"], lw=0.8, ls="--")
    ax1.set_ylabel("Gain (dB)")
    ax1.set_ylim(-40, 8)
    ax1.legend(loc="lower left")
    plt.setp(ax1.get_xticklabels(), visible=False)
    ax2.set_ylabel("Phase (°)")
    ax2.set_yticks([0, -90, -180])
    ax2.set_xlabel("Frequency (Hz)")
    save(fig, "u1-sallen-key")


def aliasing():
    fig, ax = plot(h=50)
    t = np.linspace(0, 2e-3, 4000)
    fs, f = 10e3, 9.3e3
    ts = np.arange(0, 2e-3, 1 / fs)
    ax.plot(t * 1e3, np.sin(2 * np.pi * f * t), color=C["rule"], lw=1.0, label="9.3 kHz input")
    ax.plot(t * 1e3, np.sin(2 * np.pi * (f - fs) * t), color=C["coral"], lw=1.4, ls="--", label="700 Hz alias")
    ax.plot(ts * 1e3, np.sin(2 * np.pi * f * ts), "o", color=C["navy"], ms=4, label="samples at 10 kSa/s")
    ax.set_xlabel("Time (ms)")
    ax.set_ylabel("Amplitude")
    ax.set_ylim(-1.3, 1.6)
    ax.legend(loc="upper center", ncol=3)
    save(fig, "u1-aliasing")


def bridge():
    d = Diagram(150, 62)
    cx, cy, hd = 50.0, 30.0, 13.0
    T, B, L, R = (cx, cy + hd), (cx, cy - hd), (cx - hd, cy), (cx + hd, cy)
    d.resistor(L, T, "$R + \\Delta R$", side=1, body=8)
    d.resistor(T, R, "$R - \\Delta R$", side=1, body=8)
    d.resistor(R, B, "$R + \\Delta R$", side=1, body=8)
    d.resistor(B, L, "$R - \\Delta R$", side=1, body=8)
    for p in (T, B, L, R):
        d.dot(*p, r=0.7)
    d.vsource(14, 30, label="excitation\n5 V")
    d.wire([(14, 34.5), (14, 56), (89, 56), (89, 48), (101, 48)], color=C["amber"])
    d.dot(28, 56, r=0.7, color=C["amber"])
    d.wire([(28, 56), (28, cy), L], color=C["amber"])
    d.wire([(14, 25.5), (14, 20)])
    d.ground(14, 20)
    d.wire([R, (70, cy), (70, 24)])
    d.ground(70, 24)
    d.wire([T, (cx, 47), (60, 47), (82, 47), (82, 40), (101, 40)], color=C["navy"])
    d.wire([B, (cx, 13), (82, 13), (82, 20), (101, 20)], color=C["navy"])
    ic = d.box(101, 8, 32, 46, "", kind="plain", lw=1.0)
    d.text(117, 31, "ADS1220", size=9, weight="bold")
    d.text(117, 26.5, "PGA × 128", size=7.4, color=C["muted"])
    for y, name in [(48, "REFP0"), (40, "AIN0"), (20, "AIN1"), (12, "REFN0")]:
        d.text(103, y, name, size=6.8, mono=True, ha="left")
    d.wire([(101, 12), (95, 12), (95, 9)])
    d.ground(95, 9)
    for y, name in [(46, "SCLK"), (40, "DIN"), (34, "DOUT"), (28, "CS")]:
        d.text(131, y, name, size=6.8, mono=True, ha="right")
        d.wire([(133, y), (139, y)])
    d.text(141, 37, "SPI to\nthe Pi", size=7.2, ha="left", color=C["muted"])
    d.text(64, 59.5, "the excitation is also the ADC reference", size=7.4, color=C["amber"], weight="semibold")
    d.save("u1-bridge")


def i2c_read():
    d = Diagram(168, 40)
    y_scl, y_sda = 27, 12
    x = 18.0
    d.text(14, y_scl + 2.5, "SCL", mono=True, weight="bold", ha="right")
    d.text(14, y_sda + 2.5, "SDA", mono=True, weight="bold", ha="right")
    frames = [
        ("S", None), ("0x48 · W", "c"), ("A", "t"), ("reg 0x0F", "c"), ("A", "t"),
        ("Sr", None), ("0x48 · R", "c"), ("A", "t"), ("0x01", "t"), ("A", "c"), ("0x17", "t"), ("N", "c"), ("P", None),
    ]
    widths = {"S": 4, "Sr": 4, "P": 4, "A": 4.2, "N": 4.2}
    for lab, who in frames:
        w = widths.get(lab, 15.5)
        if who is None:
            d.line((x + w / 2, 4), (x + w / 2, 35), color=C["amber"], lw=0.8, dashed=True)
            d.text(x + w / 2, 37.5, lab, size=8, color=C["amber"], weight="bold")
        else:
            kind = "navy_t" if who == "c" else "amber_t"
            edge = C["navy"] if who == "c" else C["amber"]
            pts = [(x, y_sda + 2.5), (x + 0.8, y_sda + 5), (x + w - 0.8, y_sda + 5), (x + w, y_sda + 2.5),
                   (x + w - 0.8, y_sda), (x + 0.8, y_sda)]
            d.poly(pts, fill=C[kind], edge=edge, lw=0.9, z=3)
            d.text(x + w / 2, y_sda + 2.5, lab, size=6.8 if w > 6 else 6.6, mono=True)
            n = 8 if w > 6 else 1
            pw = (w - 1.0) / n
            for k in range(n):
                px = x + 0.5 + k * pw
                d.line((px, y_scl), (px + pw * 0.25, y_scl), color=C["navy"], lw=1.0)
                d.line((px + pw * 0.25, y_scl), (px + pw * 0.25, y_scl + 5), color=C["navy"], lw=1.0)
                d.line((px + pw * 0.25, y_scl + 5), (px + pw * 0.75, y_scl + 5), color=C["navy"], lw=1.0)
                d.line((px + pw * 0.75, y_scl + 5), (px + pw * 0.75, y_scl), color=C["navy"], lw=1.0)
                d.line((px + pw * 0.75, y_scl), (px + pw, y_scl), color=C["navy"], lw=1.0)
        x += w + 0.4
    d.box(18, 0.6, 30, 4.4, "driven by the controller", kind="navy_t", size=6.8, weight="normal")
    d.box(52, 0.6, 30, 4.4, "driven by the target", kind="amber_t", size=6.8, weight="normal")
    d.text(86, 2.8, "S start   Sr repeated start   A acknowledge   N no acknowledge   P stop", size=6.8,
           color=C["muted"], ha="left")
    d.save("u1-i2c-read")


def shunt():
    d = Diagram(160, 58)
    batt = d.box(4, 22, 24, 16, "3S LiPo", sub="11.1 V nominal", kind="navy", size=8.5)
    sh = d.box(52, 25, 20, 10, "0.5 mΩ shunt", kind="coral_t", size=7.6)
    esc = d.box(116, 22, 38, 16, "Power distribution", sub="four ESCs, up to 60 A", kind="grey", size=8.5)
    ina = d.box(48, 2, 28, 12, "INA228", sub="20-bit, 85 V", kind="navy_t", size=8.5)
    mcu = d.box(116, 2, 38, 12, "Flight controller", sub="I²C", kind="purple_t", size=8.5)
    d.path([batt.right(0.75), (40, 33.5), (40, 30), sh.w_], color=C["coral"], lw=3.0, arrow_end=False)
    d.path([sh.e, (100, 30), (100, 33.5), esc.left(0.73)], color=C["coral"], lw=3.0, arrow_end=False)
    d.path([esc.left(0.27), (40, 26.3), batt.right(0.27)], color=C["coral"], lw=3.0, arrow_end=False)
    d.text(84, 37.2, "60 A path: thick copper", size=7, color=C["coral"], weight="bold")
    d.path([sh.bottom(0.15), (54.8, 19), (58, 19), ina.top(0.35)], color=C["navy"], lw=0.9, arrow_end=False)
    d.path([sh.bottom(0.85), (69.0, 19), (66, 19), ina.top(0.65)], color=C["navy"], lw=0.9, arrow_end=False)
    d.text(80, 18.8, "Kelvin sense pair,\nrouted together", size=6.8, color=C["navy"], ha="left")
    d.text(57.5, 16.7, "IN+", size=6.5, mono=True)
    d.text(66.5, 16.7, "IN−", size=6.5, mono=True)
    d.arrow(ina.e, mcu.w_, both=True, label="SDA, SCL, ALERT", size=6.8, mutation=6)
    d.save("u1-shunt")


def power_trees():
    d = Diagram(168, 96)
    d.group(1, 50, 166, 45, "Drone", color=C["magenta"])
    b = d.box(5, 66, 22, 14, "3S LiPo", sub="9.9–12.6 V", kind="magenta", size=8)
    p = d.box(33, 66, 22, 14, "Fuse and\nshunt", sub="INA228", kind="magenta_t", size=7.5, sub_size=6.5)
    e = d.box(64, 79, 30, 10, "4 × ESC, direct", sub="up to 60 A", kind="grey", size=7.6, sub_size=6.5)
    bk = d.box(64, 57, 30, 12, "5 V buck, 3 A", sub="TI, from Lab 1.4.5", kind="magenta_t", size=7.6, sub_size=6.5)
    loads = [("LaunchPad\n(3.3 V LDO)", 84), ("mmWave radar", 73), ("868 MHz radio", 62), ("RC receiver", 51.5)]
    d.arrow(b.e, p.w_, mutation=6)
    d.path([p.e, (59, 73), (59, 84), e.w_], mutation=6)
    d.path([p.e, (59, 73), (59, 63), bk.w_], mutation=6)
    for i, (lab, y) in enumerate(loads):
        node = d.box(112, y - 0.5, 34, 8.5, lab.replace("\n", " "), kind="plain", size=7.2, weight="normal")
        d.path([bk.e, (104, 63), (104, y + 3.75), node.w_], mutation=5.5, lw=0.8)
    d.group(1, 2, 166, 45, "Rack module", color=C["purple"])
    bus = d.box(5, 17, 22, 14, "12 V bus", sub="backplane", kind="purple", size=8)
    ef = d.box(33, 17, 22, 14, "eFuse and\nshunt", sub="hot swap", kind="purple_t", size=7.5, sub_size=6.5)
    d.arrow(bus.e, ef.w_, mutation=6)
    rails = [("5 V buck, 4 A", "fans, USB, drives", 36, True), ("3.3 V buck, 6 A", "BMC, NIC, logic", 26, True),
             ("1.8 V LDO, 0.5 A", "PLL, analogue", 14, False), ("0.9 V multiphase, 20 A", "SoC core", 4, True)]
    boxes = {}
    for lab, load, y, from_bus in rails:
        rb = d.box(70, y, 40, 8.5, lab, kind="purple_t", size=7.2)
        lb = d.box(122, y, 40, 8.5, load, kind="plain", size=7.0, weight="normal")
        d.arrow(rb.e, lb.w_, mutation=5.5, lw=0.8)
        boxes[lab] = rb
        if from_bus:
            d.path([ef.e, (62, 24), (62, y + 4.25), rb.w_], mutation=5.5, lw=0.8)
    d.arrow(boxes["3.3 V buck, 6 A"].bottom(0.8), boxes["1.8 V LDO, 0.5 A"].top(0.8), mutation=5.5, lw=0.8,
            color=C["purple"])
    d.text(103.5, 24.4, "from 3.3 V", size=6.4, color=C["purple"], ha="left")
    d.save("u1-power-trees")


def buck():
    setup()
    fig = plt.figure(figsize=(168 * MM, 62 * MM))
    gs = GridSpec(3, 2, width_ratios=[1.1, 1.0], wspace=0.22, hspace=0.18)
    ax0 = fig.add_subplot(gs[:, 0])
    d = schem(ax0, unit=1.9)
    d += elm.Dot(open=True).label("$V_{in}$", loc="left")
    d += elm.Line().right(0.8)
    d += (n1 := elm.Dot())
    d += elm.Switch().right().label("high side", loc="top")
    d += (sw := elm.Dot().label("SW", loc="top"))
    d += elm.Inductor2(loops=3).right().label("$L$")
    d += (out := elm.Dot())
    d += elm.Line().right(1.5)
    d += (o2 := elm.Dot())
    d += elm.Line().right(0.7)
    d += elm.Dot(open=True).label("$V_{out}$", loc="right")
    d += elm.Capacitor().at(n1.center).down().label("$C_{in}$", loc="bottom")
    d += elm.Ground()
    d += elm.Switch().at(sw.center).down().label("low\nside", loc="bottom")
    d += elm.Ground()
    d += elm.Capacitor().at(out.center).down().label("$C_{out}$", loc="bottom")
    d += elm.Ground()
    d += elm.Resistor().at(o2.center).down().label("load", loc="bottom")
    d += elm.Ground()
    d.draw(show=False)

    t = np.linspace(0, 3, 1500)
    duty = 0.275
    vsw = np.where((t % 1) < duty, 12.0, 0.0)
    il = np.interp(t % 1, [0, duty, 1], [1.7, 2.3, 1.7])
    vout = 3.3 + 0.006 * np.sin(2 * np.pi * (t % 1 - duty / 2 - 0.25))
    axes = [fig.add_subplot(gs[i, 1]) for i in range(3)]
    for ax, y, lab, col in [(axes[0], vsw, "$V_{SW}$ (V)", C["navy"]), (axes[1], il, "$I_L$ (A)", C["coral"]),
                            (axes[2], vout, "$V_{out}$ (V)", C["purple"])]:
        style_axes(ax)
        ax.plot(t, y, color=col, lw=1.2)
        ax.set_ylabel(lab, fontsize=7.6)
        if ax is not axes[2]:
            plt.setp(ax.get_xticklabels(), visible=False)
    axes[1].axhline(2.0, color=C["rule"], lw=0.8, ls="--")
    axes[1].text(2.02, 2.03, "load current", fontsize=6.8, color=C["muted"])
    axes[0].text(0.03, 9.5, "D·T", fontsize=7, color=C["navy"])
    axes[2].set_xlabel("Time (switching periods)")
    axes[2].ticklabel_format(useOffset=False)
    save(fig, "u1-buck")


def lipo():
    fig, ax = plot(h=58)
    soc = np.array([0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
    ocv = np.array([3.30, 3.50, 3.62, 3.70, 3.75, 3.79, 3.83, 3.88, 3.94, 4.01, 4.08, 4.20])
    cap_ah, cells = 5.0, 3
    s = np.linspace(100, 0, 500)
    for crate, rcell, col in [(1, 0.004, C["navy"]), (5, 0.006, C["coral"])]:
        i = crate * cap_ah
        v = cells * (np.interp(s, soc, ocv) - i * rcell)
        delivered = cap_ah * (100 - s) / 100
        wh = np.cumsum(np.r_[0, np.diff(delivered)] * v)
        keep = v >= cells * 3.5
        ax.plot(wh[keep], v[keep], color=col, label=f"{crate}C ({i:g} A)")
        ax.plot(wh[~keep], v[~keep], color=col, lw=0.8, ls=":")
        ax.annotate(f"{wh[keep][-1]:.0f} Wh usable", (wh[keep][-1], v[keep][-1]),
                    xytext=(8, 14) if crate == 1 else (-78, -14),
                    textcoords="offset points", fontsize=7.4, color=col,
                    arrowprops=dict(arrowstyle="-", color=col, lw=0.6))
    ax.axhline(cells * 3.5, color=C["amber"], ls="--", lw=1)
    ax.text(0.5, cells * 3.5 + 0.08, "cut-off 3.5 V per cell", color=C["amber"], fontsize=7.5)
    ax.set_xlabel("Energy delivered (Wh)")
    ax.set_ylabel("Pack voltage (V)")
    ax.set_ylim(9.8, 12.9)
    ax.legend(loc="upper right")
    ax.set_title("3S 5000 mAh pack, model", fontsize=8.5)
    save(fig, "u1-lipo")


def tdr():
    fig, axes = plot(h=58, ncols=3, sharex=True)
    t = np.linspace(-20, 300, 2000)
    v0, tr = 5.0, 5.0
    delay = 10.0 / (0.66 * 0.2998)  # ns, one way, for 10 m at 0.66 c

    def edge(tt):
        return np.clip(tt / tr, 0, 1)

    cases = [("Open", 1.0, C["navy"]), ("Short", -1.0, C["coral"]), ("50 Ω", 0.0, C["green"])]
    for ax, (lab, gamma, col) in zip(axes, cases):
        v = v0 / 2 * edge(t) + gamma * v0 / 2 * edge(t - 2 * delay)
        ax.plot(t, v, color=col)
        ax.set_title(f"{lab} far end", fontsize=8.5)
        ax.set_xlabel("Time (ns)")
        ax.set_ylim(-0.4, 5.6)
        ax.axvline(2 * delay, color=C["rule"], lw=0.8, ls="--")
    axes[0].set_ylabel("Near-end voltage (V)")
    axes[0].annotate("round trip\n≈ 101 ns", (2 * delay, 3.8), xytext=(10, 0), textcoords="offset points",
                     fontsize=7.2, color=C["muted"])
    save(fig, "u1-tdr")


def smith():
    setup()
    fig, ax = plt.subplots(figsize=(110 * MM, 110 * MM))
    ax.set_aspect("equal")
    ax.axis("off")

    def gamma(z):
        return (z - 1) / (z + 1)

    th = np.linspace(0, 2 * np.pi, 400)
    ax.plot(np.cos(th), np.sin(th), color=C["muted"], lw=1.0)
    for r in [0.2, 0.5, 1, 2, 5]:
        x = np.concatenate([-np.logspace(3, -3, 300), np.logspace(-3, 3, 300)])
        g = gamma(r + 1j * x)
        ax.plot(g.real, g.imag, color=C["light"] if r != 1 else C["rule"], lw=0.7)
        ax.text(gamma(r).real, 0.02, f"{r:g}", fontsize=6.5, color=C["muted"], ha="center", va="bottom")
    for xx in [0.2, 0.5, 1, 2, 5]:
        for sgn in (1, -1):
            r = np.logspace(-3, 3, 400)
            g = gamma(r + 1j * sgn * xx)
            ax.plot(g.real, g.imag, color=C["light"], lw=0.7)
        gp = gamma(1j * xx)
        ax.text(gp.real * 1.08, gp.imag * 1.08, f"+j{xx:g}", fontsize=6.3, color=C["muted"], ha="center", va="center")
        ax.text(gp.real * 1.08, -gp.imag * 1.08, f"−j{xx:g}", fontsize=6.3, color=C["muted"], ha="center", va="center")
    ax.plot([-1, 1], [0, 0], color=C["light"], lw=0.7)
    b = np.concatenate([-np.logspace(3, -3, 300), np.logspace(-3, 3, 300)])
    gz = gamma(1 / (1 + 1j * b))
    ax.plot(gz.real, gz.imag, color=C["amber"], lw=0.9, ls="--")
    zl = complex(25, -15) / 50
    x1 = np.linspace(zl.imag, 0.5, 200)
    p1 = gamma(zl.real + 1j * x1)
    ax.plot(p1.real, p1.imag, color=C["coral"], lw=2.0)
    bb = np.linspace(-1, 0, 200)
    p2 = gamma(1 / (1 + 1j * bb))
    ax.plot(p2.real, p2.imag, color=C["navy"], lw=2.0)
    for z, lab, off in [(zl, "load 25 − j15 Ω", (-14, -14)), (complex(0.5, 0.5), "after series L", (6, 6)),
                        (1, "50 Ω", (6, -12))]:
        g = gamma(z)
        ax.plot(g.real, g.imag, "o", color=C["ink"], ms=4, zorder=5)
        ax.annotate(lab, (g.real, g.imag), xytext=off, textcoords="offset points", fontsize=7.4, color=C["ink"])
    ax.set_xlim(-1.15, 1.15)
    ax.set_ylim(-1.15, 1.15)
    save(fig, "u1-smith")


def link_budget():
    fig, ax = plot(h=60)
    steps = [("TX power", 14), ("TX cable", -1), ("TX antenna", 2), ("Path, 1 km", -91.2),
             ("RX antenna", 2), ("RX cable", -1)]
    level = 0
    xs = []
    for i, (lab, dv) in enumerate(steps):
        new = level + dv
        col = C["navy"] if dv >= 0 else C["coral"]
        if i == 0:
            ax.bar(i, dv, bottom=0, color=C["navy"], width=0.6)
        else:
            ax.bar(i, dv, bottom=level, color=col, width=0.6)
        ax.text(i, max(level, new) + 2, f"{dv:+g}", ha="center", fontsize=7.4, color=C["ink"])
        level = new
        xs.append(lab)
    ax.bar(len(steps), level, bottom=0, color=C["purple"], width=0.6)
    ax.text(len(steps), level / 2, f"{level:.1f}\ndBm", ha="center", va="center", fontsize=7.4, color="white",
            weight="bold")
    xs.append("Received")
    ax.axhline(-110, color=C["amber"], lw=1.2, ls="--")
    ax.text(0.0, -107.5, "example sensitivity −110 dBm (50 kbit/s)", color=C["amber"], fontsize=7.4)
    ax.annotate("", xy=(len(steps) + 0.42, -110), xytext=(len(steps) + 0.42, level),
                arrowprops=dict(arrowstyle="<->", color=C["green"], lw=1.0))
    ax.text(len(steps) + 0.5, (level - 110) / 2, f"fade\nmargin\n{level + 110:.0f} dB", fontsize=7.4,
            color=C["green"], va="center")
    ax.set_xticks(range(len(xs)))
    ax.set_xticklabels(xs, fontsize=7.4)
    ax.set_ylabel("Level (dBm)")
    ax.set_ylim(-125, 25)
    ax.set_xlim(-0.6, len(steps) + 1.3)
    save(fig, "u1-link-budget")


def instrument_chain():
    d = Diagram(168, 34)
    tx = d.box(2, 10, 34, 15, "Transmitter", sub="up to +20 dBm", kind="navy", size=8.2)
    a1 = d.box(48, 10, 26, 15, "30 dB", sub="2 W rating", kind="amber_t", size=8.2)
    a2 = d.box(84, 10, 26, 15, "10 dB", sub="", kind="amber_t", size=8.2)
    an = d.box(124, 10, 42, 15, "tinySA Ultra", sub="max safe input from manual", kind="purple", size=8.2)
    d.arrow(tx.e, a1.w_, label="+20 dBm", size=7.2)
    d.arrow(a1.e, a2.w_, label="−10 dBm", size=7.2)
    d.arrow(a2.e, an.w_, label="−20 dBm", size=7.2)
    d.text(84, 3.5, "Check before connecting: transmit power − attenuation ≤ instrument limit − 10 dB margin",
           size=7.2, color=C["coral"], weight="semibold")
    d.save("u1-instrument-chain")


ALL = [thevenin, decoupling, mosfet, signal_chain, opamps, sallen_key, aliasing, bridge, i2c_read, shunt,
       power_trees, buck, lipo, tdr, smith, link_budget, instrument_chain]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
