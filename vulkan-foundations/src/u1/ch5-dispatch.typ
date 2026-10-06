#import "../lib/template.typ": *

= Descriptors and your first dispatch <ch-dispatch>

#chapter-meta(
  time: [6 hours],
  builds: [SAXPY, `y = a·x + y`, as a complete Vulkan program with nothing hidden: buffers, a descriptor set, a pipeline, ten dispatches with the barriers between them, and a check of every element on the CPU. Then vector addition, and descriptor sets reused across dispatches.],
  needs: [Chapters 1.2 to 1.4.],
)

#why[
  Everything in Unit 1 so far has been preparation. This chapter connects it: the shader from Chapter 1.4 meets real buffers through a _descriptor set_, the pipeline is bound into a command buffer, and the GPU finally computes something. SAXPY is the "hello, world" of GPU computing because it has every part of a real compute program and nothing else, so each line of it teaches something you will use in every program that follows.
]

#skip-test(
  rule: [If all four are easy, read the section on `std430` and do Labs 1.5.3 and 1.5.4.],
  [What is a descriptor, and which four objects does a program create to give a shader access to one buffer?],
  [How many workgroups does a dispatch need for 1,000,003 elements with 256 invocations per workgroup, and what must the shader do about the extra invocations?],
  [A dispatch reads and writes a buffer that the previous dispatch wrote. Write the barrier between them.],
  [Give the `std430` offset of each member of `struct { vec3 p; float m; vec2 v; }`.],
)

== Core ideas

=== Descriptors

A shader refers to its resources by set and binding numbers. A _descriptor_ is the small record that connects such a binding to an actual resource: for a buffer, its address and size; for an image, its view, layout and format. Descriptors are grouped into _descriptor sets_ that follow a _descriptor set layout_, and sets are allocated from a _descriptor pool_. @fig-descriptors shows how the pieces fit for SAXPY.

#fig("u1-descriptors", caption: [From the shader's bindings to real buffers. The set layout describes the bindings; the pipeline layout collects set layouts and push constants; a set allocated from a pool is written to point at buffers and bound before the dispatch.]) <fig-descriptors>

Each binding has a _descriptor type_ that says what kind of resource it holds and how the shader may use it. Compute programs mostly use these:

- `VK_DESCRIPTOR_TYPE_STORAGE_BUFFER`: a buffer the shader may read and write, of any size up to `maxStorageBufferRange`.
- `VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER`: a read-only buffer of at most `maxUniformBufferRange` bytes (at least 16 KiB, and 64 KiB on many devices), which some hardware reads through a faster path.
- `VK_DESCRIPTOR_TYPE_STORAGE_IMAGE`: an image the shader reads and writes texel by texel (Chapter 2.4).
- `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`, `VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE` and `VK_DESCRIPTOR_TYPE_SAMPLER`: images read through the texture hardware with filtering (Chapters 2.4 and 4.3).

The SAXPY shader declares two storage buffers, `x` read-only and `y` read-write, and two push constants:

#listing("u1/saxpy/saxpy.comp", caption: [SAXPY in GLSL])

The descriptor set layout mirrors the bindings. A program usually creates its set layouts once, when it starts.

#snippet("u1/saxpy/main.cpp", "set-layout", caption: [A set layout with two storage buffers])

=== Pools, sets and updates

Descriptor sets come from a pool that is created with a maximum number of sets and a budget of descriptors of each type. Allocation can fail with `VK_ERROR_OUT_OF_POOL_MEMORY` when either runs out. Programs typically create one pool per frame or per subsystem and reset it whole with `vkResetDescriptorPool` instead of freeing sets one at a time; freeing individual sets requires the flag `VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT`.

#snippet("u1/saxpy/main.cpp", "pool-and-set", caption: [A pool with room for one set of two storage buffers, and the set])

A newly allocated set points at nothing. `vkUpdateDescriptorSets` writes descriptors into it: for each binding, the buffer, the offset into it and the range the shader may see. Updating a set is a host operation that takes effect immediately, which has a consequence: a set must not be updated while a command buffer that uses it is pending, because the GPU may be reading it. Chapter 3.6 handles this with one set per frame in flight.

#snippet("u1/saxpy/main.cpp", "write-set", caption: [Pointing binding 0 at `x` and binding 1 at `y`])

