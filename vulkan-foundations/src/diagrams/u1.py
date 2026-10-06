from vkfig import C, Diagram


def loader():
    d = Diagram(168, 74)
    app = d.box(44, 62, 80, 9, "Your application", sub="calls vkCreateInstance, vkCmdDispatch, ...", kind="navy", size=8.2)
    ldr = d.box(44, 46, 80, 9, "Vulkan loader", sub="libvulkan, vulkan-1.dll: finds layers and drivers", kind="navy_t")
    val = d.box(44, 30, 80, 9, "VK_LAYER_KHRONOS_validation", sub="optional: checks every call against the specification",
                kind="amber_t", mono=False, dashed=True)
    d.arrow(app.s, ldr.n, shrink=0.5)
    d.arrow(ldr.s, val.n, shrink=0.5)
    drivers = [("NVIDIA", "nvoglv / libnvidia"), ("AMD", "amdvlk / RADV"), ("Intel", "ANV"), ("MoltenVK", "Vulkan on Metal")]
    xs = [4, 46, 88, 130]
    for (name, sub), x in zip(drivers, xs):
        n = d.box(x, 12, 34, 9, name, sub=sub, kind="purple_t" if name != "MoltenVK" else "magenta_t", size=8)
        d.arrow((val.cx, val.y), n.n, shrink=0.5, color=C["muted"], lw=0.8)
        d.box(x + 4, 1, 26, 6.5, "Apple GPU" if name == "MoltenVK" else f"{name} GPU", kind="grey", size=7.2, weight="normal")
        d.arrow(n.s, (x + 17, 7.5), shrink=0.3, color=C["muted"], lw=0.7)
    d.text(126, 36.5, "layers sit between\nthe loader and drivers", size=6.6, color=C["muted"], ha="left")
    d.text(6, 25, "installable client drivers (ICDs)", size=6.8, color=C["muted"], ha="left", weight="semibold")
    d.save("u1-loader")


def objects():
    d = Diagram(168, 96)
    inst = d.box(4, 82, 34, 9, "VkInstance", kind="navy", mono=True, size=7.8)
    phys = d.box(4, 64, 34, 9, "VkPhysicalDevice", kind="navy_t", mono=True, size=7.6)
    dev = d.box(4, 46, 34, 9, "VkDevice", kind="navy", mono=True, size=7.8)
    d.arrow(inst.s, phys.n, shrink=0.4)
    d.arrow(phys.s, dev.n, shrink=0.4)
    d.text(41, 68.5, "enumerated, not created:\none per GPU the driver exposes", size=6.6, color=C["muted"], ha="left")
    d.text(41, 86.5, "the connection to the loader,\nlayers and instance extensions", size=6.6, color=C["muted"], ha="left")

    groups = [
        ("Work", [("VkQueue", "navy_t"), ("VkCommandPool", "amber_t"), ("VkCommandBuffer", "amber_t")], 62),
        ("Memory", [("VkDeviceMemory", "coral_t"), ("VkBuffer", "coral_t"), ("VkImage", "coral_t")], 98),
        ("Programs", [("VkShaderModule", "purple_t"), ("VkPipelineLayout", "purple_t"), ("VkPipeline", "purple_t")], 134),
    ]
    d.line(dev.e, (151, dev.cy), color=C["muted"], lw=0.7)
    for label, items, x in groups:
        g = d.group(x - 2, 4, 34, 42, label, color=C["muted"], size=7.2)
        for i, (name, kind) in enumerate(items):
            d.box(x, 30 - i * 11.5, 30, 8.5, name, kind=kind, mono=True, size=6.9, weight="normal")
        d.arrow((g.cx, dev.cy), (g.cx, g.y + g.h), color=C["muted"], lw=0.7, shrink=0.2)
    d.text(64, 1.2, "submitted to queues", size=6.2, color=C["muted"], ha="left")
    d.text(100, 1.2, "bound together", size=6.2, color=C["muted"], ha="left")
    d.text(136, 1.2, "built from SPIR-V", size=6.2, color=C["muted"], ha="left")
    ds = d.box(4, 20, 34, 8.5, "VkDescriptorSetLayout", kind="green_t", mono=True, size=6.6, weight="normal")
    pool = d.box(4, 8, 34, 8.5, "VkDescriptorPool → Set", kind="green_t", mono=True, size=6.6, weight="normal")
    d.arrow(dev.s, ds.n, color=C["muted"], lw=0.7, shrink=0.3)
    d.text(22.5, 32.5, "resources for shaders", size=6.2, color=C["muted"], ha="left")
    d.save("u1-objects")


