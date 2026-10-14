from omhfig import C, SANS, Diagram, Sequence


def badge_num(d, x, y, n, r=2.1):
    d.circle(x, y, r, kind="coral", label=str(n), size=7.0, z=8)


def storage_stack():
    d = Diagram(168, 100)
    cols = ["buffered write()", "O_DIRECT + libaio", "io_uring:\nSQPOLL + IOPOLL", "SPDK"]
    rows = ["application", "system call", "page cache", "filesystem", "block layer", "NVMe driver", "completion"]
    x0, cw, gap = 36.5, 31.0, 1.6
    xs = [x0 + i * (cw + gap) for i in range(4)]
    for x, name in zip(xs, cols):
        d.box(x, 89, cw, 9.5, name, kind="navy", size=7.6)
    row_h, step = 8.4, 9.7
    ys = [78.4 - i * step for i in range(len(rows))]
    for y, name in zip(ys, rows):
        d.text(34.5, y + row_h / 2, name, size=7.4, color=C["muted"], weight="semibold", ha="right")
    skip = ("skipped", "ghost")
    cells = [
        [("write(fd, buf, 4 KiB)", "green_t"), ("io_submit()", "green_t"), ("SQE into a shared ring", "green_t"),
         ("submit on a queue pair", "green_t")],
        [("syscall", "coral_t"), ("submit and reap\nsyscalls", "coral_t"), ("none: a kernel thread\npolls the ring", "ghost"),
         ("none", "ghost")],
        [("copy into page cache", "amber_t"), skip, skip, skip],
        [("ext4 or XFS: allocate,\njournal", "navy_t"), ("ext4 or XFS: map\nthe blocks", "navy_t"),
         ("file or raw device", "navy_t"), ("SPDK bdev layer", "green_t")],
        [("writeback builds bio\nand request", "navy_t"), ("bio, request,\nhardware queue", "navy_t"),
         ("request on a\npoll queue", "navy_t"), skip],
        [("SQ entry, doorbell", "navy_t"), ("SQ entry, doorbell", "navy_t"), ("SQ entry, doorbell", "navy_t"),
         ("user-space driver;\nBAR mapped by VFIO", "green_t")],
        [("interrupt; write()\nreturned long ago", "coral_t"), ("MSI-X interrupt,\nwake-up", "coral_t"),
         ("polled; CQE into\nthe shared ring", "navy_t"), ("polled on a\ndedicated core", "green_t")],
    ]
    for r, row in enumerate(cells):
        for c, (text, kind) in enumerate(row):
            ghost = kind == "ghost"
            d.box(xs[c], ys[r], cw, row_h, text, kind=kind, size=7.2, weight="normal", dashed=ghost,
                  label_color=C["muted"] if ghost else None)
    dy = ys[-1] - step
    d.text(34.5, dy + row_h / 2, "drive", size=7.4, color=C["muted"], weight="semibold", ha="right")
    d.box(xs[0], dy, xs[3] + cw - xs[0], row_h, "NVMe controller: fetches the command, moves the data by DMA, posts a completion",
          kind="purple_t", size=7.2, weight="normal")
    legend = [("green_t", "user space", False), ("navy_t", "kernel", False), ("coral_t", "mode switch or interrupt", False),
              ("amber_t", "data copy", False), ("ghost", "skipped", True)]
    x = 36.5
    for kind, text, dashed in legend:
        d.box(x, 1.2, 5.0, 3.6, "", kind=kind, radius=0.6, dashed=dashed)
        d.text(x + 6.4, 3.0, text, size=7.2, ha="left", color=C["ink"])
        x += 6.4 + len(text) * 1.22 + 6.0
    d.save("u4-datapath-stack")


