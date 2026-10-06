#import "../lib/template.typ": *

= Validation, debugging and a helper layer <ch-validation>

#chapter-meta(
  time: [5 hours],
  builds: [Six deliberately broken programs read through their messages; named objects; a capture of a compute dispatch; a shader that prints; and a small RAII layer of your own, compared with `vkf`, the helper library that Units 2 to 4 use.],
  needs: [Chapter 1.5. RenderDoc on Windows and Linux, or Xcode on macOS.],
)

#why[
  SAXPY took about two hundred lines, and a mistake in almost any of them would have produced no error at all: Vulkan does not check your calls, and the GPU usually computes something plausible. This chapter is about the tools that find such mistakes, and about how to read what they say. It ends by wrapping the bookkeeping of Unit 1 in a small set of C++ helpers, so that from Unit 2 onwards the code says what it computes, while every Vulkan call it makes remains one you have written by hand.
]

#skip-test(
  rule: [If all four are easy, skim the core ideas and do Labs 1.6.1 and 1.6.4.],
  [A message cites `VUID-vkCmdDispatch-None-08600`. What is a VUID, and where do you find the rule it names?],
  [Name three kinds of mistake that the validation layer does not find in its default configuration.],
  [What does `vkSetDebugUtilsObjectNameEXT` change in a validation message, and in a capture?],
  [In what order must Vulkan objects be destroyed, and how can C++ destructors guarantee it?],
)

== Core ideas

=== What the validation layer checks

`VK_LAYER_KHRONOS_validation` intercepts every Vulkan call and checks it against the specification's _valid usage_ rules: thousands of statements of the form "parameter X must be Y". Its checks fall into groups that can be switched on and off separately:

- _Core validation_ checks parameters, object state and the state recorded in command buffers: that descriptors match their layouts, that buffers have the usage flags their uses require, that a pipeline's layout matches the sets bound for it. _Object lifetime_ checks catch handles used after destruction and objects still alive when their parent is destroyed. Both are on by default.
- _Thread safety_ checks detect two threads using an externally synchronised object at once. The version of the layer used for this course disables them by default.
- _Synchronisation validation_ (`validate_sync`) tracks every read and write of every resource and reports hazards that lack a barrier. It is off by default; Unit 1's programs and `vkf` turn it on.
- _GPU-assisted validation_ (`gpuav_enable`) instruments your shaders so that, at run time on the GPU, out-of-bounds descriptor indexing, out-of-bounds accesses through buffer device addresses and invalid indirect parameters are reported. It is off by default and slow. It does not work through MoltenVK at the time of writing: Metal fails to compile the instrumented shaders.
- _Debug printf_ (`printf_enable`) lets shaders print, as described below.
- _Best practices_ (`validate_best_practices`) warns about usage that is valid but likely slow, with optional checks for particular vendors.

A program can configure the layer in three ways. It can do so in code, through `VK_EXT_layer_settings`, as Chapter 1.1's instance creation does. Environment variables override that: each setting has one named `VK_LAYER_` followed by the setting's name in capitals, such as `VK_LAYER_VALIDATE_BEST_PRACTICES=1` or `VK_LAYER_PRINTF_ENABLE=1`. Finally, the SDK's _Vulkan Configurator_, `vkconfig`, can force layers and settings onto any program on the machine, which is useful for programs you cannot change.

Validation slows every API call, often several times over; synchronisation validation and GPU-assisted validation slow programs considerably more. Use them throughout development and in automated tests, and leave them out of releases and of performance measurements.

=== Reading a message

Every message has the same anatomy: a severity, the function that was called, a description of what was wrong, and a sentence that begins "The Vulkan spec states:", followed by a link that ends in a _VUID_, a valid-usage identifier. The VUID names the exact rule; searching the specification for it shows the rule in context. Here is the first of the chapter's broken programs, in which the buffer was created for transfers only and then written into a storage-buffer descriptor:

#snippet("u1/broken/main.cpp", "usage-bug", caption: [The usage bug: a storage buffer created without `VK_BUFFER_USAGE_STORAGE_BUFFER_BIT`])

#console(read("/src/console/u1-broken-usage.txt"), caption: [The message names the call, the descriptor, the flag the buffer lacks and the rule it breaks])

The program's own last line is the most instructive part of the output. The values were still multiplied correctly: this GPU did not care about the missing usage flag. Another GPU might place the buffer in memory a shader cannot reach, compress it in a format the shader cannot read, or fail in some other way. Invalid usage is undefined behaviour, and "it works here" carries no information.

