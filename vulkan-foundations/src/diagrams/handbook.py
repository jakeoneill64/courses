import numpy as np

from vkfig import C, Diagram, plot, save

UNITS = [
    ("1", "The Explicit API", "amber", [
        "Instances, devices and queues", "Memory, buffers and images", "Commands and submission",
        "Shaders, SPIR-V and pipelines", "Descriptors and your first dispatch",
        "Validation, debugging and a helper layer"]),
    ("2", "Compute Shaders", "coral", [
        "The compute execution model", "Memory in shaders", "Parallel patterns",
        "Images and image processing", "Measuring and tuning", "Dispatch at scale",
        "A ray tracer in a compute shader"]),
    ("3", "Synchronisation", "magenta", [
        "Why synchronisation is your job", "The dependency model", "Pipeline barriers in practice",
        "Fences, semaphores and events", "Queues and async compute", "Frames in flight",
        "Finding synchronisation bugs", "Render graphs"]),
    ("4", "Rendering and the Whole Frame", "purple", [
        "The graphics pipeline", "Presentation", "Drawing with data", "Compute meets graphics",
        "From OpenGL to Vulkan", "Scaling up", "Capstone: a GPU-driven sandbox"]),
]


def course_map():
    d = Diagram(168, 100)
    col_w, gap = 39.4, 2.6
    for i, (num, title, colour, chapters) in enumerate(UNITS):
        x = 2 + i * (col_w + gap)
        d.box(x, 88, col_w, 11, f"Unit {num}", sub=title, kind=colour, size=8.2, sub_size=6.6)
        for j, ch in enumerate(chapters):
            y = 78 - j * 9.4
            last = num != "1" and j == len(chapters) - 1
            d.box(x, y, col_w, 8.2, f"{num}.{j + 1}  {ch}", kind=f"{colour}_t" if not last else colour,
                  size=5.9, weight="semibold" if last else "normal", align="left", radius=1.2)
        if i < 3:
            d.arrow((x + col_w + 0.3, 93.5), (x + col_w + gap - 0.3, 93.5), color=C["muted"], lw=0.8, mutation=6)
    d.text(2, 4, "Highlighted: the projects that close Units 2 to 4, a ray tracer, a render graph "
                 "and a GPU-driven sandbox.", size=6.6, color=C["muted"], ha="left")
    d.save("h-map")


def gpu():
    d = Diagram(168, 84)
    d.group(2, 30, 40, 50, "Host", color=C["navy"], dashed=False, size=7.6)
    d.box(6, 58, 32, 12, "CPU", sub="your program, the driver", kind="navy_t", size=8, sub_size=6.2)
    d.box(6, 36, 32, 12, "System RAM", sub="staging, readback", kind="grey", size=7.6, sub_size=6.2)
    d.arrow((22, 58), (22, 48.6), both=True, color=C["muted"], lw=0.7, mutation=6)
    d.box(46, 52, 14, 10, "PCIe", sub="~32 GB/s", kind="plain", size=7.4, sub_size=6)
    d.arrow((38, 64), (46, 57), color=C["muted"], lw=0.7, mutation=6)
    d.arrow((60, 57), (66, 64), color=C["muted"], lw=0.7, mutation=6)
    d.group(64, 2, 102, 78, "Device: a discrete GPU", color=C["coral"], dashed=False, size=7.6)
    d.box(68, 60, 30, 12, "Command processor", sub="reads the queues", kind="coral_t", size=7.2, sub_size=6)
    for k in range(3):
        d.box(102 + k * 20.5, 64, 18, 7, f"queue {k}", kind="plain", size=6.6, weight="normal")
    d.text(133, 74.5, "queues feed the command processor", size=6.2, color=C["muted"])
    for k in range(4):
        x = 68 + k * 24.5
        d.group(x, 26, 22.5, 30, f"compute unit {k}" if k < 3 else "... many more", color=C["purple"], dashed=k == 3,
                size=6.0)
        if k < 3:
            for r in range(2):
                for c in range(4):
                    d.rect(x + 2 + c * 4.8, 39 + r * 4.8, 3.8, 3.8, fill=C["purple_t"], edge=C["purple"], lw=0.4)
            d.text(x + 11.25, 36, "SIMD lanes", size=5.6, color=C["purple"])
            d.box(x + 2, 28.5, 18.5, 5, "registers, shared", kind="purple_t", size=5.4, weight="normal", radius=0.8)
    d.box(68, 14, 94, 8, "L2 cache, shared by every compute unit", kind="grey", size=6.8, weight="normal")
    d.box(68, 4, 94, 8, "VRAM: gigabytes, hundreds of GB/s to over 1 TB/s", kind="coral_t", size=6.8,
          weight="normal")
    d.save("h-gpu")


