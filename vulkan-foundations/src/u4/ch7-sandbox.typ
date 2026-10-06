#import "../lib/template.typ": *

= Capstone: a GPU-driven sandbox <ch-sandbox>

#chapter-meta(
  time: [10 hours],
  builds: [One program that combines the course. A million particles are simulated on an async compute queue, with a copy of their state for each frame in flight; 50,000 cubes are culled on the GPU and drawn with an indirect draw; the high-dynamic-range image is tone-mapped in compute and presented to a window or run headless. Every frame is a render graph from Chapter 3.8, synchronisation validation stays silent, every pass is timed, and the simulation, the culling and the image are checked against the CPU. The chapter ends with the course's final project.],
  needs: [The whole course, in particular Chapters 3.6, 3.8, 4.2 and 4.4.],
)

#why[
  Each unit built a part of a modern renderer on its own. Real programs fail at the seams between the parts: a buffer shared by two queues, a swapchain image that arrives with a semaphore of its own, a frame in flight that still reads what the next frame writes. This chapter assembles the parts into one program, organises each frame as a render graph, and measures where the time goes. It then hands the program over to you: the final project extends it with a feature of your own, to the same standard of evidence as everything before it.
]

#skip-test(
  rule: [Even if all four are easy, read the sections on state across frames and on measurement, and do the final project.],
  [The simulation of frame _n_ + 1 runs while frame _n_ is still drawing its particles. What must be true of the buffers they use?],
  [How does an acquired swapchain image enter a render graph, and what must its first barrier wait for?],
  [Each frame slot compiles its own graph. What changes between two executions of the same graph, and how?],
  [Async compute barely changes the frame time here. What would you measure to decide whether to keep it?],
)

== Core ideas

=== The frame

The sandbox renders Chapter 4.4's scene: a disc of a million particles orbiting a centre among 50,000 cubes. Each frame updates its parameters, simulates the particles, culls the cubes, draws the cubes and the particles into a 16-bit floating-point image, and tone-maps that image in a compute shader. With a window, the result is blitted into the swapchain image and presented. The simulation runs on an async compute queue, and the frame waits for it only where the particles are drawn (@fig-sandbox-frame).

#fig("u4-sandbox-frame", caption: [The passes of two frames on the two queues. The next frame's simulation can run while this frame draws its particles, because it writes another copy of the state.]) <fig-sandbox-frame>

#fig("/src/figures/u4-sandbox-image.jpg", caption: [The sandbox after 240 frames, as the program wrote it.]) <fig-sandbox-image>

=== The frame as a render graph

Every frame is a graph of seven passes, nine with a window. The resources fall into three groups. The frame's parameters and its colour and depth images are transients, created by the graph. The particle state, the cubes, the list of visible cubes and the draw command are imported, because they outlive a frame. The display image is imported too, with the use the previous frame's last pass left it in:

#snippet("u4/sandbox/main.cpp", "frame-graph", caption: [The frame's resources])

Three uses are new: `vkCmdUpdateBuffer` writes in the clear stage, the cull's results are read by vertex shaders through storage buffers, and the swapchain image arrives from the presentation engine. Each is one `rg::Use`, declared once:

#snippet("u4/sandbox/main.cpp", "uses", caption: [Uses that Chapter 3.8's presets did not need])

The compute work comes first. `update` writes the frame's parameters, `simulate` advances the particles on the compute queue, and the cull resets and fills the draw command and the visible list exactly as in Chapter 4.4:

#snippet("u4/sandbox/main.cpp", "compute-passes", caption: [Updating, simulating and culling])

The cubes are drawn with the indirect command the cull wrote, then the particles from the buffer the simulation wrote, added into the same image; the post-process is the frame's side effect:

#snippet("u4/sandbox/main.cpp", "draw-passes", caption: [Drawing the visible cubes])

#snippet("u4/sandbox/main.cpp", "particle-passes", caption: [Drawing the particles and tone-mapping the image])

The graph derives the barriers that Chapter 4.4 wrote by hand, and splits the frame into three batches:

#console(read("/src/console/u4-sandbox-plan.txt"), caption: [The frame's plan, with validation on])

=== State across frames

With three frames in flight, frame _n_ + 1's simulation may start while frame _n_ is still drawing the particles it simulated. If both used one buffer, the simulation would overwrite positions the draw was reading. Each frame slot therefore owns one copy of the particle state: the simulation of frame _n_ reads copy _n_ − 1 and writes copy _n_, which frame _n_'s draw reads.

#snippet("u4/sandbox/simulate.comp", "state-copies", caption: [The previous frame's state in, this frame's state out])

The copies are used by both queue families, so they are created with `CONCURRENT` sharing, which `vkf::createBuffer` does not offer:

#snippet("u4/sandbox/main.cpp", "shared-buffer", caption: [A buffer both queue families may use without ownership transfers])

Two dependencies between frames cross the graph's boundary. The first is declared: the imported previous copy's earlier use is the previous frame's simulation, so the graph orders this frame's read after that write, on the compute queue where both run. The second comes from frame pacing. The copy that frame _n_ writes was last drawn by frame _n_ − 3, on the main queue, and the only thing that orders the new write after that draw is the frame loop's wait for frame _n_ − 3 to finish before reusing its slot. Change the number of frames in flight without changing the number of copies, and the program races.

=== Presentation

With a window, two more passes join the graph. The swapchain image is imported once, without an image, and every frame `rebind` points it at the image just acquired. Its declared earlier use, `Acquired`, names the stage at which the frame waits for the acquire semaphore, so that the graph's first barrier on the image chains after that wait, as Chapter 4.2 required:

#snippet("u4/sandbox/main.cpp", "present-passes", caption: [Blitting to the swapchain and presenting])

The frame loop paces the slots with one timeline semaphore, as in Chapter 3.6, and hands the graph the acquire semaphore to wait on and the semaphores to signal:

#snippet("u4/sandbox/main.cpp", "frame-loop", caption: [The frame loop, offscreen and with a window])

=== Checking the whole

A program this size needs checks at its seams. After the last frame, the program copies back the particles, the draw command and the visible list, and the image. Every particle must still be bound, each particle's angular momentum must be unchanged, and a sample of orbits must match the CPU's integration of the same steps:

#snippet("u4/sandbox/main.cpp", "check-particles", caption: [Checking the simulation after hundreds of frames])

The last frame's cull must match a cull on the CPU with the same planes, allowing disagreement only for cubes that touch a plane, and the image must contain both the cubes and the bright disc of particles. Running with validation on, the frame-loop's hundreds of graph executions must produce no message at all.

#console(read("/src/console/u4-sandbox.txt"), caption: [A run with validation on: every check passes, and the layer is silent])

=== Where the time goes

#console(read("/src/console/u4-sandbox-timing.txt"), caption: [Six hundred frames with async compute, with validation off])

#console(read("/src/console/u4-sandbox-one-queue.txt"), caption: [The same on one queue])

A frame takes about 2.5 ms either way, with async compute ahead by 2%, less than frames vary from run to run. The particle draw dominates the frame, and it slows from 1.77 to 2.00 ms when the simulation runs beside it, which takes back what the overlap saves. The simulation moves 64 MB a step, reading and writing a million 32-byte particles, close to the bandwidth limit that Chapter 2.5 measured, and the particle draw reads the same 32 MB of state: the two compete for the GPU instead of filling each other's gaps. As Chapter 3.5 found, a second queue pays when one workload leaves idle what the other needs. A simulation limited by arithmetic, such as the N-body forces of Chapter 2.6, would be a better partner for this draw.

The main queue's passes add up to 2.2 ms of the 2.5 ms frame. The CPU, which records seven small passes per frame from graphs compiled once per slot, is not the limit.

#keyidea[
  A real frame is many parts joined by synchronisation. Organise it as a graph so that the joins are derived, give everything a frame writes a copy per frame in flight, check the result at every seam, and measure before believing that a technique, async compute included, pays on your hardware.
]

