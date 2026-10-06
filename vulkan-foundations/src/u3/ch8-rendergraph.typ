#import "../lib/template.typ": *

= Render graphs <ch-rendergraph>

#chapter-meta(
  time: [7 hours],
  builds: [A render graph library of about 900 lines, in which passes declare the resources they read and write. Compilation culls passes whose results nothing uses, places transient resources in one allocation with aliasing, derives every barrier and layout transition, and splits work across queues with timeline semaphores; execution records each pass with its barriers and times it. A demonstration graph derives exactly the barriers Chapter 3.3 wrote by hand, saves a fifth of its memory by aliasing, and runs with async compute.],
  needs: [Chapters 3.1 to 3.7.],
)

#why[
  Every barrier in this unit so far was placed by hand. That works for a pipeline of seven passes written by one person. A frame with dozens of passes, changed by many people, is another matter: adding, removing or reordering a pass silently invalidates barriers elsewhere, and hand-placed barriers become the most fragile code in the renderer. A _render graph_ inverts the problem. Each pass declares the resources it reads and writes, and how, and the graph derives everything else: which passes matter, where temporary resources live, every barrier and layout transition, and how work splits across queues. Production engines organise their frames this way, and this chapter builds one small enough to read in an evening.
]

#skip-test(
  rule: [If all four are easy, read the sections on deriving barriers and on async compute, and do Labs 3.8.3 and 3.8.4.],
  [A pass reads a buffer that the pass before it wrote, and a pass between them also read it. What does the new pass's barrier wait for?],
  [What does it take for a pass to be removed from a frame, and why must a readback be marked so that it never is?],
  [Two transient images never live at the same time and share memory. What must the barrier before the second image's first use contain?],
  [A pass moves to another queue. What replaces the barriers that connected it to its neighbours?],
)

== Core ideas

=== Declaring a frame

A pass is a function that records commands, together with a list of the resources it uses. Each use states the pipeline stages that access the resource, the kinds of access, and, for an image, the layout the pass needs it in:

#snippet("u3/rendergraph/rendergraph.hpp", "use", caption: [One use of one resource])

Most uses are one of a few kinds, which Chapter 3.3's catalogue already listed. The library names them:

#snippet("u3/rendergraph/rendergraph.hpp", "presets", caption: [The common uses, with their stages, accesses and layouts])

A pass adds uses with `read`, when it needs the resource's current contents, and `write`, when it produces new ones; a pass that updates a resource in place calls both. A pass whose effects are outside the graph, such as one that lets the host read results, is marked as a _side effect_, and a pass can ask for the async compute queue:

#snippet("u3/rendergraph/rendergraph.hpp", "builder", caption: [Declaring a pass])

Resources are either imported, made by the program, with the use they had before the graph runs, or _transient_: created by the graph for its own passes, and free to share memory with others.

#snippet("u3/rendergraph/rendergraph.hpp", "resources", caption: [Imported and transient resources])

The demonstration declares Chapter 3.3's seven-pass pipeline as a graph, with three additions: a pass that clears the statistics, a pass that copies the blurred field for debugging, which nothing reads, and a pass that stands for the host reading the results.

#snippet("u3/rendergraph/main.cpp", "declare-resources", caption: [Seven transients and one imported buffer])

#snippet("u3/rendergraph/main.cpp", "declare-early-passes", caption: [The first five passes])

#snippet("u3/rendergraph/main.cpp", "declare-late-passes", caption: [The last five passes])

#fig("u3-declared", caption: [The demonstration's declarations. Each row is a pass, in the order declared; each column a resource.]) <fig-declared>

=== Culling

Compilation first decides which passes to keep. A pass with a side effect is kept, and so is any pass that wrote something a kept pass reads. Walking the passes backwards finds them all in one pass, because every dependency points backwards. The debug copy writes only `scratch`, which nothing reads, so it is culled. A kept pass that reads a transient nothing has written is an error, caught here:

#snippet("u3/rendergraph/rendergraph.cpp", "cull", caption: [Keeping the passes that lead to a side effect])

#console(read("/src/console/u3-rendergraph-bug-read-unwritten.txt"), caption: [A pass that reads a transient before anything writes it])

=== Placing transients

Each kept transient lives from its first user to its last. Two transients whose lifetimes do not overlap can occupy the same memory. The graph creates every transient, gathers their memory requirements, and places them in order of first use, each at the lowest offset where it overlaps no transient that is alive at the same time. Placement respects each resource's alignment, and keeps a live buffer and a live image apart by `bufferImageGranularity`, so that they never share a page of the size the device requires.

#snippet("u3/rendergraph/rendergraph.cpp", "first-fit", caption: [First fit, in order of first use])

In the demonstration, `mask` is first written after `field` is last read, and takes its memory; `command` takes the memory of `edges` the same way (@fig-aliasing). The graph's transients need 4 MiB instead of 5.

#fig("u3-aliasing", caption: [Where the transients live, and when. Two resources in one row share memory.]) <fig-aliasing>

A resource that takes over memory starts with undefined contents, but the hardware may still be using that memory for its previous occupant. Its first use therefore needs a barrier whose source is the previous occupant's last accesses, and, for an image, a transition from `UNDEFINED`. The graph treats the newcomer as inheriting the old resource's accesses, which produces exactly that. Synchronisation validation cannot check this hand-over for images (Chapter 3.7), so the graph must be right by construction.

=== Deriving barriers

The graph then simulates the frame, pass by pass, keeping for each resource what has happened to it so far on each queue: the stages and accesses of its last write, the stages that have read it since, which of those reads were already made to see the write, and its layout.

#snippet("u3/rendergraph/rendergraph.cpp", "sim", caption: [What the graph knows about a resource between passes])

At each use, three rules decide the barrier:

- A use that _modifies_ the resource, by writing it or by changing an image's layout, must wait for the last write, a write after write, and for every read since, a write after read. The last write's accesses become the barrier's source accesses; the reads contribute stages only, since an execution dependency is enough to protect a read.
- A use that only reads must wait for the last write and have it made visible to its stages and accesses, unless an earlier read has already been given exactly that. A read after a read needs nothing.
- A dependency on work in another queue's batch becomes a semaphore wait instead.

#snippet("u3/rendergraph/rendergraph.cpp", "derive", caption: [The barrier one use needs])

After each use, the simulation records what the use did:

#snippet("u3/rendergraph/rendergraph.cpp", "update", caption: [Recording a use])

Finally the dependencies before each pass are grouped into one `vkCmdPipelineBarrier2` call: one global memory barrier for each pair of stage masks, merging their accesses, and one image barrier for each layout transition. The graph uses global memory barriers even for buffers. Buffer barriers name a range, which drivers rarely exploit, and global barriers keep the plan short.

#snippet("u3/rendergraph/rendergraph.cpp", "group", caption: [One barrier per pair of stage masks, one per transition])

The result is the plan the graph prints. Each pass lists its barriers, with the resources they protect:

#console(read("/src/console/u3-rendergraph-plan.txt"), caption: [The demonstration's plan, with aliasing])

Before `select`, for example, `blurred` and `edges` share one barrier, since both were written by compute shaders and are read by one. `stats` needs its own, because its last write was the clear, in another stage. `mask` arrives in `field`'s memory with a transition from `UNDEFINED`, after compute-shader work that `field` saw.

To check the derivation, the demonstration also runs Chapter 3.3's pipeline with barriers written by hand, then compiles the graph without aliasing and compares the two, barrier by barrier. They match at every pass:

#snippet("u3/rendergraph/byhand.cpp", "by-hand", caption: [The same pipeline with its barriers written by hand])

=== Executing

A compiled graph is executed by recording its passes in order, each preceded by its barriers. The graph also brackets each pass with timestamps and with a debug label, so that captures and profilers show the passes by name:

#snippet("u3/rendergraph/rendergraph.cpp", "record-batch", caption: [Recording a batch of passes])

#console(read("/src/console/u3-rendergraph-timing.txt"), caption: [Fifty executions on one queue, with validation off])

A graph is compiled once and executed many times. One graph per frame slot, as in Chapter 3.6, gives each frame in flight its own command buffers and transients.

=== Async compute

A pass that asks for the compute queue runs there when the device has a separate one. The graph then cuts the kept passes into _batches_, runs of consecutive passes on one queue, cutting after each pass that another queue waits for and before each pass that waits:

#snippet("u3/rendergraph/rendergraph.cpp", "batches", caption: [Cutting the passes into batches])

Each queue has a timeline semaphore. A batch signals its queue's timeline when it finishes, and waits for the values of the batches it depends on, at the stages that need them. Transients used by both queues are created with `CONCURRENT` sharing, so that no ownership transfers are needed. The last batch also waits for the other queue's last batch, so that the caller's own semaphores and fence cover the whole graph.

#snippet("u3/rendergraph/rendergraph.cpp", "submit", caption: [Submitting the batches with timeline semaphores])

With `--async`, the demonstration moves `edges` to the compute queue:

#console(read("/src/console/u3-rendergraph-async.txt"), caption: [Four batches across two queues, with validation on])

The graph is correct with async compute, and slower: 1.21 ms per execution against 0.93. Its passes take only about 0.25 ms of GPU time in all, so the extra submissions and semaphore waits cost more than the overlap saves. As Chapter 3.5 measured, a second queue pays when the work it takes is large and the first queue leaves hardware idle, which Chapter 4.7's simulation does.

=== Graphics passes

The same rules cover rendering. Attachments are images whose uses name the attachment stages and layouts, and a draw that clears its attachments writes them without reading:

#console(read("/src/console/u3-rendergraph-graphics.txt"), caption: [A graph with colour and depth attachments, a copy and a read on the host])

=== Render graphs in production

Frostbite's _frame graph_ introduced the idea to a wide audience in 2017, and Unreal Engine's Render Dependency Graph and many other engines follow it. Production graphs do more than this one. They reorder passes to overlap independent work, merge passes into render passes with subpasses for tile-based GPUs, use events where independent work can run between a producer and its consumer, give attachments lazily allocated memory on tilers, track subresources such as single mip levels, and keep resources from one frame for the next, such as the history buffers of temporal effects. The design is the same: declare uses, then derive.

#keyidea[
  Declare what each pass reads and writes, and let the graph derive the passes that matter, where transients live, every barrier and layout transition, and how work splits across queues. A graph that derives the barriers a careful programmer would write makes adding a pass safe.
]