def erasure():
    d = Diagram(168, 88)
    d.text(2, 84.5, "encode: one row of G per stored shard", size=7.8, color=C["navy"], weight="bold", ha="left")
    cs, g = 6.2, 0.5
    gx, gtop = 12.0, 77.0
    row_y = [gtop - (r + 1) * cs - r * g for r in range(6)]
    for r in range(6):
        for c in range(4):
            x = gx + c * (cs + g)
            if r < 4:
                if r == c:
                    d.box(x, row_y[r], cs, cs, "1", kind="amber_t", size=7.4, radius=0.6)
                else:
                    d.box(x, row_y[r], cs, cs, "0", kind="grey", size=7.2, radius=0.6, weight="normal",
                          label_color=C["muted"])
            else:
                d.box(x, row_y[r], cs, cs, f"$c_{{{r - 3}{c + 1}}}$", kind="purple_t", size=7.6, radius=0.6,
                      weight="normal")
    gright = gx + 4 * cs + 3 * g
    top_mid = (row_y[0] + cs + row_y[3]) / 2
    bot_mid = (row_y[4] + cs + row_y[5]) / 2
    d.text(8.5, top_mid, "I", size=8.4, color=C["amber"], weight="bold")
    d.text(8.5, bot_mid, "C", size=8.4, color=C["purple"], weight="bold")
    d.text((gx + gright) / 2, gtop + 2.2, "G", size=8.2, weight="bold")
    mid = (row_y[5] + gtop) / 2
    d.text(gright + 3.4, mid, "×", size=10, weight="bold", color=C["muted"])
    vx = gright + 7.0
    vtop = mid + (4 * cs + 3 * g) / 2
    for i in range(4):
        d.box(vx, vtop - (i + 1) * cs - i * g, cs, cs, f"$d_{i + 1}$", kind="navy_t", size=7.6, radius=0.6, weight="normal")
    d.text(vx + cs / 2, vtop + 2.2, "data", size=7.4, color=C["muted"], weight="semibold")
    d.text(vx + cs + 4.0, mid, "=", size=10, weight="bold", color=C["muted"])
    wx = vx + cs + 8.0
    labels = ["$d_1$", "$d_2$", "$d_3$", "$d_4$", "$p_1$", "$p_2$"]
    for r in range(6):
        d.box(wx, row_y[r], cs, cs, labels[r], kind="navy_t" if r < 4 else "purple_t", size=7.6, radius=0.6,
              weight="normal")
    d.text(wx + cs / 2, gtop + 2.2, "shards", size=7.4, color=C["muted"], weight="semibold")
    lines = [r"$p_i = \sum_j \, c_{ij}\, d_j$ in GF($2^8$), and + is XOR",
             r"Cauchy rows: $c_{ij} = 1/(x_i + y_j)$, so every square",
             "submatrix of G is invertible and any four",
             "of the six shards rebuild the data"]
    for i, s in enumerate(lines):
        d.text(4, 28.0 - i * 5.2, s, size=7.4, ha="left", color=C["ink"])
    d.text(4, 6.0, "systematic: data shards are stored unchanged", size=7.2, ha="left", color=C["muted"])

    d.line((86, 4), (86, 86), color=C["rule"], lw=0.7)
    d.text(90, 84.5, "two shards per failure domain, then lose one", size=7.8, color=C["navy"], weight="bold", ha="left")
    drives = [("P4510 (server)", ["$d_1$", "$d_2$"]), ("NV3 (server)", ["$d_3$", "$p_1$"]), ("NVMe (Pi)", ["$d_4$", "$p_2$"])]
    dw, dg = 23.4, 2.4
    for i, (name, shards) in enumerate(drives):
        x = 90 + i * (dw + dg)
        d.group(x, 58, dw, 21, "", color=C["navy"], dashed=False)
        d.text(x + dw / 2, 75.4, name, size=7.2, weight="semibold", color=C["navy"])
        for j, s in enumerate(shards):
            kind = "coral_t" if i == 2 else ("purple_t" if s.startswith("$p") else "navy_t")
            d.box(x + 2.6 + j * 9.6, 61.5, 8.6, 7.6, s, kind=kind, size=7.6, radius=0.6, weight="normal", z=4)
    px = 90 + 2 * (dw + dg)
    d.line((px + 1, 59), (px + dw - 1, 78), color=C["coral"], lw=1.6, z=2)
    d.line((px + 1, 78), (px + dw - 1, 59), color=C["coral"], lw=1.6, z=2)
    d.text(px + dw / 2, 54.6, "unplugged", size=7.4, color=C["coral"], weight="bold")
    steps = [(r"read any four survivors: $d_1, d_2, d_3, p_1$", "navy_t", 40.0),
             (r"invert the 4 × 4 rows of G for those shards", "purple_t", 27.0),
             (r"recover $d_4$, recompute $p_2$, rewrite both", "green_t", 14.0)]
    for i, (s, k, y) in enumerate(steps):
        d.box(90, y, 76, 8.6, s, kind=k, size=7.4, weight="normal")
        if i < 2:
            d.arrow((128, y), (128, y - 4.4), mutation=6, lw=0.8)
    for x in (90 + dw / 2, 90 + dw + dg + dw / 2):
        d.arrow((x, 58), (x, 48.6), mutation=6, lw=0.8, color=C["navy"])
    d.text(128, 6.0, "no failure domain may hold more than m = 2 shards", size=7.2, color=C["coral"],
           weight="semibold")
    d.save("u4-datapath-erasure")


