import math


import numpy as np

from omhfig import C, Diagram, Sequence, Timing, ortho, save, setup


def cmos_nand():
    d = Diagram(110, 74)
    vdd_y, gnd_y = 68, 6
    d.wire([(20, vdd_y), (80, vdd_y)])
    d.text(84, vdd_y, "VDD", size=7.8, ha="left", weight="bold")
    pa = d.mosfet(32, 54, kind="p")
    pb = d.mosfet(62, 54, kind="p")
    for drain, gate, source in (pa, pb):
        d.wire([drain, (drain[0], vdd_y)])
    out_y = 40
    d.wire([pa[2], (pa[2][0], out_y), (pb[2][0], out_y), pb[2]])
    d.dot(pa[2][0], out_y)
    d.dot(pb[2][0], out_y)
    d.wire([(pb[2][0], out_y), (96, out_y)])
    d.dot(96, out_y, open_=True)
    d.text(98.5, out_y, "Y = ¬(A·B)", size=8, ha="left", weight="bold")
    na = d.mosfet(47, 28, kind="n")
    nb = d.mosfet(47, 13, kind="n")
    d.wire([(na[0][0], out_y), na[0]])
    d.wire([na[2], nb[0]])
    d.wire([nb[2], (nb[2][0], gnd_y)])
    d.ground(nb[2][0], gnd_y)
    d.wire([(8, 54), pa[1]], color=C["navy"])
    d.wire([(8, 54), (8, 28), na[1]], color=C["navy"])
    d.text(5.5, 54, "A", size=9, weight="bold", color=C["navy"], ha="right")
    d.dot(8, 54, color=C["navy"])
    d.wire([(14, 62), (52.5, 62), (52.5, 54), pb[1]], color=C["coral"])
    d.wire([(14, 62), (14, 13), nb[1]], color=C["coral"])
    d.dot(14, 62, color=C["coral"])
    d.text(11.5, 62, "B", size=9, weight="bold", color=C["coral"], ha="right")
    d.text(28, 46.5, "P-channel pair:\npulls high if either\ninput is low", size=6.6, color=C["muted"], ha="right")
    d.text(58, 20.5, "N-channel series:\npulls low only when\nboth inputs are high", size=6.6, color=C["muted"], ha="left")
    d.save("u2-cmos-nand")


def setup_hold():
    t = Timing([
        ("CLK", "000011111111000000001111"),
        ("D", "=.=.....................", ["old", "new data"]),
        ("Q", "=....=..................", ["previous", "new data"]),
    ], unit=6.2, row_h=12, name_w=16, slope=0.6)
    edge = 4
    x = t.x(edge)
    t.rect(x - 1.0 * 6.2, 4, 1.6 * 6.2, t.h - 9.5, fill=C["amber_t"], z=0)
    t.mark(edge, "sampling edge")
    t.text(x - 0.9, 2.4, "setup", size=6.8, color=C["coral"], weight="semibold", ha="right")
    t.text(x + 0.9, 2.4, "hold", size=6.8, color=C["coral"], weight="semibold", ha="left")
    t.arrow((x, 8.2), (t.x(5), 8.2), both=True, color=C["purple"], lw=0.8, mutation=5)
    t.text(t.x(5) + 1.2, 8.2, "t_cq", size=6.8, color=C["purple"], mono=True, ha="left")
    t.save("u2-setup-hold")


