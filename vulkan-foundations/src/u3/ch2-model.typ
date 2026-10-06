#import "../lib/template.typ": *

= The dependency model <ch-model>

#chapter-meta(
  time: [6 hours],
  builds: [Barriers for a table of producer and consumer scenarios, each derived from the model and checked by synchronisation validation; the same barriers made too narrow and too wide; a dependency split into a chain; and image layout transitions placed by hand.],
  needs: [Chapter 3.1.],
)

#why[
  Chapter 3.1 showed that barriers are necessary. This chapter shows what a barrier means, precisely, so that you can write the right one for any situation instead of copying one that seems similar. The model has few parts: two synchronisation scopes, the pipeline stages that bound them, the access scopes that say which memory accesses are covered, and the availability and visibility operations that move data between them. Everything else in this unit, from semaphores to render graphs, is built from the same parts.
]

#skip-test(
  rule: [If all five are easy, read the section on chains and do Labs 3.2.1 and 3.2.3.],
  [What is the difference between an execution dependency and a memory dependency, and when is the first enough?],
  [A barrier's `srcStageMask` is `VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT`. Does it wait for a copy recorded before it?],
  [Why do access masks apply only to the stages named in the stage masks, while stage masks also cover logically earlier or later stages?],
  [What does a layout transition do to an image's memory, and where in a barrier does it happen?],
  [Can one dependency be split across two barriers? Under what condition?],
)

== Core ideas

=== Execution dependencies

An _execution dependency_ between two sets of operations guarantees that every operation in the first set happens before every operation in the second. A pipeline barrier creates one between the commands recorded before it and the commands recorded after it, but only for the parts of those commands that its stage masks name. Its _first synchronisation scope_ is the work of the stages in `srcStageMask` in the commands before the barrier; its _second synchronisation scope_ is the work of the stages in `dstStageMask` in the commands after it. Work outside the scopes is not ordered at all.

#fig("u3-scopes", caption: [What a pipeline barrier does. Work in the first scope finishes and its writes in the first access scope are made available and then visible to the second access scope, before work in the second scope starts.]) <fig-scopes>

The stages come from the list in @fig-stages. Each command runs some of them: a dispatch runs `DRAW_INDIRECT`, if indirect, and `COMPUTE_SHADER`; a copy runs `COPY`; a draw runs the graphics stages. A stage mask also covers the stages that come logically before the ones it names, in a source mask, or logically after them, in a destination mask, in the order the figure shows for each kind of command. A source mask of `COLOR_ATTACHMENT_OUTPUT` therefore waits for the vertex and fragment shaders too.

#fig("u3-stages", caption: [The synchronization2 pipeline stages this course uses, in logical order for each kind of command. Tessellation and geometry shaders, which the course does not use, come between the vertex shader and the early fragment tests.]) <fig-stages>

Three stage values are special. `VK_PIPELINE_STAGE_2_NONE` names no stage: as a source it waits for nothing, and as a destination it blocks nothing. `VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT` names every stage of every command, and is correct everywhere but often slower than necessary. `VK_PIPELINE_STAGE_2_HOST_BIT` is the host's reads and writes of mapped memory, which a barrier can only make writes available to or visible from; the host itself never waits on a barrier.

=== Memory dependencies

An execution dependency is not enough when data passes between the two sides, because of caches. A _memory dependency_ adds three operations, which happen in order between the two scopes:

+ An _availability operation_ makes the writes in the first _access scope_ available: written back from whatever caches hold them to a level where every later access in the same _memory domain_ can find them.
+ A _memory domain operation_, when the barrier names the host as a destination, moves available writes from the device's domain to the host's.
+ A _visibility operation_ makes available writes visible to the accesses in the second access scope: stale copies in the caches those accesses use are discarded, so that they read the new values.

The access scopes come from the access masks: `srcAccessMask` names the kinds of write to make available, and `dstAccessMask` the kinds of access to make them visible to. Unlike stage masks, access masks apply only to accesses performed by the stages named explicitly, never to logically earlier or later ones, and each access flag is valid only with the stages that can perform it. The flags this unit uses most are `SHADER_STORAGE_READ` and `SHADER_STORAGE_WRITE` for storage buffers and images, `SHADER_SAMPLED_READ` for sampled images, `UNIFORM_READ`, `TRANSFER_READ` and `TRANSFER_WRITE` for copies, `INDIRECT_COMMAND_READ` for indirect parameters, `HOST_READ` and `HOST_WRITE`, and the catch-alls `MEMORY_READ` and `MEMORY_WRITE`.

#keyidea[
  Read a barrier as one sentence: _wait for these stages of earlier commands to finish, make these of their writes available, make them visible to these accesses of later commands, then let these stages of later commands begin._ Every field of `VkMemoryBarrier2` is one phrase of that sentence.
]