#opengl[
  OpenGL's driver works like a render graph of sorts: it sees each pass's resources as the program binds them, and derives waits and cache flushes at run time, with no knowledge of what comes next. A Vulkan render graph does that work ahead of time, once per frame structure, and sees the whole frame, which lets it cull, alias and schedule as no driver can.
]

#reading(
  [Yuriy O'Donnell, "FrameGraph: Extensible Rendering Architecture in Frostbite", GDC 2017.],
  [Hans-Kristian Arntzen, "Render graphs and Vulkan: a deep dive", 2017, on a graph for Vulkan in the Granite engine.],
  [Epic Games, "Render Dependency Graph", in the Unreal Engine documentation.],
  [Graham Wihlidal, "Halcyon Architecture: Director's Cut", SEED, 2018.],
)

== Labs

#lab([Add a pass], goal: [Extend a graph, and check what it derives.], time: [1.5 hours], code: "code/u3/rendergraph")[
  + Add a pass after `select` that counts the cells of `mask` in a new transient buffer, and make `readback` copy that count out too.
  + Write, by hand, the barriers your pass needs, then compare them with the plan the graph prints.
  #done-when(
    [The count is correct, and validation is silent.],
    [Your barriers match the graph's, or you can explain every difference.],
  )
  #evidence([The changed declarations, your barriers and the plan.])
]

