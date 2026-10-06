#import "../lib/template.typ": *

= Commands and submission <ch-commands>

#chapter-meta(
  time: [5 hours],
  builds: [A program that records fill and copy commands, submits them, waits on a fence and checks the result on the CPU; then measures staging against direct writes and the cost of a submission.],
  needs: [Chapter 1.2.],
)

#why[
  Nothing you create in Vulkan does any work until you record commands and submit them to a queue. Recording and submission are separate on purpose: you can record on any thread, ahead of time, and submit many command buffers in one call, so the driver's cost per command stays small. The price is that the GPU runs your work later, on its own timeline, and you have to say when the CPU may touch the results. This chapter introduces both timelines and the first two synchronisation tools: barriers inside a command buffer and fences between the GPU and the CPU.
]

#skip-test(
  rule: [If all four are easy, skim the core ideas and do Labs 1.3.3 and 1.3.4.],
  [Name the states of a command buffer, and what moves it between them.],
  [Why may you not overwrite a staging buffer immediately after `vkQueueSubmit2` returns, and how do you know when you may?],
  [`vkCmdFillBuffer` writes a buffer and `vkCmdCopyBuffer` then reads it. What must be recorded between them, and why does the order of recording not suffice?],
  [A program submits one command buffer two hundred times in a single `vkQueueSubmit2`. What must it have declared when it began recording?],
)

== Core ideas

=== Command pools and command buffers

A _command buffer_ holds a sequence of commands for the device. You allocate command buffers from a _command pool_, which owns their memory and belongs to one queue family: command buffers from a pool may only be submitted to queues of that family.

#snippet("u1/commands/main.cpp", "pool", caption: [A pool on the queue family we use, and a primary command buffer from it])

The flag `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT` allows each command buffer to be reset on its own, either with `vkResetCommandBuffer` or implicitly when recording begins again. Without it, the only way to reuse command buffers is to reset the whole pool with `vkResetCommandPool`, which is cheaper and is what most renderers do once per frame. `VK_COMMAND_POOL_CREATE_TRANSIENT_BIT` tells the driver that command buffers will be short-lived.

A pool and the command buffers allocated from it are _externally synchronised_: two threads must not use them at the same time. Vulkan does not lock anything for you. Programs that record on several threads give each thread its own pool, which Chapter 4.6 does.

_Primary_ command buffers are submitted to queues. _Secondary_ command buffers are executed from primaries with `vkCmdExecuteCommands`; they exist so that several threads can record parts of one rendering pass, and Chapter 4.6 uses them too.

=== Recording

Recording starts with `vkBeginCommandBuffer` and ends with `vkEndCommandBuffer`. Every command in between is a `vkCmd*` call that appends to the buffer and does nothing else: no work starts until submission. Usage flags at the beginning describe how the buffer will be submitted. `VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT` promises a single submission, which lets some drivers record more cheaply.

#snippet("u1/commands/main.cpp", "begin", caption: [Beginning a command buffer that will be submitted once])

A command buffer moves through a small set of states. It starts _initial_; `vkBeginCommandBuffer` makes it _recording_; `vkEndCommandBuffer` makes it _executable_; submission makes it _pending_ until the device finishes with it, after which it is executable again, or _invalid_ if it was a one-time submission. Resetting it returns it to initial. A pending command buffer may not be reset, re-recorded or freed, and submitting it again while it is still pending requires `VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT`.

=== Transfer commands

The simplest commands move bytes. They run on any queue whose family supports transfer, which includes every graphics or compute family.

- `vkCmdFillBuffer` writes a repeated 32-bit value; the offset and size must be multiples of 4.
- `vkCmdUpdateBuffer` copies up to 65536 bytes of data that are stored inside the command buffer itself. It suits small constant blocks; anything larger belongs in a staging buffer.
- `vkCmdCopyBuffer` copies regions between buffers.
- `vkCmdCopyBufferToImage` and `vkCmdCopyImageToBuffer` move texels between buffers and images, translating between a buffer's rows and an image's tiling. `vkCmdCopyImage` copies between images.
- `vkCmdBlitImage`, which scales and converts formats, and `vkCmdClearColorImage` complete the set. Blits require a graphics queue.

=== Barriers: a first look

Commands recorded in a command buffer start in the order you recorded them, but nothing makes one finish before the next begins. A GPU overlaps commands wherever it can, and writes may sit in caches where a later command cannot see them. When one command reads what another wrote, you must record a _pipeline barrier_ between them, which states two things: which earlier work must finish first (its _stage_), and which writes must be made visible to which later accesses (its _access masks_).

#snippet("u1/commands/main.cpp", "barrier", caption: [A global memory barrier in its synchronization2 form])

`srcStageMask` and `srcAccessMask` describe the earlier work: here, the stage of the fill command and its writes. `dstStageMask` and `dstAccessMask` describe the later work that must wait and the accesses that must see the writes. Unit 3 is devoted to this model; for now, one barrier between every writer and the reader that follows is enough.

