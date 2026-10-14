from matplotlib.patches import Circle

from omhfig import C, Diagram, Sequence


def numbered(d, x, y, n, text="", size=7.4, color=None):
    col = color or C["navy"]
    d.ax.add_patch(Circle((x, y), 2.0, facecolor=col, edgecolor=col, linewidth=0.6, zorder=7))
    d.text(x, y - 0.05, str(n), size=7.0, color=C["white"], weight="bold", z=8)
    if text:
        d.text(x + 3.0, y, text, size=size, color=C["ink"], ha="left", z=8)


def qs_dot(d, x, y):
    d.ax.add_patch(Circle((x, y), 0.9, facecolor=C["amber"], edgecolor=C["ink"], linewidth=0.5, zorder=7))


def kernel_boot_flow():
    d = Diagram(168, 88)
    d.text(27, 84.5, "your loaders", size=8, color=C["muted"], weight="bold")
    d.text(79, 84.5, "the handoff", size=8, color=C["muted"], weight="bold")
    d.text(131, 84.5, "kernel initialisation, in order", size=8, color=C["muted"], weight="bold")
    bios = d.box(3, 52, 48, 22, "Lab 2.7.1 loader", sub="BIOS boot sector and stage two:\nE820 map, long mode, ELF64",
                 kind="navy_t", size=8.2, sub_size=7.2)
    uefi = d.box(3, 18, 48, 22, "Lab 2.7.2 loader", sub="UEFI application: memory map,\nGOP, RSDP, ExitBootServices",
                 kind="navy_t", size=8.2, sub_size=7.2)
    d.text(27, 48.2, "QEMU with SeaBIOS", size=7.2, color=C["muted"])
    d.text(27, 14.2, "QEMU with OVMF, and the server", size=7.2, color=C["muted"])
    sx, sw = 58, 42
    d.box(sx, 66, sw, 8, "struct boot_info", kind="navy", size=7.6, mono=True, weight="bold", radius=0.8)
    fields = ["memory map", "framebuffer and format", "RSDP address", "command line", "kernel load address"]
    for i, f in enumerate(fields):
        d.box(sx, 59 - i * 7, sw, 7, f, kind="plain", size=7.4, weight="normal", radius=0.4, lw=0.7, align="left")
    d.text(sx + sw / 2, 27.5, "the kernel reads only this", size=7.2, color=C["muted"], style="italic")
    d.arrow(bios.e, (sx, bios.cy), mutation=6, lw=0.9)
    d.arrow(uefi.e, (sx, 34), mutation=6, lw=0.9)
    d.path([(sx + sw, 62.5), (103, 62.5), (103, 78.3), (106, 78.3)], color=C["ink"], lw=0.9, mutation=6)
    steps = [
        ("serial console, printk, panic", "4.1.1"),
        ("own GDT, TSS and IDT", "4.1.1"),
        ("higher half and direct map", "4.1.1"),
        ("buddy allocator and slab heap", "4.1.2"),
        ("APIC timer, threads, scheduler", "4.1.3"),
        ("APs online, per-CPU run queues", "4.1.3"),
        ("user mode and system calls", "4.1.4"),
        ("PCI, NVMe and FAT32", "4.1.5"),
    ]
    for i, (s, lab) in enumerate(steps):
        y = 75 - i * 9.3
        d.box(106, y, 48, 6.6, s, kind="navy_t", size=7.4, weight="semibold", radius=0.8)
        d.badge(161, y + 3.3, lab, kind="amber", size=7.2)
        if i < len(steps) - 1:
            d.arrow((130, y), (130, y - 2.7), mutation=5, lw=0.8)
    d.save("u4-kernel-boot-flow")


