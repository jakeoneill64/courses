import math

from matplotlib.patches import FancyArrowPatch, Wedge

from omhfig import C, KIND, Diagram, Sequence, Timing, plot, save


def wedge(d, cx, cy, r, width, a0, a1, kind, lw=0.8):
    edge, fill, _ = KIND[kind]
    d.ax.add_patch(Wedge((cx, cy), r, a0, a1, width=width, facecolor=fill, edgecolor=edge, linewidth=lw, zorder=3))


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def self_msg_left(s, i, label, step=8.5, size=7.6):
    y = s.y
    x = s.xs[i]
    s.path([(x, y), (x - 8, y), (x - 8, y - 4), (x - 0.6, y - 4)], color=C["ink"], lw=0.9)
    s.text(x - 9.5, y - 2, label, size=size, color=C["ink"], ha="right")
    s.y -= step + 2


def drivers_binding():
    d = Diagram(168, 96)
    xa, xb, xc, xd = 8, 54, 98, 135
    wa, wb, wc, wd = 36, 37, 30, 32
    heads = [(xa + wa / 2, "described: your overlay"), (xb + wb / 2, "matched, then probed"),
             (xc + wc / 2, "registered with"), (xd + wd / 2, "seen by userspace")]
    for x, s in heads:
        d.text(x, 93, s, size=7.6, color=C["muted"], weight="bold")
    ys = [76, 59, 42, 25]
    h = 12
    dt = [("tmp117@48", '"ti,tmp117"'), ("thermal-sensor", '"generic-adc-thermal"'),
          ("thermal-zones", "trips, cooling-maps"), ("fan@4c", '"microchip,emc2101"')]
    na = [d.box(xa, y, wa, h, a, sub=b, kind="grey", size=7.6, mono=True, sub_size=7.0, weight="bold")
          for (a, b), y in zip(dt, ys)]
    drv = [("tmp117.c", "IIO driver, mainline", "navy_t"), ("thermal-generic-adc.c", "mainline", "navy_t"),
           ("thermal_of.c", "builds zones from the tree", "navy_t"), ("emc2101.c", "hwmon driver: yours", "amber")]
    nb = [d.box(xb, y, wb, h, a, sub=b, kind=k, size=7.4, mono=True, sub_size=7.0, weight="bold")
          for (a, b, k), y in zip(drv, ys)]
    iio = d.box(xc, ys[0], wc, h, "IIO core", kind="purple_t", size=7.8)
    d.box(xc, ys[2], wc, ys[1] + h - ys[2], "thermal core", sub="zone, trips, step_wise\ngovernor, cooling device",
          kind="purple_t", size=7.8, sub_size=7.0)
    hw = d.box(xc, ys[3], wc, h, "hwmon core", kind="purple_t", size=7.8)
    abi = [("iio:device0/", "in_temp_raw, _scale"), ("thermal_zone0/", "temp, trip_point_*"),
           ("cooling_device0/", "cur_state"), ("hwmon3/", "pwm1, fan1_input")]
    nd = [d.box(xd, y, wd, h, a, sub=b, kind="plain", size=7.2, mono=True, sub_size=7.0, weight="normal")
          for (a, b), y in zip(abi, ys)]
    for i, (a, b) in enumerate(zip(na, nb)):
        d.arrow(a.e, b.w_, mutation=6, lw=0.8, color=C["muted"] if i == 2 else C["ink"], dashed=i == 2)
    d.arrow(nb[0].e, iio.w_, mutation=6, lw=0.8)
    d.arrow(nb[1].e, (xc, ys[1] + h / 2), mutation=6, lw=0.8)
    d.arrow(nb[2].e, (xc, ys[2] + h / 2), mutation=6, lw=0.8)
    d.arrow(nb[3].e, hw.w_, mutation=6, lw=0.8)
    d.arrow(iio.e, nd[0].w_, mutation=6, lw=0.8)
    d.arrow((xc + wc, ys[1] + h / 2), nd[1].w_, mutation=6, lw=0.8)
    d.arrow((xc + wc, ys[2] + h / 2), nd[2].w_, mutation=6, lw=0.8)
    d.arrow(hw.e, nd[3].w_, mutation=6, lw=0.8)
    links = [(1, 0, "io-channels"), (2, 1, "thermal-sensors"), (2, 3, "cooling-device")]
    for src, dst, lab in links:
        a, b = na[src], na[dst]
        x = a.x + 6
        if dst < src:
            p0, p1 = (x, a.y + h), (x, b.y)
        else:
            p0, p1 = (x, a.y), (x, b.y + h)
        d.arrow(p0, p1, mutation=5.5, lw=0.8, color=C["purple"], dashed=True)
        d.text(x + 1.6, (p0[1] + p1[1]) / 2, lab, size=7.0, color=C["purple"], ha="left", mono=True)
    d.text(84, 17.5, "at run time, with nothing in userspace", size=7.4, color=C["coral"], weight="bold")
    steps = [("TMP117", "converts"), ("IIO core", "m°C, processed"), ("thermal core", "compares with trips"),
             ("step_wise", "picks a state"), ("emc2101.c", "writes fan setting"), ("fan", "speed in fan1_input")]
    bw, gap = 24.6, 3.4
    for i, (a, b) in enumerate(steps):
        x = 2 + i * (bw + gap)
        d.box(x, 2, bw, 11.5, a, sub=b, kind="coral_t", size=7.4, sub_size=7.0)
        if i < len(steps) - 1:
            d.arrow((x + bw, 7.75), (x + bw + gap, 7.75), mutation=5, lw=0.8, color=C["coral"])
    d.save("u4-drivers-binding")