The program below fills a device-local buffer, copies it into a host-visible buffer and reads it on the CPU. It needs two barriers. The first orders the copy's reads after the fill's writes. The second makes the copy's writes available to the host, whose reads are a stage of their own, `VK_PIPELINE_STAGE_2_HOST_BIT`.

#snippet("u1/commands/main.cpp", "record", caption: [Fill, copy to host-visible memory, and wait])

Remove the first barrier and the program still prints the right answer on the GPU used to write this course: the fill happened to finish before the copy started. Synchronisation validation is not fooled.

#console(read("/src/console/u1-commands-nobarrier.txt"), caption: [Synchronisation validation names the hazard, both commands, and the stages and accesses that a barrier must connect])

#hazard(title: [Pitfall])[
  A program that runs correctly without a barrier is not correct. It ran on one GPU, with one driver, at one load. The same program may fail on another GPU, or on the same GPU when the copy is larger or the queue is busier. Synchronisation validation, which checks the rules instead of the outcome, is the only reliable test.
]

=== Submission and fences

`vkQueueSubmit2` hands batches of command buffers to a queue. Each `VkSubmitInfo2` is one batch: its command buffers, and optionally semaphores to wait for before it starts and to signal when it completes (Chapter 3.4). The call returns as soon as the work is queued, usually long before the device has started it.

To learn when the work has finished, pass a _fence_. A fence is a two-state object that the queue signals when every batch in the submission has completed; the host waits for it with `vkWaitForFences`, which takes a timeout in nanoseconds, or polls it with `vkGetFenceStatus`. Before a fence can be used again it must be reset with `vkResetFences`. Unit 1's `submitAndWait` creates a fence, submits one command buffer, waits and destroys the fence.

#snippet("u1/shared/basics.hpp", "submit-and-wait", caption: [Submitting one command buffer and waiting for it])

Creating and destroying a fence for every submission is wasteful, and Lab 1.3.4 measures by how much. Waiting immediately after every submission is worse: the CPU sits idle while the GPU works, and then the GPU sits idle while the CPU records the next batch. Real programs keep several submissions in flight, as Chapter 3.6 shows.

=== Two timelines

@fig-timeline shows what happens in time. The host records and submits; the device runs the commands later, at its own pace; the fence connects the two when the host needs a result. Between submission and the wait the host is free to do other work, but it must not touch anything the submitted commands use. In particular it must not overwrite a staging buffer whose copy has not yet run, free memory the commands read, or reset the command buffer while it is pending.

#fig("u1-timeline", caption: [The host and device timelines. Submission returns immediately; the device runs the work later; the fence tells the host when it has finished.]) <fig-timeline>

#keyidea[
  Every Vulkan program runs on at least two timelines: the host's and each queue's. Submission and fences are the only places where they meet, and everything you share between them must be handed over at one of those places.
]

=== Staging in practice

The program's second experiment uploads 64 MiB into a device-local buffer through a staging buffer, as Chapter 1.2 described. The barrier at the end makes the copy visible to compute shaders that will read the buffer, which is what an upload is for.

#snippet("u1/commands/main.cpp", "staged-upload", caption: [Uploading through a staging buffer, timed from the first byte written to the copy's completion])

The program then writes the same 64 MiB directly into memory that is both device-local and host-visible, when the device has such a type, and compares the two. It finishes by measuring what a submission costs, waiting for each submission in turn and then batching two hundred submissions of the same empty command buffer into one call.

#snippet("u1/commands/main.cpp", "overhead", caption: [Two hundred synchronous submissions, then the same two hundred in one batch])

#console(read("/src/console/u1-commands.txt"), caption: [`u1_commands` with validation off on an Apple M2 Pro])

On the M2 Pro, with unified memory, writing directly is faster than staging, because staging writes the data twice. On a discrete GPU the answer depends on the bus and on how the data is used. Writing through a resizable BAR mapping sends the CPU's writes across PCIe as they happen, which avoids the second copy but keeps the CPU busy for the whole transfer. A staged copy lets the CPU write at the speed of system memory and leaves the transfer to the GPU's copy engine, which can overlap other work. Reading BAR memory from the CPU is very slow either way. Measure on your own machine in Lab 1.3.3.

The submission figures show why batching matters. A submission followed by a wait costs about 20 µs, most of it in the round trip between the CPU and the GPU; batched, each command buffer costs well under a microsecond. Submission is not free, but the cost per command buffer is small when you submit many at once and do not wait.

#hazard(title: [Pitfall])[
  The batch above lists the same command buffer two hundred times. The first copy is pending while the second is submitted, so the command buffer must have been recorded with `VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT`. Without it, the validation layer reports that the command buffer "is already in use and is not marked for simultaneous use". The flag can make recording or execution slower on some drivers, so use it only when you need it.
]

