#import "../lib/template.typ": *

= Fences, semaphores and events <ch-primitives>

#chapter-meta(
  time: [5 hours],
  builds: [A pipeline in which the host produces inputs and the GPU processes them, driven by one timeline semaphore with every submission made before its input exists, and compared with the same pipeline on fences; a chain of two submissions joined by a binary semaphore; and a split barrier with an event, measured against barriers in either of its two positions.],
  needs: [Chapters 3.1 to 3.3.],
)

#why[
  Barriers order commands within a queue's stream of work. A program also needs to know when work has finished, to make one submission wait for another, and to let the host and the GPU hand data back and forth without either sitting idle. Vulkan has four primitives for these jobs, and choosing the wrong one costs either correctness or overlap. This chapter puts each to work and measures what it costs on the course's machine.
]

#skip-test(
  rule: [If all four are easy, read the sections on timeline semaphores and events, and do Labs 3.4.1 and 3.4.3.],
  [Which primitive lets the host wait for the GPU, which lets one submission wait for another, and which can do both?],
  [The host writes a buffer after submitting the command buffer that reads it. What makes the GPU wait for the write, and what makes the write visible?],
  [Why can a binary semaphore not be waited on before its signal has been submitted, when a timeline semaphore can?],
  [What does a split barrier let the GPU do that a pipeline barrier does not?],
)

== Core ideas

=== Four primitives

@tbl-primitives summarises the four. A _fence_ tells the host that a submission has finished. A _binary semaphore_ makes one submission wait for another. A _timeline semaphore_ does both, and more: it holds a 64-bit counter that only increases, which submissions and the host can wait on and signal. An _event_ splits a pipeline barrier in two within one queue.