def network_path():
    d = Diagram(168, 100)
    d.rect(10, 78, 157, 21, fill=C["green_t"], z=0)
    d.rect(10, 21, 157, 56, fill=C["grey"], z=0)
    d.rect(10, 2, 157, 18, fill=C["purple_t"], z=0, alpha=0.6)
    d.text(5.5, 88.5, "user space", size=7.4, color=C["green"], weight="bold", rotation=90)
    d.text(5.5, 49, "kernel", size=7.4, color=C["muted"], weight="bold", rotation=90)
    d.text(5.5, 11, "NIC", size=7.4, color=C["purple"], weight="bold", rotation=90)
    ax, aw = 14.0, 48.0
    acx = ax + aw / 2
    d.text(acx, 95.5, "kernel stack", size=7.8, color=C["navy"], weight="bold")
    a1 = d.box(ax, 24.0, aw, 7.6, "interrupt, then NAPI poll", kind="navy_t", size=7.4, weight="normal")
    a2 = d.box(ax, 34.6, aw, 10.0, "XDP hook: eBPF program", sub="DROP · TX · PASS · REDIRECT", kind="amber_t", size=7.4,
               sub_size=7.0, weight="semibold")
    a3 = d.box(ax, 47.6, aw, 7.6, "allocate sk_buff; GRO", kind="navy_t", size=7.4, weight="normal")
    a4 = d.box(ax, 58.2, aw, 7.6, "netfilter, IP, TCP", kind="navy_t", size=7.4, weight="normal")
    a5 = d.box(ax, 68.0, aw, 7.0, "socket receive queue", kind="navy_t", size=7.4, weight="normal")
    a6 = d.box(ax, 81.0, aw, 8.4, "recv(): copy into your buffer", kind="green_t", size=7.4, weight="normal")
    chain = [a1, a2, a3, a4, a5, a6]
    for lo, hi in zip(chain, chain[1:]):
        d.arrow((acx, lo.y + lo.h), (acx, hi.y), mutation=6, lw=0.8)
    bx, bw = 70.0, 44.0
    bcx = bx + bw / 2
    d.text(bcx, 95.5, "AF_XDP", size=7.8, color=C["navy"], weight="bold")
    b1 = d.box(bx, 47.0, bw, 12.0, "AF_XDP socket", sub="fill, completion, RX, TX rings", kind="navy_t", size=7.4,
               sub_size=7.0)
    b2 = d.box(bx, 81.0, bw, 8.4, "your loop over the rings", kind="green_t", size=7.4, weight="normal")
    d.path([(ax + aw, 39.6), (bcx, 39.6), (bcx, 47.0)], color=C["amber"], lw=0.9)
    d.text((ax + aw + bcx) / 2 + 2, 41.6, "REDIRECT", size=7.0, color=C["amber"], weight="bold", mono=True)
    d.arrow((bcx, 59.0), (bcx, 81.0), mutation=6, lw=0.8)
    d.text(bcx + 2.0, 70.0, "zero copy: frames\nland in UMEM", size=7.2, color=C["muted"], ha="left")
    cx, cw = 122.0, 34.0
    d.text(cx + 21.5, 95.5, "DPDK", size=7.8, color=C["navy"], weight="bold")
    d.box(cx, 45.0, cw, 15.0, "vfio-pci", sub="maps the device,\nthen stays out", kind="ghost", size=7.4, sub_size=7.0,
          dashed=True, label_color=C["ink"], sub_color=C["muted"])
    c2 = d.box(cx, 80.0, 43.0, 10.4, "poll-mode driver", sub="rx_burst; mbufs in hugepages", kind="green_t", size=7.4,
               sub_size=7.0)
    d.arrow((161.0, 16.0), (161.0, 80.0), mutation=6, lw=0.9, color=C["green"])
    d.text(159.0, 69.0, "DMA into mbufs", size=7.2, color=C["green"], ha="right")
    d.text(139.0, 31.0, "10 GbE at 64 B:\n14.88 Mpps, 67 ns\nper packet", size=7.2, color=C["muted"])
    nic = d.box(ax, 4.0, 152.0, 12.0, "X520 (82599): DMA into RX descriptor rings",
                sub="RSS spreads flows across queues; checksum and segmentation offloads", kind="purple_t", size=7.6,
                sub_size=7.2)
    d.arrow((acx, 16.0), (acx, 24.0), mutation=6, lw=0.8)
    d.save("u4-datapath-network")


