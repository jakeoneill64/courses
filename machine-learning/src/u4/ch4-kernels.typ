#import "../lib/template.typ": *

= Kernels <ch-kernels>

#chapter-meta(
  time: [9 hours],
  builds: [Matrix multiplication written three times as a GPU kernel (naive, tiled in shared memory, and register-blocked) and, on the Metal track, measured against the vendor's; a row-wise softmax built on subgroup reductions; and FlashAttention's forward pass, tiled over keys with an online softmax, checked against the reference and, on the Metal track, timed against attention that stores its scores and against PyTorch's own. Each kernel exists twice, in Metal, run from PyTorch, and in Vulkan's GLSL, run through the vkf library. Choose one track, or follow both.],
  needs: [Chapters 4.1 and 4.2. For the Metal track, an Apple Silicon Mac. For the Vulkan track, a GPU with a Vulkan 1.3 driver, the Vulkan SDK, CMake and Ninja; the Vulkan course's Units 1 and 2 help but are not required.],
)

#why[
  Every operation in this course has run on kernels someone else wrote. Writing them yourself shows why those kernels are shaped as they are: why a matrix multiplication tiles its inputs, why a softmax works row by row, and why FlashAttention, the most important kernel of the last few years, computes attention without ever storing it. The ideas are the same on every GPU, so the chapter offers two tracks, Apple's Metal, run straight from PyTorch, and Vulkan, which runs on GPUs from every vendor and on Macs through MoltenVK. The listings set them side by side.
]

#skip-test(
  rule: [If all four are easy, read the FlashAttention section and do Labs 4.4.3 and 4.4.4.],
  [In a naive matrix multiplication kernel, how many times is each input element read from memory? How does tiling in shared memory change that?],
  [What does register blocking add to tiling, and why does it help?],
  [How can a softmax over a row be computed in one pass, keeping a running maximum and a running sum?],
  [Why does FlashAttention read and write less memory than attention that materialises its scores?],
)

== Core ideas

=== The programming model, in two vocabularies

A GPU kernel is a function run by many threads at once, each with its own index. Threads are grouped into _threadgroups_, in Metal's vocabulary, or _workgroups_, in Vulkan's, which run together on one core, can share a small fast _threadgroup_ or _shared_ memory, and can wait for each other at a _barrier_. Within a group, threads execute in lockstep in _SIMD groups_ or _subgroups_ of 32, which can exchange values directly with reductions such as a sum or a maximum.

