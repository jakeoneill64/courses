#import "../lib/template.typ": *

= Shaders, SPIR-V and pipelines <ch-pipelines>

#chapter-meta(
  time: [5 hours],
  builds: [A compute shader compiled offline to SPIR-V, validated and disassembled; a pipeline layout with a descriptor set and push constants; three pipelines that differ only in a specialisation constant; and a pipeline cache saved to disk and loaded again.],
  needs: [Chapter 1.3. The SDK's `glslc`, `spirv-val` and `spirv-dis`.],
)

#why[
  An OpenGL driver compiled your GLSL at run time, with its own compiler, and sometimes compiled it again when unrelated state changed. A Vulkan driver never sees GLSL. It receives SPIR-V, a binary intermediate language you produced at build time, together with a complete description of everything the shader will touch, and it compiles the result once, when you create a pipeline. Knowing what goes into a pipeline, what can vary afterwards and what cannot, and when compilation happens, is what keeps a Vulkan program free of the stalls that come from compiling shaders in the middle of a frame.
]

#skip-test(
  rule: [If all four are easy, skim the core ideas and do Labs 1.4.2 and 1.4.4.],
  [What is SPIR-V, and why does Vulkan consume it instead of GLSL?],
  [What does a pipeline layout describe, and why must it exist before the pipeline does?],
  [How does a specialisation constant differ from a push constant, and when would you use each?],
  [What does a pipeline cache store, and when does loading one from disk not help?],
)

== Core ideas

=== A compute shader in GLSL

This unit's shaders are written in GLSL 4.60 with the Vulkan rules that the `GL_KHR_vulkan_glsl` extension defines. The differences from OpenGL's GLSL are about how a shader reaches the outside world. Resources are grouped into _descriptor sets_ and named by `set` and `binding` numbers instead of by name. Small parameters arrive in a _push constant_ block. Constants that are fixed when the pipeline is created carry a `constant_id`. Loose `uniform` variables outside a block do not exist.

The shader for this chapter writes a pseudo-random pattern into a buffer. Its interface declares all three kinds of input:

#snippet("u1/pipeline/fill.comp", "interface", caption: [The shader's interface: a specialisable workgroup size, two push constants and one storage buffer])

`local_size_x_id = 0` makes the workgroup's width a specialisation constant with ID 0, set when the pipeline is created; Unit 2 explains workgroups in depth. The push constant block holds a seed and an element count. The storage buffer at set 0, binding 0 holds the output; `std430` fixes the layout rules for its members, and `writeonly` promises that the shader never reads it.

#snippet("u1/pipeline/fill.comp", "main", caption: [One invocation per element])

Each invocation handles one element, chosen by its global index. The dispatch covers whole workgroups, so when the count is not a multiple of the workgroup size the last group has invocations past the end of the data. The early return keeps them from writing outside the buffer.

=== SPIR-V

_SPIR-V_ is a binary intermediate language for shaders and compute kernels, defined by Khronos. A module is a stream of 32-bit words that starts with the magic number `0x07230203`, followed by declarations of capabilities, types, constants and variables, decorations that connect them to the outside world, and functions in static single-assignment form. Vulkan 1.3 accepts SPIR-V up to version 1.6.

Taking SPIR-V instead of source text removes a compiler front end from every driver. Each OpenGL driver had its own GLSL parser, with its own bugs and its own interpretation of corner cases, and every program paid to parse its shaders at start-up. With SPIR-V, parsing and most optimisation happen once, at build time, and any language that compiles to SPIR-V can be used: GLSL, HLSL and Slang all can.

The SDK provides the tools. `glslc`, the command-line compiler from Google's shaderc project, compiles GLSL with Khronos's reference compiler, glslang. `spirv-val` checks a module against the SPIR-V specification and Vulkan's rules for it; `spirv-dis` turns it into readable text; `spirv-opt` optimises it. The course's build runs `glslc` for every shader through the CMake function `vkf_shaders`.