def threat_model():
    d = Diagram(168, 102)
    ext = dict(kind="grey", size=7.6, sub_size=7.0)
    tenant = d.box(2, 85, 27, 11, "tenant", sub="tenant network", **ext)
    update = d.box(2, 46, 27, 14, "update server", sub="signed images", **ext)
    oper = d.box(2, 9, 27, 16, "operator", sub="Redfish on the\nmanagement network", **ext)
    d.group(35, 3, 94, 97, "Module Zero", color=C["navy"], dashed=False, lw=1.0, size=7.6)
    vm = d.box(44, 87, 36, 9, "tenant VM", kind="purple_t", size=7.6)
    vmm = d.box(44, 70, 36, 10, "VMM and KVM", kind="navy_t", size=7.6)
    host = d.box(44, 50, 36, 10, "host kernel, node agent", kind="navy_t", size=7.4)
    dev = d.box(44, 22, 24, 10, "drives, NIC", kind="grey", size=7.4)
    fw = d.box(90, 80, 32, 10, "boot firmware", kind="navy_t", size=7.6)
    tpm = d.box(90, 60, 32, 10, "TPM", kind="amber_t", size=7.6)
    bmc = d.box(90, 22, 32, 10, "Board A (BMC)", kind="coral_t", size=7.6)
    cp = d.box(135, 45, 31, 14, "control plane", sub="verifier · Raft ·\nkey store", kind="purple_t", size=7.6,
               sub_size=7.0)
    d.arrow(tenant.e, (44, 90.5), mutation=6, lw=0.9)
    d.arrow((29, 55), (44, 55), mutation=6, lw=0.9)
    d.path([(29, 17), (106, 17), (106, 22)], lw=0.9)
    d.arrow((62, 80), (62, 87), both=True, mutation=5, lw=0.8)
    d.text(64, 85.0, "virtio", size=7.0, color=C["muted"], ha="left")
    d.arrow((62, 60), (62, 70), both=True, mutation=5, lw=0.8)
    d.text(60, 65, "KVM exits", size=7.0, color=C["muted"], ha="right")
    d.arrow((56, 32), (56, 50), both=True, mutation=5, lw=0.8)
    d.text(54, 45.5, "DMA", size=7.0, color=C["muted"], ha="right")
    d.path([(78, 60), (78, 65), (90, 65)], lw=0.8, arrow_start=True, mutation=5)
    d.text(79.5, 67.4, "extend, quote", size=7.0, color=C["muted"])
    d.arrow((106, 80), (106, 70), mutation=5, lw=0.8)
    d.text(108, 75, "measure", size=7.0, color=C["muted"], ha="left")
    d.path([(100, 32), (100, 44), (74, 44), (74, 50)], lw=0.8, arrow_start=True, mutation=5)
    d.text(102, 38, "UART, I²C, reset", size=7.0, color=C["muted"], ha="left")
    d.arrow((80, 52), (135, 52), both=True, mutation=5, lw=0.8)
    d.text(110, 54.2, "quote, keys", size=7.0, color=C["muted"])
    co = C["coral"]
    d.line((41.5, 83), (84, 83), color=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 39.0, 83, 1)
    d.line((41, 39), (70, 39), color=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 39.0, 39, 2)
    d.rect(87.5, 19.5, 37, 15, edge=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 124.5, 34.5, 3)
    d.rect(87.5, 77.5, 37, 15, edge=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 124.5, 92.5, 4)
    d.rect(88.4, 57.5, 36.1, 15, edge=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 124.5, 72.5, 5)
    d.line((132, 5), (132, 98), color=co, lw=1.0, dashed=True, z=5)
    badge_num(d, 132, 41, 6)
    badge_num(d, 35, 5.5, 7)
    d.text(136, 97.5, "trust boundaries", size=7.6, weight="bold", color=C["coral"], ha="left")
    items = ["tenant ↔ host", "device ↔ memory", "BMC ↔ host", "old ↔ new firmware", "TPM ↔ software",
             "module ↔ fleet", "enclosure ↔ hands"]
    for i, s in enumerate(items):
        y = 92.0 - i * 4.6
        badge_num(d, 138, y, i + 1, r=1.8)
        d.text(141.5, y, s, size=7.0, ha="left", color=C["ink"])
    d.save("u4-product-threat")