def heaps():
    d = Diagram(168, 74)
    d.text(42, 70, "A typical discrete GPU", size=8, weight="bold", color=C["navy"])
    vram = d.group(2, 30, 80, 34, "heap 0: VRAM, DEVICE_LOCAL", color=C["navy"], dashed=False, size=7)
    d.box(5, 46, 74, 7.5, "DEVICE_LOCAL", sub="fastest for the GPU; the CPU cannot map it", kind="navy_t", size=7, sub_size=6.2)
    d.box(5, 33.5, 74, 7.5, "DEVICE_LOCAL | HOST_VISIBLE", sub="resizable BAR window, or 256 MiB without it", kind="amber_t", size=7,
          sub_size=6.2)
    sysram = d.group(2, 3, 80, 25, "heap 1: system RAM", color=C["muted"], dashed=False, size=7)
    d.box(5, 12, 74, 7.5, "HOST_VISIBLE | HOST_COHERENT (| HOST_CACHED)", sub="staging and readback, over PCIe", kind="grey", size=6.8,
          sub_size=6.2)
    d.text(126, 70, "Apple M2 Pro (measured, Chapter 1.2)", size=8, weight="bold", color=C["magenta"])
    d.group(86, 3, 80, 61, "heap 0: 32 GiB unified memory, DEVICE_LOCAL", color=C["magenta"], dashed=False, size=7)
    d.box(89, 44, 74, 7.5, "type 0: DEVICE_LOCAL", kind="magenta_t", size=7)
    d.box(89, 31, 74, 9.5, "type 1: DEVICE_LOCAL | HOST_VISIBLE", sub="| HOST_COHERENT | HOST_CACHED", kind="amber_t", size=7, sub_size=6.6)
    d.box(89, 18, 74, 7.5, "type 2: DEVICE_LOCAL | LAZILY_ALLOCATED", kind="grey", size=7)
    d.text(126, 9, "one pool of memory: the CPU and GPU\nshare it, so staging copies are optional", size=6.6, color=C["muted"])
    _ = (vram, sysram)
    d.save("u1-heaps")


def suballoc():
    d = Diagram(168, 40)
    y, h = 14, 10
    d.text(2, 31, "one VkDeviceMemory allocation (64 MiB), bound to many buffers", size=7.4, weight="semibold", color=C["ink"],
           ha="left")
    segments = [(2, 30, "buffer 0", "coral_t"), (32, 4, "", "pad"), (36, 22, "buffer 1", "coral_t"), (58, 6, "", "pad"),
                (64, 40, "buffer 2", "coral_t"), (104, 62, "free: next offset starts here", "free")]
    for x, w, label, kind in segments:
        if kind == "pad":
            d.rect(x, y, w, h, fill=C["light"], edge=C["muted"], lw=0.5)
        elif kind == "free":
            d.rect(x, y, w, h, fill="none", edge=C["muted"], lw=0.6, dashed=True)
            d.text(x + w / 2, y + h / 2, label, size=6.8, color=C["muted"])
        else:
            d.box(x, y, w, h, label, kind=kind, size=7.2, radius=0.4)
    for x, label in [(2, "0"), (36, "align(r.alignment)"), (64, "align(r.alignment)"), (104, "next_")]:
        d.line((x, y - 1.2), (x, y - 4.2), color=C["ink"], lw=0.6)
        d.text(x, y - 6.2, label, size=6.4, color=C["ink"], mono=True)
    d.text(160, 31, "grey: padding to satisfy alignment", size=6.4, color=C["muted"], ha="right")
    d.save("u1-suballoc")


