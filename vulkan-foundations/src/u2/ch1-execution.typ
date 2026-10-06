#import "../lib/template.typ": *

= The compute execution model <ch-execution>

#chapter-meta(
  time: [5 hours],
  builds: [A program that shows which workgroup and subgroup runs each invocation of a dispatch and checks every identity between Vulkan's built-in indices; and a sweep of workgroup sizes for a memory-bound and an arithmetic-bound kernel.],
  needs: [Unit 1.],
)

#why[
  Unit 1 dispatched SAXPY in workgroups of 256 invocations without asking why. This chapter explains how a dispatch is divided into workgroups and subgroups, what each level guarantees and what it does not, and how the division reaches the GPU's compute units. Everything else in Unit 2 builds on it: shared memory and barriers belong to workgroups (Chapter 2.2), the fastest parallel algorithms work one subgroup at a time (Chapters 2.3 and 2.5), and the sizes you choose decide how much of the hardware a kernel can use.
]

#skip-test(
  rule: [If all four are easy, skim the core ideas and do Labs 2.1.2 and 2.1.3.],
  [A dispatch of 4 × 2 workgroups has a local size of 8 × 8. How many invocations run, and what is `gl_GlobalInvocationID` for the invocation with `gl_WorkGroupID` (1, 1) and `gl_LocalInvocationID` (3, 5)?],
  [What may the invocations of one workgroup do together that the invocations of different workgroups may not?],
  [A workgroup of 36 invocations runs on a GPU whose subgroups have 32. How many subgroups does it occupy, and how many lanes do nothing?],
  [Why are workgroup sizes usually multiples of 32 or 64?],
)

== Core ideas

=== Invocations, workgroups and dispatches

A compute shader is run by _invocations_, one instance of `main` each. Invocations are grouped into _workgroups_ whose size, the _local size_, the shader declares in up to three dimensions. A dispatch runs a grid of workgroups whose dimensions `vkCmdDispatch` gives (@fig-hierarchy). Each invocation finds its place through built-in variables:

- `gl_NumWorkGroups` and `gl_WorkGroupSize`: the grid's dimensions in workgroups, and the local size.
- `gl_WorkGroupID`: which workgroup the invocation belongs to.
- `gl_LocalInvocationID`: its position within the workgroup, and `gl_LocalInvocationIndex`, the same position as a single number, `z·X·Y + y·X + x` for a local size of X × Y × Z.
- `gl_GlobalInvocationID`: its position in the whole grid, equal to `gl_WorkGroupID * gl_WorkGroupSize + gl_LocalInvocationID`.

#fig("u2-hierarchy", caption: [A dispatch of 4 × 2 workgroups, each of 8 × 8 invocations. On the M2 Pro each workgroup is divided into two subgroups of 32 invocations.]) <fig-hierarchy>

The first program of this unit records every built-in for every invocation of a small dispatch. Its shader writes one record per invocation, at the position its global index gives:

#snippet("u2/indexing/indexing.comp", "interface", caption: [A record of everything an invocation knows about its place])

#snippet("u2/indexing/indexing.comp", "main", caption: [Each invocation writes its own record])

The C++ side mirrors the record exactly, as Chapter 1.5 taught, and checks its size against the `std430` layout:

#snippet("u2/indexing/main.cpp", "record", caption: [The host's view of a record])

The program fills the buffer with `0xFFFFFFFF` before the dispatch, so that an invocation that never ran leaves a record it can detect. It then checks every identity for every invocation, and draws the grid twice: once by workgroup, once by subgroup.

#snippet("u2/indexing/main.cpp", "checks", caption: [Checking the identities on the CPU])

#console(read("/src/console/u2-indexing.txt"), caption: [A dispatch of 4 × 2 workgroups of 8 × 8 on the M2 Pro: the device's compute limits, which workgroup and which subgroup ran each position, and the checks])

=== What a workgroup guarantees

The invocations of one workgroup run on the same compute unit, at the same time. That gives them two abilities that nothing else in a dispatch has: they can share variables declared `shared`, and they can wait for each other with `barrier()`. Chapter 2.2 is about both.

Different workgroups get no such guarantees. They run in no defined order: all at once, a few at a time, or one after another, depending on the GPU, the size of the dispatch and whatever else is running. They can communicate only through memory, with atomic operations, and a workgroup must never wait for another to do something, because Vulkan does not guarantee that the other will run while the first is waiting. A kernel that needs every workgroup to finish a step before any starts the next must end and let a second dispatch, after a barrier, do the next step. Chapter 2.3's multi-pass algorithms are built this way.

#keyidea[
  A workgroup is the largest group of invocations that can cooperate. Design an algorithm so that each workgroup does an independent piece of work, and combine the pieces in a later dispatch.
]