#console(read("/src/console/u1-spirv.txt"), caption: [The fill shader compiled, validated and disassembled, with some declarations elided])

The disassembly shows the interface explicitly. `OpEntryPoint` names the function `main` and lists the variables it uses from outside. `OpExecutionModeId ... LocalSizeId %7 ...` gives the workgroup size, whose width is `%7`, a specialisation constant decorated `SpecId 0`. The storage buffer is a variable decorated `DescriptorSet 0` and `Binding 0`. The body loads `gl_GlobalInvocationID.x`, compares it with the second push constant, multiplies, applies the exclusive-or and stores the result through a pointer into the buffer.

#fig("u1-shader-path", caption: [From GLSL to a pipeline. Compilation to SPIR-V happens at build time; the driver compiles SPIR-V to the GPU's own instructions when the pipeline is created, with the layout and the specialisation constants known.]) <fig-shader-path>

The driver translates SPIR-V into the GPU's own instruction set when the program creates a pipeline (@fig-shader-path). On macOS there is a further step: MoltenVK translates the SPIR-V into the Metal Shading Language with the SPIRV-Cross library, and Metal compiles that.

#hazard(title: [Pitfall])[
  Because MoltenVK goes through Metal's shading language, a name in your shader that collides with a name in Metal's standard library can break pipeline creation on macOS while working everywhere else. A specialisation constant called `bias` did exactly that while this course was being written. If a pipeline fails only under MoltenVK, look for such a collision and rename.
]

=== Shader modules

A _shader module_ wraps SPIR-V code for the device. Creating one is cheap: the driver keeps the words, and the real compilation waits for the pipeline. The code is passed as a size in bytes and a pointer to 32-bit words.

#snippet("u1/shared/basics.hpp", "read-spirv", caption: [Reading a SPIR-V file and creating a shader module])

#snippet("u1/pipeline/main.cpp", "module", caption: [The build tells the program where its compiled shaders are])

The build compiles with `-O`, which optimises, and `-g`, which keeps names and source lines in the module so that validation messages and capture tools can refer to them. The debug information more than doubles the module: 506 words against 252 without it. It costs nothing at run time, because the driver discards it.

=== Pipeline layouts

A shader's interface must be described to the driver before the shader can be compiled into a pipeline, so that the driver knows where each resource will be found. The _pipeline layout_ is that description: an array of _descriptor set layouts_, one for each set index the shaders use, and the ranges of push constants they read.

#snippet("u1/pipeline/main.cpp", "layouts", caption: [A descriptor set layout with one storage buffer, and a pipeline layout with eight bytes of push constants])

The descriptor set layout says that binding 0 is one storage buffer, visible to compute shaders. It describes no particular buffer: Chapter 1.5 allocates sets that follow this layout and points them at real buffers.

Push constants are a small block of bytes, at least 128 and on some devices several kilobytes (`maxPushConstantsSize`), that you write into the command buffer itself with `vkCmdPushConstants`. They need no buffer and no descriptor, which makes them the cheapest way to pass per-dispatch parameters such as counts, offsets or a seed. A push constant block uses the `std430` layout rules, and the range in the pipeline layout must cover every byte the shaders read.

=== Compute pipelines

A compute pipeline combines one shader stage with a pipeline layout. Creating it is the expensive step: the driver compiles the SPIR-V for its hardware, using everything it knows from the layout and the specialisation constants.

#snippet("u1/pipeline/main.cpp", "pipeline", caption: [A compute pipeline with its workgroup width supplied as a specialisation constant])

A _specialisation constant_ is a constant whose value is supplied at pipeline creation. `VkSpecializationInfo` maps constant IDs to bytes in a data block; the driver substitutes the values before it optimises, so a loop bound or a workgroup size behaves exactly like a literal in the source. The program builds three pipelines from one shader module, with workgroups of 64, 128 and 256 invocations. A push constant, by contrast, can change between dispatches but is an ordinary run-time value to the compiler. Use specialisation for values that change rarely and matter to the optimiser, and push constants for values that change often.

