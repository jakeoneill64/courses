#import "../lib/template.typ": *

= Queues and async compute <ch-queues>

#chapter-meta(
  time: [6 hours],
  builds: [An upload on a transfer queue whose buffer is handed to the main queue with a queue family ownership transfer, and the same upload with a buffer shared concurrently by both families; and a measurement of two independent workloads on one queue and on two, which shows when a second queue doubles the throughput and when it barely helps.],
  needs: [Chapters 3.1 to 3.4.],
)

#why[
  A GPU has more than one way in. Most expose several queues, often in families with different abilities: one for everything, one for compute and copies, one for copies alone. Work on different queues can run at the same time, which lets a frame overlap its simulation with its drawing, or stream data in while it renders. The price is that Vulkan's ordering guarantees stop at the edge of a queue. Between queues there is only what semaphores provide, and a resource used by two queue families must be handed from one to the other explicitly.
]

#skip-test(
  rule: [If all four are easy, read the section on measuring overlap and do Labs 3.5.2 and 3.5.3.],
  [Two queues of different families use one buffer in turn. What does an `EXCLUSIVE` buffer need between the uses that a `CONCURRENT` one does not?],
  [A release barrier is recorded on the transfer queue and an acquire on the main queue. What orders the acquire after the release?],
  [When does a second queue make independent work finish sooner, and when does it not?],
  [Why can a timestamp written on one queue not be compared with one written on another?],
)

== Core ideas

=== Queue families

Chapter 1.1 listed the device's queue families: each has flags saying which commands its queues accept, and a number of queues. Graphics and compute commands need a family with those flags; any family that supports either also supports transfers. On a desktop GPU, a typical arrangement is one family for everything, a family of compute-only queues for _async compute_, and a transfer-only family whose queues drive the copy engines. The M2 Pro has four families of one queue each, all able to do everything.

The project asks `vkf` for a second compute queue and a transfer queue, in families other than the main queue's where the device has them:

#console(read("/src/console/u3-queues-timing.txt"), caption: [The project on the M2 Pro: three families, two uploads and the overlap, with validation off])

Commands submitted to one queue begin in submission order, and the barriers of Chapter 3.2 order them. Commands on different queues have no order at all unless a semaphore gives them one, and a barrier on one queue says nothing about another.

=== Sharing a resource between families

A buffer or image is created with a _sharing mode_. An `EXCLUSIVE` resource is owned by one queue family at a time, and the program must transfer ownership to use its contents in another family. A `CONCURRENT` resource lists the families that will use it and can be used by any of them without a transfer. Concurrent sharing is simpler and may be slower: a driver can lay out or compress an exclusive image for one kind of hardware, which concurrent sharing prevents.

#snippet("u3/queues/main.cpp", "concurrent", caption: [A buffer shared by two families])

A _queue family ownership transfer_ is a pair of barriers with the same family indices, the same resource and, for an image, the same layout transition. The _release_ is recorded on the source queue: its source scope is the work that wrote the resource, and its destination scope is empty, because nothing on that queue uses the resource afterwards.

#snippet("u3/queues/main.cpp", "release", caption: [Copying on the transfer queue, then releasing the buffer to the main queue's family])

A semaphore then orders the two queues, and the _acquire_ is recorded on the destination queue. Its destination scope is the work that will use the resource; its source scope matches the semaphore's wait stage, so that the acquire is chained after the wait and therefore after the release.

#snippet("u3/queues/main.cpp", "acquire", caption: [Acquiring the buffer on the main queue before reading it])

#snippet("u3/queues/main.cpp", "upload-submit", caption: [A semaphore between the transfer queue and the main queue])

The release and the acquire together form a dependency: the release makes the copy's writes available, and the acquire makes them visible to the compute shader. The semaphore's signal stage, `ALL_COMMANDS`, covers the release, which executes as part of the barrier on the transfer queue.

#hazard(title: [Pitfall])[
  An ownership transfer preserves contents. A resource whose old contents will not be read, because the next family overwrites it, needs no transfer: without one, its contents are undefined in the new family, which is exactly what an overwrite expects. A resource whose contents matter and that skips the transfer can work on one GPU and show corrupted data on another. The validation layer reports an acquire with no matching release when the work is submitted, but cannot see a use that should have had both.
]

=== Async compute

The project's second experiment runs two independent workloads, each a dispatch whose invocations repeat a dependent chain of arithmetic. Each runs once on one queue, once on one queue with an execution barrier between them, and once on two queues, one dispatch each.

#snippet("u3/queues/main.cpp", "two-queues", caption: [One dispatch on the main queue and one on the compute queue])

With 8 workgroups, each workload occupies a small part of the GPU and takes 10.6 ms. On one queue they take 21.4 ms, whether or not a barrier separates them: MoltenVK runs the dispatches of one queue's Metal encoder one after another, whatever the barriers allow. On two queues they take 11.0 ms, almost exactly one workload's time. With 2,048 workgroups, each workload fills the GPU by itself, and two queues save only 9%: there is little idle hardware left for the second queue to use.