def drivers_drdy():
    rows = [
        ("DRDY", "110000000000001111111111111111111111111100"),
        ("SCLK", "000000000000001010101010101010000000000000"),
        ("DOUT", "zzzzzzzzzzzzzz=...............zzzzzzzzzzzz", ["24-bit sample, MSB first"]),
        ("IRQ", "001000000000000000000000000000000000000000"),
        ("thread", "000000001111111111111111111111111000000000"),
    ]
    t = Timing(rows, unit=3.45, row_h=10.5, name_w=17, h=74, slope=0.5)
    t.mark(2, "DRDY falls: conversion done")
    t.mark(14, "first SCLK: DRDY returns high")
    t.mark(40, "next DRDY")
    y_irq = t.h - 6 - 4 * t.row_h + 2.0
    t.text(t.x(3.4), y_irq + 4.6, "hard IRQ: iio_trigger_poll(),\ntop half stores the timestamp", size=7.0,
           color=C["ink"], ha="left", linespacing=1.1)
    y_th = t.h - 6 - 5 * t.row_h + 2.0
    t.text(t.x(23.5), y_th + 3.3, "trigger handler thread: spi_sync(),\nthen iio_push_to_buffers_with_ts()", size=7.0,
           color=C["ink"], linespacing=1.1)
    t.span(2, 14, 6.5, "the latency Lab 4.3.3 measures")
    t.text(t.x(41.2), 6.5, "one period: 500 µs at 2,000 SPS", size=7.0, color=C["muted"], ha="right")
    t.save("u4-drivers-drdy")