A write after read needs only the execution dependency, because the read has nothing to make visible; Chapter 3.1's `war` case leaves both access masks empty for this reason. A read after write and a write after write need both.

=== Three kinds of barrier

`VkDependencyInfo` carries three arrays of barriers. A _global_ barrier, `VkMemoryBarrier2`, covers every resource. A _buffer_ barrier, `VkBufferMemoryBarrier2`, adds a buffer and a range, and an _image_ barrier, `VkImageMemoryBarrier2`, adds an image, a subresource range and a pair of layouts. Both of the latter can also transfer a resource between queue families, which Chapter 3.5 explains. Here is the copy-then-dispatch case from Chapter 3.1, written with a buffer barrier:

#snippet("u3/hazards/main.cpp", "transfer-compute", caption: [A buffer barrier from a copy's writes to a dispatch's reads])

On most current GPUs a buffer barrier costs exactly what a global barrier with the same masks costs, because caches are not flushed one buffer at a time. Use global barriers for buffers on a single queue: they are shorter to write and cannot leave out a buffer. Use buffer and image barriers when they carry something a global barrier cannot: a layout transition, or a transfer of ownership.

=== Barriers to and from the host

The host is a stage of its own. When a dispatch writes results the CPU will read, the barrier's destination is the host, which adds the memory domain operation to the host's domain, and the CPU then waits on a fence before reading:

#snippet("u3/hazards/main.cpp", "device-host", caption: [Making shader writes available to the host])

If the memory is not `HOST_COHERENT`, the CPU must also invalidate the range before reading it, as Chapter 1.2 described; `vkf::Buffer::invalidate` does nothing when the memory is coherent.

#snippet("u3/bugs/main.cpp", "invalidate", caption: [Invalidating before the host reads, from Chapter 3.7's catalogue of bugs])

In the other direction no barrier is needed: submitting work makes the host's earlier writes visible to it, provided they were flushed when the memory is not coherent. The one constraint, which Chapter 3.1's `host-device` case broke, is that the host must not write memory that submitted work may still be reading.

When a copy and the host both follow a dispatch, each needs its own destination. Chapter 3.1's `compute-transfer` case orders the copy after the dispatch, then the host after the copy:

#snippet("u3/hazards/main.cpp", "compute-transfer", caption: [Shader writes, a copy, and a read on the host])

=== Image layouts and their transitions

An image's _layout_ is the arrangement of its data that the hardware uses for a kind of access, as Chapter 1.2 introduced. A program declares every change of layout in an image barrier, with `oldLayout` and `newLayout`, and the device performs a _layout transition_: it rearranges, compresses or decompresses the image's data as needed. A transition reads and writes the whole subresource range, so it is ordered like a write: after the barrier's first scope and its availability operation, and before its visibility operation and second scope (@fig-layouts).

#fig("u3-layouts", caption: [The image in Chapter 3.1's `image-layout` case. Each transition belongs to a barrier and sits between that barrier's two scopes.]) <fig-layouts>

An `oldLayout` of `VK_IMAGE_LAYOUT_UNDEFINED` promises that the old contents do not matter, so the transition need not preserve them, and an image that nothing has used yet needs nothing in the first scope:

#snippet("u3/hazards/main.cpp", "image-general", caption: [From UNDEFINED to GENERAL before a shader writes the image])

The second transition must wait for the shader's writes, because it rewrites the image itself. Chapter 3.1's broken version of this barrier left the source scope empty, and synchronisation validation reported a write after write between the shader's writes and the transition.

