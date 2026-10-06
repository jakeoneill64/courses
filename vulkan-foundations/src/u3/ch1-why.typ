#import "../lib/template.typ": *

= Why synchronisation is your job <ch-why-sync>

#chapter-meta(
  time: [4 hours],
  builds: [A catalogue of nine producer and consumer scenarios, each protected by its barrier and checked; then each run with its barrier removed, to see what synchronisation validation reports and whether the results go wrong.],
  needs: [Unit 1, and Chapters 2.1 and 2.2.],
)

#why[
  Units 1 and 2 placed a barrier wherever one was needed and explained it only briefly. This unit is about writing barriers yourself: correctly, and no more of them than the work needs. This chapter shows why they are needed at all: what a GPU does with your commands when nothing constrains it, what OpenGL's driver used to do in your place, and the three kinds of hazard that every barrier exists to prevent. The rest of the unit builds the model (Chapter 3.2), the patterns (3.3), the other primitives (3.4 to 3.6), the tools (3.7) and finally a render graph that writes the barriers for you (3.8).
]

#skip-test(
  rule: [If all four are easy, read the section on synchronisation validation and do Lab 3.1.3.],
  [Commands A and B are recorded in that order in one command buffer, with nothing between them. Does Vulkan guarantee that A finishes before B starts? That B sees what A wrote?],
  [Name the three kinds of hazard, and say which of them needs only an execution dependency.],
  [Why can a read go wrong after a write that has already finished?],
  [The CPU writes a mapped buffer after calling `vkQueueSubmit2` for a dispatch that reads it. What may the dispatch see?],
)

== Core ideas

=== The device timeline

Chapter 1.3 introduced the device's timeline: the queue runs submitted work later than, and independently of, the host. Within that timeline, Vulkan promises less than you might expect. Commands recorded into a command buffer, command buffers in a batch, and batches submitted to one queue are in _submission order_, which Vulkan uses to define what each barrier applies to. Submission order does not make one command wait for another, and says nothing about when commands finish. A GPU starts the next command as soon as it can, so that compute units freed by one dispatch's last workgroups can begin the next dispatch's first ones, and two commands with nothing between them can overlap and finish in either order (@fig-overlap).

#fig("u3-overlap", caption: [Two dispatches on four compute units. Without a barrier, B's workgroups start on each unit as soon as A's leave it, while A is still running elsewhere. With a barrier, B waits until A has finished everywhere and A's writes have been made visible.]) <fig-overlap>

Ordering is only half of the problem. A write by a shader goes first into a cache, often one private to the compute unit that made it. Another compute unit that reads the same address may find an older value in its own cache, or in memory, even after the write has finished. For one command to see another's writes, those writes must be made _available_, written back from the caches that hold them to where others can reach them, and then _visible_ to the reader, with any stale copies in the reader's caches discarded. A pipeline barrier does both, as well as ordering the commands. Chapter 3.2 makes these ideas precise.

=== What OpenGL's driver did

An OpenGL driver tracks the last command that wrote each buffer and texture. When a later command reads one, the driver inserts the waits and the cache operations itself, usually conservatively. The exception is memory written by shaders, whose addresses the driver cannot know in advance: since OpenGL 4.2, a program must call `glMemoryBarrier` with bits that name how the data will be read next, such as `GL_SHADER_STORAGE_BARRIER_BIT` or `GL_COMMAND_BARRIER_BIT`.

That tracking costs CPU time on every call, synchronises more than the work needs because the driver must assume the worst, and cannot express what the program knows, such as that two pieces of work are independent and may overlap. Vulkan removes it: the driver tracks nothing, and every ordering between commands is one you record.

=== Three kinds of hazard

A _hazard_ is a pair of accesses to the same memory whose result depends on their order. There are three kinds (@fig-hazard-kinds). A _read after write_ (RAW) needs the write to finish, and its result to be made visible, before the read. A _write after read_ (WAR) needs the read to finish before the write overwrites what it reads; nothing needs to be made visible, so an execution dependency alone suffices. A _write after write_ (WAW) needs the second write to land last, and the first write's data made available before it, so that a late write-back cannot overwrite the second. Two reads never conflict.

#fig("u3-hazard-kinds", caption: [The three hazards. Only the write after read can be prevented by ordering alone.]) <fig-hazard-kinds>

=== A catalogue of hazards

