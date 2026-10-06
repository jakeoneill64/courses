#import "../lib/template.typ": *

= Scaling up <ch-scaling>

#chapter-meta(
  time: [6 hours],
  builds: [A program that records 100,000 draws on up to eight threads into secondary command buffers and checks every pixel of the result against a CPU painting; that measures pipeline creation with and without a pipeline cache, saved to disk and validated before reuse; and that reads the memory budget before and after a large allocation.],
  needs: [Chapters 4.1 to 4.5, and Chapter 1.2's sub-allocator.],
)

#why[
  A renderer that works for one scene must keep working for a city. Costs that do not matter in a small program become the limits of a large one: recording every command on one thread, compiling a pipeline at the moment it is first needed, allocating memory one object at a time, rebuilding descriptor sets each frame. Vulkan's design anticipates each of these, but only the program can use what it offers. This chapter measures recording and pipeline creation on the course's machine, reads the memory budget, and surveys the strategies large renderers use for memory, descriptors and profiling.
]

#skip-test(
  rule: [If all four are easy, read the sections on pipeline caches and on profiling, and do Labs 4.6.2 and 4.6.4.],
  [Two threads record into command buffers allocated from the same pool. What is wrong?],
  [What must a secondary command buffer know about the rendering it will run inside, and how is that expressed with dynamic rendering?],
  [What does a pipeline cache store, and how does a program know that a cache file read from disk can be used?],
  [Why should a program not allocate one block of device memory per buffer?],
)

== Core ideas

=== Recording on many threads

A frame with many draws can take milliseconds to record. Vulkan lets several threads record at once, with one rule: a command pool, and every command buffer allocated from it, may be used by only one thread at a time. The specification calls such objects _externally synchronised_, and it is the program's job to keep them so. Each recording thread therefore has a pool of its own:

#snippet("u4/scaling/main.cpp", "worker", caption: [A pool and a secondary command buffer per thread])

The threads' work can be combined in two ways. Each thread can record a primary command buffer of its own, and the frame submits them in order. Or each thread can record a _secondary_ command buffer, and one primary executes them all with `vkCmdExecuteCommands`. Secondaries are the usual way to split one rendering pass across threads. A secondary that runs inside dynamic rendering must declare the formats of the attachments it draws into, through `VkCommandBufferInheritanceRenderingInfo`, and begin with `VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT`:

#snippet("u4/scaling/main.cpp", "record-secondary", caption: [Recording a share of the draws into a secondary command buffer])

The primary begins rendering with `VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT`, which says that the pass's commands come from secondaries, and executes them in the order given:

#snippet("u4/scaling/main.cpp", "execute-secondaries", caption: [One primary that executes every thread's secondary])

The threads are started first and wait on a latch, so that the measurement covers recording alone:

#snippet("u4/scaling/main.cpp", "record-in-parallel", caption: [Recording in parallel])

Each draw is an 8 × 8 rectangle whose corners the vertex shader makes from `gl_VertexIndex` and a push-constant block, so the draws need no vertex buffer. The rectangles cover whole pixels and their colours are exact in 8 bits, so the CPU can paint the expected image exactly, overlaps included. A secondary executed out of order would paint some overlaps the wrong way round, and every frame's image is compared with the painting.

#snippet("u4/scaling/rect.vert", "rect", caption: [A rectangle from six vertex indices])

#console(read("/src/console/u4-scaling-timing.txt"), caption: [100,000 draws on up to eight threads, and pipeline creation, with validation off])

Recording 100,000 draws takes 3.5 ms on one thread and 0.8 ms on eight, four and a half times faster, although two threads are no faster than one here, a result Lab 4.6.1 asks you to look into on your own machine. Submission takes about 11.5 ms however many threads recorded. As Chapter 4.5 found, MoltenVK encodes the Metal commands when a command buffer is submitted, on one thread, so on this machine multithreaded recording speeds up the cheaper part of the work. A driver that does its work while commands are recorded gains far more from the same change.

#hazard(title: [Pitfall])[
  Measure multithreaded recording with validation off. The validation layer protects its own state with locks, so threads queue for them: with validation on, recording 20,000 draws takes 20.5 ms on one thread and 154 ms on eight. The layer's thread-safety checks remain worth running during development, because they report two threads caught using one pool at the same time.
]

=== Pipeline caches

Creating a pipeline compiles its shaders for the GPU, together with every piece of state that affects the generated code. Each pipeline takes milliseconds, and a renderer with thousands of them cannot afford to compile one at the moment it first needs it. A `VkPipelineCache` lets the driver keep the results of compilation and reuse them when an identical pipeline is created again. The program creates pipelines that differ only in their specialisation constants:

#snippet("u4/scaling/main.cpp", "create-variants", caption: [Pipelines that differ only in two specialisation constants])