def fsm_101():
    d = Diagram(150, 66)
    y = 30
    s0 = d.state(18, y, "S0", sub="out 0")
    s1 = d.state(58, y, "S1", sub="seen 1")
    s2 = d.state(98, y, "S2", sub="seen 10")
    s3 = d.state(134, y, "S3", sub="out 1", kind="amber", double=True)
    d.loop(s0, "0", angle=90)
    d.loop(s1, "1", angle=90)
    d.arrow((s0[0] + 6, y), (s1[0] - 6, y), label="1", mutation=7, label_dy=2.0, size=7.4, label_color=C["ink"])
    d.arrow((s1[0] + 6, y), (s2[0] - 6, y), label="0", mutation=7, label_dy=2.0, size=7.4, label_color=C["ink"])
    d.curve((s2[0] + 4.2, y + 4.2), (s3[0] - 4.2, y + 4.2), 3.0, label="1", size=7.4)
    d.curve((s3[0] - 4.2, y - 4.2), (s2[0] + 4.2, y - 4.2), 3.0, label="0", size=7.4)
    d.curve((s2[0] - 3.0, y - 5.2), (s0[0] + 3.0, y - 5.2), 13.0, label="0", size=7.4)
    d.curve((s3[0] - 2.0, y + 5.6), (s1[0] + 2.0, y + 5.6), -15.0, label="1", size=7.4)
    d.arrow((2, y), (s0[0] - 6, y), mutation=7)
    d.text(3, y + 3.0, "reset", size=6.8, color=C["muted"], ha="left")
    d.save("u2-fsm-101")


def fpga_fabric():
    d = Diagram(168, 74)
    die = d.group(2, 4, 96, 66, "FPGA die", color=C["navy"], dashed=False, label_pos="top")
    for i in range(14):
        d.rect(6 + i * 6.4, 64, 5.2, 3.0, fill=C["purple_t"], edge=C["purple"], lw=0.5)
        d.rect(6 + i * 6.4, 7, 5.2, 3.0, fill=C["purple_t"], edge=C["purple"], lw=0.5)
    for j in range(8):
        d.rect(4.5, 12.5 + j * 6.3, 3.0, 5.0, fill=C["purple_t"], edge=C["purple"], lw=0.5)
        d.rect(92.5, 12.5 + j * 6.3, 3.0, 5.0, fill=C["purple_t"], edge=C["purple"], lw=0.5)
    cols = 11
    for c in range(cols):
        x = 11 + c * 7.2
        for r in range(7):
            y = 13 + r * 7.0
            if c == 4:
                if r % 2 == 0 and r < 6:
                    d.rect(x, y, 5.6, 12.4, fill=C["amber_t"], edge=C["amber"], lw=0.6)
            elif c == 8:
                if r % 2 == 0 and r < 6:
                    d.rect(x, y, 5.6, 12.4, fill=C["coral_t"], edge=C["coral"], lw=0.6)
            else:
                d.rect(x, y, 5.6, 5.4, fill=C["navy_t"], edge=C["navy"], lw=0.5)
    d.rect(11, 58.5, 6, 4, fill=C["green_t"], edge=C["green"], lw=0.6)
    d.text(14, 60.5, "PLL", size=5.6, color=C["green"], weight="bold")
    legend = [("navy_t", "logic cell: LUT + flip-flop"), ("amber_t", "block RAM"), ("coral_t", "DSP multiply-accumulate"),
              ("purple_t", "I/O blocks"), ("green_t", "PLL and clocking")]
    for i, (k, lab) in enumerate(legend):
        d.box(104, 61 - i * 6.2, 5, 4, "", kind=k, radius=0.5)
        d.text(111, 63 - i * 6.2, lab, size=7, ha="left")
    zoom = d.group(103, 4, 63, 24, "one logic cell", color=C["navy"])
    lut = d.box(108, 8, 18, 13, "LUT4", sub="any 4-input\nfunction", kind="navy_t", size=8, sub_size=5.8)
    ff = d.box(138, 8, 14, 13, "D FF", kind="navy", size=8)
    for k in range(4):
        d.arrow((104.5, 9.5 + k * 3), (lut.x, 9.5 + k * 3), mutation=4, lw=0.6)
    d.arrow(lut.e, ff.w_, mutation=5)
    d.path([(131, 14.5), (131, 23.5), (160, 23.5), (160, 14.5), (164, 14.5)], arrow_end=True, mutation=5, lw=0.7,
           color=C["muted"])
    d.arrow(ff.e, (164, 14.5), mutation=5)
    d.text(145, 25.2, "bypass", size=6, color=C["muted"])
    d.text(131, 6, "carry chain to the next cell", size=6, color=C["muted"])
    d.save("u2-fpga-fabric")