#opengl[
  An OpenGL 4.3 version of this frame is possible on desktop platforms, with compute shaders, indirect draws and `glMemoryBarrier`, and Chapter 4.5 sketched it. What it cannot express is the second queue, the copies of state per frame in flight that the driver would otherwise create behind the program's back, and a frame graph that sees every pass before any of them runs.
]

#reading(
  [Graham Wihlidal, "Optimizing the Graphics Pipeline with Compute", GDC 2016, on culling and GPU-driven rendering.],
  [Ulrich Haar and Sebastian Aaltonen, "GPU-Driven Rendering Pipelines", SIGGRAPH 2015 course "Advances in Real-Time Rendering in Games".],
  [Hans-Kristian Arntzen, "Render graphs and Vulkan: a deep dive", 2017, again, now with a whole frame in mind.],
)

== Labs

#lab([Run it every way], goal: [Know the program before changing it.], time: [1 hour], code: "code/u4/sandbox")[
  + Run `u4_sandbox --plan`, then with `--window`, then `--headless --frames 600` with validation off, with and without `--no-async`.
  + Compare your timings with this chapter's, pass by pass.
  #done-when(
    [Every run passes its checks, and the validation runs are silent.],
    [You can explain each difference between your GPU's timings and the M2 Pro's.],
  )
  #evidence([The outputs and the comparison.])
]

#lab([Move the cull], goal: [Judge a change of queue by measurement.], time: [1.5 hours], code: "code/u4/sandbox")[
  + Move `cull` to the compute queue, and print the new plan.
  + Measure the frame and the passes with validation off.
  #done-when(
    [The program passes its checks with validation silent.],
    [You can explain the new batches and semaphores, and whether the move paid.],
  )
  #evidence([The plan and the measurements.])
]

#lab([A glow pass], goal: [Add a pass to a graph you did not write.], time: [2 hours], code: "code/u4/sandbox")[
  + Add a compute pass between the particles and the post-process that adds a blurred copy of the bright parts of the image, through a new transient image.
  + Check the result against a CPU version on a small image, and measure the pass.
  #done-when(
    [The check passes and validation is silent.],
    [You can say which barriers the graph added for your pass, and why each is needed.],
  )
  #evidence([The changes, the check and the plan.])
]

#lab([The final project], goal: [Extend the sandbox with a feature of your own, to the course's standard.], time: [5 hours], code: "code/u4/sandbox")[
  + Choose a feature, for example: N-body attraction between a subset of the particles with indirect dispatch (Chapter 2.6); two levels of detail, with distant cubes drawn as points by a second indirect draw that the cull fills; occlusion culling against the previous frame's depth; or particles that collide with the cubes.
  + Declare it in the frame graph, and give it a check against the CPU.
  + Measure its cost per frame and its effect on the other passes.
  + Write a one-page report: what you built, how you checked it, what it costs, and what you would change.
  #done-when(
    [The program runs for 600 frames with every check passing, including yours, and synchronisation validation silent.],
    [Your report's measurements can be reproduced from the commands it gives.],
  )
  #evidence([The code, the outputs and the report.])
]

#problems(
  [Why does the particle draw slow down when the simulation runs beside it? What does that tell you about async compute for this frame?],
  [The sandbox keeps one copy of the particle state per frame in flight. Could two copies serve three frames in flight? What would have to change?],
  [What would go wrong if one compiled graph were shared by every frame slot?],
  [The main queue's passes add up to about 2.2 ms, and the frame takes 2.5 ms. Where could the rest go, and how would you find out?],
  [Which pass would you optimise first, and how would you check that the optimisation kept the image correct?],
)

#checklist(
  [I can organise a whole frame, with compute, graphics and presentation, as a render graph.],
  [I can keep state across frames in flight and across queues without races.],
  [I can check a large GPU program at its seams, not only at its output.],
  [I can measure a frame pass by pass and decide where to spend effort.],
  [Lab 4.7.1–4.7.4 done-when criteria all hold, with evidence filed.],
)