#hazard(title: [Pitfall])[
  When `glslc` targets Vulkan 1.3 it expresses a specialised workgroup size with the `LocalSizeId` execution mode, which requires the `maintenance4` feature. Without the feature, validation reports that "LocalSizeId is used but maintenance4 feature was not enabled". This is why Chapter 1.1's device enables `maintenance4`. Targeting Vulkan 1.2 produces the older form instead, a `WorkgroupSize` built-in made of specialisation constants, which SPIR-V 1.6 deprecates.
]

Creating a pipeline can take anything from a fraction of a millisecond to hundreds of milliseconds, depending on the shader and the driver. Create pipelines when the program starts or a level loads, never in the middle of a frame. Vulkan has no way to change a pipeline afterwards, which is also a guarantee: nothing will make the driver recompile it later.

#keyidea[
  A Vulkan pipeline is compiled once, from SPIR-V, with everything it depends on known: its layout, its specialisation constants and, for graphics, its fixed-function state. Nothing about it changes later, so nothing triggers a hidden recompile at dispatch or draw time.
]

=== Pipeline caches

A _pipeline cache_ lets the driver keep what it compiled. You pass a `VkPipelineCache` to `vkCreateComputePipelines`; the driver looks up each pipeline's description in it and stores new results in it. `vkGetPipelineCacheData` returns the contents as bytes, which a program saves to disk and passes back as initial data on its next run.

#snippet("u1/pipeline/main.cpp", "cache", caption: [Creating a cache, empty or from saved data])

#snippet("u1/pipeline/main.cpp", "save-cache", caption: [Saving the cache when the program finishes])

The data begins with a header that names the vendor, the device and a `pipelineCacheUUID` that changes whenever the driver's compiler does. The specification requires a driver to ignore data from another device or driver version. A file can also be truncated or corrupted, however, so the program checks the header itself before trusting the file; robust programs also store their own size and checksum beside the data.

#snippet("u1/pipeline/main.cpp", "cache-header", caption: [Accepting saved data only for this vendor, device and driver])

#console(read("/src/console/u1-pipeline.txt"), caption: [Two runs of `u1_pipeline` on an Apple M2 Pro])

The output shows a property of the M2 Pro's driver more than of the cache. Metal keeps its own cache of compiled shaders, shared by every program on the machine, so even the first run with an empty Vulkan cache found the compiled code: each pipeline took about a millisecond. The very first creation of this pipeline on the machine took 81 ms. Desktop drivers keep caches of their own on disk too, so a "cold" measurement is truly cold only the first time; Chapter 4.6 shows how to measure despite that.

#opengl[
  OpenGL compiles GLSL source at run time with `glShaderSource`, `glCompileShader` and `glLinkProgram`, and you find each uniform by name with `glGetUniformLocation`. A program object holds no blending, depth or vertex-format state, so drivers sometimes compile a shader again when such state changes, which shows up as a stall at an unpredictable draw call. `glGetProgramBinary` is the counterpart of a pipeline cache. OpenGL 4.6 can also accept SPIR-V through `glShaderBinary` and `glSpecializeShader`, but macOS stops at OpenGL 4.1.
]

#reading(
  [The Vulkan specification, chapters "Shaders" and "Pipelines" (compute pipelines, specialisation constants, pipeline cache), and the appendix "Vulkan Environment for SPIR-V".],
  [The SPIR-V specification, section 2, in particular "Physical Layout of a SPIR-V Module and Instruction", at #link("https://registry.khronos.org/SPIR-V/")[registry.khronos.org/SPIR-V].],
  [The `GL_KHR_vulkan_glsl` extension specification, which lists every difference between GLSL for OpenGL and for Vulkan.],
  [The Vulkan Guide, "What is SPIR-V", "Push Constants" and "Pipeline Cache".],
)

== Labs

