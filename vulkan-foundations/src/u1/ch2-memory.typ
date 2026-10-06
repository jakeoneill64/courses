#import "../lib/template.typ": *

= Memory, buffers and images <ch-memory>

#chapter-meta(
  time: [6 hours],
  builds: [A memory-map printer, a round trip through mapped memory with the flush that non-coherent memory needs, a linear sub-allocator that places a thousand buffers in one allocation, and a survey of image formats and their memory.],
  needs: [Chapter 1.1.],
)

#why[
  In OpenGL you asked for a buffer or a texture and the driver decided where it lived, when it moved, and how the CPU's writes reached the GPU. Vulkan hands every one of those decisions to you. The GPU's memory is described as a small set of heaps and types, resources are created without memory and bound to it afterwards, and the CPU's writes reach the GPU only under rules you must follow. Choosing well is the difference between an upload that runs at the bus's full speed and one that crawls, and between a program that runs on every driver and one that fails when it makes its four-thousandth allocation.
]

#skip-test(
  rule: [If you can answer all five, skim the core ideas and do Labs 1.2.2 and 1.2.3.],
  [What is the difference between a memory heap and a memory type? Which property flag tells you that the CPU can map memory, and which tells you that it need not flush?],
  [A buffer's memory requirements are size 1000, alignment 256 and `memoryTypeBits` `0b0110`. Which memory types may back it, and at which offsets in an allocation may it be bound?],
  [Why do Vulkan programs allocate a few large blocks of device memory and place many resources in each?],
  [What does an image's tiling decide, and why can you not map an optimally tiled image and write its pixels?],
  [When must a program call `vkFlushMappedMemoryRanges`, and when `vkInvalidateMappedMemoryRanges`?],
)

== Core ideas

=== Where memory lives

A discrete GPU has its own memory, VRAM, on the graphics card, and reaches the system's RAM across the PCI Express bus. The GPU reads its VRAM at hundreds of gigabytes per second and system RAM at a few tens at best. An integrated GPU, including Apple's, shares one pool of memory with the CPU. Vulkan describes both arrangements in the same terms.

A _memory heap_ is a physical pool of memory with a size and, if the device reads it fast, the flag `VK_MEMORY_HEAP_DEVICE_LOCAL_BIT`. A _memory type_ is a way of using one heap, described by property flags:

- `VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT`: the device reads and writes this memory at full speed.
- `VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT`: the CPU can map it into its address space with `vkMapMemory`.
- `VK_MEMORY_PROPERTY_HOST_COHERENT_BIT`: the CPU's writes and the device's writes reach each other without explicit flush and invalidate calls (see below).
- `VK_MEMORY_PROPERTY_HOST_CACHED_BIT`: the CPU caches this memory. Reads by the CPU are fast; without this flag the CPU reads mapped memory uncached, which is many times slower.
- `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT`: the device may never back this memory with real storage. Tile-based GPUs, Apple's among them, use it for render targets that live only in on-chip memory (Unit 4).

@fig-heaps compares a typical discrete GPU with the Apple M2 Pro used to write this course. The discrete GPU offers memory the CPU cannot touch, memory in system RAM that both can use, and often a type that is both device-local and host-visible: the whole of VRAM when the system enables resizable BAR, or a 256 MiB window when it does not. The M2 Pro has one heap and a type that has every property at once.

#fig("u1-heaps", caption: [Heaps and memory types on a typical discrete GPU and on the Apple M2 Pro. Each type is a way of using a heap; the flags tell you who can reach the memory and how fast.]) <fig-heaps>

A program reads the layout with `vkGetPhysicalDeviceMemoryProperties`. The memory-map printer of Lab 1.2.1 prints both arrays:

#snippet("u1/memory/main.cpp", "print-memory", caption: [Printing the heaps and memory types])

#console(read("/src/console/u1-memory.txt"), caption: [`u1_memory` on an Apple M2 Pro: one heap, three types, and the results of the chapter's experiments])

#opengl[
  `glBufferData` allocates storage, and the driver chooses where it lives from a usage hint such as `GL_STATIC_DRAW` or `GL_STREAM_DRAW`. It may move the storage later if your usage turns out to differ from the hint. OpenGL 4.4's `glBufferStorage` with `GL_MAP_PERSISTENT_BIT` and `GL_MAP_COHERENT_BIT` is the closest relative of a persistently mapped `HOST_VISIBLE | HOST_COHERENT` allocation in Vulkan. In Vulkan nothing moves: memory stays in the type you chose.
]