The buffers themselves are host-visible and persistently mapped, so the program fills them directly. On a discrete GPU, data read this often would be staged into device-local memory as Chapter 1.3 showed; for a first program, host-visible memory keeps the moving parts few.

#snippet("u1/saxpy/main.cpp", "buffers", caption: [Two buffers of `n` floats, filled through their mappings])

=== Push constants and `std430`

The push constants are a `float` and a `uint`. The C++ structure must lay them out exactly as the shader expects.

#snippet("u1/saxpy/main.cpp", "push", caption: [The C++ mirror of the shader's push constant block])

Buffer and push constant blocks follow the `std430` layout rules, which the course always states explicitly:

- A scalar is aligned to its size: 4 bytes for `float`, `int` and `uint`.
- A `vec2` is aligned to 8 bytes; a `vec3` and a `vec4` to 16. A `vec3` therefore occupies 12 bytes but is followed by 4 bytes of padding unless a scalar fills them.
- An array's elements are aligned to their own alignment, and its stride is the element's size rounded up to that alignment.
- A structure is aligned to its most-aligned member, and its size is rounded up to that alignment.

Uniform buffer blocks follow `std140` by default, which differs in one painful way: array elements and structures are aligned to 16 bytes, so a `float data[4]` occupies 64 bytes instead of 16. A C++ mirror of either layout should state its offsets with `alignas` and check them with `static_assert`, because a mismatch fails silently: the shader reads the wrong bytes.

The pipeline layout and the pipeline are created as Chapter 1.4 described, with a push constant range of `sizeof(Push)`:

#snippet("u1/saxpy/main.cpp", "pipeline", caption: [Pipeline layout and compute pipeline])

=== Recording the dispatch

The command buffer binds the pipeline, binds the descriptor set at set index 0 through the pipeline layout, writes the push constants and dispatches. `vkCmdDispatch` takes a number of workgroups in each of three dimensions; with 256 invocations per workgroup, `(n + 255) / 256` workgroups cover every element (@fig-dispatch). Bindings and push constants stay in effect for later dispatches in the same command buffer, so the program then dispatches nine more times without binding anything again, reusing one descriptor set for all ten.

#fig("u1-dispatch", caption: [A one-dimensional dispatch. Every workgroup has 256 invocations; the last one has more invocations than elements, and the shader's bounds check stops them.]) <fig-dispatch>

Each dispatch reads and writes `y`, which the previous one wrote: a read-after-write and a write-after-write dependency on the same buffer. A barrier from compute-shader writes to compute-shader reads and writes goes between consecutive dispatches. After the last, a barrier from compute-shader writes to host reads prepares the results for the CPU, exactly as the copy did in Chapter 1.3.

#snippet("u1/saxpy/main.cpp", "record", caption: [Bind, push, dispatch ten times with barriers, and hand the results to the host])

`maxComputeWorkGroupCount` limits the number of workgroups per dimension. The guaranteed minimum is 65,535, which with 256-wide workgroups covers 16,776,960 elements; the M2 Pro allows 2#super[30]. Chapter 2.6 handles larger problems.

#keyidea[
  A dispatch needs four things bound: a pipeline, the descriptor sets its layout names, the push constants it reads, and the barriers that order it against the work before and after. Forget any one and the validation layer will say so; forget a barrier and only synchronisation validation will.
]

=== Checking the answer

After ten dispatches every `y[i]` should equal `1 + 10 a x[i]`. The program checks every element against that formula in double precision and reports the largest relative error.

#snippet("u1/saxpy/main.cpp", "verify", caption: [Checking every element on the CPU])

#console(read("/src/console/u1-saxpy.txt"), caption: [SAXPY on an Apple M2 Pro])

The error is exactly zero here because every value involved is a multiple of 1/8 that a `float` represents exactly. With arbitrary inputs, expect differences of a few units in the last place: the GPU may fuse the multiply and the add into one operation with a single rounding, and the CPU may not. Choose tolerances accordingly, and choose test data whose exact answer you know when you can.

#opengl[
  OpenGL 4.3 added compute shaders. A program binds a buffer to an indexed binding point with `glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, buffer)`, sets parameters with `glUniform1f`, launches with `glDispatchCompute`, and calls `glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)` before a later dispatch reads what an earlier one wrote. The binding points are global state of the context, overwritten by the next bind; Vulkan's descriptor sets are objects you prepare once and bind in one call. macOS stops at OpenGL 4.1, which has no compute shaders at all.
]

