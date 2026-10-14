from pathlib import Path

from vkfig import C, Diagram

CONSOLE = Path(__file__).resolve().parents[1] / "console"


def pipeline():
    d = Diagram(168, 58)
    stages = [
        ("vertex input", "fixed", "bindings and\nattributes"),
        ("input\nassembly", "fixed", "topology"),
        ("vertex\nshader", "shader", "gl_Position"),
        ("clip, divide,\nviewport", "fixed", "dynamic viewport\nand scissor"),
        ("rasteriser", "fixed", "culling,\nfront face"),
        ("fragment\nshader", "shader", "interpolated\ninputs"),
        ("depth\ntest", "fixed", "compare op,\nwrite enable"),
        ("colour\nblend", "fixed", "blend factors"),
    ]
    w, gap = 18.6, 2.2
    for i, (name, kind, note) in enumerate(stages):
        x = 2 + i * (w + gap)
        box = d.box(x, 30, w, 13, name, kind="purple" if kind == "shader" else "grey", size=6.3,
                    weight="semibold", radius=1.0)
        d.text(x + w / 2, 23.5, note, size=5.6, color=C["muted"])
        if i < len(stages) - 1:
            d.arrow((x + w + 0.2, 36.5), (x + w + gap - 0.2, 36.5), color=C["ink"], lw=0.6, mutation=5)
        _ = box
    d.box(2, 47, 39, 7, "vertex and index buffers", kind="coral_t", size=6.2, weight="normal", radius=0.8)
    d.arrow((21.5, 46.7), (11, 43.3), color=C["coral"], lw=0.6, mutation=5)
    d.box(126, 47, 40, 7, "colour and depth attachments", kind="coral_t", size=6.2, weight="normal", radius=0.8)
    d.arrow((150, 43.3), (150, 46.7), color=C["coral"], lw=0.6, mutation=5)
    d.arrow((134, 43.3), (134, 46.7), color=C["coral"], lw=0.6, mutation=5)
    d.box(2, 4, 30, 6, "programmable stage", kind="purple", size=6, weight="normal", radius=0.8)
    d.box(36, 4, 30, 6, "fixed-function stage", kind="grey", size=6, weight="normal", radius=0.8)
    d.text(70, 7, "The stages' state is fixed when the pipeline is created, except what is declared dynamic.",
           size=6.2, ha="left", color=C["ink"])
    d.save("u4-pipeline")


def spaces():
    d = Diagram(168, 46)
    steps = [
        ("object", "model matrix"), ("world", "view matrix"), ("view", "projection"),
        ("clip", "divide by w"), ("normalised device", "viewport"), ("framebuffer", ""),
    ]
    w, gap = 23, 4.0
    for i, (name, op) in enumerate(steps):
        x = 2 + i * (w + gap)
        d.box(x, 30, w, 9, name, kind="navy_t" if i < 5 else "coral_t", size=6.4, weight="normal", radius=0.8)
        if op:
            d.arrow((x + w + 0.2, 34.5), (x + w + gap - 0.2, 34.5), color=C["ink"], lw=0.6, mutation=5)
            d.text(x + w + gap / 2, 42, op, size=5.8, color=C["muted"])
    ox, oy = 120, 6
    d.rect(ox, oy, 20, 16, fill=C["navy_t"], edge=C["navy"], lw=0.5)
    d.arrow((ox + 10, oy + 8), (ox + 20, oy + 8), color=C["coral"], lw=0.7, mutation=5)
    d.arrow((ox + 10, oy + 8), (ox + 10, oy), color=C["coral"], lw=0.7, mutation=5)
    d.text(ox + 21.5, oy + 8, "+x", size=6, ha="left", color=C["coral"])
    d.text(ox + 10, oy - 2, "+y", size=6, color=C["coral"])
    d.text(ox + 26, oy + 13, "Vulkan: (−1, −1) is the top left;\ndepth runs from 0 at the near\nplane to 1 at the far plane",
           size=5.8, ha="left", color=C["ink"])
    d.text(2, 18, "OpenGL's normalised device coordinates put +y up and depth from −1 to 1, so a projection\n"
                  "matrix written for OpenGL renders upside down in Vulkan and wastes half the depth range.",
           size=6.2, ha="left", color=C["ink"])
    d.save("u4-spaces")