That is the rule for async compute. A second queue pays when the work on the first leaves hardware idle: a shadow pass that rasterises without shading, a frame's tail of small dispatches, a simulation that cannot fill the GPU alone. It pays little when both workloads are limited by the same resource, such as memory bandwidth, and it can slow the first queue's work by competing for caches. On a desktop driver, the two dispatches on one queue may overlap without a barrier, so the gap between one queue and two may be smaller there; measure on the hardware you ship for.

`VkDeviceQueueCreateInfo` takes a priority between 0 and 1 for each queue, which drivers may use when queues compete. Two queues of one family may or may not map to separate hardware queues; separate families are a better sign that they do.

=== Measuring across queues

Timestamps can only be compared when they were written on the same queue, so the project times each queue's work on that queue, and the overlap with the CPU's clock: from the first submission to the last fence. `VK_KHR_calibrated_timestamps` relates each queue's timestamps to a CPU clock where a finer comparison is needed.

#keyidea[
  Commands on different queues are ordered only by semaphores. An `EXCLUSIVE` resource whose contents must survive a change of family needs a release on one queue and a matching acquire on the other, chained by the semaphore's wait stage. A second queue makes independent work finish sooner only when the first leaves hardware idle.
]

#opengl[
  OpenGL has one implicit queue per context. Several contexts can share objects and be used from several threads, but the driver decides whether their work runs concurrently, and none of it is exposed: there are no queue families, no ownership and no way to put compute beside graphics deliberately.
]

#reading(
  [The Vulkan specification, "Queue Family Ownership Transfer" and "Resource Sharing Mode".],
  [The Khronos wiki page "Synchronization Examples": the sections on transfers between queue families and on async compute.],
  [AMD GPUOpen, "Concurrent execution: asynchronous queues", on what async compute overlaps on AMD hardware.],
)

== Labs

#lab([Map your queues], goal: [Know what your GPU offers.], time: [1 hour], code: "code/u3/queues")[
  + List your device's queue families with `u1_devices` or `vulkaninfo`, with their flags, queue counts and `timestampValidBits`.
  + Run `u3_queues` and `u3_queues --shared-queue` and note which families `vkf` chose.
  #done-when(
    [You have a table of your families.],
    [You can say which of them allow async compute and transfers in parallel, and what `vkf` picks when a device has only one family.],
  )
  #evidence([The table and the two outputs.])
]

#lab([Hand over an image], goal: [Transfer ownership with a layout transition.], time: [1.5 hours], code: "code/u3/queues")[
  + Upload an image on the transfer queue: transition it from `UNDEFINED` for the copy, copy from a buffer, and release it to the main family with a transition to `GENERAL`.
  + Acquire it on the main queue with the same transition, and read it with `imageLoad` in a compute shader.
  #done-when(
    [The values read match the uploaded ones, and validation is silent.],
    [You can explain on which queue the transition happens, and why both barriers must name it.],
  )
  #evidence([The code and the output.])
]

#lab([Find the overlap], goal: [Measure where a second queue stops helping.], time: [1.5 hours], code: "code/u3/queues")[
  + Run the overlap experiment with 8, 32, 128, 512 and 2,048 workgroups, keeping each workload's total work constant by adjusting the steps.
  + Plot the time on two queues against the time on one.
  #done-when(
    [You have the plot.],
    [You can explain where the gain disappears in terms of how many workgroups your GPU can run at once.],
  )
  #evidence([The plot and the explanation.])
]

#lab([Break the transfer], goal: [Learn what validation sees.], time: [1 hour], code: "code/u3/queues")[
  + Remove the release, keeping the acquire, and run with validation on.
  + Restore it, remove the acquire instead, and run again.
  #done-when(
    [You have both outputs.],
    [You can explain why one mistake is reported and the other is not, and what the second could do on a GPU that compresses buffers or caches them per family.],
  )
  #evidence([The two outputs and the explanation.])
]

#problems(
  [Why must the acquire barrier's source stage match the semaphore's wait stage? What happens if it is `NONE`?],
  [A buffer written on the transfer queue is overwritten entirely by a compute shader on the main queue, which never reads the old contents. Does it need an ownership transfer? A semaphore?],
  [How would you measure, on the GPU's clock, how long the two queues' work overlapped?],
  [Two workloads limited by memory bandwidth run on two queues. Predict the result, and explain it with Chapter 2.5's roofline.],
  [A device has one family with 16 queues that support everything. Is creating two of them async compute? How would you find out?],
)

#checklist(
  [I can choose queues from the device's families and order their work with semaphores.],
  [I can transfer ownership of a buffer or image between families, and know when no transfer is needed.],
  [I can choose between exclusive and concurrent sharing, and say what each costs.],
  [I can measure whether async compute pays for a workload on my GPU.],
  [Lab 3.5.1–3.5.4 done-when criteria all hold, with evidence filed.],
)