#snippet("u4/scaling/main.cpp", "cache-modes", caption: [Without a cache, with an empty cache, and with the same cache again])

A cache's contents can be saved with `vkGetPipelineCacheData` and passed back as initial data in a later run. They are useful only to the same driver on the same device, and a header says which made them: `VkPipelineCacheHeaderVersionOne` holds the vendor, the device and a `pipelineCacheUUID` that changes whenever compiled code would. Drivers ignore data that does not match, but checking first lets the program delete a stale file instead of carrying it forever:

#snippet("u4/scaling/main.cpp", "cache-file", caption: [Creating, checking and saving a pipeline cache])

On the M2 Pro, 32 new pipelines take 170 to 215 ms to create, 5 to 7 ms each, with or without an empty cache. Created again from the same cache, they take 2.6 ms. A cache loaded from disk does not help with pipelines it has never seen.

What a cache holds depends on the driver. MoltenVK's is 4,465 bytes however many pipelines it has seen: it keeps the translation of SPIR-V into Metal's shading language, while Metal keeps compiled code in a system-wide cache of its own. That system cache makes a second run fast even without a pipeline cache, which is why `--fresh` salts the specialisation constants: without it, a measurement of "cold" creation is warm. Desktop drivers keep similar caches on disk, so every measurement of cold creation must make sure that nothing has compiled those pipelines before.

Large renderers combine a cache with other strategies. They create pipelines on background threads before they are needed; `VK_EXT_graphics_pipeline_library` links pipelines from separately compiled parts; and `VK_EXT_shader_object` replaces pipelines with shaders whose state is set at draw time, as OpenGL's was.

=== Memory at scale

Chapter 1.2 gave the reasons to sub-allocate: allocations are slow, their number is limited, and they come in coarse units. A large renderer adds two concerns. Its resources are created and destroyed constantly, so its allocator must free and reuse space without fragmenting its blocks; and the memory it may use is shared with other programs, so it must know how much it may take.

The Vulkan Memory Allocator, AMD's open-source library, is the usual answer to the first. It sub-allocates with several strategies, honours `bufferImageGranularity` and alignment, gives a resource memory of its own when the driver prefers that through `VkMemoryDedicatedRequirements`, and can defragment. The course writes its own allocators to show what such a library does; most programs should use one.

The second is answered by `VK_EXT_memory_budget`, which reports for each heap a _budget_, how much this process can use without problems, and how much it is using. Both change while the program runs, as other programs allocate and free.

#snippet("u4/scaling/main.cpp", "memory-budget", caption: [Reading the budget of every heap])

On the M2 Pro, the single heap of 32 GiB of unified memory offers a budget of 25 GiB, and allocating 256 MiB raises the usage by 0.25 GiB. A program near its budget should release caches or lower its resolution; past it, allocations may fail with `VK_ERROR_OUT_OF_DEVICE_MEMORY`, or succeed and be paged out. `VK_EXT_memory_priority` lets a program say which allocations matter most when the driver must choose.

=== Descriptors at scale

Descriptor strategies follow from how often resources change. @tbl-descriptor-strategies lists the common ones; most renderers combine several.

#figure(
  tbl(columns: (auto, 1fr), header: ([Strategy], [When it fits]), size: 8.2pt,
    [Sets by frequency of change], [Set 0 for the frame, set 1 for the material, set 2 for the object, each bound only when it changes (Chapter 4.3)],
    [Push constants], [Small values that change with every draw, such as a matrix or an index (Chapters 4.1 and 4.5)],
    [Bindless arrays], [Every texture in one large array, indexed in the shader, with descriptor indexing (Chapter 4.3)],
    [Buffer device addresses], [Buffers reached by address, with no buffer descriptors at all (Chapter 2.6)],
    [Pools reset per frame], [Sets allocated afresh each frame, freed together by `vkResetDescriptorPool`],
    [`VK_EXT_descriptor_buffer`], [Descriptors written into buffers the program manages, without pools or sets],
  ),
  caption: [Descriptor strategies],
  kind: table,
) <tbl-descriptor-strategies>

=== Profiling a frame

Optimising a frame starts with finding its limit. If the GPU idles between frames, the CPU is the limit, and the place to look is recording, submission and waiting, each timed on the CPU as the programs of Chapters 4.5 and 4.6 do. If the CPU waits for the GPU, timestamps around each pass, as in Chapter 4.4, show where the GPU's time goes. Pipeline statistics queries count the invocations of each shader stage, where the feature `pipelineStatisticsQuery` exists; MoltenVK lacks it.

Below that level, vendors' tools read the hardware's counters: NVIDIA Nsight Graphics, AMD's Radeon GPU Profiler, Arm Performance Studio and Qualcomm's Snapdragon Profiler. RenderDoc captures a frame on Windows, Linux and Android and replays it call by call, and on macOS, Xcode's Metal debugger can capture the Metal commands that MoltenVK generates. Before trusting any measurement, confirm that validation is off, that the GPU's clocks are not idling between frames, and that nothing cached the work from an earlier run.

