#import "../lib/template.typ": *

= Finding synchronisation bugs <ch-bugs>

#chapter-meta(
  time: [6 hours],
  builds: [A catalogue of six classic synchronisation bugs, each a small program that fails the way real programs do, with what the validation layer said about it and whether its results went wrong; their fixes; and a field guide to what synchronisation validation cannot see, measured on the course's machine, with a method for the bugs it misses.],
  needs: [Chapters 3.1 to 3.6.],
)

#why[
  A synchronisation bug rarely announces itself. The program that contains it usually gives the right answer on the machine it was written on, because that GPU happened to finish one command before starting the next, and fails on another GPU, on a newer driver, or one frame in a thousand. Testing results is therefore not enough. This chapter collects the bugs that recur in real programs, shows how each is found, and maps the places where the tools are blind, so that you know when a silent validation layer proves something and when it does not.
]

#skip-test(
  rule: [If all four are easy, read the section on blind spots and do Labs 3.7.2 and 3.7.4.],
  [A barrier names the right stages and no access masks. What is wrong, and will the results show it?],
  [Which pipeline stage does `vkCmdFillBuffer` run in?],
  [A semaphore wait names the compute stage, and the first command after it is a copy. What can go wrong?],
  [Name three kinds of synchronisation error that the validation layer cannot report.],
)

== Core ideas

=== Bugs that pass their tests

`u3_bugs` contains six programs, each with a classic mistake that `--bug` switches on. @tbl-bugs summarises what happened to each on the M2 Pro.

#figure(
  tbl(columns: (auto, 1.3fr, 1fr, auto), header: ([Bug], [The mistake], [Found by], [Results]), size: 7.8pt,
    [missing-visibility], [A barrier with the right stages and empty access masks], [Synchronisation validation, read after write], [correct],
    [wrong-stage], [`COPY` named as the stage of `vkCmdFillBuffer`, which runs in `CLEAR`], [Synchronisation validation, read after write], [correct],
    [layout-mismatch], [A copy from an image left in `GENERAL`, declared `TRANSFER_SRC_OPTIMAL`], [Core validation, at recording], [correct],
    [war-reuse], [A buffer uploaded again while the last dispatch may still read it], [Synchronisation validation, write after read], [wrong],
    [host-coherency], [Mapped memory used without flushes or invalidations], [Nothing on this device], [correct],
    [semaphore-stage], [A semaphore wait at the compute stage before a copy reads], [Synchronisation validation, at submission], [correct],
  ),
  caption: [Six classic bugs on the M2 Pro],
  kind: table,
) <tbl-bugs>

Five of the six gave the right answer. Only the reused buffer produced wrong results, because its upload raced a dispatch that was still reading. Without the validation layer, five of these programs would have passed every test on this machine.

=== Reading a report

A synchronisation validation report names the command that found the hazard, the kind of hazard, the resource, and the earlier access it conflicts with, and then states the stages and accesses that a barrier must connect. Object names given with `VK_EXT_debug_utils`, which `vkf` sets whenever it is given a name, label the handles with words such as `[a]`. The first bug's report is typical:

#console(read("/src/console/u3-bugs-missing-visibility.txt"), caption: [An execution dependency without a memory dependency, reported])

The read at the compute stage was ordered after the write, but the write was never made visible to it. The fix is in the report's last sentence: a source access of `SHADER_STORAGE_WRITE` and a destination access of `SHADER_STORAGE_READ`, at the stages already named.

#snippet("u3/bugs/main.cpp", "missing-visibility", caption: [The first bug, and its fix])

=== The catalogue

The second bug names the wrong stage. `vkCmdFillBuffer` and `vkCmdUpdateBuffer` are _clear_ commands and run in `VK_PIPELINE_STAGE_2_CLEAR_BIT`, so a barrier whose source is `COPY` does not wait for them. The layer reports a read after write at the dispatch, naming the stage the write really happened in:

#snippet("u3/bugs/main.cpp", "wrong-stage", caption: [The stage of a fill is `CLEAR`])

The third bug leaves an image in the wrong layout. The copy declares `TRANSFER_SRC_OPTIMAL`, but no barrier ever moved the image there. This is a core validation error, reported when the copy is recorded, because the layer tracks each subresource's layout through the command buffer:

#snippet("u3/bugs/main.cpp", "layout-mismatch", caption: [A transition the copy depends on])

#console(read("/src/console/u3-bugs-layout-mismatch.txt"), caption: [The layout the copy declares does not match the layout the image is in])

The fourth bug reuses a buffer. A loop uploads data into one buffer, dispatches a kernel that reads it, and uploads the next batch into the same buffer. Without a barrier, the next upload may overwrite the buffer while the last dispatch still reads it, a write after read. An execution dependency is enough to prevent it, as the report says, because the hazard involves no earlier write to make visible; the fix's destination access also covers the next copy's write after the previous copy's.

#snippet("u3/bugs/main.cpp", "war-reuse", caption: [Waiting for the last reader before uploading again])

#console(read("/src/console/u3-bugs-war-reuse.txt"), caption: [The only bug of the six whose results went wrong on the M2 Pro])

The fifth bug forgets that mapped memory may not be coherent. The host's writes to memory without `HOST_COHERENT` reach the device only after `vkFlushMappedMemoryRanges`, and the device's writes reach the host's view only after `vkInvalidateMappedMemoryRanges`, in addition to the barriers and fences that order them.

#snippet("u3/bugs/main.cpp", "flush", caption: [Flushing host writes before the device reads them])

#snippet("u3/bugs/main.cpp", "invalidate", caption: [Invalidating before the host reads the device's writes])

Every host-visible memory type on the M2 Pro is coherent, so on this machine the bug cannot be observed, and the layer does not track host accesses at all. A program written here and run on a GPU with non-coherent memory types, which several mobile and some desktop GPUs have, can fail with nothing to show for it.

The sixth bug waits too late in the pipeline. A semaphore wait's stage mask says which stages of the waiting submission must wait. Here the first command after the wait is a copy, but the wait names only the compute stage, so the copy may read before the signalling submission has written. The report comes at `vkQueueSubmit2`, where synchronisation validation checks the dependencies between submissions:

#snippet("u3/bugs/main.cpp", "semaphore-stage", caption: [A wait stage that must cover the first reader])

#console(read("/src/console/u3-bugs-semaphore-stage.txt"), caption: [A hazard across submissions, found at submission])

=== Blind spots

Synchronisation validation is the best tool there is, and it cannot see everything. The course's programs found these limits in version 1.4.363 of the layer:

- *Host accesses.* The layer does not track the host, so missing host barriers, flushes and invalidations go unreported (Chapter 3.1's `host-device` case and the fifth bug above).
- *Accesses through device addresses.* Shaders that reach buffers through `GL_EXT_buffer_reference` are invisible to it (Chapter 2.6).
- *Atomics.* The layer counts atomic operations as reads. A missing barrier after a pass whose only writes are atomics goes unreported, and a barrier that orders such a pass but makes nothing visible passes.
- *Aliased images.* Hazards between buffers that share memory are reported; hazards between images that share memory with each other or with buffers are not, which matters for the aliasing of Chapter 3.8.
- *Ownership transfers.* An acquire without a release is a core error at submission; a release without an acquire, followed by a use, is silent.
- *Races within a dispatch.* Invocations of one dispatch that race through shared or global memory are outside its model (Chapter 2.2).

It can also be wrong the other way. With the shader-access heuristic that `vkf` enables, the layer assumes that a shader accesses the whole of every buffer bound to it. Two dispatches that write disjoint slices of one buffer bound whole are reported as a write after write. Binding each dispatch's slice, with a separate descriptor or a dynamic offset, as Chapter 3.3's cost experiment does, removes the report without a barrier.

=== A method for what validation misses

When results are wrong and the layer is silent, or a bug appears on one GPU only:

+ *Use the big hammer.* Replace every barrier with one whose masks are `ALL_COMMANDS` and `MEMORY_READ` with `MEMORY_WRITE`, and wait for the device to go idle after each submission. If the bug disappears, it is very likely synchronisation; restore the real barriers one at a time to find it.
+ *Widen the window.* A missing dependency shows only if the consumer runs before the producer finishes. Make the producer slower, with more work or a spin loop, and run the program many times.
+ *Change the hardware.* Run on GPUs from more than one vendor, or on a software implementation such as Mesa's lavapipe, which schedules work differently.
+ *Look inside.* Capture the work with RenderDoc or Xcode and inspect the buffers between commands, or print from shaders with debug printf (Chapter 1.6).
+ *Keep the layer in the tests.* Every test should run with synchronisation validation and fail on any message, as every program in this course does.

#keyidea[
  A synchronisation bug usually gives correct results where it was written. Run synchronisation validation on every test, read each report for the two accesses and the masks that would connect them, and know the layer's blind spots, testing what it cannot see by widening race windows and changing hardware.
]