Each level has limits that a program must query, which the program above prints first. The specification guarantees at least 128 invocations per workgroup (`maxComputeWorkGroupInvocations`), local sizes of at least 128 × 128 × 64 (`maxComputeWorkGroupSize`, with the total still bounded by the first limit), 65,535 workgroups in each dimension of a dispatch (`maxComputeWorkGroupCount`) and 16 KiB of shared memory per workgroup (`maxComputeSharedMemorySize`). Most desktop GPUs allow 1024 invocations and 32 to 64 KiB.

#snippet("u2/indexing/main.cpp", "check-limits", caption: [Refusing sizes the device cannot run])

=== Subgroups

Within a workgroup, the hardware runs invocations in _subgroups_ that execute in lockstep, as Part 3 of the Handbook described. Vulkan exposes them through `VkPhysicalDeviceVulkan11Properties::subgroupSize` and, in shaders that enable `GL_KHR_shader_subgroup_basic`, through `gl_SubgroupSize`, `gl_NumSubgroups`, `gl_SubgroupID` and `gl_SubgroupInvocationID`. The subgroup size is 32 on NVIDIA and Apple GPUs; 64 on AMD's older GCN GPUs, and 32 or 64 on its RDNA GPUs, depending on the driver and the shader; and 8, 16 or 32 on Intel's, where the compiler chooses per shader. The M2 Pro reports a size of 32 and a minimum of 4.

How a workgroup's invocations are divided among subgroups is the implementation's choice. On the M2 Pro the division is linear: invocations 0 to 31 form subgroup 0, 32 to 63 subgroup 1. The program checks that this holds but does not require it, because another GPU may divide differently. Code that needs a particular arrangement must ask for it, which Chapter 2.5 shows how to do.

A workgroup whose size is not a multiple of the subgroup size wastes lanes. With a local size of 6 × 6, each workgroup has 36 invocations and occupies two subgroups of 32, the second with only four active lanes:

#console(read("/src/console/u2-indexing-partial.txt"), caption: [36 invocations need two subgroups: 28 of the 64 lanes do nothing])

#hazard(title: [Pitfall])[
  Never assume a subgroup size, the mapping of invocations to subgroups, or the order in which workgroups run. Each differs between GPUs, and a kernel that relies on what one GPU happens to do will fail on another, often silently. Query the size, use the subgroup built-ins instead of computing them, and let separate dispatches order work that must be ordered.
]

=== How a dispatch reaches the hardware

When a dispatch starts, the GPU's command processor hands workgroups to compute units. Each compute unit takes as many workgroups as its resources allow: registers, which every invocation needs, shared memory, which every workgroup needs, and a fixed number of slots for workgroups and subgroups. A workgroup stays on its compute unit until all its invocations finish, and then the unit takes another.

Two consequences matter. A dispatch must be large enough to keep every compute unit busy, with several workgroups each, or part of the GPU idles; a large GPU needs tens of thousands of invocations in flight. And very small workgroups can leave a compute unit underused even when there are many of them, because it runs out of workgroup slots before it runs out of lanes.

=== Choosing the local size

The rules of thumb follow from the hardware. Use a multiple of the subgroup size; 64 is a multiple of every common size. For one-dimensional work, 64 to 256 invocations suit most kernels; for images, 8 × 8 or 16 × 16. Go larger only for a reason, such as a tile of shared memory that a bigger workgroup can reuse. Then measure, because the best size depends on the kernel and the GPU.

Specialisation constants make the local size a parameter of the pipeline instead of the source, as Chapter 1.4 showed. The second program builds a pipeline for every power of two from 32 to the device's limit, for two kernels: SAXPY, which moves twelve bytes for every two operations, and a chain of 512 fused multiply-adds per element, which does far more arithmetic than memory traffic. It times each with `u2::timeGpu`, which records many runs with timestamps and returns the median; Chapter 2.5 explains how.

#snippet("u2/localsize/main.cpp", "sweep", caption: [One pipeline per local size, timed and checked])

Both kernels use a _grid-stride loop_: each invocation handles element `i`, then `i` plus the number of invocations in the dispatch, and so on. The loop lets a dispatch with a capped number of workgroups cover any number of elements, and makes the kernel correct for any local size.

#snippet("u2/localsize/saxpy.comp", "saxpy", caption: [SAXPY with a grid-stride loop and a specialised local size])

#console(read("/src/console/u2-localsize.txt"), caption: [The sweep on the M2 Pro, with validation off])

#fig("u2-localsize", caption: [The sweep plotted. SAXPY is limited by memory bandwidth and reaches about 180 GB/s from 64 invocations up; the chain of multiply-adds is limited by arithmetic and barely notices the local size.]) <fig-localsize>

On the M2 Pro the choice hardly matters above 32. SAXPY reaches about 180 GB/s, close to the 200 GB/s that Apple quotes for the M2 Pro's memory, and loses about a tenth with workgroups of 32. The arithmetic-bound kernel runs at about 6.4 trillion operations per second whatever the size, because each invocation has enough independent work to keep the arithmetic units busy. Discrete GPUs are often more sensitive, which Lab 2.1.3 asks you to find out on yours.