#keyidea[
  A large renderer records on many threads, each with a pool of its own, creates its pipelines before it needs them and keeps them in a cache, and sub-allocates memory within the budget. Measure each with validation off, and learn what your driver does behind each call before trusting a number.
]

#opengl[
  An OpenGL context belongs to one thread at a time, so commands are issued from one thread, and drivers parallelise internally where they can. `glGetProgramBinary` is OpenGL's pipeline cache, and a binary can be rejected after any driver update, leaving the program to compile again. Memory is the driver's business: there is no portable way to ask OpenGL how much is left, only vendor extensions such as `GL_NVX_gpu_memory_info`.
]

#reading(
  [Arseny Kapoulkine, "Writing an efficient Vulkan renderer", in _GPU Zen 2_, 2019: memory, descriptors, command buffers and pipelines in a production renderer.],
  [NVIDIA, "Vulkan Dos and Don'ts", on the developer blog.],
  [AMD GPUOpen, the documentation of the Vulkan Memory Allocator, in particular its sections on budgets and on choosing memory types.],
  [The Vulkan Guide, "Pipeline Cache".],
)

== Labs

#lab([Scale the recording], goal: [Measure how recording scales on your machine.], time: [1 hour], code: "code/u4/scaling")[
  + Run `VKF_VALIDATION=0 build/bin/u4_scaling --draws 100000 --repeat 9` three times and record the recording and submission times.
  + Add your machine's number of cores to the thread counts the program tries, and run again.
  #done-when(
    [You have a table of recording speed-up against threads.],
    [You can explain where the speed-up stops growing, why submission does not change, and whether two threads beat one on your machine.],
  )
  #evidence([The table and the explanation.])
]

#lab([Warm across runs], goal: [See a pipeline cache survive a restart.], time: [1.5 hours], code: "code/u4/scaling")[
  + Change the test of the cache from disk to create the same variants as the empty-cache test, which the previous run saved.
  + Run the program twice without `--fresh`, then twice with it.
  #done-when(
    [The second run without `--fresh` creates its variants from the disk cache faster than without a cache.],
    [You can explain, from what MoltenVK's cache and Metal's system cache each hold, every number of the four runs, or the equivalent for your driver.],
  )
  #evidence([The four outputs and the explanation.])
]

#lab([Account for memory], goal: [Reconcile the program's allocations with the budget.], time: [1.5 hours], code: "code/u4/scaling")[
  + Count the bytes the program allocates through `vkf::createBuffer` and `vkf::createImage`, with each allocation's size from its memory requirements.
  + Print the count with the heap's usage before and after the program's allocations.
  #done-when(
    [The change in the heap's usage matches your count to within 1%.],
    [You can explain any difference, from the allocation granularity and from memory the driver allocates for itself.],
  )
  #evidence([The changes and the output.])
]

#lab([Profile a frame], goal: [Compare a profiler's view with your own timestamps.], time: [1 hour], code: "code/u4/particles")[
  + Capture a frame of `u4_particles --window` with the frame debugger for your platform: RenderDoc on Windows or Linux, or Xcode's Metal debugger on macOS.
  + Find the time of each pass in the capture and compare it with the program's timestamps.
  #done-when(
    [You have the capture and the comparison.],
    [You can name the most expensive pass and explain any difference between the tool's times and the timestamps.],
  )
  #evidence([A screenshot of the capture and the comparison.])
]

#problems(
  [Recording 100,000 draws takes 3.5 ms on one thread and 0.8 ms on eight, and submitting them 11.5 ms. What frame time can the CPU sustain, and which change would shorten it most?],
  [Why does each recording thread need its own command pool? What could go wrong if two threads shared one, even if each used its own command buffer?],
  [What does `VkCommandBufferInheritanceRenderingInfo` let the driver do when it records a secondary, and what would it have to do without it?],
  [A pipeline cache saved before a driver update is loaded after it. What happens with and without the header check, and what does the program lose in each case?],
  [A device's `maxMemoryAllocationCount` is 4,096, and a scene has 20,000 meshes, each with a vertex and an index buffer. Design the allocation scheme, and say how it handles meshes that are loaded and unloaded as the camera moves.],
)

#checklist(
  [I can record one rendering pass on many threads with secondary command buffers and a pool per thread.],
  [I can cache pipelines, save the cache, and check its header before reuse.],
  [I can sub-allocate memory and keep a program within its memory budget.],
  [I can choose a descriptor strategy by how often resources change.],
  [I can find whether the CPU or the GPU limits a frame, and profile the one that does.],
  [Lab 4.6.1–4.6.4 done-when criteria all hold, with evidence filed.],
)