def rollout():
    d = Diagram(168, 80)
    w, g = 30.0, 3.5
    xs = [2 + i * (w + g) for i in range(5)]
    top = [("drain", "migrate or stop\nthe tenants"), ("stage", "fetch, verify\nsignatures"),
           ("write", "inactive slots\nonly"), ("commit", "switch slots in\ndependency order"),
           ("reboot", "new images\nmeasured")]
    bot = [("attest", "quote against the\nrelease's values"), ("health", "watch for a\nset window"),
           ("readmit", "rejoin the quorum,\nreturn tenants"), ("confirm", "raise the\nminimum version"),
           ("next module", "or finish")]
    ty, by, h = 56.0, 30.0, 15.0
    for i, (a, b) in enumerate(top):
        d.box(xs[i], ty, w, h, a, sub=b, kind="navy_t", size=7.8, sub_size=7.0)
        if i < 4:
            d.arrow((xs[i] + w, ty + h / 2), (xs[i + 1], ty + h / 2), mutation=6, lw=0.8)
    for i, (a, b) in enumerate(bot):
        x = xs[4 - i]
        d.box(x, by, w, h, a, sub=b, kind="green_t" if i >= 3 else "navy_t", size=7.8, sub_size=7.0)
        if i < 4:
            d.arrow((x, by + h / 2), (xs[3 - i] + w, by + h / 2), mutation=6, lw=0.8)
    d.arrow((xs[4] + w / 2, ty), (xs[4] + w / 2, by + h), mutation=6, lw=0.8)
    d.arrow((xs[0] + w / 2, by + h), (xs[0] + w / 2, ty), mutation=6, lw=0.8)
    d.text(xs[1] + w / 2, 50.3, "bad signature: refuse,\nnothing written", size=7.0, color=C["coral"])
    rb = d.box(100, 4, 66, 14, "roll back", sub="boot the previous slots; re-attest\nagainst the old reference values",
               kind="coral_t", size=7.8, sub_size=7.0)
    hb = d.box(64, 4, 30, 14, "halt", sub="the control plane\nholds the state", kind="coral", size=7.8, sub_size=7.0)
    for x, lab in ((xs[4] + w / 2, "quote fails"), (xs[3] + w / 2, "unhealthy")):
        d.arrow((x, by), (x, 18), mutation=6, lw=0.9, color=C["coral"])
        d.text(x + 1.4, 24.0, lab, size=7.0, color=C["coral"], ha="left")
    d.arrow((100, 11), (94, 11), mutation=6, lw=0.9, color=C["coral"])
    d.text(2, 21.5, "a halted rack: every version known", size=7.2, weight="semibold", ha="left", color=C["ink"])
    states = ["v2", "v2", "v2", "v1", "v1", "v1", "v1", "v1"]
    kinds = ["green_t", "green_t", "green_t", "coral_t", "grey", "grey", "grey", "grey"]
    for i, (s, k) in enumerate(zip(states, kinds)):
        d.box(2 + i * 7.0, 6.5, 6.0, 9.0, s, kind=k, size=7.0, radius=0.8, weight="normal")
    d.text(26.0, 3.0, "rolled back", size=7.0, color=C["coral"], ha="center")
    d.save("u4-product-rollout")


