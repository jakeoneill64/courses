#import "../lib/template.typ": *

= Compute meets graphics <ch-compute-graphics>

#chapter-meta(
  time: [7 hours],
  builds: [A frame that simulates a million particles in a compute shader and draws them as points from the same buffer; culls 50,000 cubes against the view in another compute shader, which writes the indirect draw that renders the survivors; and tone-maps the rendered image in a third. Every part is checked against the CPU, and each pass is timed.],
  needs: [Chapters 4.1 to 4.3, and Unit 3.],
)

#why[
  The most effective modern renderers let the GPU decide what to draw. Compute shaders simulate, animate and cull; the graphics pipeline draws what they produced, with parameters they wrote; and compute again post-processes the image. The CPU's part shrinks to recording a few commands per frame, whatever the scene's size. Everything that makes this work has been covered separately, compute shaders in Unit 2, barriers in Unit 3, the graphics pipeline in Chapters 4.1 to 4.3, and this chapter puts them in one frame, with the barriers between compute and graphics that join them.
]

#skip-test(
  rule: [If all four are easy, read the section on GPU culling and do Labs 4.4.2 and 4.4.4.],
  [A compute shader writes particle positions that a draw then reads as vertex attributes. Which stages and accesses does the barrier between them name?],
  [How can a compute shader decide how many instances a draw renders, without the CPU reading anything back?],
  [The frame's simulation writes the particle buffer that the previous frame's draw read. What hazard is that, and what barrier prevents it?],
  [Why render into a high-dynamic-range image and convert to the display format in a separate pass?],
)

== Core ideas

=== A frame in four passes

Each frame has four passes on one queue (@fig-frame-passes). A compute pass advances the particles. A second compute pass tests every cube against the camera's view frustum and writes the indices of the visible ones, with an indirect draw command whose instance count is the number of visible cubes. A graphics pass draws the cubes with that command and the particles as points, into a 16-bit floating-point image. A last compute pass converts the image for display. The frame then ends with a copy for checking, or a blit to the swapchain when there is a window.

#fig("u4-frame-passes", caption: [The four passes of a frame and the barriers between them.]) <fig-frame-passes>

#snippet("u4/particles/main.cpp", "record-frame", caption: [Recording a frame, with a timestamp after each pass])

=== One buffer, two roles

The particles live in one device-local buffer, created with both `STORAGE_BUFFER` and `VERTEX_BUFFER` usage, so that the simulation writes it as a storage buffer and the draw reads it as vertices, with no copy in between:

#snippet("u4/particles/main.cpp", "buffers", caption: [The particle buffer and the draw command buffer, each with every usage it needs])

#snippet("u4/shared/galaxy.hpp", "particle", caption: [A particle: a position and a velocity, each padded to four floats for `std430`])

The simulation pulls each particle towards the origin with a softened inverse-square force and advances it with semi-implicit Euler integration. The force always points along the particle's position, so each particle's angular momentum is conserved, up to rounding, which gives the program something exact to check after many steps.

#snippet("u4/particles/simulate.comp", "integrate", caption: [One step of the simulation])

The simulation pass is bracketed by two buffer barriers. The first orders this frame's writes after the previous frame's: after its simulation writes, a write after write, and after its vertex fetches, a write after read. The second makes the new positions visible to the vertex attribute fetch of this frame's draw.

#snippet("u4/particles/main.cpp", "simulate-pass", caption: [The simulation, ordered against the previous frame's draw and before this frame's])

The draw then binds the same buffer as a vertex buffer and draws one point per particle; the vertex shader reads position and velocity as attributes and colours each particle by its speed:

#snippet("u4/particles/main.cpp", "draw-points", caption: [A million points from the buffer the simulation wrote])

#snippet("u4/particles/particle.vert", "particle-inputs", caption: [The particle's vertex shader])

=== GPU culling and indirect draws

The 50,000 cubes are described by a buffer of positions and sizes. Each frame, a compute shader tests each cube's bounding sphere against the six planes of the view frustum, which the CPU extracts from the camera's matrix, and appends the index of each visible cube to a list with an atomic counter. The counter is the `instanceCount` field of a `VkDrawIndexedIndirectCommand` in the same buffer:

#snippet("u4/particles/cull.comp", "command", caption: [The draw command, as the shader sees it])

#snippet("u4/particles/cull.comp", "cull", caption: [Testing a bounding sphere against the frustum and appending the survivors])

Before the cull, a small `vkCmdUpdateBuffer` resets the command: the index count of the cube mesh, and an instance count of zero. Its barriers order it after the previous frame's indirect read and before this frame's atomic additions:

#snippet("u4/particles/main.cpp", "cull-pass", caption: [Resetting the command, then culling])

After the cull, two buffer barriers prepare its outputs for their different readers: the draw command for the indirect stage, which reads it before any shader runs, and the visible list for the vertex shader:

#snippet("u4/particles/main.cpp", "to-indirect", caption: [Two consumers, two destination scopes])

The draw reads its parameters from the buffer with `vkCmdDrawIndexedIndirect`. Each instance's vertex shader looks up its cube through the visible list, using `gl_InstanceIndex`:

#snippet("u4/particles/main.cpp", "draw-indirect", caption: [Drawing however many cubes the cull kept])

#snippet("u4/particles/cube.vert", "instance-fetch", caption: [Each instance fetches its cube through the list of visible indices])

The CPU never learns how many cubes were drawn during the frame. To check the cull, the program reads back the last frame's command and list and compares them with a cull computed on the CPU with the same planes. A cube whose sphere touches a plane may legitimately fall either way after rounding, so the check allows disagreement only for those:

#snippet("u4/particles/main.cpp", "check-cull", caption: [Comparing the GPU's cull with the CPU's])

=== Post-processing in compute

The scene is drawn into a `VK_FORMAT_R16G16B16A16_SFLOAT` image, which can hold values above 1: a million faint additive points pile up at the centre to brightnesses no 8-bit format can store. The post-process is a compute shader that reads it as a storage image, compresses its range with a simple tone map, applies the sRGB curve itself, since sRGB storage images are not portable (Chapter 1.2), and writes an 8-bit image:

#snippet("u4/particles/post.comp", "post", caption: [Tone mapping in a compute shader])

The barrier into the post-process moves the rendered image from colour attachment writes to compute reads and from `COLOR_ATTACHMENT_OPTIMAL` to `GENERAL`, and prepares the output image in the same call:

#snippet("u4/particles/main.cpp", "post-pass", caption: [From the graphics pass to the compute pass])

With a window, a blit copies and scales the result into the acquired swapchain image. The presenter is told to wait for the acquire semaphore at the blit stage, since the blit is the first thing to touch the image:

#snippet("u4/particles/main.cpp", "presenter", caption: [A swapchain written by blits])

#snippet("u4/particles/main.cpp", "blit-to-swapchain", caption: [Blitting the frame into the swapchain image])

=== Results

The program checks all three kinds of output. The particles' angular momenta must be unchanged to within 10#super[−3], relative; a sample of a thousand particles must follow the same orbits as the CPU's integration of the same steps; the cull must match the CPU's; and every pixel of the tone-mapped image must match a CPU tone map of the rendered image.

#snippet("u4/particles/main.cpp", "check-particles", caption: [Checking conservation and a sample of orbits against the CPU])

#console(read("/src/console/u4-particles.txt"), caption: [Sixty frames offscreen on the M2 Pro, with validation on])

#fig("/src/figures/u4-particles-image.jpg", caption: [The last frame: a million particles orbiting the origin, among the cubes that survived culling.]) <fig-particles>

Drawing dominates the frame: a million points and fifteen thousand cubes take 2.2 ms, against 0.3 ms to simulate the million particles and 0.016 ms to cull fifty thousand cubes. The cull is so cheap that it pays for itself many times over: it removes 70% of the cubes before any vertex is processed. On a GPU with a dedicated compute queue, the simulation of the next frame could also run alongside the current frame's drawing, which Chapter 4.7 does.

