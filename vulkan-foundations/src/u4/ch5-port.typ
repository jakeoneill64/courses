#import "../lib/template.typ": *

= From OpenGL to Vulkan <ch-port>

#chapter-meta(
  time: [6 hours],
  builds: [One scene of 10,000 turning cubes, drawn by an OpenGL 4.1 renderer and a Vulkan renderer behind the same interface and compared pixel by pixel, with the CPU cost of each API's draws, submission and frame measured; and a catalogue that translates the OpenGL the course has met, compute shaders and `glMemoryBarrier` included, into Vulkan.],
  needs: [Chapters 4.1 to 4.4, and the Handbook's part on Vulkan and OpenGL.],
)

#why[
  Much Vulkan code replaces OpenGL code that already works. A port succeeds when the new renderer draws the same pictures as the old one, and it is worth the effort when it removes a cost the old one could not avoid. This chapter ports a small renderer while keeping both versions alive behind one interface, so that every step can be checked against the original, and measures where each spends its CPU time. It then collects the translations a larger port needs, including those for OpenGL's compute shaders, which macOS cannot run but most OpenGL code on other platforms uses.
]

#skip-test(
  rule: [If all four are easy, read the two catalogues and do Labs 4.5.2 and 4.5.4.],
  [An OpenGL projection matrix is used unchanged in Vulkan. What happens to the image, and to depth?],
  [Which OpenGL calls does `vkCmdPushConstants` replace in a port, and why is it cheaper?],
  [Which `glMemoryBarrier` bit corresponds to a Vulkan barrier whose destination is `DRAW_INDIRECT` with `INDIRECT_COMMAND_READ`?],
  [An OpenGL compute shader writes a buffer that `glCopyBufferSubData` then copies. Which barrier does OpenGL need there, and which does Vulkan?],
)

== Core ideas

=== One scene, two renderers

The program draws a grid of 10,000 small cubes, each turning about its own axis, into a 512 × 512 image, with one draw call per cube. That is the hardest case for an OpenGL driver, and a common one in real programs. Both renderers take the same list of draws, a matrix and a colour for each cube, and both produce an RGBA image with its first row at the top:

#snippet("u4/glport/scene.hpp", "draw-data", caption: [Everything a draw needs, in either API])

#snippet("u4/glport/main.cpp", "run-frames", caption: [The same frames for both renderers])

The OpenGL renderer uses the core profile of OpenGL 4.1, the last version macOS supports, so that the program runs on every platform the course does. OpenGL cannot draw without a context, and on most platforms a context needs a window, here an invisible one that GLFW creates. The Vulkan renderer needs neither window nor surface.

#snippet("u4/glport/gl_renderer.cpp", "context", caption: [An OpenGL 4.1 core context in an invisible window])

Beyond version 1.1, OpenGL's functions must be looked up at run time on Windows, and the set available depends on the context, which is why libraries such as GLAD and GLEW exist. The port uses a table of its own, filled through GLFW. Vulkan's loader exports every core function, as Chapter 1.1 showed, so the Vulkan renderer needs no table.

#snippet("u4/glport/gl_api.hpp", "function-table", caption: [The OpenGL functions the port calls, loaded into a table])

=== The port, piece by piece

The vertex and index buffers are the closest pair. OpenGL chooses where the data lives from a usage hint, and records the vertex format in a _vertex array object_; Vulkan places the buffers in device-local memory through a staging copy, and the vertex format moves into the pipeline (Chapter 4.1).

#snippet("u4/glport/gl_renderer.cpp", "buffers", caption: [OpenGL: buffers, and the vertex format in a vertex array object])

#snippet("u4/glport/vk_renderer.cpp", "buffers", caption: [Vulkan: device-local buffers, uploaded through a staging buffer])

The shaders change more. OpenGL compiles GLSL source when the program runs and links the stages into a _program object_, whose loose `uniform` variables the renderer finds by name. Vulkan's GLSL has no loose uniforms: the matrix and colour become a push-constant block, and the shaders are compiled to SPIR-V when the program is built.

#snippet("u4/glport/gl_renderer.cpp", "shaders", caption: [OpenGL: GLSL 4.10, compiled at run time])

#listing("u4/glport/scene.vert", caption: [Vulkan: the same vertex shader, with a push-constant block])