def drivers_ring():
    d = Diagram(168, 86)
    cx, cy, r, wd = 36, 44, 27, 9.5
    n = 16
    span = 360 / n
    states = ["green_t"] * 4 + ["navy_t"] * 6 + ["grey"] * 6
    for i, k in enumerate(states):
        a1 = 90 - i * span
        a0 = a1 - span
        wedge(d, cx, cy, r, wd, a0, a1, k)
        mx, my = polar(cx, cy, r - wd / 2, (a0 + a1) / 2)
        d.text(mx, my, str(i), size=7.0, color=C["ink"])

    def pointer(slot, color):
        ang = 90 - slot * span
        d.arrow(polar(cx, cy, r + 8, ang), polar(cx, cy, r + 0.6, ang), mutation=6, lw=1.1, color=color)
        return polar(cx, cy, r + 8, ang)

    p0 = pointer(0, C["green"])
    d.text(p0[0], p0[1] + 2.4, "next to clean", size=7.2, color=C["green"], weight="bold")
    p4 = pointer(4, C["navy"])
    d.text(p4[0] + 1.2, p4[1], "RDH: the NIC's head", size=7.2, color=C["navy"], weight="bold", ha="left")
    p10 = pointer(10, C["coral"])
    d.text(1.0, p10[1] - 3.2, "RDT: the doorbell", size=7.2, color=C["coral"], weight="bold", ha="left")
    arc = FancyArrowPatch(polar(cx, cy, 11, 125), polar(cx, cy, 11, 25), connectionstyle="arc3,rad=-0.45",
                          arrowstyle="-|>", mutation_scale=7, color=C["muted"], lw=0.9, zorder=4)
    d.ax.add_patch(arc)
    d.text(cx, cy - 2.5, "direction\nof travel", size=7.0, color=C["muted"])
    steps = [
        ("1", "the driver fills free descriptors with\nbuffer DMA addresses, then writes RDT"),
        ("2", "the NIC DMAs a frame into the next posted\nbuffer, writes back length and DD,\nand advances RDH"),
        ("3", "an MSI-X vector fires; the handler\nmasks it and schedules NAPI"),
        ("4", "NAPI cleans DD descriptors up to its\nbudget, calls napi_gro_receive(),\nrefills, writes RDT, then unmasks"),
    ]
    hs = [9.5, 13, 9.5, 13]
    y = 84
    for (num, txt), hh in zip(steps, hs):
        y -= hh + 2.6
        d.circle(98, y + hh / 2, 3.2, kind="navy", label=num, size=7.4)
        d.box(103, y, 63, hh, "", kind="navy_t" if num in "12" else "plain")
        d.text(105, y + hh / 2, txt, size=7.0, ha="left", linespacing=1.12)
    legend = [("green_t", "written back by the NIC: DD set"), ("navy_t", "posted: owned by the NIC"),
              ("grey", "free: owned by the driver")]
    for i, (k, lab) in enumerate(legend):
        d.box(96, 20.5 - i * 5.6, 5, 3.8, "", kind=k, radius=0.5)
        d.text(103, 22.4 - i * 5.6, lab, size=7.2, ha="left")
    d.save("u4-drivers-ring")


def virt_exit():
    s = Sequence(["guest vCPU", "KVM (host kernel)", "your VMM", "device thread"], h=104, box_w=31,
                 kinds=["green", "purple", "navy", "amber"])
    st = 7.0
    s.divider("CPUID: handled inside KVM", step=6.0)
    s.msg(0, 1, "VM exit, reason 10: CPUID", note="the CPU saves guest state in the VMCS", step=st + 1.0)
    s.msg(1, 1, "emulate, skip the instruction, VMRESUME", step=st + 1.5)
    s.divider("OUT to port 0x3F8: handled in your VMM", step=6.0)
    s.msg(0, 1, "VM exit, reason 30: I/O instruction", step=st)
    s.msg(1, 2, "KVM_RUN returns KVM_EXIT_IO", dashed=True, step=st)
    s.msg(2, 2, "emulate the 16550's THR", step=st)
    s.msg(2, 1, "ioctl(KVM_RUN), then VMRESUME", step=st)
    s.divider("virtio doorbell registered with KVM_IOEVENTFD", step=6.0)
    s.msg(0, 1, "VM exit on the notify address", step=st)
    s.msg(1, 3, "signal the eventfd", dashed=True, note="KVM resumes the vCPU at once; no return to userspace",
          step=st + 1.0)
    self_msg_left(s, 3, "process the virtqueue, then KVM_IRQFD", step=st)
    s.save("u4-virt-exit")


