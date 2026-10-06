#import "lib/template.typ": *
#show: course-doc.with(unit: "2", title: "Compute Shaders", short: "Compute Shaders",
  subtitle: "The execution model, shader memory, parallel patterns, performance and a ray tracer",
  chapters: ("The compute execution model", "Memory in shaders", "Parallel patterns", "Images and image processing", "Measuring and tuning", "Dispatch at scale", "A ray tracer in a compute shader"))
#contents()

#about-unit(unit: "2",
  intro: [Unit 2 is about the GPU as a parallel computer. It explains how a dispatch becomes workgroups and subgroups on the hardware, how shaders use memory and why access patterns decide their speed, and how the classic parallel patterns, reduction, scan, compaction, histograms and sorting, are built and made fast. It processes images through storage images and samplers, measures kernels against the hardware's limits, handles problems too large for one dispatch, and ends with a ray tracer written entirely in compute shaders. From this unit on, programs use the `vkf` helper library from Chapter 1.6.],
  rows: (
    ([2.1], [A map of invocations to workgroups and subgroups; a sweep of local sizes], [5]),
    ([2.2], [Three transposes, a privatised histogram, two races observed and fixed], [6]),
    ([2.3], [Reductions at the bandwidth limit, scans, compaction and a stable radix sort], [7]),
    ([2.4], [A tiled separable blur, a sampled downscale, divergence measured in a fractal], [6]),
    ([2.5], [A bandwidth benchmark, a measured roofline, and autotuning by specialisation], [6]),
    ([2.6], [An N-body simulation with indirect dispatch and buffer device addresses], [6]),
    ([2.7], [A path tracer with a bounding volume hierarchy, checked and measured], [8]),
  ),
  before: [Finish Unit 1, and run `vkf_selftest`. Read the Handbook's part on how GPUs work if you have not.],
  needs: [The same machine and tools as Unit 1. A discrete GPU makes the measurements of Chapters 2.2 and 2.5 more instructive, but every lab runs on integrated graphics.],
)

#include "u2/ch1-execution.typ"
#include "u2/ch2-memory.typ"
#include "u2/ch3-patterns.typ"
#include "u2/ch4-images.typ"
#include "u2/ch5-tuning.typ"
#include "u2/ch6-scale.typ"
#include "u2/ch7-raytrace.typ"

#signoff(unit: "2",
  chapters: ("The compute execution model", "Memory in shaders", "Parallel patterns", "Images and image processing", "Measuring and tuning", "Dispatch at scale", "A ray tracer in a compute shader"),
  review: (
    [Explain, with a drawing of your own, how a dispatch becomes workgroups, subgroups and invocations, and where shared memory and `barrier()` act.],
    [Place each of your Unit 2 kernels on your GPU's roofline from your Lab 2.5 measurements, and say for each what limits it.],
    [Write a multi-level scan from memory, with its barriers, and explain how it extends to any size.],
    [Explain why the N-body simulation uses indirect dispatch and device addresses, and what the barrier between the preparation kernel and the dispatch must name.],
    [Explain what each of the ray tracer's three checks proves, and which bug each would miss.],
  ),
)