#snippet("u4/glport/gl_renderer.cpp", "pipeline", caption: [OpenGL: compiling, linking, and finding the uniforms])

#snippet("u4/glport/vk_renderer.cpp", "pipeline", caption: [Vulkan: a push-constant range, a layout and a pipeline])

OpenGL renders offscreen into a _framebuffer object_ with _renderbuffers_ attached, and enables depth testing and culling as global state. In Vulkan those states are in the pipeline, already created, and the targets are images that dynamic rendering clears through their load operations:

#snippet("u4/glport/gl_renderer.cpp", "targets", caption: [OpenGL: a framebuffer object, and state switched on])

#snippet("u4/glport/vk_renderer.cpp", "begin-rendering", caption: [Vulkan: attachments that clear on load])

The frames differ least in shape and most in cost. OpenGL sets two uniforms and draws; Vulkan pushes one block of constants and draws. The Vulkan frame also records into a command buffer that it then submits, where OpenGL's driver keeps a command buffer of its own and submits it when it chooses.

#snippet("u4/glport/gl_renderer.cpp", "frame", caption: [OpenGL: a frame of draws])

#snippet("u4/glport/vk_renderer.cpp", "frame", caption: [Vulkan: the same frame, recorded into a command buffer])

To measure each frame to completion, both renderers wait for the GPU, OpenGL with a _sync object_ and Vulkan with a fence:

#snippet("u4/glport/gl_renderer.cpp", "sync", caption: [OpenGL: a fence in the command stream, flushed and waited on])

#snippet("u4/glport/vk_renderer.cpp", "sync", caption: [Vulkan: a submission with a fence])

Reading the image back shows a convention that differs: `glReadPixels` returns the bottom row first, so the OpenGL renderer reverses the rows before returning them.

#snippet("u4/glport/gl_renderer.cpp", "readback", caption: [OpenGL: one call, bottom row first])

#snippet("u4/glport/vk_renderer.cpp", "readback", caption: [Vulkan: a layout transition, a copy, and a barrier to the host])

=== Clip space

The scene's matrices were written for OpenGL, whose normalised device coordinates have +y pointing up and depth from −1 to 1. Vulkan's have +y pointing down and depth from 0 to 1 (Chapter 4.1). The port keeps the OpenGL projection and multiplies it by a matrix that converts one clip space to the other:

#snippet("u4/glport/scene.hpp", "projections", caption: [OpenGL's projection, and the conversion to Vulkan's clip space])

#snippet("u4/glport/main.cpp", "port-projection", caption: [One projection for each renderer])

The conversion leaves the image the same way up as OpenGL's, so every triangle keeps its winding on the screen, and the pipeline keeps OpenGL's counter-clockwise front face and back-face culling. Two alternatives suit ports that cannot change their matrices. A viewport with a negative height, allowed since Vulkan 1.1, flips y in the viewport transform. The extension `VK_EXT_depth_clip_control` lets a pipeline accept OpenGL's depth range of −1 to 1.

=== Checking the port

The two images are compared pixel by pixel. Rasterisation rules leave implementations some freedom, so the check tolerates differences of two levels in a channel, and up to 0.5% of pixels beyond that. It also requires the cubes to cover a quarter of the image, so that two empty images cannot agree:

#snippet("u4/glport/main.cpp", "compare", caption: [Comparing the two images])

#console(read("/src/console/u4-glport.txt"), caption: [Thirty frames on the M2 Pro, with validation on])

#fig("/src/figures/u4-glport-images.jpg", caption: [The scene as OpenGL (left) and Vulkan (right) drew it. In this frame the two agree in every pixel.]) <fig-glport-images>

=== Where the CPU time goes

#console(read("/src/console/u4-glport-timing.txt"), caption: [Two hundred frames on the M2 Pro, with validation off])

OpenGL spends 6.9 ms issuing 10,000 draws, 0.69 µs per draw for two uniform updates and a draw call. Vulkan records them in 0.43 ms, 43 ns per draw for a push constant and a draw, and submits them in 0.96 ms. The frame completes in 3.3 ms against OpenGL's 7.6 ms. At each draw an OpenGL driver checks the call, works out what state has changed since the last draw and translates it for the hardware; Vulkan did that work once, when it created the pipeline.