def kernel_address_space():
    d = Diagram(168, 92)
    bx, bw = 36, 42
    regions = [
        (6, 6, "text, data, bss", "green_t", "normal"),
        (14, 6, "heap, grows up with brk", "green_t", "normal"),
        (22, 6, "mmap area", "green_t", "normal"),
        (32, 6, "user stack, grows down", "green_t", "normal"),
        (52, 13, "direct map of all RAM", "navy_t", "semibold"),
        (67, 8, "heap, stacks, MMIO", "navy_t", "normal"),
        (79, 7, "kernel image, top 2 GiB", "navy", "semibold"),
    ]
    for y, h, lab, kind, wt in regions:
        d.box(bx, y, bw, h, lab, kind=kind, size=7.4, weight=wt, radius=0.5, lw=0.7)
    d.box(bx, 40.5, bw, 9, "non-canonical hole", kind="grey", size=7.4, weight="normal", radius=0.5, lw=0.7,
          label_color=C["muted"])
    addrs = [(6, "0x0000_0000_0000_0000"), (38, "0x0000_7FFF_FFFF_FFFF"), (52, "0xFFFF_8000_0000_0000"),
             (79, "0xFFFF_FFFF_8000_0000")]
    for y, a in addrs:
        d.line((bx - 1.6, y), (bx, y), color=C["muted"], lw=0.7)
        d.text(bx - 2.2, y, a, size=7.0, mono=True, ha="right", color=C["ink"])
    d.text(57, 89, "virtual address space (not to scale)", size=7.4, color=C["muted"], weight="bold")
    d.text(81, 22, "lower half:\nthe running\nprocess", size=7.4, color=C["green"], ha="left", weight="semibold")
    d.text(81, 66, "upper half:\nthe kernel,\nsame for all", size=7.4, color=C["navy"], ha="left", weight="semibold")
    for x, name in ((104, "A's PML4"), (154, "B's PML4")):
        d.box(x, 14, 10, 32, "", kind="green_t", radius=0.4, lw=0.7)
        d.box(x, 46, 10, 32, "", kind="navy_t", radius=0.4, lw=0.7)
        d.text(x + 5, 81.5, name, size=7.6, weight="bold", color=C["ink"])
        d.text(x + 5, 30, "entries 0 to 255", size=7.0, rotation=90, color=C["green"])
        d.text(x + 5, 62, "entries 256 to 511", size=7.0, rotation=90, color=C["navy"])
    kern = d.box(121, 56, 26, 16, "kernel tables", sub="shared by every\naddress space", kind="navy", size=7.6,
                 sub_size=7.0)
    ua = d.box(121, 33, 26, 9, "A's user tables", kind="green_t", size=7.2)
    ub = d.box(121, 18, 26, 9, "B's user tables", kind="green_t", size=7.2)
    d.arrow((114, 62), kern.left(0.4), mutation=5.5, lw=0.8, color=C["navy"])
    d.arrow((154, 62), kern.right(0.4), mutation=5.5, lw=0.8, color=C["navy"])
    d.arrow((114, 34), ua.w_, mutation=5.5, lw=0.8, color=C["green"])
    d.arrow((154, 26), ub.e, mutation=5.5, lw=0.8, color=C["green"])
    d.text(134, 8, "a switch from A to B loads B's PML4 into CR3", size=7.2, color=C["muted"])
    d.save("u4-kernel-address-space")


def kernel_smp_bringup():
    s = Sequence(["BSP (CPU 0)", "AP (CPU n)", "low memory"], h=100, box_w=40, kinds=["navy", "purple", "grey"])
    s.msg(0, 2, "copy trampoline to 0x8000; store CR3, stack and entry", step=7.6)
    s.msg(0, 1, "INIT IPI through the ICR", step=7.6)
    s.divider("wait 10 ms")
    s.msg(0, 1, "STARTUP IPI, vector 0x08", step=7.6)
    s.divider("wait 200 µs")
    s.msg(0, 1, "second STARTUP IPI, vector 0x08", step=7.6)
    s.msg(1, 1, "real mode at 0x8000 → long mode", step=7.6)
    s.msg(2, 1, "CR3, stack, per-CPU pointer", dashed=True, step=7.6)
    s.msg(1, 1, "own GDT, TSS, IDT; GS base", step=7.6)
    s.msg(1, 2, "online flag = 1", step=7.6)
    s.msg(2, 0, "BSP sees the flag and starts the next AP", dashed=True, step=7.6)
    s.save("u4-kernel-smp-bringup")