#tbl(columns: (1fr, 1fr, 1fr), header: ([Idea], [Metal], [Vulkan GLSL]),
  [Thread's index in the grid], [`thread_position_in_grid`], [`gl_GlobalInvocationID`],
  [Group of threads], [threadgroup], [workgroup, `local_size`],
  [Index within the group], [`thread_position_in_threadgroup`], [`gl_LocalInvocationID`],
  [Group's memory], [`threadgroup float t[...]`], [`shared float t[...]`],
  [Barrier], [`threadgroup_barrier(...)`], [`barrier()`],
  [Lockstep subset, 32 wide here], [SIMD group, `simd_sum`], [subgroup, `subgroupAdd`],
)

The Metal track compiles its kernels at run time with `torch.mps.compile_shader` and calls them on PyTorch tensors, so checking against PyTorch's own result is one line:

#snippet("u4/kernels_metal.py", "compile", caption: [Metal: compiling the kernels from Python])

The Vulkan track compiles GLSL to SPIR-V with `glslc` at build time, and a C++ program uploads data, dispatches the kernels through vkf, times them with timestamp queries, and checks sampled results against a CPU reference in double precision:

#snippet("kernels/vulkan/main.cpp", "kernel", caption: [Vulkan: a pipeline per kernel, with sizes passed as push constants])

=== Naive matrix multiplication

The naive kernel runs one thread per output element, each computing the dot product of a row and a column:

#snippet("u4/kernels.metal", "naive", caption: [Metal: one output element per thread])

#snippet("kernels/vulkan/matmul_naive.comp", "naive", caption: [Vulkan: the same kernel in GLSL])

Each thread reads $2k$ floats to perform $2k$ FLOPs, an intensity of $1 \/ 4$, and threads that need the same row or column read it again. Neighbouring threads read neighbouring columns of $B$, which the memory system combines into wide transactions, so the kernel runs faster than its intensity suggests, although still far from the roofline's ridge.

=== Tiling in shared memory

A threadgroup of $16 times 16$ threads computes a $16 times 16$ tile of the output. It walks along the inner dimension 16 at a time: each thread loads one element of $A$'s tile and one of $B$'s into shared memory, the group waits at a barrier, and each thread then performs 16 multiply-adds from shared memory before the next tiles are loaded. Every element loaded from main memory is now used 16 times.

#snippet("u4/kernels.metal", "tiled", caption: [Metal: tiles of $A$ and $B$ in threadgroup memory])

#snippet("kernels/vulkan/matmul_tiled.comp", "tiled", caption: [Vulkan: the same, in shared memory])

The two barriers per step are both necessary: the first stops threads computing with a tile that others have not finished loading, the second stops them overwriting a tile that others are still reading.

=== Register blocking

Shared memory is fast, but each multiply-add above still reads two values from it. _Register blocking_ has each thread compute a $4 times 4$ block of outputs: per step of the inner dimension, it loads four values of $A$ and four of $B$ into registers and performs sixteen multiply-adds, so each value read from shared memory is used four times. A threadgroup of $16 times 16$ threads then covers a $64 times 64$ output tile.

#snippet("u4/kernels.metal", "blocked", caption: [Metal: $4 times 4$ outputs per thread from a $64 times 64$ tile])

#snippet("kernels/vulkan/matmul_blocked.comp", "blocked", caption: [Vulkan: the same blocking])

The Metal track launches each kernel with a grid matching its tile:

#snippet("u4/kernels_metal.py", "launch", caption: [Metal: launching the three kernels, and PyTorch's for comparison])

#console-part("/src/console/u4-kernels-metal.txt", to: 6, caption: [Metal track: GFLOP/s on the M2 Pro])

#console-part("/src/console/u4-kernels-vulkan.txt", to: 7, caption: [Vulkan track: GFLOP/s on the M2 Pro through MoltenVK])

On both tracks the naive kernel reaches about 0.4 TFLOP/s, reading every operand from memory for every product. Tiling through shared memory nearly doubles it, to about 0.73, and register blocking more than doubles that again, to about 1.8 TFLOP/s at the larger sizes. There the two tracks agree within a few per cent, as expected, since MoltenVK translates the Vulkan kernels into Metal ones and the hardware underneath is the same. The vendor's kernel reaches 5.5 TFLOP/s, three times the blocked kernel's. It uses the GPU's SIMD-group matrix instructions, which multiply small matrices held across a SIMD group's registers in a single operation, together with larger tiles and loads overlapped with arithmetic. The Metal option of Lab 4.4.3 tries the matrix instructions.

=== Softmax, one row per threadgroup

A softmax over a row needs the row's maximum and the sum of exponentials, both reductions. One threadgroup handles one row: each thread reduces a strided share of the row, the SIMD group or subgroup combines its 32 threads' values in registers, the first thread of each writes its result to shared memory, and one more reduction across the groups gives the row's value.

#snippet("u4/kernels.metal", "softmax", caption: [Metal: a row softmax with SIMD-group reductions])

#snippet("kernels/vulkan/softmax.comp", "softmax", caption: [Vulkan: the same with subgroup operations])

#console-part("/src/console/u4-kernels-metal.txt", from: 6, to: 7, command: false, caption: [Metal track: softmax bandwidth])

#console-part("/src/console/u4-kernels-vulkan.txt", from: 7, to: 8, command: false, caption: [Vulkan track: softmax bandwidth])

The softmax is memory-bound, so it is measured by bandwidth, counting one read of the row and one write of the result. This kernel reads the row three times, for the maximum, the sum and the output. A better one keeps the row in registers or shared memory and reads it once, or, as the next section shows, avoids the separate maximum altogether. Even so, this kernel beats PyTorch's general softmax on this shape, 130 GB/s against 112, and the Vulkan version reaches 146.

=== FlashAttention

Attention as written in Chapter 2.3 computes the $T times T$ scores, writes them to memory, reads them back for the softmax, writes the weights, and reads them again to multiply by the values. For long sequences these scores dominate both memory traffic and memory use. FlashAttention never stores them: it processes the keys in blocks and computes the softmax as it goes, using an _online_ softmax.

#derivation[
  For one query, keep a running maximum $m$, a running sum $ell$ of $exp(s_j - m)$ and an accumulator $o$ of $sum_j exp(s_j - m) v_j$. When a new score $s$ arrives with value $v$, the new maximum is $m' = max(m, s)$; the old sum and accumulator were computed relative to $m$, so rescale them by $exp(m - m')$, then add the new term: $ell' = ell e^(m - m') + e^(s - m')$, $o' = o e^(m - m') + e^(s - m') v$. After the last key, $o \/ ell$ is exactly the softmax-weighted average, computed in one pass, with no score stored.
]

