#import "../lib/template.typ": *

= Memory in shaders <ch-shader-memory>

#chapter-meta(
  time: [6 hours],
  builds: [A matrix transpose three ways, measured against a copy; a 256-bin histogram with global atomics and with per-workgroup bins in shared memory, on uniform and on contended input; and two data races, observed and then fixed.],
  needs: [Chapter 2.1.],
)

#why[
  The speed of most kernels is decided by how they touch memory, not by their arithmetic. The same work can run at a fraction of its speed with a different access pattern, and an innocent-looking pattern gives wrong answers when two invocations meet at one address without synchronising. This chapter covers the kinds of memory a shader can use, the access patterns the hardware rewards, shared memory and the barriers that coordinate it, atomic operations, and data races. Every algorithm in the rest of the unit depends on them.
]

#skip-test(
  rule: [If all five are easy, skim the core ideas and do Labs 2.2.1 and 2.2.3.],
  [Which kinds of memory can a compute shader read and write, and which of them can another workgroup see?],
  [Why is a naive matrix transpose slower than a copy on most GPUs, and how does a tile in shared memory help?],
  [Thirty-two invocations read `tile[i][2]` from `shared float tile[32][32]`, one value of `i` each. Why might that be slow, and what does declaring `tile[32][33]` change?],
  [A thousand invocations each execute `counter += 1` on the same buffer element. What can the result be, and what are two correct ways to count?],
  [When is `barrier()` required, and where may it not be called?],
)

== Core ideas

=== Where shader data lives

A compute shader can use five kinds of memory, summarised in @tbl-memory. They differ in size, in speed, in who can see them, and in how long they last.

#figure(
  tbl(columns: (auto, 1fr, 1fr), header: ([Kind], [Declared as], [Size, visibility, lifetime]),
    [Storage buffer], [`buffer` block with `std430`], [Up to `maxStorageBufferRange`; read and written by every invocation of every dispatch; lasts as long as the buffer.],
    [Uniform buffer], [`uniform` block, `std140` by default], [Up to `maxUniformBufferRange`, at least 16 KiB; read-only; often read through a faster, cached path.],
    [Push constants], [`push_constant` block], [Up to `maxPushConstantsSize`, at least 128 bytes; read-only; set per dispatch in the command buffer.],
    [Shared memory], [`shared` variables], [Up to `maxComputeSharedMemorySize`, at least 16 KiB; read and written by one workgroup; lasts while the workgroup runs.],
    [Private], [ordinary local variables], [Registers, private to one invocation; large arrays may spill to slower memory.],
  ),
  caption: [The memory a compute shader can use],
  kind: table,
) <tbl-memory>

Qualifiers on buffer blocks tell the compiler how a buffer is used. `readonly` and `writeonly` promise the obvious and let the compiler and the driver choose faster paths. `restrict` promises that no other binding refers to the same memory, so the compiler may keep values in registers and reorder accesses; all of this unit's kernels use it. `coherent` makes writes visible to other invocations of the same dispatch without waiting for the dispatch to end; it is needed only when invocations communicate through a buffer while they run, which Chapter 2.3's single-pass algorithms discuss.

=== Access patterns: the transpose

Part 3 of the Handbook explained _coalescing_: when the invocations of a subgroup access consecutive addresses, the hardware serves them with a few wide memory transactions; when they access scattered addresses, each costs a transaction of its own. A matrix transpose shows the difference in the plainest way. Reading a row is coalesced, and writing it out as a column is not (@fig-transpose).

#fig("u2-transpose", caption: [Two ways to transpose. The naive kernel reads rows and writes columns. The tiled kernel reads a 32 × 32 tile in rows, stores it in shared memory, and writes the transposed tile in rows too.]) <fig-transpose>

The naive kernel assigns a 32 × 32 tile to each workgroup of 32 × 8 invocations, each handling four rows of the tile. Consecutive invocations read consecutive elements of a row and write elements a whole row of the destination apart:

#snippet("u2/transpose/naive.comp", "naive", caption: [The naive transpose: coalesced reads, strided writes])

The tiled kernel stages the tile through _shared memory_, a small on-chip memory that the invocations of a workgroup share and that is about as fast as the L1 cache. It reads the tile in rows, waits until the whole workgroup has done so, and writes the transposed tile in rows, so that both the reads and the writes of global memory are coalesced:

#snippet("u2/transpose/tiled.comp", "tiled", caption: [The tiled transpose, with optional padding chosen by a specialisation constant])

The program runs four kernels, all specialisations of three shaders, and checks every result bit for bit: a plain copy, which is the bandwidth any transpose can at best match, the naive transpose, the tiled transpose, and the tiled transpose with padded rows.

#snippet("u2/transpose/main.cpp", "variants", caption: [The four variants])

#console(read("/src/console/u2-transpose.txt"), caption: [A 4096 × 4096 transpose on the M2 Pro, with validation off])

#console(read("/src/console/u2-transpose-cached.txt"), caption: [The same with a 1024 × 1024 matrix, which fits in the M2 Pro's caches])

#fig("u2-transpose-results", caption: [The transposes on the M2 Pro. With a small matrix, tiling recovers most of what the naive kernel loses; with a large one, every kernel is limited by memory bandwidth.]) <fig-transpose-results>

The results are not the textbook's, and the difference is instructive. With the 64 MiB matrix, all three transposes run within about 15% of the copy: the M2 Pro's caches gather the scattered writes of each tile before they reach memory, so the naive kernel hardly suffers, and memory bandwidth limits all of them. With the 4 MiB matrix, the data stays in the GPU's caches, the copy reaches nearly 400 GB/s, and the naive kernel falls to less than half of it, while the tiled kernels recover most of the difference. On many discrete GPUs, the naive kernel is slow at every size, because their caches do not absorb strided writes as well. The rule that survives every GPU is to measure: an optimisation that matters a great deal on one device may matter little on another.

=== Shared memory banks

Shared memory is divided into _banks_, typically 32 of them, each four bytes wide, with consecutive words in consecutive banks. A subgroup's accesses to different banks proceed together; accesses to different addresses in the same bank are serialised, a _bank conflict_. In a 32 × 32 tile of floats every row is 32 words long, so a whole column lies in a single bank, and the tiled transpose's column reads conflict 32 ways. Padding each row by one float shifts each row by one bank and spreads a column over all of them (@fig-banks).

#fig("u2-banks", caption: [Bank conflicts, drawn with eight banks for legibility. Without padding, a column of the tile lies in one bank; with one word of padding per row, it spreads across every bank.]) <fig-banks>

The padded kernel is the fastest of the four with the small matrix. With the large one it gains nothing, because memory bandwidth limits it, not shared memory. Apple does not document how its GPUs organise shared memory, which is one more reason to measure instead of reasoning from another vendor's design.

=== `barrier()` and memory barriers

The tiled transpose would be wrong without its `barrier()`: an invocation would read elements of the tile that other invocations had not yet written. `barrier()` does two things. It is an _execution barrier_, which no invocation of the workgroup passes until all have reached it, and it is a _memory barrier_ for shared memory, which makes every write to shared memory before it visible to every read after it. Together these let the invocations of a workgroup hand data to each other through shared memory.

The memory barrier functions `memoryBarrierShared()`, `memoryBarrierBuffer()`, `memoryBarrierImage()` and `groupMemoryBarrier()` order an invocation's own memory accesses as other invocations observe them, without waiting for anyone. They matter for communication through buffers and images, combined with `barrier()` within a workgroup or with `coherent` memory across workgroups, which the course needs only rarely.

#hazard(title: [Pitfall])[
  Every invocation of a workgroup must reach the same `barrier()`. Calling it inside a branch that some invocations skip, or after an early `return` taken by some, is undefined behaviour: on some GPUs the workgroup waits forever and the device is lost. Keep barriers in code that the whole workgroup executes, and turn bounds checks into conditions around the work instead of early returns.
]

=== Atomic operations: the histogram

An _atomic operation_ reads, modifies and writes one memory location as a single indivisible step, so that concurrent updates from many invocations are all applied. GLSL provides `atomicAdd`, `atomicMin`, `atomicMax`, `atomicAnd`, `atomicOr`, `atomicXor`, `atomicExchange` and `atomicCompSwap` on 32-bit integers in buffers and in shared memory; each returns the value the location held before. 64-bit and floating-point atomics are optional features that a program must check for.