def async_fifo():
    d = Diagram(168, 70)
    d.group(2, 5, 62, 64, "write clock domain", color=C["navy"])
    d.group(104, 5, 62, 64, "read clock domain", color=C["purple"])
    ram = d.box(68, 30, 32, 22, "dual-port RAM", sub="write port, read port", kind="grey", size=8.2)
    wp = d.box(8, 42, 34, 12, "write pointer", sub="binary + Gray", kind="navy_t", size=7.8)
    rp = d.box(126, 42, 34, 12, "read pointer", sub="binary + Gray", kind="purple_t", size=7.8)
    full = d.box(8, 12, 34, 12, "full?", sub="compare with synced\nread pointer", kind="navy", size=8, sub_size=6.2)
    empty = d.box(126, 12, 34, 12, "empty?", sub="compare with synced\nwrite pointer", kind="purple", size=8,
                  sub_size=6.2)
    s1 = d.box(66, 10, 17, 9, "2-FF sync", kind="amber_t", size=7)
    s2 = d.box(85, 18, 17, 9, "2-FF sync", kind="amber_t", size=7)
    d.arrow(wp.e, ram.left(0.7), label="waddr", size=6.8)
    d.arrow(rp.w_, ram.right(0.7), label="raddr", size=6.8)
    d.path([wp.right(0.25), (47, 45), (47, 22.5), (85, 22.5)], arrow_end=True, color=C["navy"], lw=0.9)
    d.path([(102, 22.5), (118, 22.5), (118, 18), (126, 18)], arrow_end=True, color=C["navy"], lw=0.9)
    d.text(110, 25, "wptr (Gray)", size=6.4, color=C["navy"])
    d.path([rp.right(0.25), (163, 45), (163, 7), (74.5, 7), (74.5, 10)], arrow_end=True, color=C["purple"], lw=0.9)
    d.path([(66, 14.5), (50, 14.5), (50, 18), (42, 18)], arrow_end=True, color=C["purple"], lw=0.9)
    d.text(54, 11.5, "rptr (Gray)", size=6.4, color=C["purple"])
    d.text(84, 1.0, "only one pointer bit changes per increment, so a late sample is off by at most one",
           size=6.8, color=C["muted"])
    d.save("u2-async-fifo")


def rv32i_formats():
    d = Diagram(168, 72)
    x0, bw = 18.0, 4.6
    rows = [
        ("R", [("funct7", 31, 25, "purple_t"), ("rs2", 24, 20, "navy_t"), ("rs1", 19, 15, "navy_t"),
               ("funct3", 14, 12, "purple_t"), ("rd", 11, 7, "green_t"), ("opcode", 6, 0, "grey")]),
        ("I", [("imm[11:0]", 31, 20, "amber_t"), ("rs1", 19, 15, "navy_t"), ("funct3", 14, 12, "purple_t"),
               ("rd", 11, 7, "green_t"), ("opcode", 6, 0, "grey")]),
        ("S", [("imm[11:5]", 31, 25, "amber_t"), ("rs2", 24, 20, "navy_t"), ("rs1", 19, 15, "navy_t"),
               ("funct3", 14, 12, "purple_t"), ("imm[4:0]", 11, 7, "amber_t"), ("opcode", 6, 0, "grey")]),
        ("B", [("imm[12|10:5]", 31, 25, "amber_t"), ("rs2", 24, 20, "navy_t"), ("rs1", 19, 15, "navy_t"),
               ("funct3", 14, 12, "purple_t"), ("imm[4:1|11]", 11, 7, "amber_t"), ("opcode", 6, 0, "grey")]),
        ("U", [("imm[31:12]", 31, 12, "amber_t"), ("rd", 11, 7, "green_t"), ("opcode", 6, 0, "grey")]),
        ("J", [("imm[20|10:1|11|19:12]", 31, 12, "amber_t"), ("rd", 11, 7, "green_t"), ("opcode", 6, 0, "grey")]),
    ]
    for b in (31, 25, 24, 20, 19, 15, 14, 12, 11, 7, 6, 0):
        d.text(x0 + (31 - b) * bw + bw / 2, 68.5, str(b), size=6.2, color=C["muted"])
    for i, (name, fields) in enumerate(rows):
        y = 58 - i * 10.4
        d.text(x0 - 4, y + 3.5, name, size=9, weight="bold", color=C["navy"])
        d.bitfield(x0, y, fields, bit_w=bw, h=7.0, size=6.6)
    d.line((x0 + 0 * bw, 4), (x0 + 0 * bw, 66), color=C["coral"], dashed=True)
    d.text(x0 + 1, 1.8, "bit 31 is always the sign bit of the immediate", size=6.6, color=C["coral"], ha="left")
    d.save("u2-rv32i-formats")