=== Buffers and their memory requirements

A _buffer_ is a range of bytes that commands and shaders can use. Creating one with `vkCreateBuffer` allocates no memory. The create-info states the size and the _usage flags_: how the buffer will be used, such as `VK_BUFFER_USAGE_STORAGE_BUFFER_BIT` for shader reads and writes, `VK_BUFFER_USAGE_TRANSFER_SRC_BIT` and `VK_BUFFER_USAGE_TRANSFER_DST_BIT` for copies, or `VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT` for indirect commands. Using a buffer in a way its usage flags do not include is invalid, and the driver may choose a layout or a memory type based on them. The sharing mode decides whether one queue family owns the buffer at a time (`VK_SHARING_MODE_EXCLUSIVE`, the default and the faster choice) or several may use it at once (`VK_SHARING_MODE_CONCURRENT`); Chapter 3.5 explains the difference.

`vkGetBufferMemoryRequirements` then reports what the buffer needs from memory: a size, which may be larger than the size you asked for; an alignment, which the offset you bind it at must be a multiple of; and `memoryTypeBits`, a bit mask in which bit _i_ is set when memory type _i_ may back the buffer. A program picks the first type that is both allowed and has the properties it wants:

#snippet("u1/shared/basics.hpp", "find-memory-type", caption: [Choosing a memory type: allowed by the resource and with every required property])

The specification constrains the order of the memory types: a type whose flags are a strict subset of another's comes first, and of two types with the same flags, the one on the faster heap comes first. Taking the first suitable type therefore takes the one with the fewest extra properties, which is usually the cheapest that does the job.

Unit 1's `createBuffer` performs every step for one buffer: create, query requirements, allocate, bind and, for host-visible memory, map.

#snippet("u1/shared/basics.hpp", "create-buffer", caption: [A buffer with its own allocation])

=== Allocations are expensive and limited

`createBuffer` is fine for a handful of buffers and wrong for a real program. `vkAllocateMemory` asks the operating system's kernel driver for memory; it can take a millisecond or more, and the number of live allocations is limited by `maxMemoryAllocationCount`. The specification only guarantees 4096, and several desktop drivers report exactly that; Apple's reports more than a billion. Allocations are also made in coarse units, often 4 or 64 KiB, so a small buffer in its own allocation wastes most of it.

The answer is _sub-allocation_: allocate a few large blocks, typically 64 to 256 MiB each, and bind many resources at different offsets within them (@fig-suballoc). `vkBindBufferMemory` takes the offset as an argument, and the only rules are the ones the memory requirements state: the type must be allowed, the offset must be a multiple of the alignment, and the resource must fit.

#fig("u1-suballoc", caption: [A linear sub-allocator. Each buffer is placed at the next offset rounded up to its alignment; the grey gaps are the padding that alignment costs.]) <fig-suballoc>

The simplest sub-allocator only moves forward. It cannot free a single buffer, only the whole block, which suits resources that live and die together, such as everything a frame or a level needs.

#snippet("u1/memory/main.cpp", "linear-allocator", caption: [A linear sub-allocator: one allocation, many buffers])

The memory experiment above places a thousand buffers of random sizes between 256 bytes and 64 KiB in one 64 MiB allocation and checks that none overlaps the next. Rounding and alignment cost about 0.1 MiB of the 31.5 MiB used.

#hazard(title: [Pitfall])[
  When a block holds both buffers and optimally tiled images, a further limit applies: `bufferImageGranularity`. A linear resource (a buffer, or a linear image) and an optimal image that share a page of that size may interfere with each other on some hardware. Allocators either keep the two kinds in separate blocks or round their offsets apart. The linear allocator above places only buffers, so the limit does not arise.
]