#lab([Compile, validate, disassemble], goal: [Read SPIR-V well enough to find your own code in it.], time: [1 hour], code: "code/u1/pipeline")[
  + Compile `fill.comp` with `glslc --target-env=vulkan1.3` four ways: with and without `-O`, and with and without `-g`. Record the size of each module in words.
  + Validate each with `spirv-val --target-env vulkan1.3`.
  + Disassemble the optimised module without debug information and annotate it: the entry point and its interface, the execution mode, every decoration, and the instructions that implement each line of `main`.
  #done-when(
    [You have four sizes and four clean validations.],
    [Every line of `main` is matched to its instructions in your annotation.],
  )
  #evidence([The annotated disassembly.])
]

#lab([Break the pipeline on purpose], goal: [Recognise the messages that bad shader interfaces produce.], time: [1 hour], code: "code/u1/pipeline")[
  + In a copy of `basics.hpp`, stop enabling `maintenance4` and run `u1_pipeline`. Record the message and the call that produced it.
  + Restore it. Set `pName` to `"main2"` and run. Record both messages, the validation layer's and the driver's.
  + Restore it. Compile `fill.comp` with `--target-env=vulkan1.2`, disassemble it, and find how the workgroup size is expressed now.
  #done-when(
    [You have recorded both validation messages with the VUID each cites.],
    [You can explain the difference between the two SPIR-V forms of a specialised workgroup size.],
  )
  #evidence([The messages and the two disassembly excerpts.])
]

#lab([Two specialisation constants], goal: [Pass several constants through one specialisation block.], time: [1.5 hours], code: "code/u1/pipeline")[
  + Add a second specialisation constant to `fill.comp`, `layout(constant_id = 1) const uint stride = 1;`, and use it to scale the index the shader writes to.
  + Pass both constants from a C++ struct, with one `VkSpecializationMapEntry` per member and the right offsets.
  + Disassemble the result and find both `SpecId` decorations.
  + Create pipelines for all combinations of three workgroup sizes and two strides.
  #done-when(
    [Six pipelines are created with no validation errors.],
    [Your map entries use `offsetof` instead of hand-written offsets.],
  )
  #evidence([The shader, the struct and its map entries.])
]

#lab([Warm and cold caches], goal: [Measure what a pipeline cache saves on your machine, and when.], time: [1.5 hours], code: "code/u1/pipeline")[
  + Run `u1_pipeline` twice and record the creation times and the cache size.
  + Change one byte of the saved file's UUID and confirm that the program treats the cache as cold.
  + Extend the program to create twenty pipelines, with workgroup widths of 32 to 640 in steps of 32, and time the whole set with a cache, without one, and with a cache loaded from disk.
  #done-when(
    [You have the three timings for the set of twenty pipelines, from three runs each.],
    [You can explain your results in terms of your driver's own caching, with evidence such as a first-ever run on a new shader.],
  )
  #evidence([The timings and your explanation.])
]

#problems(
  [Give two reasons why Vulkan consumes SPIR-V instead of GLSL, and one thing a program gives up by not shipping its shader source.],
  [A shader's push constant block contains a `uint` followed by a `vec4`. Give each member's offset and the size of the `VkPushConstantRange` the pipeline layout needs.],
  [For each of these, choose a specialisation constant or a push constant and explain why: the side of a tile in shared memory; the number of elements in this dispatch; a flag that enables an expensive debug path.],
  [A program copies its pipeline cache file from a development machine with one GPU to a user's machine with another. What happens when the user's machine loads it, and what would you do instead?],
  [What happens to the elements beyond `count` if the bounds check in `main` is removed and `count` is not a multiple of the workgroup width? Which tool would tell you, and when?],
)

#checklist(
  [I can compile GLSL to SPIR-V, validate it, and read its disassembly.],
  [I can create shader modules, descriptor set layouts, pipeline layouts and compute pipelines.],
  [I can choose between specialisation constants and push constants, and supply both.],
  [I can save and reload a pipeline cache and validate its header.],
  [Lab 1.4.1–1.4.4 done-when criteria all hold, with evidence filed.],
)