def swapchain():
    d = Diagram(168, 66)
    d.group(116, 6, 50, 56, "presentation engine", color=C["coral"], dashed=False, size=6.8)
    for i in range(3):
        y = 44 - i * 15
        d.box(120, y, 42, 10, f"swapchain image {i}", kind="coral_t", size=6.4, weight="normal", radius=0.8)
    d.text(141, 9, "owns the images; shows them\nin the order they are presented", size=5.8, color=C["muted"])
    steps = [
        (54, "vkAcquireNextImageKHR", "returns an image index; signals\nimage acquired [frame slot]"),
        (36, "record and vkQueueSubmit2", "waits for image acquired at\nCOLOR_ATTACHMENT_OUTPUT; signals\nready to present [image]"),
        (16, "vkQueuePresentKHR", "waits for ready to present [image];\nhands the image back"),
    ]
    for y, call, note in steps:
        d.box(4, y, 46, 9, call, kind="navy_t", size=6.2, weight="normal", mono=True, radius=0.8)
        d.text(54, y + 4.5, note, size=5.8, ha="left", color=C["ink"])
    d.arrow((119.5, 49), (98, 58.5), color=C["muted"], lw=0.6, mutation=5)
    d.arrow((98, 20.5), (119.5, 34), color=C["muted"], lw=0.6, mutation=5)
    d.arrow((27, 53.6), (27, 45.4), color=C["ink"], lw=0.6, mutation=5)
    d.arrow((27, 35.6), (27, 25.4), color=C["ink"], lw=0.6, mutation=5)
    d.text(4, 8, "One acquire semaphore per frame in flight; one ready-to-present semaphore per image.", size=6.2,
           ha="left", color=C["ink"])
    d.text(4, 3.5, "Only acquiring an image again proves that its last presentation no longer uses its semaphore.",
           size=6.0, ha="left", color=C["muted"])
    d.save("u4-swapchain")


def mips():
    d = Diagram(168, 48)
    x = 4
    size = 24.0
    labels = ["256", "128", "64", "32", "...", "1"]
    for i, lab in enumerate(labels):
        if lab == "...":
            d.text(x + 3, 16, "...", size=8, color=C["muted"])
            x += 10
            continue
        s_ = size / (2 ** i) if lab != "1" else 1.6
        s_ = max(s_, 1.6)
        d.rect(x, 6, s_, s_, fill=C["navy_t"] if i == 0 else C["purple_t"],
               edge=C["navy"] if i == 0 else C["purple"], lw=0.6)
        d.text(x + s_ / 2, 3, f"level {i if lab != '1' else 8}: {lab}²", size=5.6, color=C["ink"])
        if i < len(labels) - 1 and labels[i + 1] != "...":
            d.arrow((x + s_ + 0.5, 6 + s_ / 2), (x + s_ + 8.5, 6 + s_ / 4), color=C["coral"], lw=0.6, mutation=5)
            d.text(x + s_ + 4.5, 6 + s_ / 2 + 3, "blit", size=5.6, color=C["coral"])
        x += s_ + 12
    d.text(4, 45, "Level 0 arrives by copy; each later level is a linear blit of the one above.", size=6.4, ha="left",
           color=C["ink"])
    d.text(4, 40.5, "Before each blit, the level above moves from TRANSFER_DST_OPTIMAL to TRANSFER_SRC_OPTIMAL;",
           size=6.2, ha="left", color=C["muted"])
    d.text(4, 36.5, "after the last, every level moves to SHADER_READ_ONLY_OPTIMAL for sampling.", size=6.2,
           ha="left", color=C["muted"])
    d.save("u4-mips")