def timeline():
    d = Diagram(168, 50)
    d.text(10, 40, "host", size=8, weight="bold", ha="right")
    d.text(10, 18, "queue", size=8, weight="bold", ha="right")
    d.line((12, 40), (164, 40), color=C["rule"], lw=1.2)
    d.line((12, 18), (164, 18), color=C["rule"], lw=1.2)
    d.box(14, 36, 30, 8, "record", sub="vkCmd*", kind="amber_t", size=7.2, sub_size=6.2)
    d.box(46, 36, 22, 8, "submit", sub="vkQueueSubmit2", kind="navy", size=7.2, sub_size=5.8)
    d.box(70, 36, 50, 8, "free to do other work", kind="grey", size=7, weight="normal")
    d.box(122, 36, 30, 8, "wait", sub="vkWaitForFences", kind="coral_t", size=7.2, sub_size=6)
    d.box(74, 14, 24, 8, "fill", kind="purple_t", size=7.2)
    d.box(100, 14, 24, 8, "copy", kind="purple_t", size=7.2)
    d.arrow((57, 36), (76, 22.5), color=C["navy"], lw=0.8)
    d.text(52, 27, "commands queued", size=6.4, color=C["navy"], ha="right")
    d.circle(129, 18, 2.2, kind="green", label="")
    d.text(129, 10.5, "fence signalled", size=6.4, color=C["green"])
    d.arrow((131, 20), (137, 35.5), color=C["green"], lw=0.8)
    d.text(99, 5, "the GPU runs the commands later, at its own pace", size=6.4, color=C["muted"])
    d.save("u1-timeline")


def shader_path():
    d = Diagram(168, 42)
    boxes = [
        ("fill.comp", "GLSL source", "grey"),
        ("glslc", "at build time", "amber_t"),
        ("fill.comp.spv", "SPIR-V words", "navy_t"),
        ("VkShaderModule", "vkCreateShaderModule", "navy_t"),
        ("VkPipeline", "driver compiles to its ISA", "purple"),
    ]
    x = 2
    nodes = []
    for label, sub, kind in boxes:
        n = d.box(x, 22, 30, 11, label, sub=sub, kind=kind, size=7.4, sub_size=6.2, mono=label.endswith((".comp", ".spv")))
        nodes.append(n)
        x += 33.5
    for a, b in zip(nodes, nodes[1:]):
        d.arrow(a.e, b.w_, shrink=0.3, lw=0.8)
    lay = d.box(103, 4, 30, 9, "VkPipelineLayout", sub="descriptor sets + push constants", kind="purple_t", size=7, sub_size=5.6)
    spec = d.box(136.5, 4, 30, 9, "specialisation", sub="constants fixed at creation", kind="purple_t", size=7, sub_size=5.8)
    d.arrow(lay.n, (nodes[4].x + 6, nodes[4].y), shrink=0.3, lw=0.7, color=C["purple"])
    d.arrow(spec.n, (nodes[4].x + 22, nodes[4].y), shrink=0.3, lw=0.7, color=C["purple"])
    d.text(35, 14, "offline: portable, validated with spirv-val", size=6.6, color=C["muted"])
    d.save("u1-shader-path")