Production allocators also free individual resources, keep separate blocks per memory type, give very large resources an allocation of their own, and report statistics. Writing one well is a project in itself; most programs use AMD's open-source Vulkan Memory Allocator, which Chapter 4.6 discusses.

#keyidea[
  Creating a resource and giving it memory are separate steps. That separation lets one allocation serve thousands of resources, and lets two resources that are never used at the same time share memory. Every allocator is built on it.
]

=== Mapping and coherence

`vkMapMemory` returns a CPU pointer into a host-visible allocation. The usual practice is to map once, keep the pointer for the allocation's lifetime and write through it whenever needed; Unit 1's `createBuffer` does exactly that. An allocation can only be mapped once at a time, which is one more reason to share mapped blocks between resources.

The CPU's caches sit between your writes and the memory. With `HOST_COHERENT` memory the hardware keeps the two in step: once your writes are complete, the device can see them. Without it, your writes may still be in a CPU cache, and you must _flush_ the range you wrote with `vkFlushMappedMemoryRanges` before the device reads it. In the other direction, after the device writes non-coherent memory, you must _invalidate_ the range with `vkInvalidateMappedMemoryRanges` before reading it, or the CPU may read stale cached values. Ranges passed to either call must be aligned to the device's `nonCoherentAtomSize`, or cover the whole allocation.

#snippet("u1/memory/main.cpp", "flush", caption: [Flushing host writes when, and only when, the memory is not coherent])

The round trip below asks only for `HOST_VISIBLE` memory, so it may receive a non-coherent type on some devices and must handle both. On the M2 Pro it receives type 1, which is coherent.

#snippet("u1/memory/main.cpp", "mapped", caption: [Writing through a persistent mapping])

Coherence makes writes reach memory; it does not make them safe to use at any moment. The device must not read data the CPU is still writing, and the CPU must not read results the device has not finished. Two rules handle this, and both appear again in Chapter 1.3 and Unit 3. Host writes made before `vkQueueSubmit`, and flushed if the memory is not coherent, are visible to the commands of that submission. Device writes become available to the host only after a barrier to the host and a wait for the work to finish.

#hazard(title: [Pitfall])[
  Memory without `HOST_CACHED` is often _write-combined_: the CPU gathers writes and sends them in bursts, which is fast, but every read goes all the way to memory, which is very slow. Writing into such memory with `memcpy` is fine. Reading from it, or updating it with `+=`, can be ten or a hundred times slower than ordinary memory. Prefer `HOST_CACHED` types for buffers the CPU reads back.
]

=== Images

An _image_ is an array of _texels_ with a format, an extent in up to three dimensions, a number of mip levels and array layers, a sample count, a tiling and usage flags. Images exist because GPUs have hardware for them: texture units that filter and convert formats on the fly, compression, and render targets.

#snippet("u1/memory/main.cpp", "image", caption: [A 1024 × 1024 RGBA image for shader writes and copies, and its memory requirements])

The _format_ names the components, their sizes and how to interpret them. `VK_FORMAT_R8G8B8A8_UNORM` has four 8-bit components read as numbers from 0 to 1; `_SRGB` applies the sRGB curve on reads and writes; `_SFLOAT`, `_UINT` and `_SINT` store floating-point, unsigned and signed integer values. Support varies by format, by tiling and by use, and `vkGetPhysicalDeviceFormatProperties` reports it:

#snippet("u1/memory/main.cpp", "format-support", caption: [Which formats can be storage images, be sampled, or be rendered to])

The output shows that the M2 Pro can write `VK_FORMAT_R8G8B8A8_SRGB` from a shader. Many desktop drivers cannot, which is why portable compute code writes `UNORM` and converts to sRGB itself, or writes through a `UNORM` view of an sRGB image created with `VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT` and `VK_IMAGE_CREATE_EXTENDED_USAGE_BIT`.