def kernel_nvme_queues():
    d = Diagram(168, 96)
    d.group(2, 2, 100, 60, "host memory", color=C["navy"])
    d.group(108, 2, 58, 82, "NVMe controller", color=C["purple"])
    d.box(4, 66, 76, 14, "driver, running on a CPU", kind="navy", size=8.4)
    x0, sw, n = 8, 9, 8
    xe = x0 + n * sw
    sq_y, cq_y = 44, 20
    d.text(x0, 55.5, "I/O submission queue: 64-byte commands", size=7.4, ha="left")
    for i in range(n):
        filled = 3 <= i <= 5
        d.box(x0 + i * sw, sq_y, sw, 7, "cmd" if filled else "", kind="navy_t" if filled else "grey", size=7.0,
              weight="normal", radius=0.4, lw=0.7)
    for i, lab in ((3, "head"), (6, "tail")):
        cx = x0 + i * sw + sw / 2
        d.arrow((cx, sq_y - 5.2), (cx, sq_y - 0.4), mutation=4.5, lw=0.7, color=C["muted"])
        d.text(cx, sq_y - 7.0, lab, size=7.2, color=C["muted"])
    d.text(x0, 31.5, "I/O completion queue: 16-byte entries, phase bit shown", size=7.4, ha="left")
    for i in range(n):
        new = i in (2, 3)
        phase = "1" if i < 4 else "0"
        d.box(x0 + i * sw, cq_y, sw, 7, phase, kind="green_t" if new else "grey", size=7.2, mono=True,
              weight="bold" if new else "normal", radius=0.4, lw=0.7,
              label_color=C["ink"] if new else C["muted"])
    cx = x0 + 2 * sw + sw / 2
    d.arrow((cx, cq_y - 5.2), (cx, cq_y - 0.4), mutation=4.5, lw=0.7, color=C["muted"])
    d.text(cx, cq_y - 7.0, "head", size=7.2, color=C["muted"])
    d.box(8, 3.5, 34, 6, "4 KiB page, PRP1", kind="amber_t", size=7.2, weight="normal", radius=0.4, lw=0.7)
    d.box(45, 3.5, 34, 6, "4 KiB page, PRP2", kind="amber_t", size=7.2, weight="normal", radius=0.4, lw=0.7)
    sqdb = d.box(112, 70, 42, 8, "BAR0: SQ 1 tail doorbell", kind="purple_t", size=7.4)
    d.box(112, 58, 42, 8, "BAR0: CQ 1 head doorbell", kind="purple_t", size=7.4)
    d.box(112, 4, 42, 50, "fetch, execute,\nmove data", kind="purple", size=8.2)
    tail_x = x0 + 6 * sw + sw / 2
    d.arrow((tail_x, 66), (tail_x, sq_y + 7.2), mutation=6, lw=0.9, color=C["navy"])
    numbered(d, tail_x + 4.5, 58.6, 1, "command")
    d.arrow((80, 74), sqdb.w_, mutation=6, lw=0.9, color=C["navy"])
    numbered(d, 87, 76.6, 2, "new tail")
    d.arrow((xe, sq_y + 3.5), (112, sq_y + 3.5), mutation=6, lw=0.9, color=C["purple"])
    numbered(d, 84.5, sq_y + 6.2, 3, "fetch")
    d.arrow((79, 6.5), (112, 6.5), mutation=6, lw=0.9, color=C["purple"], both=True)
    numbered(d, 84.5, 9.6, 4, "data")
    d.arrow((112, cq_y + 3.5), (xe, cq_y + 3.5), mutation=6, lw=0.9, color=C["purple"])
    numbered(d, 84.5, cq_y + 6.2, 5, "post")
    d.path([(154, 30), (160, 30), (160, 90), (42, 90), (42, 80)], color=C["coral"], lw=0.9, mutation=6)
    numbered(d, 66, 92.4, 6, "MSI-X interrupt, or the driver polls the phase bit", color=C["coral"])
    d.path([(80, 69), (104, 69), (104, 62), (112, 62)], color=C["navy"], lw=0.9, mutation=6)
    numbered(d, 87, 66.2, 7, "new head")
    d.save("u4-kernel-nvme-queues")