def compliance_timeline():
    d = Diagram(168, 76)
    t0, scale, xl = 2024.0, 35.0, 18.0

    def X(t):
        return xl + (t - t0) * scale

    for yr in range(2024, 2029):
        x = X(yr)
        d.line((x, 8), (x, 68), color=C["light"], lw=0.7, z=0)
        d.text(x, 4.5, str(yr), size=7.4, color=C["muted"])
    gb_y, eu_y = 54.0, 26.0
    d.line((xl, gb_y), (X(2028.2), gb_y), color=C["navy"], lw=1.4, z=2)
    d.line((xl, eu_y), (X(2028.2), eu_y), color=C["purple"], lw=1.4, z=2)
    d.text(2, gb_y, "UK", size=8.0, color=C["navy"], weight="bold", ha="left")
    d.text(2, eu_y, "EU", size=8.0, color=C["purple"], weight="bold", ha="left")
    today = X(2026 + 277 / 365)
    d.line((today, 8), (today, 70), color=C["amber"], lw=1.0, dashed=True, z=1)
    d.text(today + 1.0, 71.6, "today: 5 Oct 2026", size=7.2, color=C["amber"], weight="bold", ha="left")
    events = [
        (2024 + 119 / 366, gb_y, "PSTI in force\n29 Apr 2024", 46.6, "center", C["navy"]),
        (2024 + 274 / 366, gb_y, "GB accepts UKCA or CE\nindefinitely, 1 Oct 2024", 62.6, "left", C["navy"]),
        (2024 + 344 / 366, eu_y, "CRA in force\n10 Dec 2024", 17.6, "center", C["purple"]),
        (2025 + 29 / 365, eu_y, "EN 18031 listed\n30 Jan 2025", 33.8, "left", C["purple"]),
        (2025 + 212 / 365, eu_y, "RED cyber act 2022/30\napplies, 1 Aug 2025", 42.4, "left", C["purple"]),
        (2026 + 161 / 365, eu_y, "CRA rules for notified\nbodies, 11 Jun 2026", 17.6, "right", C["purple"]),
        (2026 + 253 / 365, eu_y, "CRA reporting applies\n11 Sep 2026", 34.6, "right", C["purple"]),
        (2027 + 344 / 365, eu_y, "CRA applies in full;\n2022/30 repealed\n11 Dec 2027", 15.4, "right", C["purple"]),
    ]
    for t, ly, label, ty, ha, col in events:
        x = X(t)
        d.circle(x, ly, 1.3, kind="navy" if col == C["navy"] else "purple", lw=0.6, z=6)
        edge = ty + (-3.2 if ty > ly else 3.2)
        if label.count("\n") == 2 and ty < ly:
            edge = ty + 4.6
        d.line((x, ly), (x, edge), color=col, lw=0.6, z=3)
        tx = x if ha == "center" else (x - 0.8 if ha == "right" else x + 0.8)
        d.text(tx, ty, label, size=7.2, color=C["ink"], ha=ha)
    d.save("u4-product-compliance")