The _tiling_ decides how texels are arranged in memory. `VK_IMAGE_TILING_LINEAR` stores rows one after another, so the CPU can map and address them, but devices support linear images only for a few formats and uses. `VK_IMAGE_TILING_OPTIMAL` uses whatever arrangement suits the hardware, typically tiles or curves that keep neighbouring texels close in memory, and the arrangement is not documented. Optimal images therefore receive their data through copy commands from buffers, which know how to translate. On the M2 Pro the optimal 1024 × 1024 image needs exactly its 4 MiB of pixels; on other hardware expect padding, and alignments as large as 64 KiB.

Shaders and render passes do not use an image directly but through an _image view_, which selects a range of mip levels and layers and can reinterpret the format. Unit 2 creates views for compute and Unit 4 for rendering.

Finally, every image is always in a _layout_: an arrangement of its data suited to a particular kind of access, such as `VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL` for copies into it, `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL` for sampling, or `VK_IMAGE_LAYOUT_GENERAL`, which allows any access at a possible cost in speed. An image starts in `VK_IMAGE_LAYOUT_UNDEFINED`, which means its contents may be discarded, and moves between layouts through _layout transitions_ that you record in barriers. Chapter 3.2 explains transitions as part of the dependency model; Chapter 2.4 uses them.

#opengl[
  `glTexStorage2D` allocates a texture and the driver chooses its tiling and layout; `glTexSubImage2D` uploads pixels through a staging copy the driver makes for you. Formats such as `GL_RGBA8` are converted to the GPU's native arrangement behind the scenes, and layout changes never appear in your code. Vulkan makes each of those steps explicit: the staging buffer, the copy, the layout and its transitions.
]

=== Staging

Memory the CPU cannot map receives its data in two steps. The program writes into a host-visible _staging buffer_, then records a copy from the staging buffer into the device-local buffer or image, with `vkCmdCopyBuffer` or `vkCmdCopyBufferToImage`. Recording and submitting a copy is the subject of Chapter 1.3, which also measures staging against writing directly into memory that is both device-local and host-visible. On a discrete GPU, staging is the normal path for data the GPU reads repeatedly. On unified memory, and on discrete GPUs with resizable BAR, writing directly is an alternative, and Lab 1.3.3 measures which is faster on your machine.

#reading(
  [The Vulkan specification, chapters "Memory Allocation" (in particular "Device Memory" and "Host Access to Device Memory Objects") and "Resource Creation" (buffers, images, image layouts and "Resource Memory Association"), at #link("https://docs.vulkan.org/spec/latest/index.html")[docs.vulkan.org/spec].],
  [The Vulkan Guide, "Memory Allocation" and "Formats".],
  [The Vulkan Memory Allocator documentation (AMD GPUOpen), the pages "Choosing memory type" and "Recommended usage patterns", which describe how memory types differ across real hardware.],
)

== Labs

#lab([Map your machine's memory], goal: [Read your device's heaps and types and decide what each is for.], time: [45 minutes], code: "code/u1/memory")[
  + Run `build/bin/u1_memory` and save the output.
  + Draw your device's heaps and memory types in the style of @fig-heaps.
  + For each of these, choose a memory type and justify it from the flags: a large buffer the GPU reads every frame and the CPU never touches; a staging buffer for uploads; a buffer the CPU reads results from.
  #done-when(
    [Your drawing accounts for every heap and type in the output.],
    [Each choice names a type index and the flags that justify it, or explains why your device offers no better choice.],
  )
  #evidence([The output, the drawing, the three choices with reasons.])
]