#figure(
  tbl(columns: (auto, auto, auto, 1fr), header: ([Primitive], [Signalled by], [Waited on by], [Typical use]), size: 8.2pt,
    [Fence], [A submission], [The host], [Knowing that a submission's resources can be reused],
    [Binary semaphore], [A submission, or presentation], [One later submission], [Ordering submissions across queues, and the swapchain (Chapter 4.2)],
    [Timeline semaphore], [Submissions or the host, with a value], [Submissions or the host, for a value], [Frames in flight, host and device pipelines, async compute],
    [Event], [A command], [A later command in the same queue], [Letting independent work run between a producer and its consumer],
  ),
  caption: [Vulkan's synchronisation primitives beyond barriers],
  kind: table,
) <tbl-primitives>

All four obey the dependency model of Chapter 3.2: a signal operation has a first synchronisation scope, the commands before it, and a wait has a second, the commands after it. The stage masks given with a semaphore name the stages that must finish before the signal, and the stages that must wait.

=== Fences

A fence is signalled when every command of the submission that names it has completed, and it makes all their memory writes available. The host waits for it with `vkWaitForFences`, and must reset it with `vkResetFences` before submitting with it again. The project's fence pipeline gives each of three slots a fence: it fills a slot's input, submits, and checks the slot's result three submissions later, when the slot comes round again.

#snippet("u3/timeline/main.cpp", "fence-loop", caption: [A ring of three slots, each with its own fence])

The writes the host makes before `vkQueueSubmit2` need no barrier: a submission makes every host write that came before it visible to the work it submits, once non-coherent memory has been flushed. The results need a barrier to the host stage in the command buffer: the fence orders the host's reads after the GPU's work, but only a barrier whose destination is the host makes the GPU's writes visible to it (Chapter 3.2).

=== Binary semaphores

A binary semaphore has two states. A submission signals it when the commands before the signal have completed, and a later submission waits for it, with the stages that must wait. Each signal is consumed by exactly one wait, and the wait must not be submitted before its signal is. Within one queue, the semaphore below joins two submissions so that the second reads what the first wrote; across queues, the same pattern is the only way to order work (Chapter 3.5).

#snippet("u3/timeline/main.cpp", "binary-chain", caption: [Two submissions joined by a binary semaphore])

A semaphore signal makes the writes of its first scope available, and the wait makes them visible to its second scope, so no barrier is needed between the two submissions.

=== Timeline semaphores

A timeline semaphore holds a counter. A wait names a value and completes when the counter reaches it; a signal names a value and sets the counter to it. Submissions signal and wait through `VkSemaphoreSubmitInfo`, and the host can do both too: `vkSignalSemaphore` sets the value from the CPU, and `vkWaitSemaphores` blocks until a value is reached, with a timeout. A timeline semaphore can replace both fences and binary semaphores, and one semaphore serves any number of submissions.

Unlike a binary semaphore, a timeline semaphore can be waited on before anything has been submitted to signal it, which is called _wait-before-signal_. The project uses it to submit each item's command buffer before the host has written that item's input. Item _i_ waits for value $2i + 1$, which the host signals once the input is written, and signals $2i + 2$ when its result is ready:

#snippet("u3/timeline/main.cpp", "timeline-helpers", caption: [Submitting an item, and signalling and waiting on the host])

Because the host writes after the submission, the submission does not cover those writes. The command buffer therefore begins with a barrier from the host's writes to the shader's reads, and the semaphore wait orders it after the host's signal:

#snippet("u3/timeline/main.cpp", "record-item", caption: [An item's commands: from the host, the dispatch, back to the host])

The loop keeps three items in flight. It submits each item as soon as its slot is free, fills the input, and signals when the input is ready:

#snippet("u3/timeline/main.cpp", "timeline-loop", caption: [Driving the pipeline from one timeline])

#console(read("/src/console/u3-timeline-timing.txt"), caption: [Two thousand items both ways, with validation off])

The timeline version is correct and slower than the fences, 6,043 items per second against 7,631. The cause is a rule about values. A timeline's value only increases, and the host may signal a value only if it is lower than every signal still pending on the GPU. While item _i_ is pending with its signal of $2i + 2$, the host cannot signal $2i + 3$, so it must wait for item _i_ before releasing item $i + 1$: one semaphore carrying both directions forces the host and the GPU to take turns. Lab 3.4.1 gives each direction a timeline of its own.

=== Events

A pipeline barrier waits for its source scope and blocks its destination scope at one point in the command stream. An event splits that point in two: `vkCmdSetEvent2` marks where the source scope ends, `vkCmdWaitEvents2` marks where the destination scope begins, and commands recorded between them may run while the producer finishes. Both take the same `VkDependencyInfo`.

#snippet("u3/events/main.cpp", "split", caption: [One dependency, used three ways])

The project runs three dispatches: A, B, which is independent of A and twice as long, and C, which reads A's output. A barrier where the set goes makes B wait for A; a barrier where the wait goes makes C wait for B as well as A; the event makes C wait for A alone. Events used only by commands are created with `VK_EVENT_CREATE_DEVICE_ONLY_BIT`, which tells the driver that the host never sets, resets or reads them:

#snippet("u3/events/main.cpp", "event", caption: [A device-only event])

#console(read("/src/console/u3-events-timing.txt"), caption: [The three placements, with validation off])

The event saves a quarter of the time. Its 8.1 ms is what A and B side by side, followed by C, would take: A and B overlap, but C still starts after B. Both barriers take the same 10.6 ms, although the barrier where the wait goes leaves A and B free to overlap. MoltenVK runs the dispatches of one Metal compute encoder one after another, and ends the encoder at each event command, which is what lets A overlap B here. On a desktop driver, the barrier where the wait goes may save as much as the event does here, and the event more. An event pays only where the hardware can overlap the work around it, so measure before keeping one.

#hazard(title: [Pitfall])[
  On a portability implementation such as MoltenVK, events are one of the optional features of `VK_KHR_portability_subset`, and a feature is enabled only if the program chains `VkPhysicalDevicePortabilitySubsetFeaturesKHR` into device creation with it set. The course's own `vkf` once enabled the extension without the structure, and every event it created was invalid: the validation layer reported `VUID-vkCreateEvent-events-04468`. Enable the portability features you use, and run validation on a Mac before trusting code written elsewhere.
]

=== Waiting for idle

`vkQueueWaitIdle` and `vkDeviceWaitIdle` wait for everything submitted to a queue or a device. They are correct and simple, and right at shutdown, before destroying objects, and in tests. In a loop they serialise the CPU and the GPU: the host waits for all work instead of the work it needs, and nothing is queued while it waits. Prefer a fence or a timeline value that names exactly the work you depend on.