def virt_walk():
    d = Diagram(168, 84)
    rows = ["guest CR3: root table", "PML4 entry: PDPT", "PDPT entry: page directory", "PD entry: page table",
            "PT entry: data page"]
    cols = [62, 80, 98, 116]
    gx = 138
    ys = [62, 50, 38, 26, 14]
    for y, lab in zip(ys, rows):
        d.text(4, y, lab, size=7.2, ha="left")
        d.text(53, y, "gPA", size=7.0, color=C["muted"], ha="right", mono=True)
    for x, lab in zip(cols, ["PML4", "PDPT", "PD", "PT"]):
        d.text(x, 71.5, lab, size=7.2, color=C["purple"], weight="semibold")
    d.text(gx, 71.5, "guest read", size=7.2, color=C["navy"], weight="semibold")
    d.text((cols[0] + cols[-1]) / 2, 78.5, "EPT walk: gPA → hPA, the hypervisor's tables", size=7.4,
           color=C["purple"], weight="bold")
    d.text(gx + 2, 78.5, "guest tables", size=7.4, color=C["navy"], weight="bold")
    n = 0
    for ri, y in enumerate(ys):
        prev = None
        for x in cols:
            n += 1
            d.circle(x, y, 3.9, kind="purple_t", label=str(n), size=7.2)
            if prev is not None:
                d.arrow((prev + 3.9, y), (x - 3.9, y), mutation=5, lw=0.7, color=C["purple"])
            prev = x
        if ri < 4:
            n += 1
            d.box(gx - 5.5, y - 3.9, 11, 7.8, str(n), kind="navy_t", size=7.2, radius=0.8)
            d.arrow((cols[-1] + 3.9, y), (gx - 5.5, y), mutation=5, lw=0.7, color=C["navy"])
            d.arrow((gx - 4.5, y - 3.9), (cols[0] + 3.0, ys[ri + 1] + 2.8), mutation=5, lw=0.6, color=C["muted"],
                    dashed=True)
        else:
            d.box(gx - 7, y - 3.9, 14, 7.8, "data", kind="green", size=7.2, radius=0.8)
            d.arrow((cols[-1] + 3.9, y), (gx - 7, y), mutation=5, lw=0.7, color=C["green"])
    xs = (cols[2] + cols[3]) / 2
    d.line((xs, 8), (xs, 68), color=C["coral"], dashed=True)
    d.text(xs + 1.2, 4.5, "with 2 MiB EPT pages each EPT walk ends here: 19 reads", size=7.0, color=C["coral"],
           ha="left")
    d.text(4, 4.5, "(4 + 1) × (4 + 1) − 1 = 24 reads on a TLB miss", size=7.2, color=C["ink"], ha="left",
           weight="semibold")
    d.save("u4-virt-2d-walk")


