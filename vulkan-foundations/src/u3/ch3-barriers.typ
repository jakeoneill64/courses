#import "../lib/template.typ": *

= Pipeline barriers in practice <ch-barriers>

#chapter-meta(
  time: [6 hours],
  builds: [A seven-pass compute pipeline, from generating a field to an indirect dispatch and a read on the host, with the fewest barriers it can have, checked against the CPU; and an experiment that measures what barriers cost, precise and over-wide, between dependent and independent dispatches.],
  needs: [Chapter 3.2.],
)

#why[
  Chapter 3.2 gave the model and a procedure for applying it. This chapter is about using it well in real command streams: a catalogue of the patterns that recur in compute and graphics work, a pipeline of several passes with exactly the barriers it needs and no others, and a measurement of what barriers cost. A barrier is the point where the GPU stops overlapping work, so every unnecessary barrier, and every barrier wider than it needs to be, can leave hardware idle.
]

#skip-test(
  rule: [If all four are easy, read the section on cost and do Labs 3.3.2 and 3.3.3.],
  [A compute pass writes a vertex buffer that the next draw reads. Write the barrier's four masks.],
  [Two independent dispatches each write a buffer that a third reads. How many barriers do you need, and where?],
  [A barrier's source scope is the compute stage. Which earlier dispatches does it wait for: the one that wrote the data, or all of them?],
  [Why might `VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT` with `MEMORY_WRITE` and `MEMORY_READ` be correct but slow?],
)

== Core ideas

=== A catalogue of dependencies

@tbl-catalogue extends Chapter 3.2's list with the graphics cases that Unit 4 meets. Each row is one hazard; a real program finds its rows, then batches the barriers that fall at the same point.

#figure(
  tbl(columns: (1fr, 1fr, 1.6fr), header: ([Producer], [Consumer], [Source → destination, and layouts]), size: 7.8pt,
    [dispatch writes storage], [dispatch reads or writes it], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `COMPUTE_SHADER`, `SHADER_STORAGE_READ` (and `_WRITE`)],
    [dispatch reads storage], [dispatch writes it], [`COMPUTE_SHADER`, none → `COMPUTE_SHADER`, none],
    [copy, fill or update writes], [dispatch reads], [`COPY`, `CLEAR` or `TRANSFER`, `TRANSFER_WRITE` → `COMPUTE_SHADER`, `SHADER_STORAGE_READ`],
    [dispatch writes], [copy reads, for readback], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `COPY`, `TRANSFER_READ`],
    [dispatch writes parameters], [indirect dispatch or draw], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `DRAW_INDIRECT`, `INDIRECT_COMMAND_READ`],
    [dispatch writes vertices], [draw reads them], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `VERTEX_ATTRIBUTE_INPUT`, `VERTEX_ATTRIBUTE_READ`],
    [dispatch writes indices], [indexed draw], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `INDEX_INPUT`, `INDEX_READ`],
    [dispatch writes an image], [draw samples it], [`COMPUTE_SHADER`, `SHADER_STORAGE_WRITE` → `FRAGMENT_SHADER`, `SHADER_SAMPLED_READ`; `GENERAL` → `SHADER_READ_ONLY_OPTIMAL`],
    [draw renders an image], [dispatch reads it], [`COLOR_ATTACHMENT_OUTPUT`, `COLOR_ATTACHMENT_WRITE` → `COMPUTE_SHADER`, `SHADER_SAMPLED_READ`; `COLOR_ATTACHMENT_OPTIMAL` → `SHADER_READ_ONLY_OPTIMAL`],
    [copy writes an image], [draw samples it], [`COPY`, `TRANSFER_WRITE` → `FRAGMENT_SHADER`, `SHADER_SAMPLED_READ`; `TRANSFER_DST_OPTIMAL` → `SHADER_READ_ONLY_OPTIMAL`],
    [device writes], [host reads after a fence], [the writer's stage and access → `HOST`, `HOST_READ`; then invalidate if not coherent],
    [host writes], [submitted work reads], [no barrier: write and flush before `vkQueueSubmit2`],
  ),
  caption: [The dependencies this course uses, with prefixes and suffixes left out as in Chapter 3.2],
  kind: table,
) <tbl-catalogue>

=== A pipeline of seven passes

