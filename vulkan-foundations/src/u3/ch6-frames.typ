#import "../lib/template.typ": *

= Frames in flight <ch-frames>

#chapter-meta(
  time: [5 hours],
  builds: [A loop that renders frames without a window, in which the CPU prepares each frame's inputs and the GPU computes an image from them, run with one, two and three frames in flight. Per-frame resources live in rings, one timeline semaphore paces the loop, a palette replaced every sixteen frames is destroyed only when no frame can still read it, and every frame's image is checked against a checksum the CPU computed.],
  needs: [Chapters 3.1 to 3.4.],
)

#why[
  A real-time program has two processors working on every frame. If the CPU waits for each frame to finish before preparing the next, the GPU idles while the CPU works and the CPU idles while the GPU works, and the frame takes the sum of both. Keeping more than one frame _in flight_ lets each processor work on a different frame at once, so that a frame takes only as long as the slower of the two. The cost is that every resource the CPU writes for a frame must exist once per frame in flight, and nothing may be destroyed while a frame in flight can still use it.
]

#skip-test(
  rule: [If all four are easy, read the section on deferred destruction and do Labs 3.6.2 and 3.6.3.],
  [With two frames in flight, which per-frame resources need two copies, and which can be shared?],
  [Before reusing the resources of frame _n_ − 2, what must the CPU wait for, and how does one timeline semaphore express it?],
  [A buffer that frames still in flight may read must be replaced. When can the old one be destroyed?],
  [What does a third frame in flight buy over a second, and what does it cost?],
)

== Core ideas

=== Pipelining the CPU and the GPU

The project's frames are a stand-in for a renderer's: for each frame, the CPU spends 1.8 ms generating 16,384 seeds and the checksum the frame's image must have, and the GPU spends 1.1 ms turning the seeds into a 256 × 256 image, which is copied back to the host. With one frame in flight the CPU prepares a frame, submits it, and waits for it before preparing the next, so the two processors take turns (@fig-frames).

#fig("u3-frames", caption: [The measured frame times as a timeline. With one frame in flight a frame costs the CPU's time plus the GPU's, and more; with two it costs the larger of the two.]) <fig-frames>

#console(read("/src/console/u3-frames-timing.txt"), caption: [Three hundred frames with one, two and three in flight, with validation off])

With one frame in flight a frame takes 3.6 ms: 1.8 ms of CPU work, and 1.8 ms of waiting, which is the GPU's 1.1 ms plus the time to submit the work, have it start, and learn that it finished. With two in flight it takes 1.8 ms, the CPU's work alone, and the CPU never waits: the CPU is now the limit, and the GPU idles a third of the time. A third frame changes nothing, because nothing is left to overlap.

=== Rings of per-frame resources

Everything the CPU writes for a frame must not be written again while the GPU may still be reading it. With _F_ frames in flight, each such resource becomes a _ring_ of _F_ copies, and frame _f_ uses copy _f_ mod _F_. Here that means the seeds, the readback buffer, the command buffer, the GPU timer and the descriptor set; in a renderer, the uniform buffers and the per-frame descriptor sets as well. Resources that only the GPU touches, one frame after another, can be shared. The project's image is one such: each frame overwrites it, and a barrier orders the overwrite after the previous frame's copy, since frames run in submission order on one queue.

#snippet("u3/frames/main.cpp", "record-frame", caption: [Each frame discards the previous frame's image after its copy has read it])

#snippet("u3/frames/main.cpp", "record-copy", caption: [Copying the frame's image into the frame's slot of the readback ring])

=== Pacing with a timeline semaphore

One timeline semaphore paces the loop. Frame _f_'s submission signals the value _f_ + 1 when it completes. Before frame _f_ reuses slot _f_ mod _F_, the CPU waits for the value _f_ − _F_ + 1, which says that frame _f_ − _F_, the last user of the slot, has finished; it can then check that frame's result and overwrite its resources.

#snippet("u3/frames/main.cpp", "pace", caption: [Waiting for the frame that last used this slot, then checking its result])

#snippet("u3/frames/main.cpp", "submit-frame", caption: [Re-recording the slot's command buffer and submitting the frame])

The command buffer is re-recorded every frame, because its descriptor set changes with the palette; a program whose commands never change could record one per slot once. The descriptor set itself is updated in place, which is allowed because the frame that last used it has finished.

=== Deferred destruction

Every sixteen frames the program replaces the palette that the shader reads. The old palette cannot be destroyed at once, because frames already submitted may still read it. It is _retired_ instead: kept, with the timeline value after which no frame can use it, and destroyed when the semaphore passes that value.

#snippet("u3/frames/main.cpp", "retired", caption: [A resource waiting for the frames that may use it])