def manufacturing():
    d = Diagram(168, 64)
    w, g = 37.5, 5.0
    xs = [2 + i * (w + g) for i in range(4)]
    top = [("board assembly", "SMT, reflow, AOI;\nlot and reel IDs"), ("flying probe", "opens and shorts\nbefore power"),
           ("functional test", "self-test firmware;\nsensors against limits"),
           ("provisioning", "key born in the ATECC608;\nper-unit credentials")]
    bot = [("integration", "boards into the sled;\nserials linked"), ("burn-in", "24 h under load;\ntemperature and power"),
           ("system test", "real firmware; quote\nto the factory verifier"),
           ("pack and enrol", "label; identity enrolled\nin the fleet verifier")]
    ty, by, h = 44.0, 4.0, 16.0
    for i, (a, b) in enumerate(top):
        d.box(xs[i], ty, w, h, a, sub=b, kind="navy_t", size=7.8, sub_size=7.0)
        if i < 3:
            d.arrow((xs[i] + w, ty + h / 2), (xs[i + 1], ty + h / 2), mutation=6, lw=0.8)
        d.arrow((xs[i] + w / 2, ty), (xs[i] + w / 2, 35.0), mutation=5, lw=0.7, dashed=True, color=C["amber"])
    for i, (a, b) in enumerate(bot):
        x = xs[3 - i]
        d.box(x, by, w, h, a, sub=b, kind="green_t" if i == 3 else "navy_t", size=7.8, sub_size=7.0)
        if i < 3:
            d.arrow((x, by + h / 2), (xs[2 - i] + w, by + h / 2), mutation=6, lw=0.8)
        d.arrow((x + w / 2, by + h), (x + w / 2, 27.0), mutation=5, lw=0.7, dashed=True, color=C["amber"])
    d.box(2, 27.0, 150, 8.0, "manufacturing database: serial → lot, boards, public keys, test records, firmware versions",
          kind="amber_t", size=7.4, weight="semibold")
    d.path([(xs[3] + w - 4, ty), (xs[3] + w - 4, by + h)], lw=0.8, mutation=6)
    d.save("u4-product-manufacturing")


def capstone_arch():
    d = Diagram(168, 106)
    buses = [("VLAN 10: management", C["navy"], 84.0), ("VLAN 20: storage", C["purple"], 80.5),
             ("VLAN 30: tenant", C["amber"], 77.0)]
    for _, col, y in buses:
        d.line((4, y), (166, y), color=col, lw=1.5, z=2)
    x = 4.0
    for name, col, _ in buses:
        d.line((x, 102.2), (x + 6, 102.2), color=col, lw=1.8)
        d.text(x + 7.5, 102.2, name, size=7.2, color=col, weight="semibold", ha="left")
        x += 7.5 + len(name) * 1.25 + 6.0
    d.text(166, 102.2, "TL-SG108E, 802.1Q", size=7.2, color=C["muted"], ha="right")

    def tick(x, y0, dots):
        d.line((x, y0), (x, 84.0), color=C["ink"], lw=0.9, z=3)
        for col, y in dots:
            d.dot(x, y, r=0.9, color=col)

    mg, st, tn = (C["navy"], 84.0), (C["purple"], 80.5), (C["amber"], 77.0)
    cp = d.box(4, 87, 94, 10, "control plane, on the voters", sub="rack Redfish · dashboard · scheduler · rollouts",
               kind="purple_t", size=7.6, sub_size=7.0)
    d.line((51, 87), (51, 84), color=C["ink"], lw=0.9)
    d.dot(51, 84, r=0.9, color=C["navy"])
    lap = d.box(104, 87, 62, 10, "laptop", sub="curl · dashboard · screen capture", kind="grey", size=7.6, sub_size=7.0)
    d.line((135, 87), (135, 84), color=C["ink"], lw=0.9)
    d.dot(135, 84, r=0.9, color=C["navy"])

    image_sub = "agent · Raft voter · verifier\nkey store · VMM · stripe store"
    d.group(4, 4, 52, 70, "server (x86-64)", color=C["navy"], dashed=False, size=7.4)
    d.box(7, 59, 30, 8, "iDRAC8: Redfish", kind="coral_t", size=7.2)
    tick(33, 67, [mg])
    d.box(7, 32, 46, 24, "node image", sub=image_sub, kind="navy_t", size=7.8, sub_size=7.0)
    tick(47, 56, [mg, st, tn])
    d.box(7, 19, 20, 9, "TPM 2.0", kind="amber_t", size=7.4)
    d.box(30, 19, 23, 9, "P4510, NV3", sub="2 shards", kind="grey", size=7.2, sub_size=7.0)
    d.box(7, 7, 46, 9, "tenant VM", sub="volume over all three nodes", kind="purple_t", size=7.4, sub_size=7.0)

    d.group(60, 28, 52, 46, "Board B (arm64, CM5)", color=C["navy"], dashed=False, size=7.4)
    d.box(63, 44, 46, 22, "node image", sub=image_sub, kind="navy_t", size=7.8, sub_size=7.0)
    tick(103, 66, [mg, st, tn])
    d.box(63, 31, 20, 9, "SLB 9672", kind="amber_t", size=7.4)
    d.box(86, 31, 23, 9, "NVMe", sub="2 shards", kind="grey", size=7.2, sub_size=7.0)
    d.box(60, 4, 52, 14, "Board A: BMC-lite", sub="MSP432E401Y · Redfish over lwIP\nATECC608 · INA228 · TMP117 · fans",
          kind="coral_t", size=7.6, sub_size=7.0)
    d.arrow((66, 18), (66, 28), both=True, mutation=5, lw=0.8)
    d.text(68.5, 23.0, "UART · I²C · power-enable\npower-good · reset · presence", size=7.0, color=C["muted"], ha="left")
    d.path([(112, 11), (115, 11), (115, 84)], arrow_end=False, color=C["ink"], lw=0.9)
    d.dot(115, 84, r=0.9, color=C["navy"])

    d.group(119, 28, 47, 46, "Pi 5 (third voter)", color=C["navy"], dashed=False, size=7.4)
    d.box(122, 44, 41, 22, "node image", sub="agent · Raft voter\nverifier · stripe store", kind="navy_t", size=7.8,
          sub_size=7.0)
    tick(158, 66, [mg, st])
    d.box(122, 31, 41, 9, "NVMe on the M.2 HAT+", sub="2 shards", kind="grey", size=7.2, sub_size=7.0)
    d.box(119, 4, 47, 18, "(4, 2) stripes with two\nshards per node: any one\nnode can disappear", kind="ghost",
          size=7.2, weight="normal", label_color=C["ink"])
    d.save("u4-capstone-arch")