#snippet("u3/hazards/main.cpp", "image-transfer", caption: [From GENERAL to TRANSFER_SRC_OPTIMAL before the copy reads it])

#hazard(title: [Pitfall])[
  `oldLayout` must be the layout the image is actually in, or `VK_IMAGE_LAYOUT_UNDEFINED`. Vulkan does not track layouts for you: claiming the wrong old layout is undefined behaviour, which the validation layer reports when it can see it. Using `UNDEFINED` on an image whose contents you still need discards them.
]

=== Chains

Dependencies compose. If a barrier's second synchronisation scope and a later barrier's first scope share a stage, the two barriers form an _execution dependency chain_: the first barrier's first scope happens before the second barrier's second scope, as if a single barrier had joined them (@fig-chain). The same holds for memory: a write made available by the first barrier can be made visible by the second.

#fig("u3-chain", caption: [An execution dependency chain. A happens before B by barrier 1 and B before C by barrier 2; because both barriers include the compute stage between them, A also happens before C.]) <fig-chain>

Chains are why a barrier between every pair of consecutive passes is enough in a long pipeline, and why a barrier need not name stages far back in the command stream. They also explain a common surprise: a barrier whose source stages do not include the stage of the command you meant to wait for orders nothing, however close the two are in the command buffer.

=== Writing a barrier

The model reduces barrier writing to a procedure:

+ Find each resource's last writer before the point, and the stage and access of the write.
+ Find each access after the point that conflicts with it, and its stage and access.
+ For images, find the layout the next access needs.
+ Write one barrier per hazard: global for buffers, image barriers for images, with exactly those stages and accesses.
+ Put all the barriers at one point into one `VkDependencyInfo`, so that the device synchronises once.

@tbl-recipes lists the combinations this unit meets most; Chapter 3.3 gives the full catalogue.

#figure(
  tbl(columns: (1fr, 1fr, 1fr), header: ([Producer], [Consumer], [Source → destination]), size: 8pt,
    [dispatch writes a buffer], [dispatch reads it], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `COMPUTE_SHADER`, `SHADER_STORAGE_READ`],
    [dispatch reads a buffer], [dispatch overwrites it], [`COMPUTE_SHADER`, none → `COMPUTE_SHADER`, none],
    [copy or fill writes], [dispatch reads], [`COPY` or `CLEAR`, `TRANSFER_WRITE` → `COMPUTE_SHADER`, `SHADER_STORAGE_READ`],
    [dispatch writes], [copy reads], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `COPY`, `TRANSFER_READ`],
    [dispatch writes parameters], [indirect dispatch or draw], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `DRAW_INDIRECT`, `INDIRECT_COMMAND_READ`],
    [any device write], [host reads after a fence], [the writer's stage and access → `HOST`, `HOST_READ`],
    [nothing yet], [first write to an image], [`NONE`, none → the writer's stage and access, with `UNDEFINED` → the layout],
  ),
  caption: [Common dependencies, with the prefixes `VK_PIPELINE_STAGE_2_` and `VK_ACCESS_2_` and the suffix `_BIT` left out],
  kind: table,
) <tbl-recipes>

#opengl[
  `glMemoryBarrier`'s bits each name a kind of later access, such as `GL_SHADER_STORAGE_BARRIER_BIT` or `GL_COMMAND_BARRIER_BIT`, and correspond to Vulkan's destination access masks. OpenGL has no source scope: every earlier write of the relevant kind is made visible, from every stage. It has no destination stage either, and no layouts, which its driver manages.
]

#reading(
  [The Vulkan specification, chapter "Synchronization and Cache Control": "Execution and Memory Dependencies", "Pipeline Stages", "Access Types", "Pipeline Barriers" and "Image Layout Transitions". Read the definitions slowly: this chapter paraphrases them.],
  [The Vulkan Guide, "Synchronization" and "VK_KHR_synchronization2".],
  [Hans-Kristian Arntzen, "Yet another blog explaining Vulkan synchronization" (2019), in full.],
)

== Labs