def frame_passes():
    d = Diagram(168, 64)
    passes = [
        ("simulate", "compute", "particles"),
        ("cull", "compute", "visible list,\ndraw command"),
        ("draw", "graphics", "HDR image"),
        ("post-process", "compute", "display image"),
        ("blit or copy", "transfer", "swapchain or\nreadback"),
    ]
    w, gap = 25, 9.0
    for i, (name, kind, writes) in enumerate(passes):
        x = 2 + i * (w + gap)
        colour = {"compute": "coral_t", "graphics": "purple_t", "transfer": "navy_t"}[kind]
        d.box(x, 38, w, 12, name, sub=kind, kind=colour, size=7, sub_size=5.8)
        d.text(x + w / 2, 31, "writes " + writes, size=5.8, color=C["ink"])
        if i < len(passes) - 1:
            d.line((x + w + gap / 2, 22), (x + w + gap / 2, 58), color=C["amber"], lw=1.4)
            d.arrow((x + w + 0.3, 44), (x + w + gap - 0.3, 44), color=C["ink"], lw=0.6, mutation=5)
    notes = [
        "COMPUTE write →\nVERTEX_ATTRIBUTE_INPUT",
        "COMPUTE write →\nDRAW_INDIRECT and\nVERTEX_SHADER reads",
        "COLOR_ATTACHMENT write →\nCOMPUTE read; layout\nto GENERAL",
        "COMPUTE write →\nBLIT or COPY read",
    ]
    for i, note in enumerate(notes):
        x = 2 + i * (w + gap) + w + gap / 2
        d.text(x, 14, note, size=5.4, color=C["amber"])
    d.text(84, 2.5, "The four barriers between passes, all on one queue; the next frame's simulation also waits for "
                    "this frame's vertex reads.", size=6.0, color=C["muted"])
    d.save("u4-frame-passes")


def sandbox_frame():
    d = Diagram(168, 50)
    d.text(2, 47, "Two frames of the sandbox on two queues (not to scale)", size=7, weight="bold",
           ha="left", color=C["navy"])
    x0 = 30
    main_y, comp_y = 22, 8
    d.text(x0 - 2, main_y + 3, "main queue", size=6.2, ha="right", color=C["muted"])
    d.text(x0 - 2, comp_y + 3, "compute queue", size=6.2, ha="right", color=C["muted"])
    for y in (main_y, comp_y):
        d.line((x0, y - 0.8), (166, y - 0.8), color=C["rule"], lw=0.4)
    frame_w = 66
    for f, label in enumerate(("frame n", "frame n + 1")):
        x = x0 + f * frame_w
        d.text(x + 1, 38.5, label, size=6.4, weight="bold", ha="left", color=C["ink"])
        d.line((x, 36), (x, 4), color=C["rule"], lw=0.4, dashed=True)
        d.box(x + 0.5, main_y, 15, 6, "update, cull", kind="navy_t", size=5.6, weight="normal",
              radius=0.5)
        d.box(x + 16, main_y, 11, 6, "draw cubes", kind="navy_t", size=5.6, weight="normal",
              radius=0.5)
        d.box(x + 27.5, main_y, 29, 6, "draw particles", kind="coral_t", size=5.6,
              weight="normal", radius=0.5)
        d.box(x + 57, main_y, 8.5, 6, "post", kind="navy_t", size=5.6, weight="normal",
              radius=0.5)
    d.box(x0 + 0.5, comp_y, 18, 6, "simulate n", kind="purple_t", size=5.6, weight="normal",
          radius=0.5)
    d.box(x0 + 27.5, comp_y, 18, 6, "simulate n + 1", kind="purple_t", size=5.6,
          weight="normal", radius=0.5)
    d.arrow((x0 + 18.5, comp_y + 6), (x0 + 27.5, main_y), color=C["purple"], lw=0.6,
            mutation=4.5)
    d.text(x0 + 47, comp_y + 3, "runs beside frame n's particles: it writes another copy",
           size=5.6, ha="left", color=C["muted"])
    d.text(x0 + 31, 16.6, "semaphore, at vertex input", size=5.4, ha="left", color=C["purple"])
    d.text(x0, 1.4, "Each frame slot owns a copy of the particle state: simulate n reads copy "
                    "n − 1 and writes copy n, which frame n's draw reads.", size=5.6, ha="left",
           color=C["muted"])
    d.save("u4-sandbox-frame")


if __name__ == "__main__":
    for f in (pipeline, spaces, swapchain, mips, frame_passes, sandbox_frame):
        f()
        print("drew", f.__name__)