#lab([Round trips and coherence], goal: [Handle coherent and non-coherent memory correctly, and let validation check your ranges.], time: [1.5 hours], code: "code/u1/memory")[
  + Change the round trip to request `HOST_VISIBLE | HOST_CACHED` and note the type it receives and whether it flushed.
  + Write `invalidateBeforeRead`, the mirror image of `flushHostWrites`, with `vkInvalidateMappedMemoryRanges`.
  + Write a version of each that takes an offset and size inside the allocation and rounds them to `nonCoherentAtomSize`. Call it for bytes 100 to 299 of the buffer, with and without the rounding, and run with validation on. The rules on the range apply whether or not the memory is coherent, so the layer checks them on every device.
  + If your device has a host-visible type without `HOST_COHERENT`, force the round-trip buffer into it and confirm that the flush runs.
  #done-when(
    [Without rounding, validation reports the misaligned range; with rounding it is silent.],
    [The program prints which memory type each buffer received and whether a flush or invalidate ran.],
  )
  #evidence([The validation message for the misaligned range, and your rounding code.])
]

#lab([A thousand buffers in one allocation], goal: [Measure what sub-allocation saves.], time: [1.5 hours], code: "code/u1/memory")[
  + Run the program and confirm that the thousand buffers do not overlap.
  + Add a variant that gives each of the thousand buffers its own `vkAllocateMemory`, and time both versions of the loop with `std::chrono::steady_clock`, excluding buffer creation.
  + Print `maxMemoryAllocationCount` and `bufferImageGranularity` for your device.
  + Add a `reset()` to `LinearAllocator` that makes the whole block free again, and test that a full block throws and a reset block accepts buffers.
  #done-when(
    [You have the time per buffer for both strategies on your device.],
    [You can say how many separately allocated buffers your device's driver would allow.],
    [The overflow and reset tests pass with no validation errors.],
  )
  #evidence([The timings and limits, and the test output.])
]

#lab([Survey formats and image memory], goal: [Learn what your device supports before you rely on it.], time: [1 hour], code: "code/u1/memory")[
  + Add `VK_FORMAT_R8_UNORM`, `VK_FORMAT_B8G8R8A8_UNORM`, `VK_FORMAT_R32G32B32A32_SFLOAT` and `VK_FORMAT_D32_SFLOAT` to the format survey, and print the linear-tiling features beside the optimal ones.
  + Print the memory requirements of optimal images of 1000 × 1000 and 1024 × 1024 texels, and of a linear 1024 × 1024 image. For the linear one, also print `vkGetImageSubresourceLayout`'s `rowPitch`.
  #done-when(
    [Your table covers eight formats and both tilings.],
    [You can name one format your device can sample but not write from a shader, or explain why it has none.],
    [You can explain any difference between the row pitch and 1024 × 4 bytes.],
  )
  #evidence([The table and the image sizes, with one sentence on each surprise.])
]

#problems(
  [A device has heap 0 (8 GiB, device-local) with types `DEVICE_LOCAL` and `DEVICE_LOCAL | HOST_VISIBLE | HOST_COHERENT`, and heap 1 (32 GiB) with types `HOST_VISIBLE | HOST_COHERENT` and `HOST_VISIBLE | HOST_CACHED`. Choose a type for each of: a 2 GiB mesh uploaded once, a 64 KiB block of parameters rewritten every frame, and a 16 MiB buffer of results read by the CPU every frame. Justify each choice.],
  [A buffer's requirements are size 1000, alignment 256 and `memoryTypeBits` `0b101`. A linear allocator's next free offset is 4100 in a block of memory type 2. At what offset is the buffer bound, and how much padding does that cost? What happens if the block's memory type is 1?],
  [Why is the number of allocations limited, and why does a sub-allocator not suffer from the limit?],
  [Explain why writing pixels through a mapped pointer works for a linear image but not for an optimal one. What does `vkCmdCopyBufferToImage` do that the CPU cannot?],
  [`nonCoherentAtomSize` is 64. You wrote bytes 100 to 299 of a 4096-byte non-coherent allocation. Which range do you flush, and why may flushing more than you wrote be harmless here but wrong in general?],
)

#checklist(
  [I can read a device's heaps and memory types and choose a type for a given use.],
  [I can create a buffer and an image, query their requirements, and bind them at valid offsets.],
  [I can explain coherence, and flush and invalidate correctly aligned ranges.],
  [I can explain tiling, formats and layouts, and query format support.],
  [Lab 1.2.1–1.2.4 done-when criteria all hold, with evidence filed.],
)