#lab([Barriers for a table of scenarios], goal: [Derive barriers from the model and have them checked.], time: [2 hours], code: "code/u3/hazards")[
  + Add four cases to `u3_hazards`: `vkCmdFillBuffer` then a dispatch that reads; a dispatch that writes a buffer the next dispatch reads as a uniform buffer; a dispatch that writes an image the next dispatch samples in `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`; two copies into the same buffer.
  + For each, write the barrier from the procedure above before running anything, with the hazard type in a comment in your notebook.
  + Run each with validation on, then with its barrier removed.
  #done-when(
    [All four cases pass with synchronisation validation silent.],
    [With each barrier removed, the reported hazard is the one you predicted.],
  )
  #evidence([The four barriers with your derivations, and the reports.])
]

#lab([Too narrow and too wide], goal: [Learn which mistakes validation catches and which it cannot.], time: [1 hour], code: "code/u3/hazards")[
  + In the `compute-compute` case, try these destinations in turn: `TRANSFER_READ` instead of `SHADER_STORAGE_READ`; the `FRAGMENT_SHADER` stage instead of `COMPUTE_SHADER`; and `ALL_COMMANDS` with `MEMORY_READ`.
  + Try a source of `ALL_COMMANDS` with `MEMORY_WRITE`.
  + Classify each as wrong, correct but wider than needed, or correct and minimal.
  #done-when(
    [You have the validation output for each variant.],
    [Your classification agrees with the model, and you can say why validation accepts the wide versions.],
  )
  #evidence([The variants, their outputs and the classification.])
]

#lab([Split a dependency into a chain], goal: [Use the chain rule deliberately.], time: [1.5 hours], code: "code/u3/hazards")[
  + Between the two dispatches of `compute-compute`, record an unrelated copy, and replace the barrier with two: from the dispatch's writes to the `COPY` stage with no access, and from the `COPY` stage with no access to the compute shader's reads.
  + Run with validation on. Then change the second barrier's source stage to `HOST` and run again.
  #done-when(
    [You have recorded what synchronisation validation says about each version.],
    [You can explain each result with the definition of an execution dependency chain.],
  )
  #evidence([The two versions and the explanations.])
]

#lab([Layouts by hand], goal: [Place layout transitions and see what goes wrong without them.], time: [1.5 hours], code: "code/u3/hazards")[
  + In the `image-layout` case, copy from the image in `VK_IMAGE_LAYOUT_GENERAL` without the second transition, adjusting the barrier's other fields, and confirm that it is valid.
  + Claim the wrong `oldLayout`, `TRANSFER_DST_OPTIMAL`, in the second barrier, and record the validation message.
  + Use `UNDEFINED` as the `oldLayout` of the second barrier and record what happens to the data.
  #done-when(
    [You have the three outcomes recorded.],
    [You can explain when staying in `GENERAL` is acceptable and when a specific layout is worth a transition.],
  )
  #evidence([The three outcomes and your explanation.])
]

#problems(
  [Write the `VkMemoryBarrier2` for a dispatch that writes a buffer that the next dispatch reads as a uniform buffer, and for the reverse, where a dispatch overwrites a buffer that the previous one read as uniforms.],
  [A barrier's `srcStageMask` is `VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT`. Does it wait for a copy recorded before it? Use @fig-stages to explain.],
  [Explain availability and visibility using two compute units with private caches, one writing a value and one reading it.],
  [Why is `VK_PIPELINE_STAGE_2_NONE` a correct source scope for an image's first transition from `UNDEFINED`? When would it be wrong for a transition from `UNDEFINED`?],
  [Two dispatches write disjoint halves of a buffer, and a third reads all of it. Which barriers are needed, and where? Would two buffer barriers with ranges be better than one global barrier?],
)

#checklist(
  [I can state what an execution dependency and a memory dependency each guarantee.],
  [I can choose stage and access masks for any producer and consumer, and say what the stage expansion covers.],
  [I can place layout transitions and explain what they do to an image's memory.],
  [I can use chains, and write barriers with the five-step procedure.],
  [Lab 3.2.1–3.2.4 done-when criteria all hold, with evidence filed.],
)