#opengl[
  OpenGL's version of these bugs is the missing `glMemoryBarrier` after a shader writes, which no layer reports and which a driver that waits conservatively hides. The rest of the catalogue has no OpenGL counterpart, because the driver chose stages, layouts and waits itself, and kept mapped buffers coherent unless the program asked otherwise.
]

#reading(
  [The validation layer's documentation, "Synchronization Validation", in the Vulkan-ValidationLayers repository, including its list of known limitations.],
  [LunarG, "Guide to Vulkan Synchronization Validation", a white paper on the layer's design and use.],
  [The Khronos wiki page "Synchronization Examples", as a reference for the fixes.],
)

== Labs

#lab([Fix them blind], goal: [Fix each bug from its report alone.], time: [2 hours], code: "code/u3/bugs")[
  + Run `u3_bugs --bug NAME` for each of the six bugs, with validation on.
  + For each, write the fix from the report alone, without reading the program's fixed version, then compare.
  #done-when(
    [Your six fixes pass with validation silent.],
    [Where your fix differs from the program's, you can say whether both are correct, and which is cheaper.],
  )
  #evidence([The six reports and your fixes.])
]

#lab([An atomic blind spot], goal: [See a hazard the layer cannot report.], time: [1.5 hours], code: "code/u3/bugs")[
  + Write a pass that only increments counters with `atomicAdd`, followed by a pass that reads the counters, with no barrier between them.
  + Run with validation on, then widen the window by giving the first pass much more work, and run many times.
  #done-when(
    [Validation is silent, and you have either wrong results or an argument, from how your GPU runs the two passes, for why none appeared.],
    [You have added the barrier, and can name its masks.],
  )
  #evidence([The program, the outputs and the explanation.])
]

#lab([From report to barrier], goal: [Translate reports into masks quickly.], time: [1 hour], code: "code/u3/hazards")[
  + Run three of Chapter 3.1's cases with `--bug`, and from each report alone write the barrier that fixes it.
  + Check each against the case's own barrier.
  #done-when(
    [All three of your barriers are correct.],
    [You can point to the part of each report that gave you each mask.],
  )
  #evidence([The reports, annotated.])
]

#lab([A second opinion], goal: [See the same bugs on different hardware.], time: [1 hour], code: "code/u3/bugs")[
  + Run every `--bug` variant on a second device: another GPU, or Mesa's lavapipe on Linux.
  + Compare which bugs produce wrong results there.
  #done-when(
    [You have a table of both devices' results.],
    [You can explain each difference from how the two devices schedule work.],
  )
  #evidence([The table and the explanation.])
]

#problems(
  [Why did five of the six bugs produce correct results on the M2 Pro? What would make them fail there?],
  [The semaphore-stage hazard is reported at `vkQueueSubmit2`, not while the command buffer is recorded. Why?],
  [Two dispatches write disjoint halves of one buffer, bound whole, and the layer reports a write after write. Is it a real hazard? How would you silence the report without adding a barrier?],
  [Write the big hammer's barrier. Why is a bug that disappears under it evidence of a synchronisation bug, and not proof?],
  [A program that is silent under synchronisation validation fails on another vendor's GPU. List the blind spots you would examine first, and how you would test each.],
)

#checklist(
  [I can read a synchronisation validation report and write the barrier it asks for.],
  [I can recognise the six classic bugs and fix each.],
  [I know what synchronisation validation cannot see, and how to test it otherwise.],
  [I can hunt a synchronisation bug that the tools miss, systematically.],
  [Lab 3.7.1–3.7.4 done-when criteria all hold, with evidence filed.],
)