`u3_hazards` runs nine producer and consumer scenarios, one per common situation, and checks every result on the CPU. Each records its barrier with the raw synchronization2 structures. The first is the case Unit 2 met in every multi-pass kernel: one dispatch writes a buffer and the next reads it.

#snippet("u3/hazards/main.cpp", "compute-compute", caption: [Read after write between two dispatches])

A `VkMemoryBarrier2` names two _synchronisation scopes_. The source scope, `srcStageMask` and `srcAccessMask`, describes the earlier work and the writes that must be made available: compute shaders, and their writes to storage. The destination scope, `dstStageMask` and `dstAccessMask`, describes the later work that must wait and the accesses that must see the writes: compute shaders, and their reads of storage. `VkDependencyInfo` collects any number of such barriers, and `vkCmdPipelineBarrier2` records them. Chapter 3.2 explains every field.

The write after read needs only the ordering. Its barrier names the stages and leaves both access masks empty:

#snippet("u3/hazards/main.cpp", "war", caption: [Write after read: an execution dependency, with no memory dependency])

#console(read("/src/console/u3-hazards.txt"), caption: [All nine scenarios, each with its barrier, checked on the M2 Pro])

=== Removing the barriers

With `--bug`, each scenario leaves its barrier out, or in two cases breaks the synchronisation another way, and the program reports what synchronisation validation said and whether the results were wrong. The first case shows the usual outcome:

#console(read("/src/console/u3-hazards-bug-compute-compute.txt"), caption: [The read after write without its barrier])

@tbl-hazard-bugs summarises all nine. Synchronisation validation found every hazard between two commands, and the results were correct in every one of those cases on the M2 Pro: its GPU happened to finish the first command before starting the second. The two hazards between the host and the device are different. The validation layer does not track the host's accesses, so it reported neither, and one of them produced wrong results.

#figure(
  tbl(columns: (auto, auto, 1fr, auto), header: ([Case], [Hazard], [Validation reported], [Results]),
    [`compute-compute`], [RAW], [`SYNC-HAZARD-READ-AFTER-WRITE`], [correct],
    [`war`], [WAR], [`SYNC-HAZARD-WRITE-AFTER-READ`], [correct],
    [`waw`], [WAW], [`SYNC-HAZARD-WRITE-AFTER-WRITE`], [correct],
    [`transfer-compute`], [RAW], [`SYNC-HAZARD-READ-AFTER-WRITE`], [correct],
    [`compute-transfer`], [RAW], [`SYNC-HAZARD-READ-AFTER-WRITE`], [correct],
    [`compute-indirect`], [RAW], [`SYNC-HAZARD-READ-AFTER-WRITE`], [correct],
    [`host-device`], [RAW], [nothing: host accesses are not tracked], [1,029,416 values wrong],
    [`device-host`], [RAW], [nothing: host accesses are not tracked], [correct],
    [`image-layout`], [RAW], [`SYNC-HAZARD-WRITE-AFTER-WRITE`, against the layout transition], [correct],
  ),
  caption: [The nine scenarios with their synchronisation removed or broken, on the M2 Pro],
  kind: table,
) <tbl-hazard-bugs>

The case that went wrong writes on the host. The correct version finishes writing a mapped buffer before submitting the dispatch that reads it, because host writes made before `vkQueueSubmit2` are visible to the submitted work. The broken version submits first and writes afterwards, while the GPU is already reading:

#snippet("u3/hazards/main.cpp", "host-device", caption: [Host writes before and after the submission that reads them])

#console(read("/src/console/u3-hazards-bug-host-device.txt"), caption: [Writing after the submission: the GPU read the buffer while the CPU was still writing it])

The GPU read a mixture of old and new values, and almost every result was wrong. No layer can catch this, because the bug is in what the CPU does between two Vulkan calls.

#keyidea[
  Without a barrier, two commands are unordered, and a write need not be visible to anyone else. A barrier creates an ordering and makes writes visible at one point in the command stream, and nothing else in Vulkan does. A correct result proves only that the timing was kind on that occasion.
]

=== Synchronisation validation

Synchronisation validation records, for every range of every buffer and image, the last accesses made to it, with their stages and access types, and the barriers recorded since. When a new access arrives, it checks whether those barriers order it after every conflicting earlier access and make the earlier writes visible to it. If not, it reports the hazard, the two commands involved, and the stages and accesses that a barrier would need to connect, which is usually enough to write the barrier. It also checks the boundaries between command buffers and between submissions, including semaphores.