=== Six bugs

`u1_broken` doubles an array of floats twice, with two dispatches. Its `--bug` option introduces one of six mistakes, each a line or two away from the correct program:

#tbl(columns: (auto, 1fr, auto), header: ([Option], [Mistake and what reports it], [Outcome on the M2 Pro]),
  [`usage`], [Buffer created without storage usage; core validation at `vkUpdateDescriptorSets`.], [correct],
  [`descriptor-type`], [A uniform-buffer descriptor written into a storage-buffer binding; two core validation errors.], [correct],
  [`push-range`], [Eight bytes pushed into a four-byte push constant range; core validation at `vkCmdPushConstants`.], [correct],
  [`leak`], [The buffer and its memory not destroyed before the device; object lifetime validation.], [correct],
  [`barrier`], [No barrier between the two dispatches; synchronisation validation only.], [correct],
  [`unbound`], [Dispatch with no descriptor set bound; core validation at `vkCmdDispatch`.], [crash],
)

Five of the six produced the right numbers. The missing barrier is the most dangerous kind: only synchronisation validation sees it, and its consequences depend on timing.

#snippet("u1/broken/main.cpp", "barrier-bug", caption: [The barrier that `--bug barrier` leaves out])

#console(read("/src/console/u1-broken-barrier.txt"), caption: [A write-after-write hazard between two dispatches, found by synchronisation validation])

The message names the hazard (`WRITE_AFTER_WRITE`), the buffer, the descriptor it was reached through, the pipeline, and the stage and access that the missing barrier needed to connect. The buffer and the pipeline appear as `[values]` and `[double the values]`, names the program gave them (see below), which is what makes such a message quick to act on.

The sixth bug shows what the layer's messages are worth. The driver is entitled to assume valid usage, and here it did: after reporting the error twice, once for each dispatch, the program crashed inside the driver.

#console(read("/src/console/u1-broken-unbound.txt"), caption: [A dispatch with no descriptor set bound: the message, then a crash])

#keyidea[
  Treat every validation error as a crash that happened to be survived. The programs in this course fail when the layer reports an error, and so should yours, in every test run.
]

=== Names and labels

`VK_EXT_debug_utils` lets a program attach names to objects and labels to regions of a command buffer. Names appear in validation messages, in capture tools and in vendors' crash reports. Labels group commands in a capture, so that a frame of a thousand commands reads as a dozen named passes.

#snippet("u1/broken/main.cpp", "name", caption: [Naming an object, when the extension is available])

The function is an extension function, looked up with `vkGetInstanceProcAddr` after the instance is created. Labels work the same way, through `vkCmdBeginDebugUtilsLabelEXT` and `vkCmdEndDebugUtilsLabelEXT`. Neither costs anything that matters, so name every object you create.

=== Capturing a dispatch

A _capture_ records every call a program makes, with the contents of its buffers and images, so that you can inspect the state of the GPU before and after each command at leisure. RenderDoc, which is free and open source, captures Vulkan programs on Windows and Linux. It normally captures a frame between two presents; a compute program without a window marks the region to capture with RenderDoc's in-application API, by calling `StartFrameCapture` and `EndFrameCapture` from `renderdoc_app.h`. NVIDIA Nsight Graphics, AMD's Radeon GPU Profiler and Intel's Graphics Performance Analyzers add hardware counters, which Chapter 2.5 uses.

On macOS, MoltenVK can write a capture of the Metal commands it generates, which Xcode opens:

```sh
METAL_CAPTURE_ENABLED=1 MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=1 \
  MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE=saxpy.gputrace ./build/bin/u1_saxpy
```

The capture shows Metal's view of your program, including the Metal shader that MoltenVK generated from your SPIR-V, which is also where a name collision of the kind described in Chapter 1.4 becomes visible.

=== Printing from shaders

The `GL_EXT_debug_printf` extension adds `debugPrintfEXT` to GLSL. With debug printf enabled in the validation layer, the layer rewrites the shader so that each call writes its arguments into a buffer, and prints the results after the work completes:

```glsl
#extension GL_EXT_debug_printf : enable
if (i < 4) debugPrintfEXT("x[%u] = %f\n", i, x[i]);
```

