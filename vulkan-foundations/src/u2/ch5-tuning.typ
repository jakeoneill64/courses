#import "../lib/template.typ": *

= Measuring and tuning <ch-tuning>

#chapter-meta(
  time: [6 hours],
  builds: [GPU timing with timestamp queries; a benchmark of your device's memory bandwidth, with copies, vector loads and strided reads; a roofline measured point by point; and an autotuner that builds thirty variants of the reduction with specialisation constants and a pipeline cache, and picks the fastest.],
  needs: [Chapters 2.1 to 2.4.],
)

#why[
  Every chapter of this unit has reported times, and every claim about speed has rested on them. This chapter explains how they are taken, and how to turn them into understanding: what the hardware can do at best, how close a kernel comes, and what limits it. It measures your GPU's real bandwidth and arithmetic peak instead of the vendor's, draws its roofline from measurements, and uses specialisation constants to let the GPU tell you which configuration of a kernel suits it best. These are the habits that separate tuning from guessing.
]

#skip-test(
  rule: [If all four are easy, read the section on autotuning and do Labs 2.5.1 and 2.5.3.],
  [What does `vkCmdWriteTimestamp2` record, and how do you convert the values it returns to milliseconds?],
  [Why does a benchmark need a warm-up, and why report the median rather than the mean?],
  [A kernel performs 2 FLOP per byte and reaches 380 GFLOP/s on a GPU with 190 GB/s of bandwidth and 6 TFLOP/s of arithmetic. Is it memory-bound or compute-bound, and how far is it from its limit?],
  [Why tune with specialisation constants rather than by editing the shader?],
)

== Core ideas

=== Timestamps

A _timestamp query_ records the GPU's clock at a point in a command buffer. Queries live in a `VkQueryPool` of type `VK_QUERY_TYPE_TIMESTAMP`. A program resets the queries it will use, writes timestamps with `vkCmdWriteTimestamp2`, and after the work completes reads them with `vkGetQueryPoolResults`. The values are counts of ticks; `timestampPeriod`, a device limit, gives the nanoseconds per tick, and each queue family's `timestampValidBits` says how many bits are meaningful, zero meaning that the family cannot write timestamps at all. `vkf::GpuTimer` wraps these steps:

#snippet("common/src/timing.cpp", "query-pool", caption: [A pool of timestamp queries, after checking that the queue supports them])

#snippet("common/src/timing.cpp", "stamp", caption: [Resetting the pool and writing timestamps in a command buffer])

#snippet("common/src/timing.cpp", "read", caption: [Reading the ticks and converting them to milliseconds])

A timestamp is written when every earlier command in submission order has completed the stage it names. With `VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT`, the default here, that means when everything before it has finished, which makes the difference between two timestamps the time the work between them took on the device. Timestamps measure only the GPU; time that a submission spends waiting in the driver or the queue is not included, which is what makes them more useful than wall-clock time for kernels.

=== Measuring well

A single timing is not a measurement. GPUs raise their clocks over the first milliseconds of load and lower them when idle; the first run of a pipeline may pay for compilation or for page faults; other programs share the GPU. Unit 2's programs time every kernel with `u2::timeGpu`, which first runs the kernel for about 25 ms to warm the GPU up, then runs it repeatedly with a timestamp before and after each run and a full barrier between runs, so that runs cannot overlap, and returns the median:

#snippet("u2/shared/u2.hpp", "time-gpu", caption: [Warm-up, repeated runs and the median])

The median ignores the occasional run that something else interrupted, which would distort a mean. Lab 2.5.2 asks you to look at the whole distribution.

=== Bandwidth

The first question about any kernel that reads and writes memory is how fast memory can be read and written at all. `u2_bandwidth` measures three ways of copying 128 MiB: `vkCmdCopyBuffer`, which uses whatever path the driver chooses; a shader that copies one float per iteration; and a shader that copies a `vec4`, sixteen bytes, per iteration.

#snippet("u2/bandwidth/copy_vec4.comp", "copy-vec4", caption: [A copy with sixteen-byte loads and stores])

#snippet("u2/bandwidth/main.cpp", "copies", caption: [Timing the three copies and checking each result])

The program then reads with a stride: neighbouring invocations read floats a fixed distance apart, so that the reads of a subgroup are scattered across memory, while the output is still written contiguously.

#snippet("u2/bandwidth/strided.comp", "strided", caption: [Reads a stride apart, writes contiguous])

#console(read("/src/console/u2-bandwidth.txt"), caption: [Copies, strided reads and the roofline on the M2 Pro, with validation off])

The M2 Pro's memory reaches 191 GB/s through `vkCmdCopyBuffer`, 95% of the 200 GB/s Apple quotes, and a little less through shaders. Strided reads fall quickly (@fig-strided). Memory is read in lines of many bytes, so once neighbouring invocations read floats sixteen or more apart, each four-byte read costs a whole line, and the bandwidth that reaches the kernel falls to about a seventh.