#snippet("u3/frames/main.cpp", "deferred", caption: [Destroying what the GPU has finished with, and retiring the old palette])

The same pattern serves every resource a renderer replaces while it runs: textures streamed out, buffers resized, pipelines rebuilt. The program reports that each palette lived at most one frame beyond its replacement, which is as soon as the timeline allows.

=== How many frames in flight

Two frames in flight are enough when the CPU and the GPU each take less than a frame's budget. A third hides variation: when one frame's CPU work is unusually long, the GPU still has a frame queued. Each frame in flight costs memory for its ring of resources and, for an interactive program, latency: the image on screen reflects input sampled one frame earlier for every frame queued ahead of it. Chapter 4.2 adds presentation, whose own images and semaphores interact with this loop.

#keyidea[
  Give everything the CPU writes for a frame a ring of as many copies as there are frames in flight, pace the loop with one timeline semaphore whose value counts finished frames, and retire replaced resources until the semaphore passes the last frame that could use them.
]

#opengl[
  An OpenGL driver keeps frames in flight on the program's behalf: it buffers commands, renames buffers that the program overwrites with `glBufferData`, and blocks in `SwapBuffers` when it is too far ahead. Persistently mapped buffers, from OpenGL 4.4, make the program responsible again, with `glFenceSync` playing the part of the timeline semaphore.
]

#reading(
  [The Vulkan Guide, "Synchronization", on frames in flight with a swapchain.],
  [Hans-Kristian Arntzen, "Yet another blog explaining Vulkan synchronization", 2017, on the frame loop's dependencies.],
  [The Khronos wiki page "Synchronization Examples": the section on swapchain image acquire and present.],
)

== Labs

#lab([Who limits the frame], goal: [Make each processor the bottleneck in turn.], time: [1 hour], code: "code/u3/frames")[
  + Run with `--cpu-rounds` set to 8, 48 and 96, with validation off.
  + For each, record the frame time with one, two and three frames in flight.
  #done-when(
    [You have a table of nine frame times.],
    [You can predict each from the CPU and GPU columns, and say when a third frame in flight helps.],
  )
  #evidence([The table and the predictions.])
]

#lab([Break the ring], goal: [See what happens when a frame overwrites another's inputs.], time: [1 hour], code: "code/u3/frames")[
  + Make every frame write its seeds to the first slot of the seed ring, and bind that slot in its descriptor set.
  + Run with two frames in flight and `--cpu-rounds 1`, so that the CPU writes the next frame's seeds while the GPU still runs the current one, with validation on and then off.
  #done-when(
    [You have the checksum counts from both runs.],
    [You can explain why the validation layer says nothing, and why the damage may vary from run to run.],
  )
  #evidence([The outputs and the explanation.])
]

#lab([Destroy too soon], goal: [Find an off-by-one in deferred destruction.], time: [1 hour], code: "code/u3/frames")[
  + Retire the old palette with the value _f_ − 1 instead of _f_, and run with three frames in flight and validation on.
  #done-when(
    [You have the validation message.],
    [You can explain which frame could still read the palette, and why the message names a command buffer.],
  )
  #evidence([The message and the explanation.])
]

#lab([Measure the latency], goal: [Put a number on what frames in flight cost.], time: [1.5 hours], code: "code/u3/frames")[
  + Record, for each frame, the CPU time at which its seeds were prepared and the time at which its result was checked.
  + Report the median latency with one, two and three frames in flight.
  #done-when(
    [You have the three latencies.],
    [You can explain why the latency grows with frames in flight while the frame time does not.],
  )
  #evidence([The changes and the numbers.])
]

#problems(
  [With two frames in flight the CPU never waits, and the frame takes 1.8 ms. Which processor limits the frame rate, and what would make a third frame useful?],
  [Why can the image be shared by every frame while the seeds need a ring? What would change if the GPU wrote the seeds?],
  [The palette is retired with the value _f_. Why not _f_ + 1, and why not _f_ − 1?],
  [Show that waiting for the value _f_ − _F_ + 1, with _F_ = 1, is waiting for the previous frame to finish.],
  [A game samples input at the start of each frame and runs three frames in flight at 60 frames per second. Estimate the delay between input and its effect on screen, before presentation adds its own.],
)

#checklist(
  [I can pipeline the CPU and the GPU with frames in flight and measure the result.],
  [I can decide which resources need a ring and which can be shared.],
  [I can pace a frame loop with one timeline semaphore.],
  [I can defer the destruction of replaced resources until no frame can use them.],
  [Lab 3.6.1–3.6.4 done-when criteria all hold, with evidence filed.],
)