Enable it with `VK_LAYER_PRINTF_ENABLE=1`, and add `VK_LAYER_PRINTF_TO_STDOUT=1` to print to the terminal instead of through the debug messenger. To instrument the shader, the layer enables device features it needs, such as `bufferDeviceAddress`, and prints a warning that lists them. Without the layer, drivers ignore the call. Printing from thousands of invocations produces thousands of lines, so guard every call with a condition.

=== A helper layer

Most of SAXPY is bookkeeping: filling structures, checking results, and destroying everything in the right order. The order matters because every object must be destroyed before the object it was created from, and the device and the instance last. C++ destroys local objects in reverse order of declaration, so a wrapper that destroys its handle in its destructor gets the order right for free, provided the device's owner is declared first.

#snippet("common/include/vkf/handles.hpp", "unique", caption: [`vkf::Unique`: a move-only owner of one Vulkan handle])

The course's helper library, `vkf`, is built from wrappers like this, and from functions that perform the steps of Unit 1 in one call each. Its central object is `vkf::Context`, which performs everything Chapter 1.1 did: instance, validation with synchronisation validation, the messenger, the device, its queues and a command pool. Its options say what a program needs.

#snippet("common/include/vkf/context.hpp", "options", caption: [What a program asks of the context])

Memory is requested by intent instead of by flags, and `vkf` chooses the memory type as Chapter 1.2 described.

#snippet("common/include/vkf/memory.hpp", "memory-use", caption: [Four ways a buffer can be used, each mapped to memory flags])

@tbl-vkf maps each chapter of this unit to the `vkf` functions that replace its code.

#figure(
  tbl(columns: (auto, 1fr, 1.2fr), header: ([Chapter], [You wrote], [`vkf` provides]),
    [1.1], [instance, layers, messenger, device, queues], [`Context`, `ContextOptions`, `mainQueue()`, `computeQueue()`, `transferQueue()`, `features()`, `properties()`],
    [1.2], [memory types, buffers, images, mapping, flushing], [`createBuffer` with `MemoryUse`, `createImage`, `upload`, `download`, `Buffer::flush`, `Buffer::invalidate`],
    [1.3], [pools, command buffers, submission, fences, barriers], [`submitNow`, `createCommandPool`, `submit`, `createFence`, `memoryBarrier`, `bufferBarrier`, `imageBarrier`],
    [1.4], [modules, layouts, pipelines, specialisation], [`loadShader`, `shaderPath`, `createPipelineLayout`, `createComputePipeline`, `Specialization`],
    [1.5], [set layouts, pools, sets, updates], [`DescriptorSetLayoutBuilder`, `DescriptorPool`, `DescriptorWriter`],
    [1.6], [names, labels, counting errors], [`Context::name`, `beginLabel`, `endLabel`, `run`; and `GpuTimer` for Unit 2],
  ),
  caption: [What each chapter of Unit 1 becomes in `vkf`],
  kind: table,
) <tbl-vkf>

`vkf`'s self-test shows the result. The part below creates two buffers, uploads the input, builds a pipeline with two specialisation constants, writes a descriptor set and runs a dispatch with timestamps around it: SAXPY's two hundred lines in fifty.

#snippet("common/test/selftest.cpp", "scale", caption: [A complete compute dispatch with `vkf`])

Every `vkf` program wraps its body in `vkf::run`, which catches exceptions, prints them, and returns a non-zero exit status if the body threw or if the validation layer reported any error. A program that runs cleanly therefore proves that validation was silent.

`vkf` is deliberately thin. It never hides a barrier or a submission: the functions that record them, such as `submitNow`, `upload` and the barrier helpers, say so in their names. Each of its functions does one thing that Unit 1 did by hand, so you can always read through it to the Vulkan calls underneath. It also makes simplifications that real programs should not: one allocation per buffer instead of sub-allocation, and `submitNow` and `upload`, which wait for the GPU before returning. Larger projects build on established libraries instead: Vulkan-Hpp, whose `vk::raii` namespace provides wrappers like `Unique` for every object; the Vulkan Memory Allocator; `vk-bootstrap` for instance and device creation; and `volk`, which loads Vulkan functions without going through the loader's dispatch.

#opengl[
  An OpenGL error sets a flag that `glGetError` returns later, with a code such as `GL_INVALID_OPERATION` and no indication of which call or which rule; `KHR_debug` adds a callback with a message chosen by the driver. Capture tools such as RenderDoc support OpenGL too. What OpenGL has no equivalent of is synchronisation validation, because its driver inserted the barriers itself.
]

