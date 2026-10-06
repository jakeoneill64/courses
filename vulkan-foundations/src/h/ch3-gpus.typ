#import "../lib/template.typ": *

= GPUs from the outside in <h-gpus>

This part is a short tour of the hardware that Vulkan programs. It contains no Vulkan, only the ideas the units rely on. Unit 2 returns to each of them with measurements on your own GPU.

== Host and device

A GPU is a separate processor, and the most useful way to think of it is as a separate computer. A program runs on the _host_, the CPU, and sends work to the _device_, the GPU. A discrete GPU has its own memory, called VRAM, and reaches the host's memory across the PCI Express bus, which moves about 32 GB/s in each direction at PCIe 4.0 with sixteen lanes, and twice that at PCIe 5.0. An integrated GPU, such as Apple's or those built into most laptop processors, shares memory with the CPU instead. @fig-gpu shows the parts that matter to a programmer.

#fig("h-gpu", caption: [Host and device. The host sends work through queues that the GPU's command processor reads; the compute units do the work; every unit shares the L2 cache and the device's memory.]) <fig-gpu>

The host does not call functions on the GPU. It writes commands into memory and tells the GPU where they are. The GPU's _command processor_ reads them and starts the work, at its own pace, while the host carries on. Vulkan exposes this arrangement directly: command buffers hold the commands, queues are where you submit them, and fences and semaphores report when they are done. Unit 1 builds each of these.

== Throughput, not latency

A CPU core is built to finish one thread's work as soon as possible. It spends most of its silicon on large caches, branch prediction and out-of-order execution, so that a single instruction stream rarely waits. A GPU is built to finish a very large amount of work as soon as possible, and does not mind if any single piece of it waits. It spends its silicon on arithmetic units and on keeping a very large number of threads ready to run. A large desktop GPU holds on the order of a hundred thousand threads in flight at once.

The work is divided among _compute units_: NVIDIA calls them streaming multiprocessors, AMD compute units, Intel Xe-cores, and Apple GPU cores. A desktop GPU has from a few dozen to over a hundred. Each has its own schedulers, arithmetic units, a large register file and a small, fast memory that its threads can share.

== SIMT: one instruction, many lanes

Threads on a GPU do not each have their own instruction stream. They are grouped, and every thread in a group executes the same instruction at the same time on its own data: _single instruction, multiple threads_, or SIMT. Vulkan calls the threads _invocations_ and the hardware group a _subgroup_. Vendors use their own names and sizes: NVIDIA's _warps_ have 32 threads; AMD's _wavefronts_ have 64 on older GCN hardware and 32 or 64 on RDNA; Intel uses 8, 16 or 32; Apple's _SIMD-groups_ have 32.

The model has one consequence that every GPU programmer meets. When the invocations of a subgroup take different branches, the subgroup executes both branches, one after the other, with the invocations that did not take each branch switched off (@fig-simt). Code whose branches depend on data can therefore run at a fraction of the hardware's speed. Chapter 2.1 measures it, and the ray tracer in Chapter 2.7 meets it at every bounce.

#fig("h-simt", caption: [Divergence. Eight lanes of a subgroup run an `if` whose condition differs between lanes: the subgroup runs both branches in turn, with the lanes that did not take each branch masked off.]) <fig-simt>

== Hiding latency

Reading memory takes a GPU hundreds of cycles. The GPU does not try to make that faster. Instead, each compute unit keeps many subgroups resident at once, and when one stalls on a load, the scheduler switches to another that is ready, at no cost (@fig-latency). As long as some subgroup is ready, the arithmetic units never wait.

#fig("h-latency", caption: [Latency hiding. Four subgroups share one compute unit; while each waits for memory, the others compute.]) <fig-latency>

How many subgroups a compute unit can hold is called its _occupancy_. It is limited by the resources each subgroup needs: registers, which every invocation uses, and shared memory, which a workgroup uses. A shader that uses many registers leaves room for fewer subgroups, and so has fewer to switch between. Occupancy is not a goal in itself, but too little of it leaves the compute unit idle while memory is slow. Chapter 2.5 measures the trade-off.

== The memory hierarchy

GPU memory forms a hierarchy (@fig-hierarchy). _Registers_ are private to each invocation and fastest; a compute unit has hundreds of kilobytes of them, more than its cache. _Shared memory_, a small scratchpad that the invocations of one workgroup share, is almost as fast and is managed by the program. The _L1_ and _L2_ caches are managed by the hardware; L2 is shared by the whole GPU. _VRAM_ holds everything else.

#fig("h-hierarchy", caption: [The memory hierarchy, from registers to system RAM. Each level is larger, slower and farther from the arithmetic than the one above.]) <fig-hierarchy>

Two properties of the hierarchy shape GPU code. First, memory moves in blocks: when the invocations of a subgroup read neighbouring addresses, the hardware combines their reads into a few wide transactions, called _coalescing_, and when they read scattered addresses, each read costs a transaction. Second, shared memory lets a workgroup load data once and use it many times, which is the basis of most fast GPU algorithms. Unit 2 relies on both.

== Bandwidth and arithmetic

A GPU's arithmetic is far faster than its memory. A desktop GPU can perform tens of trillions of floating-point operations per second but read only about a trillion bytes per second from VRAM, so a kernel must do tens of operations for every byte it reads to keep the arithmetic busy. The ratio of operations to bytes is the kernel's _arithmetic intensity_.

The _roofline model_ turns this into a picture (@fig-roofline). A kernel's attainable speed is the lower of two limits: the peak arithmetic rate, and the memory bandwidth multiplied by its arithmetic intensity. The two meet at the _ridge point_. Kernels to its left are _memory-bound_: the only way to make them faster is to move fewer bytes. Kernels to its right are _compute-bound_. SAXPY, the first program of the course, performs two operations for every twelve bytes it moves, and is about as memory-bound as a kernel can be.

#fig("h-roofline", caption: [The roofline of an illustrative GPU with 1 TB/s of memory bandwidth and 40 TFLOP/s of arithmetic, computed. The kernels are placed by their arithmetic intensity, assuming each byte moves between memory and the GPU once. Chapter 2.5 measures the roofline of your own GPU.]) <fig-roofline>

== Why explicit APIs

OpenGL and Direct3D 11 were designed when a GPU was a fixed-function device driven by a single CPU thread. As GPUs became general processors and CPUs gained cores instead of speed, the drivers behind those APIs became the bottleneck. A driver had to track the state of every object, validate every call, decide when to compile shaders, find dependencies between commands and insert barriers, and manage memory, all on the one thread that owned the context. Much of that work was invisible to the program, and its cost was unpredictable: a draw call could trigger a shader compilation or a copy of a texture.

Game consoles had long offered thin, explicit interfaces to their GPUs, and their games were faster for it. AMD's Mantle, announced in 2013, brought the idea to the PC. Apple released Metal in 2014 and Microsoft Direct3D 12 in 2015. Khronos, which maintains OpenGL, built Vulkan from Mantle and released it in 2016. All of these APIs make the same trade: the driver does less and the program does more, in exchange for lower and predictable CPU cost, recording on many threads, and control over memory and synchronisation. Part 4 compares Vulkan and OpenGL in detail.