def virt_virtqueue():
    d = Diagram(168, 72)
    d.group(46, 1.5, 77, 69, "guest memory, shared", color=C["muted"], label_pos="tl")
    d.text(84.5, 64, "descriptor table: driver writes", size=7.4, weight="bold", color=C["navy"])
    hdr = ["addr", "len", "flags", "next"]
    cw = [22, 12, 25, 10]
    x0 = 50
    rows = [("0", ["0x1_2000", "16", "NEXT", "1"], "navy_t"), ("1", ["0x5_7000", "4096", "NEXT | WRITE", "2"], "navy_t"),
            ("2", ["0x1_2010", "1", "WRITE", "none"], "navy_t"), ("3", ["", "", "free", ""], "grey")]
    x = x0
    for w, hname in zip(cw, hdr):
        d.text(x + w / 2, 59.8, hname, size=7.0, color=C["muted"], mono=True)
        x += w
    for i, (idx, cells, k) in enumerate(rows):
        y = 51.5 - i * 6.3
        d.text(x0 - 1.4, y + 2.8, idx, size=7.0, color=C["muted"], ha="right", mono=True)
        x = x0
        for w, c in zip(cw, cells):
            d.box(x, y, w, 5.6, c, kind=k, size=7.0, mono=True, weight="normal", radius=0.4, lw=0.6)
            x += w
    d.text(84.5, 25.0, "available ring: driver writes", size=7.4, weight="bold", color=C["navy"])
    d.text(84.5, 11.6, "used ring: device writes", size=7.4, weight="bold", color=C["purple"])
    av = [("flags", 14), ("idx = 1", 18), ("ring[0] = 0", 24), ("ring[1]", 13)]
    us = [("flags", 14), ("idx = 1", 18), ("ring[0] = {0, 4097}", 33), ("…", 4)]
    for items, y, k in ((av, 16.0, "navy_t"), (us, 2.8, "purple_t")):
        x = 50
        for lab, w in items:
            d.box(x, y, w, 6.0, lab, kind=k, size=7.0, mono=True, weight="normal", radius=0.4, lw=0.6)
            x += w
    left = [("1", "write the request chain:\nheader, data, status"), ("2", "put the head index\nin the available ring"),
            ("3", "barrier, then\navailable idx += 1"), ("4", "notify: write the\nqueue's doorbell")]
    ly = [56, 41, 26, 11]
    for (num, txt), y in zip(left, ly):
        d.circle(4.5, y, 3.0, kind="navy", label=num, size=7.2)
        d.text(9, y, txt, size=7.0, ha="left", linespacing=1.12)
    right = [("5", "read available idx,\nwalk the chain"), ("6", "do the I/O; write\ndata and status"),
             ("7", "used ring entry,\nbarrier, idx += 1"), ("8", "interrupt: MSI-X\nthrough KVM_IRQFD")]
    for (num, txt), y in zip(right, ly):
        d.circle(130, y, 3.0, kind="purple", label=num, size=7.2)
        d.text(134.5, y, txt, size=7.0, ha="left", linespacing=1.12)
    d.arrow((37.5, 56.5), (49.6, 56.8), mutation=5, lw=0.8, color=C["navy"])
    d.path([(37.5, 41), (42, 41), (42, 19.0), (49.5, 19.0)], color=C["navy"], lw=0.8, mutation=5)
    d.arrow((126.5, 56), (119.5, 54.3), mutation=5, lw=0.8, color=C["purple"])
    d.path([(126.5, 26), (125, 26), (125, 5.8), (119.4, 5.8)], color=C["purple"], lw=0.8, mutation=5)
    d.save("u4-virt-virtqueue")


def virt_precopy():
    fig, ax = plot(h=64)
    bw = 1.1
    mem = 8.0
    cases = [(0.05, 0.5, "idle: 0.05 GiB/s over a 0.5 GiB working set"),
             (0.5, 2.0, "busy: 0.5 GiB/s over 2 GiB"),
             (1.5, 1.0, "hot: 1.5 GiB/s over 1 GiB")]
    limit = 0.1 * bw
    for (rate, ws, lab), col in zip(cases, [C["green"], C["navy"], C["coral"]]):
        v = [mem]
        for _ in range(9):
            v.append(ws * (1 - math.exp(-rate * (v[-1] / bw) / ws)))
        ax.plot(range(len(v)), v, marker="o", ms=3.2, color=col, label=lab)
    ax.axhline(limit, color=C["amber"], lw=1.0, ls=(0, (4, 2)))
    ax.text(9.0, limit * 1.2, "stop and copy below here: 100 ms of downtime at 1.1 GiB/s", color=C["amber"],
            fontsize=7.4, ha="right", va="bottom", weight="semibold")
    ax.text(9.0, 0.26, "stalls: throttle the guest or switch to post-copy", color=C["coral"], fontsize=7.4,
            ha="right", va="bottom")
    ax.set_yscale("log")
    ax.set_ylim(0.004, 12)
    ax.set_yticks([0.01, 0.1, 1, 10])
    ax.set_yticklabels(["0.01", "0.1", "1", "10"])
    ax.minorticks_off()
    ax.set_xlim(-0.3, 9.3)
    ax.set_xticks(range(10))
    ax.set_xlabel("pre-copy round")
    ax.set_ylabel("data left to send (GiB)")
    ax.legend(loc="upper right", bbox_to_anchor=(1.0, 1.02))
    save(fig, "u4-virt-precopy")


ALL = [drivers_binding, drivers_drdy, drivers_ring, virt_exit, virt_walk, virt_virtqueue, virt_precopy]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