def linux_write_path():
    d = Diagram(168, 98)
    lx, lw_, rx, rw = 27, 77, 110, 56
    d.text(lx + lw_ / 2, 95, "process context: the system call", size=8, color=C["muted"], weight="bold")
    d.text(rx + rw / 2, 95, "interrupt context, later", size=8, color=C["muted"], weight="bold")
    rows = [
        ("user", 'write(1, "hi\\n", 3)', "green_t"),
        ("entry", "entry_SYSCALL_64 → do_syscall_64", "navy_t"),
        ("VFS", "__x64_sys_write → ksys_write", "navy_t"),
        ("", "vfs_write → new_sync_write", "navy_t"),
        ("tty core", "tty_write → file_tty_write → iterate_tty_write", "navy_t"),
        ("line discipline", "n_tty_write: \\n becomes \\r\\n", "navy_t"),
        ("serial core", "uart_write → kfifo_in(xmit_fifo)", "navy_t"),
        ("8250 driver", "serial8250_start_tx: enable THRI", "purple_t"),
    ]
    ys = []
    for i, (sub, fn, kind) in enumerate(rows):
        y = 84 - i * 10.8
        ys.append(y)
        d.box(lx, y, lw_, 7.6, fn, kind=kind, size=7.0, mono=True, weight="normal", radius=0.8)
        if sub:
            yy = y + 3.8 if sub != "VFS" else y - 1.6
            d.text(lx - 2.2, yy, sub, size=7.2, color=C["muted"], weight="bold", ha="right")
        if i < len(rows) - 1:
            d.arrow((lx + lw_ / 2, y), (lx + lw_ / 2, y - 3.2), mutation=5, lw=0.8)
    right = [
        ("16550 raises the THRE interrupt", "amber_t", False),
        ("serial8250_handle_irq", "purple_t", True),
        ("serial8250_tx_chars: kfifo → THR", "purple_t", True),
        ("serial_out(up, UART_TX, c)", "purple_t", True),
        ("bytes leave the UART for SOL", "amber_t", False),
    ]
    rys = []
    for j, (txt, kind, mono) in enumerate(right):
        y = ys[3 + j]
        rys.append(y)
        d.box(rx, y, rw, 7.6, txt, kind=kind, size=7.0 if mono else 7.4, mono=mono, weight="normal", radius=0.8)
        if j < len(right) - 1:
            d.arrow((rx + rw / 2, y), (rx + rw / 2, y - 3.2), mutation=5, lw=0.8)
    d.path([(lx + lw_, ys[7] + 3.8), (107, ys[7] + 3.8), (107, rys[0] + 3.8), (rx, rys[0] + 3.8)],
           color=C["coral"], lw=0.9, dashed=True, mutation=6)
    d.save("u4-linux-write-path")