#keyidea[
  Use a fence or a timeline value to know when work is done, a semaphore to order submissions, and an event to let independent work run between a producer and its consumer. Host writes made before a submission are covered by it; host writes made after it need a semaphore to order them and a barrier to make them visible.
]

#opengl[
  `glFenceSync` and `glClientWaitSync` are OpenGL's fences, and `glWaitSync` makes the server wait for one, which is as close as OpenGL comes to a semaphore. There is no counterpart to timeline semaphores or events: the driver decides how much work overlaps, and a program cannot submit work before its inputs exist.
]

#reading(
  [The Vulkan specification, "Synchronization and Cache Control": the sections on fences, semaphores and events.],
  [The Khronos Group, "Vulkan Timeline Semaphores", 2019: the extension's introduction, with examples.],
  [The Khronos wiki page "Synchronization Examples" in the Vulkan-Docs repository, in particular the sections on semaphores and events.],
)

== Labs

#lab([Two timelines], goal: [Let the host and the GPU run independently.], time: [1.5 hours], code: "code/u3/timeline")[
  + Replace the single timeline with two: one the host signals when an input is ready, and one the GPU signals when a result is ready.
  + Measure items per second with two, three and four slots, with validation off.
  #done-when(
    [Every item is correct, and validation is silent.],
    [Your version beats the single timeline, and you can explain how it compares with the fences.],
  )
  #evidence([The changes and the table.])
]

#lab([Wait before signal], goal: [See a wait that no submission can satisfy.], time: [1 hour], code: "code/u3/timeline")[
  + Submit one item that waits for a timeline value, without signalling it, and call `vkWaitSemaphores` for the item's result with a timeout of one second.
  + Then signal the value from the host and wait again.
  + Try the same with a binary semaphore that nothing has signalled, with validation on.
  #done-when(
    [The first wait times out and the second succeeds.],
    [You have the validation message from the binary semaphore, and can explain why the rule differs between the two kinds.],
  )
  #evidence([The output and the message.])
]

#lab([Where events pay], goal: [Predict when a split barrier saves time.], time: [1 hour], code: "code/u3/events")[
  + Change the program so that B's work is half of, equal to and four times A's.
  + Time A, B and C alone, predict each variant's time from those, and compare with the measurements.
  #done-when(
    [Your predictions are within 10% of the measurements.],
    [You can explain why the two barrier placements take the same time on your device, or why they do not.],
  )
  #evidence([The table of predictions and measurements.])
]

#lab([What idling costs], goal: [Measure an idle wait against a fence.], time: [1 hour], code: "code/u3/timeline")[
  + In the fence pipeline, replace the wait for each slot's fence with `vkQueueWaitIdle` after every submission.
  + Measure items per second against the original.
  #done-when(
    [Both versions are correct, with validation silent.],
    [You can explain the difference from what each wait lets the host do while the GPU works.],
  )
  #evidence([The two measurements and the explanation.])
]

#problems(
  [A fence is submitted a second time without being reset. What does the validation layer report, and what would a driver do without it?],
  [Two submissions wait on the same signal of one binary semaphore. What is wrong, and how would you express the same dependency correctly?],
  [In the timeline loop, why can the host not signal $2i + 3$ as soon as it has written item $i + 1$'s input?],
  [`vkCmdWaitEvents2` must be given the same `VkDependencyInfo` as `vkCmdSetEvent2`. Why does the wait need the source scope at all?],
  [When is `vkDeviceWaitIdle` the right call, and what does it cost inside a frame loop?],
)

#checklist(
  [I can choose between fences, binary and timeline semaphores, and events for each kind of dependency.],
  [I can drive a host and device pipeline from timeline semaphores, including waits submitted before their signals.],
  [I can tell when a submission covers host writes, and when they need a semaphore and a barrier.],
  [I can split a barrier with an event, and measure whether it pays on my device.],
  [Lab 3.4.1–3.4.4 done-when criteria all hold, with evidence filed.],
)