def descriptors():
    d = Diagram(168, 66)
    d.group(2, 4, 48, 58, "saxpy.comp", color=C["muted"], size=7.4)
    d.box(5, 40, 42, 8, "set 0, binding 0: X", kind="grey", size=6.8, mono=True, weight="normal")
    d.box(5, 29, 42, 8, "set 0, binding 1: Y", kind="grey", size=6.8, mono=True, weight="normal")
    d.box(5, 12, 42, 9, "push_constant: a, n", kind="grey", size=6.8, mono=True, weight="normal")
    sl = d.box(60, 32, 46, 13, "VkDescriptorSetLayout", sub="0: STORAGE_BUFFER, 1: STORAGE_BUFFER", kind="green_t", size=7.2, sub_size=6.0)
    pl = d.box(60, 10, 46, 13, "VkPipelineLayout", sub="set layouts + push constant range", kind="purple_t", size=7.2, sub_size=6.0)
    ds = d.box(118, 40, 46, 11, "VkDescriptorSet", sub="from a VkDescriptorPool", kind="green", size=7.2, sub_size=6.0)
    bx = d.box(118, 22, 21, 9, "VkBuffer x", kind="coral_t", size=6.8, mono=True, weight="normal")
    by = d.box(143, 22, 21, 9, "VkBuffer y", kind="coral_t", size=6.8, mono=True, weight="normal")
    d.arrow((47, 40.5), sl.w_, color=C["muted"], lw=0.7, shrink=0.3)
    d.arrow((47, 16.5), pl.w_, color=C["muted"], lw=0.7, shrink=0.3)
    d.arrow(sl.s, pl.n, color=C["purple"], lw=0.7, shrink=0.3)
    d.arrow(sl.e, ds.w_, color=C["green"], lw=0.8, shrink=0.3, label="allocate", label_dy=2.2, size=6.4)
    d.arrow((ds.x + 10, ds.y), bx.n, color=C["coral"], lw=0.7, shrink=0.3)
    d.arrow((ds.x + 36, ds.y), by.n, color=C["coral"], lw=0.7, shrink=0.3)
    d.text(141, 16, "vkUpdateDescriptorSets writes\nwhich buffers the set points to", size=6.4, color=C["muted"])
    d.text(141, 6.5, "vkCmdBindDescriptorSets", size=6.6, color=C["ink"], mono=True)
    d.save("u1-descriptors")


def dispatch():
    d = Diagram(168, 44)
    n_groups = 6
    w = 25
    for g in range(n_groups):
        x = 6 + g * (w + 1.5)
        last = g == n_groups - 1
        d.rect(x, 18, w, 12, fill=C["navy_t"] if not last else C["amber_t"], edge=C["navy"] if not last else C["amber"], lw=0.7)
        for k in range(8):
            fill = C["navy"] if not last or k < 3 else "none"
            d.rect(x + 1.2 + k * 2.95, 20.5, 2.3, 7, fill=fill, edge=C["navy"], lw=0.3)
        label = f"group {g}" if g < n_groups - 1 else "group 4095"
        if g == n_groups - 2:
            label = "..."
        d.text(x + w / 2, 33, label, size=6.8, color=C["ink"])
        if last:
            d.text(x + w / 2, 36.5, "", size=6)
    d.text(6, 12.5, "vkCmdDispatch(cmd, (n + 255) / 256, 1, 1): one invocation per element, 256 per workgroup", size=7,
           ha="left", mono=True)
    d.text(6, 6, "gl_GlobalInvocationID.x = gl_WorkGroupID.x * 256 + gl_LocalInvocationID.x", size=7, ha="left",
           mono=True, color=C["purple"])
    d.text(162, 40, "invocations past n return early", size=6.6, color=C["amber"], ha="right", weight="semibold")
    d.save("u1-dispatch")


def validation():
    d = Diagram(168, 46)
    app = d.box(2, 26, 30, 12, "application", sub="vkUpdateDescriptorSets", kind="navy", size=7.6, sub_size=5.8)
    val = d.box(44, 26, 40, 12, "validation layer", sub="checks valid-usage rules", kind="amber_t", size=7.6, sub_size=6.2)
    drv = d.box(96, 26, 30, 12, "driver", sub="assumes valid input", kind="purple_t", size=7.6, sub_size=6.2)
    gpu = d.box(136, 26, 30, 12, "GPU", kind="grey", size=7.6)
    d.arrow(app.e, val.w_, shrink=0.3)
    d.arrow(val.e, drv.w_, shrink=0.3)
    d.arrow(drv.e, gpu.w_, shrink=0.3)
    cb = d.box(44, 4, 40, 11, "debug messenger callback", sub="your function, with the VUID", kind="coral_t", size=7.2,
               sub_size=6.0)
    d.arrow(val.s, cb.n, color=C["coral"], lw=0.8, shrink=0.3, label="on a violation", label_dx=10, label_dy=0, size=6.4)
    d.text(130, 9, "without the layer, invalid usage\nis undefined behaviour: a crash,\na hang or wrong results", size=6.4,
           color=C["muted"])
    d.save("u1-validation")


ALL = [loader, objects, heaps, suballoc, timeline, shader_path, descriptors, dispatch, validation]

if __name__ == "__main__":
    for fn in ALL:
        fn()
        print("drew", fn.__name__)