Each threadgroup takes 64 queries, one per thread. The group loads blocks of 32 keys and values into shared memory, and each thread updates its query's running maximum, sum and accumulator from the block. Causal masking stops each query at its own position, and a threadgroup stops loading key blocks after its last query's position, which skips the masked half of the work.

#snippet("u4/kernels.metal", "flash", caption: [Metal: FlashAttention's forward pass, one query per thread, blocks of keys in threadgroup memory])

#snippet("kernels/vulkan/flash.comp", "flash", caption: [Vulkan: the same kernel])

#snippet("u4/kernels_metal.py", "attention", caption: [Metal: materialised attention, your kernel and PyTorch's])

#console-part("/src/console/u4-kernels-metal.txt", from: 7, command: false, caption: [Metal track: causal attention by length])

#console-part("/src/console/u4-kernels-vulkan.txt", from: 8, command: false, caption: [Vulkan track: the flash kernel by length])

Materialised attention holds the whole matrix of scores, 512 MiB at a length of 4,096 for eight heads, and would hold gigabytes at the lengths of current models. The flash kernel holds none. Its time grows with the square of the length, as attention's must, but it is two and a half to three and a half times slower than materialised attention, whose two products run on Apple's tuned matrix kernels. It is up to sixteen times slower than PyTorch's fused kernel, which has both advantages, and beyond length 512 the Vulkan track's kernel is slower again. The algorithm is correct, and the gap comes from the simple implementation. One query per thread computes each inner product with scalar arithmetic, and every group of 64 queries reloads every key block, while the vendor's kernel uses the matrix instructions, gives each thread several queries and keeps more of each block in registers. Lab 4.4.3 closes part of the gap. A kernel for training also needs the backward pass, which recomputes the scores block by block from the maxima and sums saved by the forward pass, trading arithmetic for memory again.

#keyidea[
  A fast kernel moves each byte from memory as few times as possible: tiling reuses inputs from shared memory, register blocking reuses them from registers, and FlashAttention's online softmax avoids writing the attention scores at all. In each case the arithmetic is the same and the memory traffic is lower.
]

#inpytorch[
  Production kernels are written in CUDA, in Triton, a Python-embedded language that compiles tile-level programs for NVIDIA and AMD GPUs, or in Metal and its Metal Performance Shaders on Apple hardware. FlashAttention's own implementations use the GPUs' matrix units, process several queries per thread, and include a backward pass that recomputes the scores rather than storing them. PyTorch's `scaled_dot_product_attention` dispatches to such kernels where they exist.
]