def simt():
    d = Diagram(168, 58)
    lanes = 8
    d.text(2, 53, "8 lanes run  if (x < 4) a(); else b();  then c();", size=7.2, ha="left",
           color=C["ink"])
    steps = [("load x", [1] * 8, "navy"), ("a()", [1, 1, 1, 1, 0, 0, 0, 0], "coral"),
             ("b()", [0, 0, 0, 0, 1, 1, 1, 1], "amber"), ("c()", [1] * 8, "navy")]
    x0, cw = 26, 30
    for s, (name, mask, kind) in enumerate(steps):
        x = x0 + s * (cw + 4)
        d.text(x + cw / 2, 46, name, size=7.2, weight="semibold", mono=True)
        for lane in range(lanes):
            y = 38 - lane * 4.4
            on = mask[lane]
            d.rect(x, y, cw, 3.4, fill=C[kind] if on else C["grey"], edge=C[kind] if on else C["rule"], lw=0.4)
    for lane in range(lanes):
        d.text(23, 39.7 - lane * 4.4, f"lane {lane}", size=6.2, ha="right", color=C["muted"])
    d.arrow((x0, 3.5), (x0 + 4 * cw + 12, 3.5), color=C["muted"], lw=0.7, mutation=6)
    d.text(x0 + 4 * cw + 14, 3.5, "time", size=6.4, color=C["muted"], ha="left")
    d.text(164, 53, "grey: lane masked off, its result discarded", size=6.2, color=C["muted"], ha="right")
    d.save("h-simt")


def latency():
    d = Diagram(168, 46)
    rows = ["group 0", "group 1", "group 2", "group 3"]
    unit = 5.4
    x0 = 24
    wait = 12
    work = {
        0: [(0, 3, "c"), (3, 4, "l"), (16, 19, "c")],
        1: [(4, 7, "c"), (7, 8, "l"), (19, 22, "c")],
        2: [(8, 11, "c"), (11, 12, "l"), (22, 25, "c")],
        3: [(12, 15, "c"), (15, 16, "l")],
    }
    for r, name in enumerate(rows):
        y = 34 - r * 8
        d.text(x0 - 2, y + 2.2, name, size=6.8, ha="right")
        d.line((x0, y + 2.2), (x0 + 25 * unit, y + 2.2), color=C["rule"], lw=0.5)
        for t0, t1, k in work[r]:
            if k == "c":
                d.rect(x0 + t0 * unit, y, (t1 - t0) * unit, 4.4, fill=C["purple"], edge=C["purple"], lw=0.4)
            else:
                d.rect(x0 + t0 * unit, y, (t1 - t0) * unit, 4.4, fill=C["amber"], edge=C["amber"], lw=0.4)
                end = min(t1 + wait, 25)
                d.rect(x0 + t1 * unit, y + 1.4, (end - t1) * unit, 1.6, fill=C["amber_t"], edge=C["amber"],
                       lw=0.3, dashed=True)
    d.box(x0, 1, 22, 5, "computing", kind="purple", size=6.2, weight="normal", radius=0.6)
    d.box(x0 + 25, 1, 22, 5, "issues a load", kind="amber", size=6.2, weight="normal", radius=0.6)
    d.box(x0 + 50, 1, 50, 5, "waiting for memory (hundreds of cycles)", kind="amber_t", size=6.2,
          weight="normal", radius=0.6)
    d.text(x0 + 25 * unit, 42.5, "one compute unit, never idle while some group is ready", size=6.4,
           color=C["muted"], ha="right")
    d.save("h-latency")


def hierarchy():
    d = Diagram(168, 66)
    levels = [
        ("Registers", "per invocation; the fastest storage", "purple", 30),
        ("Shared memory and L1", "per compute unit; tens to a few hundred KiB", "purple_t", 52),
        ("L2 cache", "whole GPU; a few MiB to tens of MiB", "grey", 74),
        ("VRAM or unified memory", "gigabytes; hundreds of GB/s to over 1 TB/s", "coral_t", 98),
        ("System RAM across PCIe", "discrete GPUs only; tens of GB/s", "plain", 122),
    ]
    for i, (name, sub, kind, w) in enumerate(levels):
        y = 54 - i * 12
        x = 84 - w / 2
        d.box(x, y, w, 9.5, name, sub=sub, kind=kind, size=7.4, sub_size=6.0)
    d.arrow((154, 60), (154, 8), color=C["muted"], lw=0.7, mutation=6)
    d.text(157, 34, "larger, slower,\nfarther away", size=6.4, color=C["muted"], ha="left")
    d.save("h-hierarchy")


