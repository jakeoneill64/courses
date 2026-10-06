#import "../lib/template.typ": *

= The course <h-course>

Vulkan Foundations teaches GPU programming with Vulkan from first principles, to programmers who know C++ well and have never used Vulkan. It treats the GPU as what it is, a separate computer with its own memory, its own queues of work and its own timeline, and Vulkan as the explicit interface to it. Compute comes first, because compute shaders show the GPU's execution model without the machinery of rendering, and synchronisation gets a unit of its own, because it is where most Vulkan programs go wrong. Graphics follows, built on everything before it. Throughout, the course compares Vulkan with OpenGL, so that readers who know OpenGL can map what they know and readers who do not can see why Vulkan is shaped the way it is.

The course is practical. Every chapter has labs with measurable done-when criteria, every listing in these volumes is taken from companion code that compiles, runs and checks its own results, and every console listing is real output from those programs. All of it was run on an Apple M2 Pro through MoltenVK with the validation layers on, and the text says wherever other hardware behaves differently.

== What you will have built

- *A Vulkan compute program with nothing hidden.* SAXPY written against the raw C API, from the instance to the dispatch and the check of every element, and six broken versions of it diagnosed from their validation messages.
- *A library of parallel primitives.* Reductions, prefix sums, stream compaction, histograms and a radix sort, each measured against your GPU's memory bandwidth, and image filters, an N-body simulation and a tuning harness built on them.
- *A ray tracer in a compute shader.* A Monte Carlo path tracer with spheres, triangle meshes and a bounding volume hierarchy, diffuse, metallic and glass materials, and progressive accumulation, verified against a CPU reference and measured in rays per second.
- *A synchronisation toolkit.* A catalogue of hazards and the barriers that prevent them, each checked by synchronisation validation; host and device pipelines on timeline semaphores; async compute with queue ownership transfers; frames in flight; and a render graph that derives every barrier and layout transition, aliases transient memory, and schedules work across queues.
- *A renderer.* The graphics pipeline from a triangle to a textured, depth-tested mesh, presentation through a swapchain, and a million particles simulated in compute and culled on the GPU.
- *A port from OpenGL.* The same scene in OpenGL and in Vulkan, with the CPU cost of each measured.
- *A GPU-driven sandbox.* The capstone: simulation, culling, indirect drawing, async compute and frames in flight, organised by your render graph and timed pass by pass, with synchronisation validation silent.

== Four units

#tbl(columns: (auto, 1fr, auto), header: ([Unit], [Chapters], [Hours]), align: (left, left, right),
  [*1* The Explicit API], [Instances, devices and queues; memory, buffers and images; commands and submission; shaders, SPIR-V and pipelines; descriptors and your first dispatch; validation, debugging and a helper layer], [32],
  [*2* Compute Shaders], [The compute execution model; memory in shaders; parallel patterns; images and image processing; measuring and tuning; dispatch at scale; a ray tracer in a compute shader], [44],
  [*3* Synchronisation], [Why synchronisation is your job; the dependency model; pipeline barriers in practice; fences, semaphores and events; queues and async compute; frames in flight; finding synchronisation bugs; render graphs], [45],
  [*4* Rendering and the Whole Frame], [The graphics pipeline; presentation; drawing with data; compute meets graphics; from OpenGL to Vulkan; scaling up; capstone: a GPU-driven sandbox], [47],
)

The hours are study time: reading, labs, problem sets and the checklist. The whole course is about 170 hours; at eight to ten hours a week it takes about five months. Hours are a guide; done-when criteria are the contract.

#fig("h-map", caption: [The course map. Each unit builds on the units before it, and Units 2 to 4 each close with a project that draws the unit together.]) <fig-map>

== Four threads

Four threads run through the units, and most chapters advance more than one.

- *The execution model.* How the GPU runs work: queues and command buffers (Chapters 1.3 and 3.5), invocations, workgroups and subgroups (2.1), memory in shaders (2.2), occupancy and bandwidth (2.5), and the graphics pipeline as a sequence of programmable and fixed stages (4.1).
- *Synchronisation.* The first barrier (1.3), barriers between dispatches (1.5 and Unit 2), the dependency model (3.2), every primitive Vulkan offers (3.3 to 3.6), the tools that find mistakes (1.6 and 3.7), and finally a render graph that writes the barriers for you (3.8), which the capstone uses (4.7).
- *OpenGL.* Every chapter has "Coming from OpenGL" notes that map its ideas to OpenGL's. Part 4 of this Handbook is the big picture, and Chapter 4.5 ports a program and measures the difference.
- *Measurement.* Timestamps from Unit 2 on, bandwidth and the roofline (2.5), overlap on queues (3.5), frame pacing (3.6), CPU recording costs (4.5 and 4.6), and the per-pass timings of the capstone.

== Who the course is for

The course assumes that you write C++ fluently: classes and RAII, move semantics, lambdas and templates at the level of the standard library, and the build tools of your platform. It uses C++20, mostly for designated initialisers, which make Vulkan's structures readable. It assumes the linear algebra of vectors and 4 × 4 matrices that 3D graphics uses, which Unit 4 and the ray tracer need, and nothing more advanced.

It assumes no knowledge of Vulkan, GPUs or graphics. Readers who know OpenGL, CUDA or another GPU API will move faster through the early chapters and should use the skip tests at the start of each chapter to decide what to skim.

== The volumes and the code

The course is five volumes: this Handbook and four units. The companion code is a single CMake project with one directory per lab project, `code/u1/devices` to `code/u4/sandbox`, and a small helper library, `vkf`, that Unit 1 builds up to and the other units use. It arrives as an archive beside the volumes; Part 5 explains how to build it.

== Conventions

- *Versions.* The course targets Vulkan 1.3 core. It uses synchronization2 and dynamic rendering, both core in 1.3, and avoids extensions unless a chapter is about one. Shaders are GLSL 4.60 compiled to SPIR-V 1.6.
- *Spelling.* British spelling in prose, API names verbatim: synchronisation in the text, `synchronization2` in code.
- *Numbering.* Chapters are numbered unit.chapter, so Chapter 3.2 is the second chapter of Unit 3. Labs are numbered unit.chapter.lab, and figures and tables unit.chapter.number.
- *Listings.* Each listing names the file it comes from, relative to the code folder, and shows a region marked in that file. Console listings begin with the command that produced them, run from the code folder. Long validation messages are wrapped to fit the page, and the values of object handles, which change from run to run, are shown as `0x...`.
- *Time* is in hours. Measurements name the device they were made on.
- *Platform.* "The M2 Pro" is the Apple M2 Pro on which this course's code was run. Commands assume a POSIX shell; on Windows, use the equivalent in PowerShell or a Developer Command Prompt.