#snippet("u1/commands/main.cpp", "simultaneous", caption: [Declaring that a command buffer may be pending more than once])

#opengl[
  OpenGL records commands into a driver-managed buffer as you call them, and decides itself when to send them to the GPU. `glFlush` asks it to send what it has; `glFinish` waits for everything to complete, like a `vkQueueWaitIdle`; a fence sync object, created with `glFenceSync` and waited on with `glClientWaitSync`, corresponds to a Vulkan fence. Between commands, the OpenGL driver tracks which buffer and texture each command writes and inserts the barriers itself; the exception is shader writes to buffers and images, for which OpenGL 4.2 introduced `glMemoryBarrier` because the driver cannot see which addresses a shader will touch. Vulkan asks you for every barrier, including those for copies.
]

#reading(
  [The Vulkan specification, chapters "Command Buffers" (lifecycle, recording and submission), "Copy Commands", "Clear Commands", and the "Fences" section of "Synchronization and Cache Control".],
  [The Vulkan Guide, "Queues", "Synchronization" and "Common Pitfalls for New Vulkan Developers".],
  [Khronos, "Synchronization Examples" in the Vulkan Guide, the transfer cases only; Unit 3 covers the rest.],
)

== Labs

#lab([Fill, update, copy and read back], goal: [Record and verify a short chain of transfer commands.], time: [1 hour], code: "code/u1/commands")[
  + Run `build/bin/u1_commands` and confirm `fill, copy and read back 1 MiB: ok`.
  + After the fill, add a `vkCmdUpdateBuffer` that writes the first 256 bytes with the values 0 to 63 as `uint32_t`, with the barrier it needs.
  + Extend the check on the CPU to expect both patterns.
  #done-when(
    [The read-back data matches both patterns.],
    [The program runs with no validation errors, and you can say which stages and accesses your new barrier connects.],
  )
  #evidence([The recorded commands, with a sentence per barrier.])
]

#lab([Remove each barrier in turn], goal: [See what synchronisation validation reports, and compare it with what happens.], time: [45 minutes], code: "code/u1/commands")[
  + Remove the barrier between the fill and the copy, run, and record the message and the printed result.
  + Restore it and remove the barrier between the copy and the host read instead. Run again and record what happens.
  + Restore both.
  #done-when(
    [For each removal you have recorded whether validation reported it, what it named, and whether the result was still correct.],
    [You can explain why a correct result proves nothing here.],
  )
  #evidence([Both messages, or the absence of one, with your explanation.])
]

#lab([Staging against direct writes], goal: [Find out which upload path is faster on your machine, and when.], time: [1.5 hours], code: "code/u1/commands")[
  + Run the program with `VKF_VALIDATION=0` three times and record both upload timings.
  + Make the size a command-line option and measure 1, 4, 16, 64 and 256 MiB.
  + On a discrete GPU, find out whether resizable BAR is enabled: is there a device-local, host-visible type, and is its heap the size of VRAM?
  #done-when(
    [You have a table of both paths at five sizes, from three runs each.],
    [You can explain the result from your device's memory types.],
  )
  #evidence([The table and the memory types it depends on.])
]

#lab([What a submission costs], goal: [Measure submission overhead and the ways to reduce it.], time: [1.5 hours], code: "code/u1/commands")[
  + Remove `VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT`, run with validation on, and record the message.
  + Restore it. Change `submitAndWait` to create its fence once and reset it before each submission, and measure the change in cost per synchronous submission.
  + Measure the batched cost per command buffer for batches of 1, 10, 100 and 1000.
  #done-when(
    [You have the cost per synchronous submission with and without fence reuse, and the batched cost at four batch sizes, with validation off.],
    [The program runs with no validation errors.],
  )
  #evidence([The timings, and a sentence on what dominates the cost of a synchronous submission.])
]

#problems(
  [Draw the lifecycle of a command buffer allocated from a pool created with `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT`, from allocation through two submissions to freeing. Mark the transitions that are invalid while it is pending.],
  [Why are command pools externally synchronised instead of being made thread-safe by the driver, and how does a program that records on eight threads organise its pools?],
  [A program calls `vkQueueSubmit2` for an upload and immediately writes the next upload's data into the same staging buffer. What can go wrong, and what are two correct alternatives?],
  [When would you use `vkCmdUpdateBuffer` and when a staging buffer with `vkCmdCopyBuffer`? State the restrictions on the first.],
  [A synchronous submission costs about 20 µs on the machine above. Why is "a 60 Hz frame can afford 800 of them" the wrong conclusion?],
)

#checklist(
  [I can create command pools and command buffers, record transfer commands, and explain the command buffer lifecycle.],
  [I can record a barrier between a writer and a reader, and between the device and the host.],
  [I can submit work with `vkQueueSubmit2` and wait for it with a fence.],
  [I can explain the host and device timelines and what each may touch when.],
  [Lab 1.3.1–1.3.4 done-when criteria all hold, with evidence filed.],
)