def roofline():
    fig, ax = plot(h=66)
    bandwidth = 1.0e12
    peak = 40e12
    ai = np.logspace(-2, 3, 400)
    attain = np.minimum(peak, ai * bandwidth)
    ax.loglog(ai, attain / 1e12, color=C["navy"], lw=1.4)
    ridge = peak / bandwidth
    ax.axvline(ridge, color=C["muted"], lw=0.7, ls="--")
    ax.text(ridge * 1.08, 0.025, f"ridge point\n{ridge:.0f} FLOP/byte", fontsize=6.6, color=C["muted"], va="bottom")
    kernels = [("SAXPY", 2 / 12, C["coral"], "left"), ("3 × 3 blur", 9 * 2 / 8, C["amber"], "left"),
               ("N-body, tiled", 320.0, C["purple"], "right")]
    for name, k, col, side in kernels:
        y = min(peak, k * bandwidth) / 1e12
        ax.plot([k], [y], "o", color=col, ms=4.5, zorder=5)
        label = f"{name}\n{k:.2f} FLOP/byte" if k < 10 else f"{name}\n{k:.0f} FLOP/byte"
        x = k * 1.2 if side == "left" else k / 1.2
        ax.text(x, y * 0.62, label, fontsize=6.6, color=col, va="top", ha=side)
    ax.set_xlabel("arithmetic intensity (floating-point operations per byte moved)")
    ax.set_ylabel("attainable TFLOP/s")
    ax.set_xlim(0.01, 1000)
    ax.set_ylim(0.005, 100)
    ax.text(0.012, 60, "illustrative GPU: 1 TB/s memory bandwidth, 40 TFLOP/s peak", fontsize=6.8, color=C["ink"],
            va="top")
    save(fig, "h-roofline")


def drivers():
    d = Diagram(168, 74)
    d.text(41, 70, "OpenGL", size=8.6, weight="bold", color=C["navy"])
    d.text(127, 70, "Vulkan", size=8.6, weight="bold", color=C["coral"])
    d.box(4, 56, 74, 9, "Your program", sub="calls into one current context", kind="navy_t", size=7.6, sub_size=6.2)
    gl = d.box(4, 14, 74, 38, "", kind="navy", lw=0.9)
    d.text(41, 48.5, "The OpenGL driver", size=7.8, weight="bold", color=C["white"])
    for i, s in enumerate(["tracks every object's state and validates every call",
                           "compiles GLSL, sometimes again when state changes",
                           "chooses where memory lives and moves it",
                           "finds hazards and inserts barriers",
                           "decides when to submit, on one thread"]):
        d.text(8, 43 - i * 5.8, s, size=6.4, color=C["white"], ha="left")
    d.box(4, 3, 74, 7, "GPU", kind="grey", size=7.2)
    d.arrow((41, 56), (41, 52.3), color=C["muted"], lw=0.7, mutation=6)
    d.arrow((41, 14), (41, 10.3), color=C["muted"], lw=0.7, mutation=6)

    d.box(90, 37, 74, 28, "", kind="coral_t", lw=0.9)
    d.text(127, 61.5, "Your program", size=7.8, weight="bold", color=C["ink"])
    for i, s_ in enumerate(["creates objects and allocates memory",
                            "compiles SPIR-V into pipelines, ahead of time",
                            "records barriers between dependent work",
                            "records on any thread, submits when it chooses"]):
        d.text(94, 56 - i * 5.0, s_, size=6.4, color=C["ink"], ha="left")
    d.box(110, 28, 34, 6.5, "validation layer", sub="development only", kind="plain", size=6.2, sub_size=5.4,
          dashed=True)
    d.box(90, 15, 74, 8, "The Vulkan driver: a thin translation", kind="coral", size=7.2)
    d.box(90, 3, 74, 7, "GPU", kind="grey", size=7.2)
    d.arrow((127, 37), (127, 34.8), color=C["muted"], lw=0.7, mutation=6)
    d.arrow((127, 28), (127, 23.3), color=C["muted"], lw=0.7, mutation=6)
    d.arrow((127, 15), (127, 10.3), color=C["muted"], lw=0.7, mutation=6)
    d.save("h-drivers")


if __name__ == "__main__":
    for f in (course_map, gpu, simt, latency, hierarchy, roofline, drivers):
        f()
        print("drew", f.__name__)