def linux_blk_mq():
    d = Diagram(168, 94)
    x0, span = 32, 134
    d.box(x0, 82, span, 8, "bio from the page cache, a filesystem or O_DIRECT", kind="grey", size=7.8)
    cw, cp = 14.5, (span - 14.5) / 7
    ctx = []
    for i in range(8):
        hot = i == 5
        ctx.append(d.box(x0 + i * cp, 62, cw, 10, f"CPU {i}", sub="ctx", kind="coral_t" if hot else "navy_t",
                         size=7.6, sub_size=7.0))
    hw, hp = 31.5, (span - 31.5) / 3
    hctx, qp = [], []
    for j in range(4):
        hot = j == 2
        x = x0 + j * hp
        h = d.box(x, 37, hw, 13, f"hctx {j}", sub="nvme_queue_rq", kind="coral_t" if hot else "navy_t", size=7.6,
                  sub_size=7.0)
        q = d.box(x, 15, hw, 13, f"SQ {j + 1}, CQ {j + 1}", sub=f"vector {j + 1} → CPUs {2 * j}, {2 * j + 1}",
                  kind="coral_t" if hot else "purple_t", size=7.6, sub_size=7.0)
        hctx.append(h)
        qp.append(q)
        d.arrow(h.bottom(), q.top(), mutation=5, lw=0.9 if hot else 0.8, color=C["coral"] if hot else C["ink"])
        d.arrow((q.cx, 15), (q.cx, 10), mutation=5, lw=0.9 if hot else 0.8, both=True,
                color=C["coral"] if hot else C["purple"])
    for i, b in enumerate(ctx):
        h = hctx[i // 2]
        tx = h.cx + (-5 if i % 2 == 0 else 5)
        hot = i == 5
        d.arrow(b.bottom(), (tx, 50), mutation=5, lw=0.9 if hot else 0.7, color=C["coral"] if hot else C["muted"])
    d.box(x0, 2, span, 8, "NVMe controller: fetches from every submission queue, posts to every completion queue",
          kind="purple_t", size=7.4)
    d.arrow((ctx[5].cx, 82), ctx[5].top(), mutation=5.5, lw=0.9, color=C["coral"])
    labels = [(86, "block layer"), (67, "software\ncontexts,\none per CPU"), (56, "map_queues"),
              (43.5, "hardware\ncontexts"), (21.5, "queue pairs\nin host\nmemory"), (6, "device")]
    for y, lab in labels:
        d.text(x0 - 2.5, y, lab, size=7.2, color=C["muted"], weight="bold", ha="right", mono=lab == "map_queues")
    d.save("u4-linux-blk-mq")


def linux_rcu():
    d = Diagram(168, 74)
    t0 = 24

    def X(t):
        return t0 + t

    rows = [("writer", 58), ("CPU 0", 46), ("CPU 1", 36), ("CPU 2", 26), ("CPU 3", 16)]
    for name, y in rows:
        d.text(t0 - 3, y, name, size=7.6, mono=True, ha="right", weight="bold")
        if name != "writer":
            d.line((X(0), y), (X(140), y), color=C["rule"], lw=0.7)
    pub, gp_end = 40, 104
    d.rect(X(pub), 6.5, gp_end - pub, 46, fill=C["amber_t"], z=0)
    d.text(X((pub + gp_end) / 2), 9.2, "grace period", size=7.6, color=C["amber"], weight="bold")
    readers = [
        (46, 6, 54, "old"), (36, 26, 98, "old"), (26, 56, 86, "new"), (26, 110, 136, "new"),
        (16, 2, 22, "old"), (16, 62, 112, "new"),
    ]
    for y, a, b, v in readers:
        old = v == "old"
        d.box(X(a), y - 2.6, b - a, 5.2, f"reads {v}", kind="navy_t" if old else "green_t", size=7.0,
              weight="normal", radius=1.2, lw=0.7)
    for y, t in ((46, 57), (36, 101), (26, 47), (16, 51)):
        qs_dot(d, X(t), y)
    d.box(X(pub), 55.4, gp_end - pub, 5.2, "synchronize_rcu() waits", kind="grey", size=7.0, mono=True,
          weight="normal", radius=1.2, lw=0.7)
    d.box(X(gp_end + 3), 55.4, 24, 5.2, "kfree(old)", kind="coral_t", size=7.0, mono=True, weight="normal",
          radius=1.2, lw=0.7)
    d.line((X(pub), 5), (X(pub), 64), color=C["coral"], lw=0.9, dashed=True, z=5)
    d.text(X(pub), 67, "rcu_assign_pointer(gp, new)", size=7.2, mono=True, color=C["coral"])
    d.arrow((X(0), 2.5), (X(140), 2.5), mutation=5, lw=0.7, color=C["muted"])
    d.text(X(140) + 1.0, 2.5, "time", size=7.2, color=C["muted"], ha="left")
    qs_dot(d, X(108), 67)
    d.text(X(110), 67, "quiescent state", size=7.2, color=C["muted"], ha="left")
    d.save("u4-linux-rcu")


ALL = [kernel_boot_flow, kernel_address_space, kernel_smp_bringup, kernel_nvme_queues, linux_write_path,
       linux_blk_mq, linux_rcu]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