It has three limits that this chapter has shown or that matter later. It does not see host accesses, so the rules for mapped memory are yours to keep. It does not see races inside a single dispatch, such as those of Chapter 2.2. And it learns which buffers a shader reads and writes from a static analysis of the SPIR-V, the heuristic that the course's code enables, which can occasionally report a hazard that cannot happen. Every program in this unit runs with synchronisation validation on and must be silent.

#opengl[
  In OpenGL, the two dispatches of the first case need `glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)` between them, the indirect dispatch needs `GL_COMMAND_BARRIER_BIT`, and a buffer read back by `glGetBufferSubData` after a shader wrote it needs `GL_BUFFER_UPDATE_BARRIER_BIT`. Copies need nothing, because the driver tracks them, and neither do the host cases, because `glBufferSubData` and `glGetBufferSubData` wait for the GPU when they must. Every one of those implicit waits is a barrier, or a stall, that Vulkan leaves to you.
]

#reading(
  [The Vulkan specification, chapter "Synchronization and Cache Control", the introduction and the section "Execution and Memory Dependencies".],
  [Hans-Kristian Arntzen, "Yet another blog explaining Vulkan synchronization" (2019), the sections up to pipeline barriers.],
  [The validation layer's documentation on synchronisation validation, in the Vulkan-ValidationLayers repository.],
)

== Labs

#lab([Run the catalogue], goal: [See every hazard reported, or not, on your GPU.], time: [1 hour], code: "code/u3/hazards")[
  + Run `build/bin/u3_hazards` and confirm that all nine cases pass.
  + Run each case with `--case NAME --bug`, and build your own version of @tbl-hazard-bugs.
  + For one RAW case, one WAR case and the image case, read the full validation message and identify the stages and accesses it says a barrier must connect.
  #done-when(
    [Your table has nine rows, with what was reported and whether the results were correct.],
    [For three cases, the barrier you would write from the message matches the one in the code.],
  )
  #evidence([The table and the three messages, annotated.])
]

#lab([Try to make a hazard show], goal: [Learn how much timing hides.], time: [1.5 hours], code: "code/u3/hazards")[
  + In a copy of the compute-compute case, make the producer slower, for example by repeating its work in a loop, and the consumer faster, and run it with the barrier removed.
  + Try at least three variations of size and work, with validation on and off, and record whether the results go wrong.
  + Run the host-device case with `--bug` several times and record how many values are wrong each time.
  #done-when(
    [You have recorded the outcome of every variation.],
    [You can explain why your GPU did or did not produce wrong results, and why that tells you nothing about other GPUs.],
  )
  #evidence([The variations, their outcomes and your explanation.])
]

#lab([Write the barriers yourself], goal: [Place every barrier in a chain of commands.], time: [1.5 hours], code: "code/u3/hazards")[
  + Add a case that runs this chain: fill buffer `a` with a dispatch; copy `a` to `b`; transform `b` into `a` with a dispatch; copy `a` to the readback buffer; read it on the host.
  + Write the barriers it needs with raw `VkMemoryBarrier2` structures, and check the result.
  + Remove each barrier in turn, predict what synchronisation validation will report, and run.
  #done-when(
    [The chain runs correctly with validation silent.],
    [Each of your predictions names the hazard type and the two commands, and matches the report.],
  )
  #evidence([The barriers with a sentence each, and the predictions next to the reports.])
]

#problems(
  [Give an example of each kind of hazard from the programs of Units 1 and 2.],
  [Why does a write after read need no access masks? What would adding them cost, if anything?],
  [A barrier between a dispatch that writes a buffer and one that reads it has both stage masks set to `VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT` and both access masks empty. Is the program correct? What will synchronisation validation report?],
  [Explain why, on the M2 Pro, the host-device bug produced wrong results while every missing barrier between commands did not.],
  [For each of the nine scenarios, give the OpenGL call, if any, that would order it, and say what the OpenGL driver does when no call is needed.],
)

#checklist(
  [I can explain what submission order guarantees and what it does not.],
  [I can explain availability and visibility, and why finished writes may still be invisible.],
  [I can name the three hazards, and say which needs a memory dependency.],
  [I can read a synchronisation validation message and write the barrier it asks for, and I know what the layer cannot see.],
  [Lab 3.1.1–3.1.3 done-when criteria all hold, with evidence filed.],
)