#fig("u2-strided", caption: [Bandwidth against the stride between neighbouring invocations' reads, on the M2 Pro.]) <fig-strided>

=== The roofline, measured

Part 3 of the Handbook drew a roofline from an illustrative GPU's specification. The program measures one. Its kernel reads a `vec4`, applies `k` fused multiply-adds to it and writes the result, so that `k`, a specialisation constant, sets the arithmetic intensity: each element moves eight bytes and performs 2k operations.

#snippet("u2/bandwidth/roofline.comp", "roofline", caption: [A kernel whose arithmetic intensity is set by a specialisation constant])

#snippet("u2/bandwidth/main.cpp", "roofline-point", caption: [One point of the roofline])

#fig("u2-roofline", caption: [The M2 Pro's roofline, measured. Up to 32 operations per byte, the kernel runs at the memory's bandwidth; beyond, at about 6.2 trillion operations per second.]) <fig-roofline>

The measured points follow the two bounds closely, and the ridge, where the arithmetic catches up with the memory, falls at about 33 operations per byte. Most kernels of this unit so far lie far to its left: SAXPY at 0.17, the reduction at 0.25, the separable blur at about 4. For such kernels the arithmetic is nearly free, and the only way to speed them up is to move fewer bytes, or to move them more efficiently, which is what tiling, coalescing and coarsening did. The Mandelbrot renderer, which reads nothing and writes a few bytes per pixel after hundreds of iterations, lies far to the right, as do Chapter 2.6's N-body simulation and Chapter 2.7's ray tracer.

#keyidea[
  Before optimising a kernel, place it on your GPU's roofline. Left of the ridge, count bytes; right of it, count operations. A kernel close to its bound is finished, whatever its absolute speed.
]

=== Occupancy, registers and subgroups

Between the bounds lie the limits of the execution model. A kernel can fall short of the bandwidth bound because too few subgroups are resident to hide memory latency, the _occupancy_ of Part 3 of the Handbook, which registers and shared memory per workgroup limit; because its accesses are not coalesced; or because its workgroups synchronise too often. Vendor profilers show occupancy directly: NVIDIA Nsight Graphics, AMD's Radeon GPU Profiler and Xcode's Metal debugger all report the resident subgroups, the registers per invocation and the memory throughput of each dispatch. Vulkan does not expose them, so a portable program measures effects instead, as the rest of this chapter does.

The subgroup size is one more parameter. Vulkan 1.3's `subgroupSizeControl` lets a pipeline require a particular size, within `minSubgroupSize` and `maxSubgroupSize`, for the stages listed in `requiredSubgroupSizeStages`, through a `VkPipelineShaderStageRequiredSubgroupSizeCreateInfo`; `vkf::ComputePipelineDesc::requiredSubgroupSize` passes one. On AMD's RDNA and on Intel GPUs the choice can matter. On the M2 Pro, MoltenVK lists no stages in `requiredSubgroupSizeStages`, so the size cannot be chosen, and the tuner below checks for that:

#snippet("u2/tune/main.cpp", "subgroup-sizes", caption: [The subgroup sizes worth trying, if the device lets a compute pipeline choose])

=== Autotuning

The best local size and coarsening factor for a kernel depend on the GPU, and sometimes on the problem's size. Instead of guessing, a program can try them. `u2_tune` builds the subgroup reduction of Chapter 2.3 with every combination of five local sizes and six coarsening factors, both specialisation constants, times each, checks each sum, and reports the fastest.

#snippet("u2/tune/main.cpp", "variants", caption: [The combinations to try])

#snippet("u2/tune/main.cpp", "build", caption: [One pipeline per combination, through the pipeline cache])

Thirty pipelines take time to build, so the tuner uses a pipeline cache, as Chapter 1.4 described, and reports what the cache saves:

#snippet("u2/tune/main.cpp", "cold-warm", caption: [Building every variant with an empty cache, then from its contents])

#snippet("u2/tune/main.cpp", "measure", caption: [Timing and checking every variant])

#console(read("/src/console/u2-tune.txt"), caption: [Thirty variants of the reduction on the M2 Pro, with validation off])

This run's first build was truly cold. Run the tuner again and the build with an empty cache takes only a few milliseconds as well, because Metal keeps the shaders it has compiled in a cache of its own, outside the program's control; Chapter 4.6 measures pipeline caches with that in mind.

#fig("u2-tune", caption: [The reduction's bandwidth for each combination. Coarsening matters far more than the local size: one element per invocation is slow at every size but the largest.]) <fig-tune>

The fastest variant reaches 190 GB/s, the bandwidth of a copy, with 64 invocations per workgroup and four elements each. Most combinations with two or more elements per invocation come within 10% of it, and every combination with one element is half as fast, except, on this GPU, with 1024 invocations per workgroup. A real program would run such a tuner once per device, store the winner beside its pipeline cache, and build only that variant thereafter.