`u3_passes` runs a small image-analysis pipeline over a 512 × 512 field of values and checks its final statistics against the CPU (@fig-passes). It generates the field into an image; computes a blur and an edge measure of it in two independent passes; selects the cells whose blur is high and whose edge measure is low, counting them with atomics and listing their indices; writes an indirect dispatch command sized to the number selected; scores the selected cells in that indirect dispatch; and copies the statistics to the host. It has seven barriers, one at each point where data passes between passes, and no more.

#fig("u3-passes", caption: [The pipeline and its four barriers between passes. Before them, a transition takes the field's image from `UNDEFINED` to `GENERAL`; after them, two barriers carry the statistics to a copy and then to the host.]) <fig-passes>

The first barrier serves two consumers. The blur and the edge passes both read the field and write different buffers, so neither needs a barrier against the other, and they may run at the same time:

#snippet("u3/passes/main.cpp", "before-filters", caption: [One barrier for two independent consumers])

Before the selection, two dependencies meet: the filters' outputs, written by shaders, and the statistics buffer, cleared by `vkCmdFillBuffer` at the start of the command buffer and about to be updated atomically. One `VkDependencyInfo` carries both barriers, so the device synchronises once:

#snippet("u3/passes/main.cpp", "before-select", caption: [Two barriers batched into one call])

The command pass writes a `VkDispatchIndirectCommand`, which the indirect dispatch reads at the `DRAW_INDIRECT` stage, before any shader runs; a barrier that named only the compute stage as its destination would not cover that read:

#snippet("u3/passes/main.cpp", "before-score", caption: [Indirect parameters written by a shader])

#console(read("/src/console/u3-passes.txt"), caption: [The pipeline, checked against the CPU, followed by the cost experiment, with validation on])

=== What a barrier costs

A barrier is where the GPU stops overlapping work. It must let every command in the source scope finish before anything in the destination scope starts, so the compute units drain, wait and fill again; with small dispatches, that bubble can cost more than the work. The second half of `u3_passes` measures it: 256 small dispatches, first as a chain in which each depends on the last, then as a set of independent dispatches writing separate ranges of a buffer, with precise barriers, with full `ALL_COMMANDS` barriers, and, for the independent set, with none.

#snippet("u3/passes/main.cpp", "cost-record", caption: [The dispatches of the cost experiment, with a barrier of the chosen kind between them])

The independent dispatches select their range of the buffer with a _dynamic offset_: the descriptor's type is `VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC`, and each `vkCmdBindDescriptorSets` supplies an offset that is added to the binding's, so one descriptor set serves every range.

#console(read("/src/console/u3-passes-timing.txt"), caption: [The cost experiment with validation off, median of 50 runs])

#fig("u3-cost", caption: [256 dispatches of 16,384 elements on the M2 Pro. Any barrier makes each dispatch cost about 20 µs; without barriers, independent dispatches overlap and cost about 3 µs each.]) <fig-cost>

On the M2 Pro the scope of the barrier hardly mattered, but its presence did. With a barrier between each pair, every dispatch cost about 20 µs whether the barrier was precise or covered all commands and all memory. Without barriers, the independent dispatches cost 3.2 µs each, because the GPU could run many at once. Precise barriers only where needed, a barrier between each dependent pair and none in the independent set, took 6.2 ms in all; a full barrier after every dispatch took 11.1 ms.

The scope matters more on other GPUs and in other situations. A source scope of `ALL_COMMANDS` waits for every earlier command on the queue, including graphics work or copies that have nothing to do with the data, and `MEMORY_WRITE` with `MEMORY_READ` can make a driver flush and invalidate caches that a narrower barrier would leave alone. Lab 3.3.2 measures both on your GPU.

#keyidea[
  A barrier waits for all earlier work in its source stages, not just for the command you had in mind. Independent work recorded before a barrier is caught by it, and independent work recorded after it is held back. Minimise the number of barriers first, and their width second.
]

=== Placing and batching barriers

A few habits keep barriers few and narrow:

- *Batch.* Collect every barrier needed at one point into one `VkDependencyInfo`. One call lets the driver synchronise once.
- *Do not separate independent work.* Dispatches that touch different data need nothing between them, as the blur and edge passes show.
- *Prefer global barriers for buffers.* They cost the same as buffer barriers on most hardware, and cannot miss a buffer. Keep image barriers for layout transitions and ownership transfers.
- *Delay what you can.* A barrier placed just before the consumer gives the producer's work the longest time to overlap with whatever comes between, provided the barrier's source stages do not include that work. When they would, events (Chapter 3.4) or a second queue (Chapter 3.5) can separate the two.
- *Let a tool do it.* A render graph derives and batches barriers from declarations of what each pass reads and writes. Chapter 3.8 builds one.