#keyidea[
  Compute and graphics share memory, queues and synchronisation rules. A buffer written by a compute shader can be a vertex buffer, an index buffer or an indirect command; an image rendered by the graphics pipeline can be a compute shader's input. The only thing to add between them is the barrier, with the graphics stage that actually reads.
]

#opengl[
  OpenGL 4.3 can do all of this: compute shaders write a buffer bound as a vertex buffer, `glDrawElementsIndirect` reads a command from a buffer, and `glMemoryBarrier` takes `GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT` or `GL_COMMAND_BARRIER_BIT` before the draw. The differences are in control: OpenGL's barrier waits for everything, cannot express that the draw's other inputs are unaffected, and cannot put the compute work on another queue.
]

#reading(
  [The Vulkan specification, "Drawing Commands" (in particular "Indirect Drawing") and the graphics stages in "Synchronization and Cache Control".],
  [The Vulkan Guide, "Synchronization Examples": the compute-to-graphics cases.],
  [Arm, _Mali GPU Best Practices Developer Guide_, on compute and graphics interaction on tile-based GPUs.],
)

== Labs

#lab([Run and time the frame], goal: [See where the frame's time goes.], time: [1 hour], code: "code/u4/particles")[
  + Run `VKF_VALIDATION=0 build/bin/u4_particles` and record the time of each pass.
  + Run with `--n` set to 250,000 and 4,000,000 and record how each pass scales.
  #done-when(
    [Every run passes its checks.],
    [You can say which pass grows with the number of particles and which do not, and why.],
  )
  #evidence([The table of pass times.])
]

#lab([Remove each barrier], goal: [Connect each barrier to the hazard it prevents.], time: [1.5 hours], code: "code/u4/particles")[
  + Remove, one at a time, the second barrier of the simulation pass, the barrier after the command's reset, and the barrier into the post-process.
  + Run each with validation on and record the report and whether the checks still pass.
  #done-when(
    [You have the three reports.],
    [Each is explained by the hazard type and the stages it names.],
  )
  #evidence([The reports and explanations.])
]

#lab([Cull more finely], goal: [Extend GPU culling.], time: [2 hours], code: "code/u4/particles")[
  + Add a distance test to the cull: cubes beyond a given distance are not drawn.
  + Count, with a second atomic counter, how many cubes each test rejected, and read the counts back.
  + Check the new cull against the CPU.
  #done-when(
    [The GPU's counts match the CPU's.],
    [You have the draw pass's time with and without the distance test.],
  )
  #evidence([The changes and the timings.])
]

#lab([Exposure and the HDR image], goal: [Use the high-dynamic-range image.], time: [1.5 hours], code: "code/u4/particles")[
  + Make the exposure a command-line option and render with exposures of 0.25, 1 and 4.
  + Replace the tone map with plain clamping and compare the centre of the image.
  + Update the CPU's reference so that the check still passes.
  #done-when(
    [Every variant passes its pixel check.],
    [You can explain what the tone map preserves that clamping loses.],
  )
  #evidence([The images and the explanation.])
]

#problems(
  [Write the barrier that would be needed if the particles were drawn as instanced quads, reading positions in the vertex shader from a storage buffer instead of as vertex attributes.],
  [Why must the draw command's instance count be reset each frame, and why with `vkCmdUpdateBuffer` and not a compute shader? Is there another way?],
  [The cull appends visible indices with an atomic counter, so their order varies from frame to frame. Does that matter for this scene? When would it?],
  [Estimate the vertex shader invocations saved per frame by culling, and the cost of the cull itself, from the measurements above.],
  [The simulation pass's first barrier has two source stages. What would go wrong with only `COMPUTE_SHADER`, and with only `VERTEX_ATTRIBUTE_INPUT`?],
)

#checklist(
  [I can use one buffer as both a storage buffer and a vertex buffer, with the barriers between the roles.],
  [I can cull on the GPU and draw with indirect parameters a compute shader wrote.],
  [I can render to a high-dynamic-range image and post-process it in compute.],
  [I can check GPU-driven rendering against the CPU, allowing exactly for legitimate differences.],
  [Lab 4.4.1–4.4.4 done-when criteria all hold, with evidence filed.],
)