On this machine both APIs run on Metal. Apple implements OpenGL on Metal, as its version string shows, and MoltenVK translates Vulkan to Metal. MoltenVK records Vulkan commands into a list of its own and encodes them for Metal when the command buffer is submitted, which is why submission here costs more than recording; a native driver does most of that work as the commands are recorded. The ratio between the two APIs differs from driver to driver, but the cost of a Vulkan draw is lower than an OpenGL draw's on every platform, and more predictable.

With validation on, recording takes 16.9 ms, about forty times longer, because the layer checks every command. Measure with it off, and develop with it on.

#hazard(title: [Pitfall])[
  OpenGL's driver submits work while the program is still issuing draws, so its frame overlaps the CPU's work with the GPU's. A port that records a whole frame, submits it and waits loses that overlap. Frames in flight (Chapter 3.6) restore it: record the next frame while the GPU executes this one.
]

=== A catalogue for larger ports

The port above meets a few of the differences between the APIs. @tbl-port-pitfalls lists those that change results in larger ports, where a direct translation of each call would still draw the wrong picture.

#figure(
  tbl(columns: (auto, 1fr, 1fr), header: ([Topic], [OpenGL], [Vulkan]), size: 8.2pt,
    [Clip space], [+y up, depth from −1 to 1], [+y down, depth from 0 to 1],
    [Image rows], [The first row of a framebuffer, and of `glReadPixels`, is the bottom one], [The first row is the top one],
    [Shader resources], [Loose `uniform` variables found by name; `binding` alone], [Blocks only: push constants, or uniform buffers with `set` and `binding`],
    [Built-ins], [`gl_VertexID`; `gl_InstanceID` counts from zero in every draw], [`gl_VertexIndex`; `gl_InstanceIndex` starts at the draw's first instance],
    [Default state], [Depth test, culling and blending off until enabled], [Everything stated in the pipeline],
    [sRGB output], [Encoded only with `GL_FRAMEBUFFER_SRGB` enabled], [Decided by the attachment's format],
    [Point size], [`glPointSize`, or `gl_PointSize` with `GL_PROGRAM_POINT_SIZE` enabled], [The vertex shader must write `gl_PointSize`],
    [Shader compilation], [GLSL compiled by the driver when the program runs], [SPIR-V compiled at build time, pipelines created at start-up],
  ),
  caption: [Differences that change results],
  kind: table,
) <tbl-port-pitfalls>

The larger difference is synchronisation. OpenGL's driver sees every access it performs itself: rendering, copies, clears, uploads and readbacks. It orders them without being asked. What it cannot see are the writes shaders make through storage buffers, images and atomic counters, so after those, and only those, OpenGL requires `glMemoryBarrier`, whose bits name the kind of _later_ access that must see the writes. A Vulkan barrier needs both sides: the source is the stage of the shader that wrote, with `SHADER_STORAGE_WRITE`, and @tbl-memory-barrier gives the destination for each bit.

#figure(
  tbl(columns: (auto, 1fr, 1.2fr), header: ([`glMemoryBarrier` bit], [Later access], [Vulkan destination]), size: 8pt,
    [`SHADER_STORAGE`], [Storage buffer reads and writes], [The reading shader's stage, `SHADER_STORAGE_READ` and `SHADER_STORAGE_WRITE`],
    [`ATOMIC_COUNTER`], [Atomic counters], [The same as `SHADER_STORAGE`],
    [`SHADER_IMAGE_ACCESS`], [Image loads, stores and atomics], [The shader's stage, `SHADER_STORAGE_READ` and `SHADER_STORAGE_WRITE`, with the image in `GENERAL`],
    [`TEXTURE_FETCH`], [Sampling], [The shader's stage, `SHADER_SAMPLED_READ`, with the image in `SHADER_READ_ONLY_OPTIMAL`],
    [`UNIFORM`], [Uniform buffer reads], [The shader's stage, `UNIFORM_READ`],
    [`VERTEX_ATTRIB_ARRAY`], [Vertex attribute fetch], [`VERTEX_ATTRIBUTE_INPUT`, `VERTEX_ATTRIBUTE_READ`],
    [`ELEMENT_ARRAY`], [Index fetch], [`INDEX_INPUT`, `INDEX_READ`],
    [`COMMAND`], [Indirect draw and dispatch parameters], [`DRAW_INDIRECT`, `INDIRECT_COMMAND_READ`],
    [`BUFFER_UPDATE`, `TEXTURE_UPDATE`, `PIXEL_BUFFER`], [Copies, uploads and readbacks], [`COPY`, `TRANSFER_READ` or `TRANSFER_WRITE`, then `HOST` with `HOST_READ` for the CPU],
    [`FRAMEBUFFER`], [Rendering, blits and `glReadPixels` through a framebuffer], [`COLOR_ATTACHMENT_OUTPUT` or the fragment tests, with attachment access and layout, or `BLIT`],
    [`CLIENT_MAPPED_BUFFER`], [CPU reads through a persistent mapping], [`HOST`, `HOST_READ`, after a fence],
  ),
  caption: [`glMemoryBarrier` bits, without their `GL_` prefix and `_BARRIER_BIT` suffix, and the Vulkan barriers that replace them],
  kind: table,
) <tbl-memory-barrier>

Compute shaders arrived in OpenGL 4.3, which macOS lacks. Here is the frame of Chapter 4.4 as an OpenGL 4.3 program would record it, with the bindings that do not change between frames left out:

```cpp
glUseProgram(simulate);
glUniform1f(dtLocation, dt);
glDispatchCompute((particleCount + 255) / 256, 1, 1);
glMemoryBarrier(GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT);

const DrawElementsIndirectCommand reset{cubeIndexCount, 0, 0, 0, 0};
glBindBuffer(GL_DRAW_INDIRECT_BUFFER, drawCommand);
glBufferSubData(GL_DRAW_INDIRECT_BUFFER, 0, sizeof(reset), &reset);
glUseProgram(cull);
glUniform4fv(planesLocation, 6, planes);
glDispatchCompute((cubeCount + 255) / 256, 1, 1);
glMemoryBarrier(GL_COMMAND_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);

glBindFramebuffer(GL_FRAMEBUFFER, hdrFramebuffer);
glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
glUseProgram(drawCubes);
glBindVertexArray(cubeVertexArray);
glDrawElementsIndirect(GL_TRIANGLES, GL_UNSIGNED_SHORT, nullptr);
glUseProgram(drawPoints);
glBindVertexArray(particleVertexArray);
glDrawArrays(GL_POINTS, 0, particleCount);

glUseProgram(post);
glBindImageTexture(0, hdrImage, 0, GL_FALSE, 0, GL_READ_ONLY, GL_RGBA16F);
glBindImageTexture(1, displayImage, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);
glDispatchCompute((width + 15) / 16, (height + 15) / 16, 1);
glMemoryBarrier(GL_FRAMEBUFFER_BARRIER_BIT);
```

It has three memory barriers, the last of which belongs to the blit that follows the frame. Chapter 4.4's frame records eleven barriers before that point, and only three of them, the one after the simulation and the two after the cull, correspond to `glMemoryBarrier` calls. The other eight cover hazards that OpenGL's driver handles without being asked: the next frame's simulation overwriting particles this frame drew, a write after read; the reset of the draw command after its last indirect read, and before the cull's atomics; the cull's writes to the visible list after the last frame's vertex shaders read it; the draw into the HDR image, and the post-process's reads of it; and every layout transition. A port that translates only the `glMemoryBarrier` calls will pass its tests on some GPUs and corrupt frames on others. Synchronisation validation finds the rest.

#keyidea[
  Port behind an interface, with both renderers alive and their images compared at each step. Translate each call by what it meant, using the catalogues, and then add the barriers that OpenGL's driver used to infer.
]

#opengl[
  A large port need not happen at once. OpenGL 4.6 accepts SPIR-V through `glSpecializeShader`, so during a transition one GLSL source can serve both renderers, compiled by the same tools, with the differences of @tbl-port-pitfalls kept apart by the predefined macro `VULKAN`. The extensions `GL_EXT_memory_object` and `GL_EXT_semaphore` let OpenGL use memory and semaphores that Vulkan created, so that a program can move one pass at a time to Vulkan while OpenGL draws the rest. macOS offers neither.
]

#reading(
  [The OpenGL 4.6 core profile specification, "Shader Memory Access", for exactly what `glMemoryBarrier` covers.],
  [The Vulkan Guide, "Decoder Ring": Vulkan's terms in the vocabulary of other APIs.],
  [The Khronos wiki page "Synchronization Examples" in the Vulkan-Docs repository, for the Vulkan side of each translation.],
  [The Mesa documentation for Zink, an OpenGL implementation on Vulkan: the same translation in the opposite direction.],
)

== Labs

#lab([Measure both APIs], goal: [Find the cost of a draw in each API on your machine.], time: [1 hour], code: "code/u4/glport")[
  + Run `VKF_VALIDATION=0 build/bin/u4_glport --frames 200 --warmup 20` with `--objects` set to 1000, 10,000 and 50,000.
  + Compute the CPU time per draw for each API, with Vulkan's recording and submission separately.
  + Run once with validation on and record what it costs.
  #done-when(
    [You have a table of costs per draw for both APIs at the three sizes.],
    [You can explain how your driver divides Vulkan's cost between recording and submission.],
  )
  #evidence([The table and the explanation.])
]

#lab([Instancing in both], goal: [See what happens to the gap when the draws disappear.], time: [2 hours], code: "code/u4/glport")[
  + Draw all the cubes with one instanced draw in each API, reading each cube's matrix and colour from a buffer per instance.
  + In OpenGL 4.1, use instanced vertex attributes with `glVertexAttribDivisor`, adding the functions you need to the table. In Vulkan, use a second vertex binding with `VK_VERTEX_INPUT_RATE_INSTANCE`.
  + Measure as in Lab 4.5.1.
  #done-when(
    [Both images pass the comparison.],
    [You can explain how the difference between the APIs changed, from what each driver does per draw.],
  )
  #evidence([The changes and the timings.])
]