def pipeline():
    d = Diagram(168, 66)
    names = ["IF", "ID", "EX", "MEM", "WB"]
    subs = ["fetch at PC", "decode,\nread registers", "ALU, branch\nresolves", "load or\nstore", "write\nregister"]
    bw, gap, y = 22, 11, 26
    nodes = []
    for i, (n, s) in enumerate(zip(names, subs)):
        x = 4 + i * (bw + gap)
        nodes.append(d.box(x, y, bw, 18, n, sub=s, kind="navy" if n == "EX" else "navy_t", size=9.5, sub_size=6.4))
        if i < 4:
            rx = x + bw + gap / 2 - 1.2
            d.rect(rx, y - 3, 2.4, 24, fill=C["amber"], edge=None)
            d.arrow((x + bw, y + 9), (rx, y + 9), mutation=5, lw=0.8)
            d.arrow((rx + 2.4, y + 9), (x + bw + gap, y + 9), mutation=5, lw=0.8)
    d.text(4 + bw + gap / 2, y + 23.5, "pipeline registers", size=6.6, color=C["amber"], ha="left")
    ex = nodes[2]
    memreg_x = 4 + 2 * (bw + gap) + bw + gap / 2
    wbreg_x = 4 + 3 * (bw + gap) + bw + gap / 2
    d.path([(memreg_x, y + 21), (memreg_x, 55), (ex.cx - 3, 55), (ex.cx - 3, y + 18)], color=C["coral"], lw=1.1)
    d.path([(wbreg_x, y + 21), (wbreg_x, 60), (ex.cx + 3, 60), (ex.cx + 3, y + 18)], color=C["coral"], lw=1.1)
    d.text(memreg_x + 2, 56.5, "forward EX/MEM", size=6.6, color=C["coral"], ha="left")
    d.text(wbreg_x + 2, 61.5, "forward MEM/WB", size=6.6, color=C["coral"], ha="left")
    hz = d.box(4 + bw + gap - 2, 4, 30, 10, "load-use detector", kind="purple_t", size=7)
    d.arrow(hz.top(0.25), (nodes[0].cx + 6, y), mutation=5, color=C["purple"], lw=0.8, label="stall", label_dx=-6)
    d.arrow((ex.cx, y), (ex.cx, 18), mutation=5, color=C["green"], lw=0.8)
    d.text(ex.cx + 1.5, 17, "branch taken:\nflush IF and ID,\nredirect PC", size=6.4, color=C["green"], ha="left", va="top")
    d.save("u2-pipeline")