def lifeline_note(s, i, text, w=30.0, h=8.6, kind="amber_t", advance=True):
    x = s.xs[i]
    s.box(x - w / 2, s.y - h, w, h, text, kind=kind, size=7.0, weight="normal")
    if advance:
        s.y -= h + 6.0


def boxed_text(d, x, y, text, size=7.2, color=None, ha="center", weight="normal"):
    d.ax.text(x, y, text, fontsize=size, color=color or C["ink"], ha=ha, va="center", family=SANS, weight=weight,
              zorder=7, bbox=dict(boxstyle="square,pad=0.15", facecolor="white", edgecolor="none"))


def smsg(s, i, j, label, dashed=False, step=7.6):
    y = s.y
    s.msg(i, j, "", step=step, dashed=dashed)
    boxed_text(s, (s.xs[i] + s.xs[j]) / 2, y + 2.3, label)


def sdivider(s, label, step=7.0):
    y = s.y + 1.5
    s.line((2, y), (s.w - 2, y), color=C["amber"], lw=0.8, dashed=True)
    boxed_text(s, 4, y + 2.4, label, color=C["amber"], ha="left", weight="bold")
    s.y -= step - 1.0


def capstone_coldstart():
    s = Sequence(["laptop", "Board A", "Board B", "server", "Pi (voter)"], h=128, box_w=28,
                 kinds=["purple", "coral", "navy", "navy", "navy"])
    smsg(s, 0, 1, "Redfish: Reset (On)")
    smsg(s, 1, 2, "power-enable; watch PG")
    smsg(s, 0, 3, "Redfish to the iDRAC: Reset (On)")
    s.y -= 1.0
    lifeline_note(s, 2, "verified U-Boot,\nsigned FIT, PCRs", advance=False)
    lifeline_note(s, 3, "Secure Boot,\nPCRs extended")
    sdivider(s, "server bootstraps the quorum; the Pi joins as the second voter", step=9.0)
    smsg(s, 2, 3, "beacon on VLAN 10")
    smsg(s, 3, 2, "nonce")
    smsg(s, 2, 3, "quote, event log, EK cert")
    s.y -= 1.0
    lifeline_note(s, 3, "replay the log against\nthe release's values", w=31)
    smsg(s, 3, 4, "Raft: admit Board B")
    smsg(s, 4, 3, "commit", dashed=True)
    smsg(s, 3, 2, "credentials, disk key", dashed=True)
    s.y -= 1.5
    sdivider(s, "joined: stop the clock started by the first Redfish call")
    s.save("u4-capstone-coldstart")


ALL = [storage_stack, erasure, network_path, threat_model, rollout, compliance_timeline, manufacturing, capstone_arch,
       capstone_coldstart]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