#reading(
  [Tri Dao, Daniel Fu, Stefano Ermon, Atri Rudra and Christopher Ré, "FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness", NeurIPS 2022.],
  [Maxim Milakov and Natalia Gimelshein, "Online Normalizer Calculation for Softmax", 2018.],
  [Simon Boehm, "How to Optimize a CUDA Matmul Kernel for cuBLAS-like Performance: a Worklog", 2022.],
  [Apple, _Metal Shading Language Specification_, sections on threadgroup memory and SIMD-group functions; and the Vulkan course, Chapters 2.1 to 2.5, for the Vulkan track.],
)

== Labs

#lab([Tile sizes], goal: [Map the tiled kernel's speed against its tile size.], time: [2 hours], code: "code/u4/kernels.metal or code/kernels/vulkan")[
  + In your track, make the tiled kernel's tile size a parameter and measure tiles of 8, 16 and 32 at $n = 2048$.
  + For the register-blocked kernel, try $2 times 2$, $4 times 4$ and $8 times 4$ outputs per thread.
  #done-when(
    [Your table has six measurements, all checked against the reference.],
    [You can explain the best of each in terms of reuse and of the registers and shared memory each thread needs.],
  )
  #evidence([The table and the explanation.])
]

#lab([A one-pass softmax], goal: [Halve the softmax's memory traffic.], time: [1.5 hours], code: "code/u4/kernels.metal or code/kernels/vulkan/softmax.comp")[
  + Use the online softmax to compute each thread's maximum and sum in one pass over its share, combining partial results with the rescaling rule.
  + Then keep the row in registers between the reduction and the output, so the row is read once.
  #done-when(
    [Both versions match the reference.],
    [Your measured bandwidth rises, and you can relate the gain to the bytes saved.],
  )
  #evidence([The kernels and the measurements.])
]

#lab([A faster flash kernel], goal: [Close part of the gap to the vendor's attention.], time: [3 hours], code: "code/u4/kernels.metal or code/kernels/vulkan/flash.comp")[
  + Change the flash kernel so that each thread handles two queries, sharing each loaded key and value between them, and try key blocks of 16 and 64.
  + On the Metal track, optionally replace the inner products with `simdgroup_matrix` operations.
  #done-when(
    [Your kernel still passes the program's check against the reference.],
    [It is faster than the original at length 4,096, by a measured factor.],
  )
  #evidence([The kernel, the check and the timings.])
]

#lab([The other track], goal: [Port one kernel between Metal and Vulkan.], time: [1.5 hours], code: "code/u4/kernels.metal and code/kernels/vulkan")[
  + Port your best kernel from Lab 4.4.1 or 4.4.3 to the other track.
  + Compare the two versions' speeds on the same machine and explain any difference.
  #done-when(
    [The ported kernel passes its track's checks.],
    [You can account for the difference in speed, or its absence.],
  )
  #evidence([Both kernels and the comparison.])
]

#problems(
  [For the tiled kernel with tiles of $t times t$, how many bytes are read from main memory per output element, and what is the kernel's intensity as a function of $t$?],
  [Why does the register-blocked kernel's threadgroup cover a $64 times 64$ tile with only 256 threads, and what limits making the blocks larger?],
  [Show that the online softmax's rescaling gives exactly the same result as the two-pass softmax, in exact arithmetic.],
  [Materialised attention for 8 heads at 4,096 tokens holds how many MiB of scores in float32? How much does FlashAttention hold?],
  [Why does causal FlashAttention do about half the work of non-causal, while the materialised version as written does the full work and masks half of it?],
)

#checklist(
  [I can write, launch and check a GPU kernel in Metal or Vulkan.],
  [I can explain tiling and register blocking in terms of reuse and memory traffic.],
  [I can implement reductions with SIMD-group or subgroup operations.],
  [I can derive the online softmax and implement FlashAttention's forward pass.],
  [Lab 4.4.1–4.4.4 done-when criteria all hold, with evidence filed.],
)