#opengl[
  OpenGL 4.3 compute shaders use the same built-in variables and the same `layout(local_size_x = 64) in;` declaration, and `glDispatchCompute` takes the same three counts. The local size is fixed in the source; varying it needs the `ARB_compute_variable_group_size` extension, where Vulkan uses specialisation constants. Subgroup operations reached OpenGL only through the `GL_KHR_shader_subgroup` extension, which macOS does not have.
]

#reading(
  [The Vulkan specification, chapter "Dispatching Commands", and the descriptions of the compute built-ins in "Built-In Variables".],
  [The Vulkan Guide, "Compute Shaders" and "Subgroups".],
  [Hwu, Kirk and El Hajj, _Programming Massively Parallel Processors_, chapters 3 and 4, on the CUDA equivalents: grids, blocks and warps.],
)

== Labs

#lab([Map a dispatch], goal: [Predict how invocations are placed, then check.], time: [1 hour], code: "code/u2/indexing")[
  + Before running anything, draw the workgroup and subgroup pictures you expect for `--groups 3,2 --local 16,4` on your GPU.
  + Run `build/bin/u2_indexing --groups 3,2 --local 16,4` and compare.
  + Run it with `--local 6,6`, and with a local size of your choice that leaves more than half of the lanes idle.
  #done-when(
    [Your predictions match the output, or you can explain each difference.],
    [For each local size you have the number of subgroups per workgroup and the fraction of lanes in use.],
  )
  #evidence([The predictions, the outputs and the fractions.])
]

#lab([Three dimensions], goal: [Extend the program to three-dimensional dispatches.], time: [1.5 hours], code: "code/u2/indexing")[
  + Add `local_size_z_id = 2` to the shader and a third component to each `uvec2` in the record, and update the C++ mirror and its `static_assert`.
  + Accept three numbers in `--groups` and `--local`, and check the three-dimensional identities, including `gl_LocalInvocationIndex = z·X·Y + y·X + x`.
  + Run with `--groups 2,2,2 --local 4,4,4`.
  #done-when(
    [Every identity holds in three dimensions, with validation on.],
    [Your record's size and offsets are checked at compile time and match `std430`.],
  )
  #evidence([The changed record and the output.])
]

#lab([Sweep the local size on your GPU], goal: [Find out how sensitive your GPU is to the local size.], time: [1 hour], code: "code/u2/localsize")[
  + Run `VKF_VALIDATION=0 build/bin/u2_localsize` three times and plot both throughputs against the local size.
  + Look up your GPU's memory bandwidth in its specification and compare it with SAXPY's best.
  + Run again with `--n 65536` and explain how the results change.
  #done-when(
    [You have both plots from three runs, with the spread.],
    [You can state what fraction of your GPU's quoted bandwidth SAXPY reaches, and why the small problem behaves differently.],
  )
  #evidence([The plots and two paragraphs of explanation.])
]

#lab([Exceed the limits], goal: [See what the limits protect against.], time: [45 minutes], code: "code/u2/indexing")[
  + Ask for a local size larger than your device's `maxComputeWorkGroupInvocations` and record the program's refusal.
  + Remove the call to `checkLimits`, run again with validation on, and record which call fails and what the validation layer says.
  #done-when(
    [You have recorded both outcomes and the limit each concerns.],
    [You can say what the specification promises about a program that exceeds the limit with validation off.],
  )
  #evidence([The messages, and one sentence on the guarantee.])
]

#problems(
  [A 75 × 40 image is processed with 16 × 16 workgroups. How many workgroups does the dispatch need, and how many invocations have no pixel? What must the shader do about them?],
  [Explain why a workgroup must not wait for a flag that another workgroup of the same dispatch sets. Describe a GPU and a dispatch on which such a kernel never finishes.],
  [A GPU has 40 compute units, each able to hold 32 subgroups of 32 invocations. How many invocations can be resident at once? What fraction of that does a dispatch of 8192 invocations use, and why does that matter for a memory-bound kernel?],
  [From the M2 Pro's results, choose a local size for SAXPY there. What would you measure before using the same size on a discrete GPU?],
  [Write `gl_LocalInvocationIndex` for a local size of X × Y × Z, and its inverse: `gl_LocalInvocationID` from the index.],
)

#checklist(
  [I can relate every compute built-in to the others, and compute dispatch sizes for any problem.],
  [I can state what workgroups and subgroups guarantee and what they do not.],
  [I can explain how workgroups are distributed to compute units, and what that implies for dispatch and workgroup sizes.],
  [I can choose a local size, make it a specialisation constant, and measure the choice.],
  [Lab 2.1.1–2.1.4 done-when criteria all hold, with evidence filed.],
)