#lab([Clip space without the matrix], goal: [Convert clip space in the viewport.], time: [1 hour], code: "code/u4/glport")[
  + Remove `vulkanFromOpenGlClip` from the Vulkan renderer's projection and run. Describe the image and the check's result.
  + Flip y with a negative viewport height instead, and run again.
  + Replace the Vulkan renderer's projection with `u4::perspective` from Chapter 4.1, without the negative viewport.
  #done-when(
    [Both corrected versions pass the comparison.],
    [You can explain why OpenGL's depth range did not change this image with the viewport flip alone, and which objects it would have clipped.],
  )
  #evidence([The three results and the explanation.])
]

#lab([Port a compute frame], goal: [Find every barrier that OpenGL inferred.], time: [1 hour], code: "code/u4/particles")[
  + For each `glMemoryBarrier` in this chapter's OpenGL 4.3 frame, write the Vulkan barrier that replaces it, using @tbl-memory-barrier.
  + List every other hazard in the frame that needs a Vulkan barrier, with its type and the two accesses.
  + Match your two lists against the eleven barriers that `u4_particles` records.
  #done-when(
    [Every barrier of `u4_particles` matches an entry in one of your lists.],
    [For each entry of your second list, you can say how OpenGL's driver knew about the hazard.],
  )
  #evidence([The two lists and the matching.])
]

#problems(
  [At the costs per draw you measured in Lab 4.5.1, how many draws can each API issue in half of a 60 Hz frame, counting Vulkan's recording and submission together?],
  [Why does the OpenGL renderer need a window, and the Vulkan renderer not even a surface?],
  [A port's vertex shader indexes a per-instance array with the instance number, in a draw whose first instance is 100. What must change between OpenGL and Vulkan?],
  [OpenGL needs no `glMemoryBarrier` between a draw that renders into a texture and a compute shader that reads it with `imageLoad`. What does Vulkan need there, and how did OpenGL's driver know?],
  [The comparison allows differences of two levels, and up to 0.5% of pixels beyond that. Why not demand identical images? What would let a broken port pass if the coverage test were removed?],
)

#checklist(
  [I can port an OpenGL renderer to Vulkan behind one interface and check each step against the original image.],
  [I can convert between OpenGL's and Vulkan's clip spaces, by matrix or by viewport.],
  [I can measure the CPU cost of draws in both APIs and explain the difference.],
  [I can translate `glMemoryBarrier` calls into Vulkan barriers, and find the hazards that OpenGL handled silently.],
  [Lab 4.5.1–4.5.4 done-when criteria all hold, with evidence filed.],
)