A histogram counts how many input values fall in each bin, and is a natural use of atomics. The straightforward kernel adds every byte of its input to one of 256 bins in a storage buffer:

#snippet("u2/histogram/global.comp", "global", caption: [A histogram with an atomic add to global memory for every byte])

On most GPUs, atomics on global memory are performed in the L2 cache, and atomics on the same address are serialised there. The usual remedy is _privatisation_: each workgroup counts into its own bins in shared memory, where atomics are cheap, and adds its bins to the global ones once at the end.

#snippet("u2/histogram/shared.comp", "shared", caption: [Counting in shared memory first: one global atomic per bin per workgroup])

The program checks both against a histogram computed on the CPU, for two inputs: random bytes, which spread evenly over the bins, and an input in which every byte is the same, so that every atomic lands on one bin.

#snippet("u2/histogram/main.cpp", "reference", caption: [The CPU's histogram, the reference for every result])

#console(read("/src/console/u2-histogram.txt"), caption: [The histograms on the M2 Pro, with validation off])

#fig("u2-histogram", caption: [Time to build the histogram of 64 MiB. Privatisation is about thirteen times faster on random input, and more than thirty times faster when every update hits one bin.]) <fig-histogram>

Privatisation turns 64 million global atomics into about a million: 4096 workgroups adding 256 bins each. On random input it runs at the speed of memory; with every byte the same, the shared-memory atomics contend too, but cost far less than the global ones.

=== Data races

A _data race_ occurs when two invocations access the same location without synchronisation and at least one of them writes. Its result is undefined, which in practice means that it depends on timing. The third program commits two races on purpose. In the first, a million invocations each add one to a counter with an ordinary read, add and write; the fix, chosen by a Boolean specialisation constant, is `atomicAdd`.

#snippet("u2/race/counter.comp", "counter", caption: [A counter updated without and with an atomic operation])

#snippet("u2/race/main.cpp", "bool-constant", caption: [A Boolean specialisation constant passed as a `VkBool32`])

In the second, each workgroup sums 256 values in shared memory with a tree: half the invocations add the upper half of the array to the lower, then a quarter, and so on. Without the barriers, an invocation can read a partial sum before another invocation has written it.

#snippet("u2/race/tree_sum.comp", "tree", caption: [A tree sum in shared memory, with its barriers made optional])

#console(read("/src/console/u2-race.txt"), caption: [Both races on the M2 Pro])

#console(read("/src/console/u2-race-fix.txt"), caption: [The same kernels, synchronised])

The counter's result is the most extreme possible: a million invocations each added one, and the counter ended at one. Every invocation read the counter's initial zero before any wrote its one. The missing barriers corrupted about one sum in fifty in this run, a rate that changes from run to run. On another GPU, or with another load, either number could be different, and that is exactly what makes races dangerous: a race that happens rarely passes tests and fails in production. Synchronisation validation checks the barriers between commands, not the accesses inside a dispatch, so it cannot see these races; only careful design and testing can.

#keyidea[
  Within a workgroup, `barrier()` orders execution and shared memory. Within a dispatch, between workgroups, only atomic operations are safe on shared locations. Between dispatches, pipeline barriers order everything. Each level of the hierarchy has its own tool.
]

=== The Vulkan memory model

Vulkan 1.2 adopted a formal _memory model_, the `vulkanMemoryModel` feature, that defines precisely when a write by one invocation becomes visible to another. It describes writes becoming _available_ and then _visible_, at a _scope_: the subgroup, the workgroup, the queue family or the device. GLSL exposes it through the `GL_KHR_memory_scope_semantics` extension, which adds atomic loads and stores with explicit scopes and acquire and release semantics. Most compute code never needs it explicitly, because `barrier()`, atomics and pipeline barriers already provide the guarantees. Unit 3 uses the same ideas of availability and visibility for the barriers between commands.

#opengl[
  The shader side of this chapter is identical in OpenGL 4.3 and later: shared variables, `barrier()`, the memory barrier functions, atomics and the `coherent`, `restrict`, `readonly` and `writeonly` qualifiers all come from GLSL. Only the host side differs: OpenGL binds storage buffers to numbered binding points and orders dispatches with `glMemoryBarrier`, where Vulkan uses descriptor sets and pipeline barriers.
]