def cache():
    d = Diagram(168, 78)
    d.text(4, 73, "address", size=7.6, color=C["muted"], ha="left", weight="bold")
    tag = d.box(20, 68, 64, 8, "tag", kind="purple_t", size=7.6)
    idx = d.box(84, 68, 28, 8, "index", kind="amber_t", size=7.6)
    off = d.box(112, 68, 22, 8, "offset", kind="green_t", size=7.6)
    ways = 4
    for w in range(ways):
        x = 8 + w * 38
        d.text(x + 15, 60, f"way {w}", size=7.2, color=C["muted"], weight="semibold")
        for r in range(6):
            yy = 50 - r * 5.2
            sel = r == 2
            d.rect(x, yy, 8, 4.4, fill=C["purple_t"] if sel else C["grey"], edge=C["purple"] if sel else C["rule"],
                   lw=0.6)
            d.rect(x + 9, yy, 22, 4.4, fill=C["navy_t"] if sel else C["grey"], edge=C["navy"] if sel else C["rule"],
                   lw=0.6)
        d.text(x + 4, 56, "tag", size=6, color=C["muted"])
        d.text(x + 20, 56, "data line", size=6, color=C["muted"])
        cmp_ = d.circle(x + 4, 12, 3.6, kind="purple_t", label="=", size=8)
        d.arrow((x + 4, 39.6), (x + 4, 15.6), mutation=4.5, lw=0.7, color=C["purple"])
        d.arrow((x + 20, 39.6), (x + 20, 8), mutation=4.5, lw=0.7, color=C["navy"])
    d.path([idx.bottom(), (98, 63), (2, 63), (2, 41.6), (8, 41.6)], color=C["amber"], lw=0.9)
    d.text(3.5, 45, "select\nset", size=6.2, color=C["amber"], ha="left")
    d.path([tag.bottom(0.15), (29.6, 64.5), (160, 64.5), (160, 12), (154, 12)], arrow_end=True, color=C["purple"], lw=0.8)
    d.text(161.5, 30, "tag to all\nfour\ncomparators", size=6.2, color=C["purple"], ha="left")
    d.box(30, 1.0, 104, 5.4, "hit if any comparator matches; the matching way's line goes to the offset multiplexer",
          kind="ghost", size=6.6, weight="normal")
    d.save("u2-cache")