#opengl[
  `glMemoryBarrier` is always global and always waits for every earlier command; `GL_ALL_BARRIER_BITS` is OpenGL's version of the full barrier above. Drivers also insert their own barriers between draws and dispatches when they detect a hazard, and a program cannot see or remove them. Vulkan's barriers cost something too, but every one is in your code, where you can count and measure it.
]

#reading(
  [The Vulkan Guide, "Synchronization Examples", the compute and transfer sections, and the graphics sections for Unit 4.],
  [The Vulkan specification, "Pipeline Barriers" and the valid-usage list of `vkCmdPipelineBarrier2`.],
  [NVIDIA, "Vulkan Dos and Don'ts", the section on barriers.],
)

== Labs

#lab([Justify every barrier], goal: [Read a real pipeline's barriers against the model.], time: [1 hour], code: "code/u3/passes")[
  + For each of the seven barriers in `Passes::record`, write the hazard it prevents, the producer and the consumer, and why each mask has the value it has.
  + Remove the second barrier of the batch before the selection, the one for the fill, and run with validation on.
  + Change the destination of the barrier before the score from `DRAW_INDIRECT` to `COMPUTE_SHADER`, keeping the access, and run again.
  #done-when(
    [Your notes justify every field of every barrier.],
    [You have recorded and explained both validation reports.],
  )
  #evidence([The seven justifications and the two reports.])
]

#lab([Measure barriers on your GPU], goal: [Find out what barriers cost on your hardware.], time: [1.5 hours], code: "code/u3/passes")[
  + Run `VKF_VALIDATION=0 build/bin/u3_passes --repeats 50` three times and record the cost table.
  + Run again with `--elements 4096` and with `--elements 262144`, which set the elements per dispatch.
  + Plot the cost per dispatch against the elements per dispatch, with and without barriers.
  #done-when(
    [You have the plot, from three runs at each size.],
    [You can state at what dispatch size a barrier's cost stops mattering on your GPU, and whether its scope matters there.],
  )
  #evidence([The plot and your conclusion.])
]

#lab([Independent work across a barrier], goal: [See a barrier catch work it was not meant for.], time: [1.5 hours], code: "code/u3/passes")[
  + Record a second, independent copy of the pipeline, on its own buffers and image, and time running the two one after the other.
  + Interleave the two copies pass by pass, keeping every barrier, and time again.
  + Explain the result with the definition of a barrier's source scope.
  #done-when(
    [Both versions produce correct results with validation silent.],
    [You can explain why interleaving did or did not help, and name the two features that could help.],
  )
  #evidence([The two timings and your explanation.])
]

#lab([Batch and unbatch], goal: [Measure what batching saves.], time: [1 hour], code: "code/u3/passes")[
  + Split the batch before the selection into two `vkCmdPipelineBarrier2` calls, and time the pipeline with validation off.
  + Then merge the barriers before the filters and before the selection into one point, moving the edge pass after the blur pass's barrier, and explain why that is or is not still correct.
  #done-when(
    [You have timings for the batched and unbatched versions, from three runs each.],
    [Your explanation of the merged version uses the hazards involved.],
  )
  #evidence([The timings and the explanation.])
]

#problems(
  [A compute pass writes a vertex buffer that the next draw reads. Write the `VkMemoryBarrier2`. Write it again for the same buffer used as an index buffer.],
  [A render pass draws into an image that a compute pass then reads with a sampler. Write the image barrier, with its layouts.],
  [Why does a barrier between two dependent dispatches also delay an unrelated dispatch recorded before it? What would change if the unrelated dispatch were recorded after the barrier?],
  [On the M2 Pro each barrier between small dispatches cost about 20 µs. How many such barriers would fill a 60 Hz frame, and why is that the wrong way to budget them?],
  [The batch before the selection holds two global barriers. Could it be one barrier? Write it, and say what it would cost or gain.],
)

#checklist(
  [I can find the dependency for any producer and consumer in the catalogue, including graphics ones.],
  [I can give a multi-pass pipeline exactly the barriers it needs, batched.],
  [I can explain what a barrier costs, and why its source scope catches unrelated work.],
  [I can measure barrier costs and judge when they matter.],
  [Lab 3.3.1–3.3.4 done-when criteria all hold, with evidence filed.],
)