#reading(
  [The validation layer's documentation in the Vulkan-ValidationLayers repository on GitHub (`docs/` directory), in particular the pages on synchronisation validation, GPU-assisted validation and debug printf.],
  [The Vulkan Guide, "Vulkan Validation Overview" and "Development Tools".],
  [RenderDoc's documentation, "In-application API", for capturing programs without a window.],
)

== Labs

#lab([Read six broken programs], goal: [Learn to go from a message to a fix quickly.], time: [1.5 hours], code: "code/u1/broken")[
  + Run `build/bin/u1_broken --bug` with each of the six mistakes.
  + For each, record the VUID or hazard, explain the rule in your own words after reading it in the specification, and say whether the result was correct.
  + Fix each mistake in a copy of the program and confirm that the run is clean.
  #done-when(
    [Your table has six rows, each with the rule, the fix and the outcome.],
    [You can explain why the `unbound` case crashed and the others did not.],
  )
  #evidence([The table, and the crash explained in two sentences.])
]

#lab([Print from a shader], goal: [Look inside a running shader.], time: [45 minutes], code: "code/u1/saxpy")[
  + Add the two lines of debug printf shown above to `saxpy.comp`, printing `x[i]` and `y[i]` before the update for the first four invocations.
  + Run with `VK_LAYER_PRINTF_ENABLE=1` and `VK_LAYER_PRINTF_TO_STDOUT=1`, and record the output and the warnings the layer prints at device creation.
  + Run again with `VK_LAYER_GPUAV_ENABLE=1` instead, and compare the run time with validation in its default configuration. On macOS, record the error that pipeline creation reports instead.
  #done-when(
    [Your notebook has the printed values for all ten dispatches and agrees with the CPU's arithmetic.],
    [You have the run times for default validation and debug printf, and for GPU-assisted validation or the error it produces on your platform.],
  )
  #evidence([The printed lines, the features the layer forced on, and the three run times.])
]

#lab([Capture a dispatch], goal: [Inspect buffers before and after a dispatch in a capture tool.], time: [1 hour], code: "code/u1/saxpy")[
  + Name `x`, `y` and the pipeline, and wrap the dispatches in a label.
  + Capture one run: with RenderDoc's in-application API on Windows or Linux, or with the MoltenVK settings above on macOS.
  + In the capture, find the first dispatch, and the contents of `y` before and after it.
  #done-when(
    [Your capture shows the names and the label.],
    [You have recorded three values of `y` before and after the first dispatch, and they agree with the CPU's arithmetic.],
  )
  #evidence([A screenshot of the dispatch in the capture, with the buffer contents.])
]

#lab([Your own RAII layer], goal: [Design the helpers yourself before using `vkf`.], time: [2 hours], code: "code/u1/saxpy")[
  + Write a move-only owner template for device-level handles and an owner for a buffer with its memory, without looking at `vkf`.
  + Rewrite SAXPY with them. Make every object an owner, and make the order of declarations guarantee the order of destruction.
  + Compare your design with `vkf/handles.hpp` and `vkf/memory.hpp`, and write down two differences and which design you prefer.
  #done-when(
    [Your SAXPY passes with validation on and no leaks reported, in fewer than 120 lines.],
    [Moving the device's owner after the buffers makes object lifetime validation report the error, which you have recorded.],
  )
  #evidence([Your helpers, the new SAXPY, and the comparison.])
]

#problems(
  [Validation is on, synchronisation validation is on, and both are silent. Name three classes of bug that may remain, and a tool or technique that would find each.],
  [Why do the validation layers offer settings at all, instead of running every check every time?],
  [In the `unbound` case the driver crashed after the message. Why is it allowed to, and what does that imply for code that "works with validation errors"?],
  [A `vkf::Unique<VkBuffer>` is declared before the `vkf::Context` whose device created the buffer. What happens at the end of the scope, and what does the validation layer report?],
  [`vkf::createBuffer` makes one allocation per buffer. Using Chapter 1.2, explain when that would fail on a real device, and how you would change `vkf` to avoid it without changing its interface.],
)

#checklist(
  [I can configure the validation layer in code, with environment variables and with `vkconfig`, and say what each group of checks finds.],
  [I can read a validation message, find its rule by VUID, and fix the cause.],
  [I can name objects, label commands, capture a dispatch and print from a shader.],
  [I can explain how `vkf` maps to the Vulkan calls of Chapters 1.1 to 1.5.],
  [Lab 1.6.1–1.6.4 done-when criteria all hold, with evidence filed.],
)