def mesi():
    d = Diagram(168, 78)
    subs = {"M": "Modified", "E": "Exclusive", "S": "Shared", "I": "Invalid"}
    kinds = {"M": "coral", "E": "amber", "S": "navy_t", "I": "grey"}
    r = 7.2

    def panel(ox, title, color, edges, arc=None):
        pos = {"I": (ox + 10, 36), "S": (ox + 42, 13), "E": (ox + 42, 59), "M": (ox + 74, 36)}
        for k, (x, y) in pos.items():
            d.state(x, y, k, sub=subs[k], kind=kinds[k], r=r)
        for a, b, label, side, ha in edges:
            (x1, y1), (x2, y2) = pos[a], pos[b]
            L = math.hypot(x2 - x1, y2 - y1)
            ux, uy = (x2 - x1) / L, (y2 - y1) / L
            p1, p2 = (x1 + ux * r, y1 + uy * r), (x2 - ux * r, y2 - uy * r)
            d.arrow(p1, p2, color=color, lw=0.9, mutation=6)
            mx, my = (p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2
            d.text(mx - uy * side * 3.4, my + ux * side * 3.4, label, size=6.4, color=color, ha=ha)
        if arc:
            a, b, label = arc
            (x1, y1), (x2, y2) = pos[a], pos[b]
            d.curve((x1, y1 + r), (x2, y2 + r), -27, color=color, lw=0.9, mutation=6)
            d.text((x1 + x2) / 2, 73.2, label, size=6.4, color=color)
        d.text(ox + 42, 2.2, title, size=7.2, color=color, weight="bold")

    panel(0, "requests from this cache", C["navy"], [
        ("I", "S", "read, others\nhold a copy", -1, "center"),
        ("I", "E", "read, no other\ncopy", 1, "center"),
        ("S", "M", "write: invalidate\nthe others", -1, "center"),
        ("E", "M", "write, silently", 1, "center"),
        ("I", "M", "write miss", 1, "center"),
    ])
    panel(86, "requests seen from other caches", C["coral"], [
        ("M", "S", "read: write back", -1, "center"),
        ("E", "S", "read", 1, "left"),
        ("E", "I", "write", -1, "center"),
        ("S", "I", "write", 1, "center"),
    ], arc=("M", "I", "write: write back, then invalidate"))
    d.save("u2-mesi")


def sv39():
    d = Diagram(168, 72)
    d.text(4, 66.5, "virtual address", size=7.4, color=C["muted"], ha="left", weight="bold")
    f2 = d.box(36, 62, 27, 8, "VPN[2]  38:30", kind="amber_t", size=7)
    f1 = d.box(63, 62, 27, 8, "VPN[1]  29:21", kind="amber_t", size=7)
    f0 = d.box(90, 62, 27, 8, "VPN[0]  20:12", kind="amber_t", size=7)
    of = d.box(117, 62, 34, 8, "offset  11:0", kind="green_t", size=7)
    satp = d.box(4, 30, 22, 10, "satp", sub="root PPN", kind="purple", size=8)
    tabs = []
    for i, x in enumerate((36, 76, 116)):
        t = d.group(x, 8, 30, 44, f"level {2 - i}", color=C["navy"], dashed=False)
        for r in range(8):
            yy = 11 + r * 4.8
            sel = r == 4 - i
            d.rect(x + 3, yy, 24, 3.8, fill=C["navy_t"] if sel else C["grey"], edge=C["navy"] if sel else C["rule"],
                   lw=0.5)
        tabs.append(t)
    d.arrow(satp.e, (36, 35), mutation=5, label="table base", size=6.4)
    d.arrow(f2.bottom(), (51, 52), mutation=5, color=C["amber"])
    d.arrow(f1.bottom(), (91, 52), mutation=5, color=C["amber"])
    d.arrow(f0.bottom(), (131, 52), mutation=5, color=C["amber"])
    d.arrow((63, 32.6), (76, 32), mutation=5, label="PPN", size=6.4)
    d.arrow((103, 27.8), (116, 28), mutation=5, label="PPN", size=6.4)
    pa = d.box(150, 20, 16, 16, "PA", sub="PPN +\noffset", kind="green", size=8, sub_size=6)
    d.arrow((143, 23), pa.w_, mutation=5)
    d.path([of.bottom(0.8), (144.2, 56), (162, 56), (162, 36)], arrow_end=True, color=C["green"], lw=0.8)
    d.text(84, 2.5, "one memory access per level on a TLB miss: three for Sv39, four for x86-64", size=6.8,
           color=C["muted"])
    d.save("u2-sv39")


def pcie():
    s = Sequence(["CPU (driver)", "Root complex + IOMMU", "Host memory", "PCIe device"], h=96, box_w=34,
                 kinds=["navy", "purple", "grey", "amber"])
    s.msg(0, 3, "MWr to BAR0 doorbell", note="posted write: no completion")
    s.msg(3, 1, "MRd descriptor (IOVA)")
    s.msg(1, 2, "translate IOVA → PA, read", color=C["purple"])
    s.msg(1, 3, "CplD: descriptor data", dashed=True)
    s.divider("device DMAs the payload")
    s.msg(3, 1, "MWr 4 KiB to IOVA, as 16 × 256 B TLPs")
    s.msg(1, 2, "translated write", color=C["purple"])
    s.divider("completion")
    s.msg(3, 1, "MWr to MSI-X address, vector data")
    s.msg(1, 0, "interrupt remapped to a core and vector", color=C["purple"])
    s.save("u2-pcie")


def trap():
    d = Diagram(168, 74)
    d.group(2, 8, 50, 62, "U-mode program", color=C["green"])
    d.group(58, 8, 50, 62, "hardware, in one step", color=C["purple"])
    d.group(114, 8, 52, 62, "M-mode handler", color=C["navy"])
    u = d.box(8, 52, 38, 10, "ecall", sub="pc = 0x0000_0120", kind="green_t", size=8, mono=True)
    hw = ["mepc ← pc", "mcause ← 8 (ecall from U)", "mtval ← 0", "mstatus.MPP ← U", "MPIE ← MIE;  MIE ← 0",
          "pc ← mtvec"]
    for i, line in enumerate(hw):
        d.box(62, 56 - i * 8.2, 42, 6.6, line, kind="purple_t", size=6.8, mono=True, weight="normal")
    sw = ["csrrw sp, mscratch, sp", "save 31 registers", "call C; mepc += 4", "restore registers",
          "csrrw sp, mscratch, sp", "mret"]
    for i, line in enumerate(sw):
        d.box(118, 56 - i * 8.2, 44, 6.6, line, kind="navy_t", size=6.8, mono=True, weight="normal")
    d.arrow(u.e, (62, 59.3), mutation=6)
    d.path([(104, 15.3), (111, 15.3), (111, 59.3), (118, 59.3)], color=C["ink"], lw=0.9)
    d.path([(140, 14.0), (140, 4), (27, 4), (27, 52)], color=C["green"], lw=0.9)
    d.text(30, 26, "mret: pc ← mepc,\nmode ← MPP,\nMIE ← MPIE", size=6.6, color=C["green"], ha="left")
    d.save("u2-trap")


def mcu_map():
    d = Diagram(168, 84)
    regions = [
        ("0xE000_0000", "Private peripheral bus", "NVIC, SysTick, SCB, MPU", "purple_t", 9),
        ("0x4000_0000", "Peripherals", "GPIO, UART, I²C, QSSI, timers, ADC,\nµDMA, EEPROM, SHA/MD5, Ethernet", "amber_t", 15),
        ("0x2000_0000", "SRAM, 256 KB", ".data, .bss, heap, stack", "green_t", 12),
        ("0x0100_0000", "ROM", "boot loader and driver library", "grey", 9),
        ("0x0000_0000", "Flash, 1 MB", "vector table, .text, .rodata,\n.data load image", "navy_t", 17),
    ]
    y = 80
    for addr, name, sub, kind, h in regions:
        y -= h + 1.6
        d.box(30, y, 52, h, name, sub=sub, kind=kind, size=7.8, sub_size=6.2)
        d.text(28, y + h - 1.6, addr, size=6.6, mono=True, ha="right", color=C["muted"])
    d.text(56, 81.2, "address map (not to scale)", size=7, color=C["muted"], weight="bold")
    steps = [
        ("1", "hardware reads flash word 0", "initial SP"),
        ("2", "hardware reads flash word 1", "reset handler address, then jumps"),
        ("3", "your startup code", "copy .data, zero .bss"),
        ("4", "your clock setup", "25 MHz crystal, PLL, MEMTIM0"),
        ("5", "main()", "16 MHz internal clock until step 4"),
    ]
    for i, (n, a, b) in enumerate(steps):
        yy = 66 - i * 14
        d.circle(98, yy + 4, 3.4, kind="navy", label=n, size=7.4)
        d.box(104, yy, 60, 9, a, sub=b, kind="navy_t" if i < 2 else "plain", size=7.4, sub_size=6.2)
        if i < 4:
            d.arrow((98, yy + 0.6), (98, yy - 6.6), mutation=5, lw=0.7)
    d.save("u2-mcu-map")


def ab_boot():
    d = Diagram(168, 74)
    d.text(4, 70, "flash (16 KB erase blocks)", size=7.4, color=C["muted"], ha="left", weight="bold")
    segs = [("boot\nloader", 18, "purple"), ("slot A", 52, "navy_t"), ("slot B", 52, "navy_t"),
            ("free", 30, "grey")]
    x = 4
    for lab, w, k in segs:
        d.box(x, 56, w, 11, lab, kind=k, size=7.6, radius=0.6)
        x += w + 0.8
    d.text(32, 53.2, "header: magic · version · size · SHA-256 · signature", size=6.4, color=C["muted"], ha="left")
    d.text(4, 45, "EEPROM", size=7.4, color=C["muted"], ha="left", weight="bold")
    r0 = d.box(4, 30, 74, 11, "record 0", sub="seq 41 · slot A · v1.2 · CRC ok", kind="amber_t", size=7.4, sub_size=6.4)
    r1 = d.box(86, 30, 78, 11, "record 1", sub="seq 42 · slot B · v1.3 · CRC ok", kind="amber", size=7.4, sub_size=6.4)
    d.text(125, 44, "highest valid seq wins", size=6.6, color=C["amber"], weight="semibold")
    steps = ["write inactive slot", "hash and verify", "rewrite the older record\nwith seq + 1, last",
             "reboot: boot newest\nvalid record", "confirm healthy,\nraise minimum version"]
    for i, s in enumerate(steps):
        xx = 4 + i * 33
        d.box(xx, 5, 30, 14, s, kind="navy_t" if i != 2 else "coral_t", size=6.6, weight="semibold")
        if i < 4:
            d.arrow((xx + 30, 12), (xx + 33, 12), mutation=5, lw=0.8)
    d.text(84, 22.5, "a power cut before the commit leaves the old record valid; a cut during it leaves a bad CRC",
           size=6.4, color=C["coral"])
    d.save("u2-ab-boot")


def measured_boot():
    d = Diagram(168, 70)
    stages = [("SEC + PEI", "core root of trust,\nmemory init"), ("DXE", "drivers, option ROMs"),
              ("BDS", "boot manager"), ("Bootloader", "shim, GRUB or yours"), ("Kernel", "initrd, cmdline"),
              ("Userspace", "IMA file hashes")]
    pcrs = ["PCR 0, 1", "PCR 2, 3", "PCR 1, 7", "PCR 4, 5", "PCR 8–11", "PCR 10"]
    nodes = []
    for i, ((a, b), p) in enumerate(zip(stages, pcrs)):
        x = 3 + i * 27.4
        n = d.box(x, 42, 24.5, 16, a, sub=b, kind="navy_t", size=7.8, sub_size=5.9)
        nodes.append(n)
        d.arrow(n.bottom(), (n.cx, 27), mutation=5, color=C["purple"], lw=0.8)
        d.text(n.cx, 24.5, p, size=6.6, color=C["purple"], weight="semibold")
        if i < len(stages) - 1:
            d.arrow(n.e, (x + 27.4, 50), mutation=5, lw=0.8)
    tpm = d.box(3, 4, 162, 14, "TPM 2.0", sub="PCR_new = SHA-256(PCR_old ‖ measurement), and an event-log entry per extend",
                kind="purple", size=8.5, sub_size=6.8)
    d.text(84, 64, "each stage measures the next before running it", size=7.2, color=C["muted"], weight="semibold")
    d.save("u2-measured-boot")


def attestation():
    s = Sequence(["Attester: module + TPM", "Verifier: control plane", "Relying party: quorum"], h=104, box_w=42,
                 kinds=["navy", "purple", "amber"])
    s.msg(0, 1, "EK certificate, AK public key")
    s.msg(1, 0, "MakeCredential challenge for the AK", note="decryptable only by that TPM")
    s.msg(0, 1, "ActivateCredential: the secret", note="proves the AK lives in a genuine TPM")
    s.divider("every boot")
    s.msg(1, 0, "nonce")
    s.msg(0, 1, "quote(PCRs, nonce) signed by AK, plus event log")
    s.msg(1, 1, "check signature and nonce; replay log; compare reference values")
    s.msg(1, 2, "admit or refuse", dashed=True)
    s.msg(2, 0, "credentials and disk key, only if admitted", dashed=True)
    s.save("u2-attestation")


def netboot():
    s = Sequence(["Client (UEFI)", "dnsmasq: DHCP + TFTP", "HTTP: scripts, images", "Verifier"], h=104, box_w=34,
                 kinds=["navy", "purple", "amber", "green"])
    s.msg(0, 1, "DHCPDISCOVER, option 93 = UEFI x64")
    s.msg(1, 0, "OFFER: address, next-server, ipxe.efi", dashed=True)
    s.msg(0, 1, "TFTP read ipxe.efi")
    s.divider("iPXE running")
    s.msg(0, 1, "DHCP again, user class iPXE")
    s.msg(1, 0, "boot script URL", dashed=True)
    s.msg(0, 2, "GET /boot?mac=… then kernel and initrd")
    s.divider("installer and first-boot agent")
    s.msg(0, 2, "GET configuration")
    s.msg(0, 3, "EK cert, AK, quote")
    s.msg(3, 2, "release disk key for this node", dashed=True)
    s.save("u2-netboot")


ALL = [cmos_nand, setup_hold, fsm_101, fpga_fabric, async_fifo, rv32i_formats, pipeline, cache, mesi, sv39, pcie,
       trap, mcu_map, ab_boot, measured_boot, attestation, netboot]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