#reading(
  [The Vulkan specification, chapter "Resource Descriptors" (descriptor set layouts, pools, allocation, updates and binding) and the section "Dispatching Commands".],
  [The Vulkan specification, section "Offset and Stride Assignment" in "Shader Interfaces", which defines `std140`, `std430` and the scalar layout.],
  [The Vulkan Guide, "Shader Memory Layout", "Descriptor Dynamic Offset" and "Compute Shaders".],
)

== Labs

#lab([SAXPY end to end], goal: [Run, read and stress the complete program.], time: [1.5 hours], code: "code/u1/saxpy")[
  + Run `build/bin/u1_saxpy`, then read `main.cpp` from top to bottom and write one sentence in your notebook for each Vulkan call.
  + Run it with `--n` set to 1, 255, 256, 257 and 1,000,003.
  + Work out the largest `n` that your device's `maxComputeWorkGroupCount[0]` allows with 256-wide workgroups, and the largest that `maxStorageBufferRange` allows.
  #done-when(
    [Every run passes with no validation errors.],
    [You have the two limits for your device, and can say which one binds first.],
  )
  #evidence([The sentence-per-call annotation and the limits.])
]

#lab([Vector addition], goal: [Write a second compute program from the first.], time: [1 hour], code: "code/u1/saxpy")[
  + Copy the project to `vadd`, add a third binding `z`, declared `writeonly`, and compute `z = x + y` once.
  + Extend the set layout, the pool and the descriptor writes for three buffers.
  + Check every element on the CPU.
  #done-when(
    [The program passes for `n` of 1 and 1,000,003, with no validation errors.],
    [Removing the third descriptor write produces a validation error at the dispatch, which you have recorded.],
  )
  #evidence([The differences from SAXPY, and the validation message.])
]

#lab([Ping-pong between two sets], goal: [Reuse descriptor sets across dispatches.], time: [1.5 hours], code: "code/u1/saxpy")[
  + Allocate a second set that binds `y` at binding 0 and `x` at binding 1, so that a dispatch with it computes `x = a·y + x`.
  + Record ten dispatches that alternate between the two sets, with the barriers they need, and compute the expected values on the CPU.
  + Record which barriers you changed, and why the old ones are no longer enough.
  #done-when(
    [The program passes with synchronisation validation on.],
    [The pool is sized for exactly the sets and descriptors you allocate.],
  )
  #evidence([The recorded commands and your note on the barriers.])
]

#lab([`std430` by hand], goal: [Make a C++ structure match a shader's layout exactly.], time: [1 hour], code: "code/u1/saxpy")[
  + Write a shader that reads an array of `struct Particle { vec3 position; float mass; vec2 velocity; uint id; }` from one buffer and writes each field, as floats, to a second buffer in a known order.
  + Write the C++ mirror with `alignas` where needed, and `static_assert` its size and every member's offset.
  + Fill the input with distinct values and check the output on the CPU.
  #done-when(
    [The offsets in your `static_assert`s are the `std430` offsets, and the check passes.],
    [You can state the structure's size and array stride, and what both would be in a `std140` uniform block.],
  )
  #evidence([The structure, the asserts and the two layouts compared.])
]

#problems(
  [A shader uses set 0 with two storage buffers and set 1 with one uniform buffer. List every object the program must create to dispatch it, in order.],
  [How many workgroups does `vkCmdDispatch` need for 1,000,003 elements with 64-wide workgroups? How many invocations do nothing?],
  [Why may a program not call `vkUpdateDescriptorSets` on a set that a pending command buffer uses? What are two ways to change the buffers a shader sees between frames?],
  [Give the `std430` and `std140` offsets of every member of `struct { float a; vec3 b; float c[3]; vec2 d; }`, and the structure's size under each.],
  [The SAXPY program's error is exactly zero. Construct inputs for which the GPU's result differs from a naive C++ loop, and explain the difference.],
)

#checklist(
  [I can create descriptor set layouts, pools and sets, and write buffer descriptors into sets.],
  [I can lay out push constant and buffer data under `std430`, and mirror it in C++.],
  [I can record a dispatch with its bindings and the barriers before and after it.],
  [I can verify a GPU result on the CPU with a tolerance I can justify.],
  [Lab 1.5.1–1.5.4 done-when criteria all hold, with evidence filed.],
)