#hazard(title: [Pitfall])[
  A benchmark that does not check its results measures nothing. A kernel that skips work, reads the wrong buffer or exits early can look very fast. Every timed variant in this course verifies its output, and the tuner rejects a variant whose sum is wrong, however fast it was.
]

#opengl[
  OpenGL measures GPU time with timer queries, `glQueryCounter(query, GL_TIMESTAMP)` and `glBeginQuery(GL_TIME_ELAPSED, …)`, and the same caveats about warm-up and variation apply. Tuning by specialisation has no direct equivalent: an OpenGL program would compile a separate program object for each variant, usually by editing the source text with `#define`s.
]

#reading(
  [The Vulkan specification, chapter "Queries", in particular "Timestamp Queries", and `VkPhysicalDeviceSubgroupSizeControlProperties`.],
  [Samuel Williams, Andrew Waterman and David Patterson, "Roofline: An Insightful Visual Performance Model for Multicore Architectures", _Communications of the ACM_ 52(4), 2009.],
  [Your GPU vendor's optimisation guide from the Handbook's reference library: NVIDIA's "Vulkan Dos and Don'ts", AMD's _RDNA Performance Guide_, or Apple's documentation for Metal's GPU counters.],
)

== Labs

#lab([Your GPU's roofline], goal: [Measure your device's bounds and place this unit's kernels against them.], time: [1.5 hours], code: "code/u2/bandwidth")[
  + Run `VKF_VALIDATION=0 build/bin/u2_bandwidth` three times and plot the roofline from the median of each point.
  + Compare the measured bandwidth and arithmetic peaks with your GPU's published figures.
  + Place SAXPY, the coarsened reduction and the separable blur on the plot, from their measured speeds and arithmetic intensities.
  #done-when(
    [Your plot shows both bounds and at least twelve measured points.],
    [For each of the three kernels you can say which bound limits it, and by how much it misses it.],
  )
  #evidence([The plot and the three placements.])
]

#lab([Timestamps by hand], goal: [Use timestamp queries without the helper, and see what a distribution looks like.], time: [1 hour], code: "code/u2/localsize")[
  + Write a timer of your own around one SAXPY dispatch: a query pool, a reset, two timestamps and a read, with `timestampPeriod` and `timestampValidBits` applied.
  + Time 200 runs, without warm-up, and plot the times in order and as a histogram.
  #done-when(
    [Your timer agrees with `vkf::GpuTimer` to within the run-to-run variation.],
    [Your plots show the warm-up and the spread, and you can say how many runs to discard and why the median is the right summary.],
  )
  #evidence([The code and both plots.])
]

#lab([Tune on your GPU], goal: [Find out how stable the tuner's choice is.], time: [1.5 hours], code: "code/u2/tune")[
  + Run `VKF_VALIDATION=0 build/bin/u2_tune` three times and record the winner each time.
  + Run it with `--n` set to 2#super[20] and 2#super[26].
  + If your device allows the subgroup size to be chosen, record its effect.
  #done-when(
    [You have the three winners at the default size, and the winners at the two other sizes.],
    [You can say whether the winning configuration depends on the problem's size on your GPU, and how much choosing the second-best would cost.],
  )
  #evidence([The tables and your conclusion.])
]

#lab([Look inside with a profiler], goal: [Connect the measurements to the hardware's counters.], time: [1.5 hours], code: "code/u2/reduce")[
  + Capture the reduction with your vendor's profiler, or with Xcode on macOS through MoltenVK's capture settings from Chapter 1.6.
  + Find, for the slowest and the fastest variant, the occupancy or resident subgroups, the memory throughput, and the registers per invocation where the tool reports them.
  #done-when(
    [You have the counters for both variants.],
    [You can explain the difference in speed from the counters.],
  )
  #evidence([Screenshots of the counters, annotated.])
]

#problems(
  [Timestamps are written with `VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT`. What would a timestamp at `VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT` measure instead, and why is it rarely what you want?],
  [`timestampPeriod` is 1.0 and `timestampValidBits` is 36. After how long does the counter wrap, and how does `vkf::GpuTimer` cope?],
  [The strided read at stride 32 runs at 22 GB/s. Assuming memory is read in lines of 64 bytes, what bandwidth would you predict, and why might it differ?],
  [A kernel performs 40 operations per byte. On the M2 Pro's measured roofline, what is its best possible speed? On the illustrative GPU of the Handbook?],
  [The tuner keeps the fastest variant. Name two situations in which a slightly slower variant would be the better choice.],
)

#checklist(
  [I can time GPU work with timestamp queries and report a sound measurement.],
  [I can measure my GPU's bandwidth and arithmetic peak and draw its roofline.],
  [I can place a kernel on the roofline and say what limits it.],
  [I can tune a kernel with specialisation constants and a pipeline cache, and know when not to trust the result.],
  [Lab 2.5.1–2.5.4 done-when criteria all hold, with evidence filed.],
)