#lab([Memory to spare], goal: [Make aliasing visible and check its barriers.], time: [1.5 hours], code: "code/u3/rendergraph")[
  + Run with and without `--no-alias`, and compare the placements.
  + Add a transient image that is used only after `select`, and find where the graph places it and what its first barrier contains.
  #done-when(
    [Your image's results are correct, and validation is silent.],
    [You can explain each reuse in the plan, and why its first barrier names the stages it does.],
  )
  #evidence([The two plans and the explanation.])
]

#lab([From one frame to the next], goal: [Carry a resource between executions.], time: [2 hours], code: "code/u3/rendergraph")[
  + Import a buffer that accumulates the statistics of every execution, read and written by a new pass, with its previous use set to that pass's use.
  + Execute the graph ten times and check the accumulated totals.
  #done-when(
    [The totals are correct after ten executions, and validation is silent.],
    [You can explain the barrier the graph derives before the first use in each execution.],
  )
  #evidence([The changes and the output.])
]

#lab([Schedule for overlap], goal: [Judge which work belongs on the compute queue.], time: [1.5 hours], code: "code/u3/rendergraph")[
  + Move each of `blur`, `edges` and `select` to the compute queue in turn, and print each plan's batches.
  + Time each configuration with validation off, at `--side 512` and `--side 2048`.
  #done-when(
    [You have a table of batches and times.],
    [You can explain which placements add semaphores without overlap, and why the larger size changes the picture.],
  )
  #evidence([The table and the explanation.])
]

#problems(
  [Before `select`, `blurred` and `edges` share one barrier, but `stats` has its own. Why?],
  [The barrier before `mask`'s first use has a source access of `SHADER_STORAGE_WRITE`, although nothing has written `mask`. Why?],
  [Why is the debug copy culled, and what is the smallest change to the declarations that would keep it?],
  [The graph uses global memory barriers for buffers. What would buffer barriers add, and when would they be worth it?],
  [Describe a frame in which reordering two passes would let more work overlap, and what a graph must know to reorder them safely.],
)

#checklist(
  [I can declare a frame as passes that read and write resources, with the right stages, accesses and layouts.],
  [I can cull passes, place transients with aliasing, and say what a resource's first use in shared memory needs.],
  [I can derive the barriers between passes from their declarations, as the graph does.],
  [I can split a graph across queues with timeline semaphores, and judge when that pays.],
  [Lab 3.8.1–3.8.4 done-when criteria all hold, with evidence filed.],
)