#reading(
  [The GLSL 4.60 specification, sections on shared variables, "Shader Invocation Control Functions" (`barrier`), "Shader Memory Control Functions" and "Atomic Memory Functions".],
  [The Vulkan Guide, "Shader Memory Layout" and "Atomics".],
  [Hwu, Kirk and El Hajj, _Programming Massively Parallel Processors_, chapters 5 (memory and tiling), 6 (performance, including coalescing) and 9 (parallel histogram).],
)

== Labs

#lab([Transpose at four sizes], goal: [Find where tiling matters on your GPU.], time: [1.5 hours], code: "code/u2/transpose")[
  + Run `VKF_VALIDATION=0 build/bin/u2_transpose` with `--n` set to 512, 1024, 2048 and 4096, using `--runs 50` for the two smallest.
  + Plot the bandwidth of each kernel against the matrix size.
  + Find your GPU's L2 cache size, and mark it on the plot at the matrix size whose source and destination together fill it.
  #done-when(
    [You have the plot from three runs at each size.],
    [You can explain where the naive kernel falls behind the tiled ones on your GPU, in terms of its caches.],
  )
  #evidence([The plot and your explanation.])
]

#lab([Read your bank conflicts], goal: [Measure the cost of bank conflicts directly.], time: [1 hour], code: "code/u2/transpose")[
  + Add a variant of `tiled.comp` that writes `tile[id.x][row]` in the first phase and reads `tile[row][id.x]` in the second: the same transpose with the conflicts moved to the writes.
  + Measure all the tiled variants with padding of 0, 1 and 2 at `--n 1024 --runs 50`.
  #done-when(
    [Every variant still transposes exactly.],
    [You have the timings, and can say whether your GPU shows bank conflicts and how large they are.],
  )
  #evidence([The variant's code and the table of timings.])
]

#lab([Histograms under contention], goal: [Measure how contention and privatisation interact.], time: [1.5 hours], code: "code/u2/histogram")[
  + Add an input in which every byte is one of four values, and run all three inputs with both kernels.
  + Change `wordsPerInvocation`, which sets how many workgroups the dispatch uses, to 4 and to 64, and measure again.
  + Explain the effect of the number of workgroups on each kernel.
  #done-when(
    [Every histogram is exact.],
    [You have a table of the six measurements at three numbers of workgroups, and your explanation refers to where the atomics are performed.],
  )
  #evidence([The table and the explanation.])
]

#lab([Races, observed and fixed], goal: [See how a race's symptoms vary.], time: [1 hour], code: "code/u2/race")[
  + Run `build/bin/u2_race` ten times and record both failure rates each time.
  + In `tree_sum.comp`, keep the barrier before the loop and remove only the one inside it, then the reverse, and record the failure rate of each.
  + Run `--fix` and confirm that both kernels are exact.
  #done-when(
    [You have the failure rates for all three versions of the tree, over ten runs each.],
    [You can explain which data each missing barrier lets an invocation read too early.],
  )
  #evidence([The rates and the explanation.])
]

#problems(
  [How many bytes does a transpose of an N × N matrix of floats move, and what is its arithmetic intensity? Why can no transpose run faster than a copy of the same matrix?],
  [Thirty-two invocations read `tile[i][5]` from `shared float tile[32][32]` for i = 0 to 31. Which banks do they touch, assuming 32 banks of four bytes? Which with `tile[32][33]`?],
  [A histogram has 65,536 bins of 32-bit counts. Why can privatisation in shared memory not work as written here, and what would you do instead?],
  [The racing counter ended at exactly one on the M2 Pro. Describe an execution in which it ends at 256 instead.],
  [Give an example of a kernel that needs the `coherent` qualifier on a buffer, and explain what could go wrong without it.],
)

#checklist(
  [I can choose the right kind of memory for each piece of shader data and use the buffer qualifiers.],
  [I can explain coalescing and use a tile in shared memory, with its barriers, to make accesses coalesced.],
  [I can recognise bank conflicts and remove them with padding.],
  [I can use atomics, privatise contended updates, and recognise and fix data races.],
  [Lab 2.2.1–2.2.4 done-when criteria all hold, with evidence filed.],
)
