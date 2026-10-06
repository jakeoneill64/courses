#import "../lib/template.typ": *

= Vulkan and OpenGL <h-opengl>

Most readers of this course will have met OpenGL, or will meet it in code they maintain. This part compares the two APIs as a whole: where they came from, how they differ in design, what OpenGL's driver did that Vulkan hands to you, and when OpenGL is still the better choice. Each later chapter adds detailed "Coming from OpenGL" notes, and Chapter 4.5 ports a program from one to the other and measures the difference.

== Two histories

OpenGL 1.0 was published in 1992 by Silicon Graphics, derived from its proprietary IRIS GL, and for twenty-five years it was the portable way to program graphics hardware. An Architecture Review Board of vendors evolved it until 2006, when the Khronos Group took it over. Each version tracked the hardware of its day: programmable shaders in GLSL with OpenGL 2.0 in 2004; a core profile that dropped the fixed-function pipeline with 3.2 in 2009; compute shaders and shader storage buffers with 4.3 in 2012; direct state access with 4.5 in 2014; and SPIR-V shaders with 4.6 in 2017, the last version. OpenGL ES, a subset for embedded and mobile devices, and WebGL, its browser counterpart, extended its reach. Apple stopped at OpenGL 4.1 and deprecated it in 2018.

Vulkan 1.0 was released by Khronos in February 2016, built from AMD's Mantle with the participation of every major GPU vendor. Its versions have folded widely used extensions into the core: 1.1 in 2018 (subgroups, multiple GPUs), 1.2 in 2020 (timeline semaphores, descriptor indexing, buffer device addresses), 1.3 in 2022 (synchronization2, dynamic rendering) and 1.4 in 2024. Unlike OpenGL, Vulkan has a single API for desktop and mobile, with optional features that each device reports.

== Two designs

OpenGL is a _state machine_ attached to an implicit _context_. A thread makes a context current, and from then on every call reads or changes that context's global state: the bound buffer, the active texture unit, the current program, the blend mode. Objects are named by integers, and most are edited by binding them first ("bind to edit"). A draw call takes its inputs from whatever state happens to be current, so the driver must check that state at every draw, and only then can it work out what the GPU must do.

Vulkan has no current context and no global state. Every call names the objects it uses. State that a draw or dispatch depends on is collected into objects created ahead of time, above all the _pipeline_, which bakes shaders and fixed-function state together, and the _descriptor set_, which collects resources. Work is recorded into command buffers on any thread and submitted explicitly. The driver checks nothing at run time; the validation layer checks everything during development.

#fig("h-drivers", caption: [What the driver does. An OpenGL driver tracks state, validates, compiles, manages memory, finds hazards and decides when to submit. A Vulkan driver translates what the program has already decided; validation moves into a layer used during development.]) <fig-drivers>

== One program in both

Chapter 1.5 writes SAXPY, `y = a·x + y`, in Vulkan in about two hundred lines. Here is the host side of the same program in OpenGL 4.5, with context creation and error checks left out. Its shader is the SAXPY shader of Chapter 1.5 with two changes: the buffers are named by `binding` alone, without a `set`, and `a` and `n` are plain `uniform` variables instead of push constants.

```cpp
GLuint shader = glCreateShader(GL_COMPUTE_SHADER);
glShaderSource(shader, 1, &source, nullptr);
glCompileShader(shader);
GLuint program = glCreateProgram();
glAttachShader(program, shader);
glLinkProgram(program);

GLuint buffers[2];
glCreateBuffers(2, buffers);
glNamedBufferStorage(buffers[0], bytes, x.data(), 0);
glNamedBufferStorage(buffers[1], bytes, y.data(), 0);

glUseProgram(program);
glUniform1f(glGetUniformLocation(program, "a"), a);
glUniform1ui(glGetUniformLocation(program, "n"), n);
glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffers[0]);
glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, buffers[1]);
for (int r = 0; r < 10; ++r) {
    if (r > 0) glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
    glDispatchCompute((n + 255) / 256, 1, 1);
}
glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
glGetNamedBufferSubData(buffers[1], 0, bytes, y.data());
```

Every line has a Vulkan counterpart, and most have several. The context hides the instance, the device and its queue (Chapter 1.1). `glNamedBufferStorage` hides the choice of memory type, the allocation and the binding (1.2). `glCompileShader` and `glLinkProgram` compile at run time what Vulkan compiles to SPIR-V at build time and into a pipeline at start-up, with its layout (1.4). `glBindBufferBase` and `glUniform*` are the descriptor set and the push constants (1.5). The dispatches go into a command buffer that the driver manages and submits for you, and `glGetNamedBufferSubData` waits for them, which in Vulkan is a submission, a barrier to the host and a fence (1.3). Only the barriers between dispatches appear in both programs, because OpenGL's driver cannot see what a shader writes.

== What OpenGL's driver did for you

Each of these is something you will do yourself in Vulkan, and each has a chapter.

- *Hazard tracking.* An OpenGL driver knows which command wrote a buffer or texture and which command reads it next, and it inserts the necessary waits and cache operations. It cannot see which addresses a shader will write, which is why OpenGL 4.2 added `glMemoryBarrier` for shader writes. In Vulkan you record every barrier (Chapter 1.3 and Unit 3), or let a render graph derive them (Chapter 3.8).
- *Memory management.* `glBufferData` asks for storage and the driver chooses where it lives, moves it when it guesses wrong, and keeps old copies alive while the GPU still uses them. In Vulkan you choose memory types, allocate, sub-allocate and decide when memory may be reused (Chapters 1.2 and 4.6).
- *Shader compilation.* An OpenGL driver compiles GLSL at run time with its own compiler, and may compile again when state that the program object does not capture changes, causing stalls at unpredictable draw calls. Vulkan compiles SPIR-V when you create a pipeline, with everything it depends on known (Chapter 1.4).
- *State validation.* OpenGL checks every call, as part of the specification, in a finished program as much as in development, unless the program asks for a context without error checking, which OpenGL 4.6 allows. Vulkan checks nothing at run time; the validation layer checks everything during development (Chapter 1.6).
- *Threading.* An OpenGL context belongs to one thread at a time, so submitting work is essentially single-threaded; sharing objects between contexts on several threads is possible but fragile. Vulkan command buffers can be recorded on any number of threads, each with its own pool, and submitted from one (Chapter 4.6).
- *Submission and pacing.* An OpenGL driver buffers commands and decides when to send them, and the swap of the default framebuffer hides the synchronisation between frames. In Vulkan you submit, pace frames in flight and synchronise presentation yourself (Chapters 3.6 and 4.2).

== The concepts side by side

@tbl-map maps the OpenGL concepts this course meets to their Vulkan counterparts and to the chapter that teaches each.

#figure(
  tbl(columns: (1fr, 1.25fr, auto), header: ([OpenGL], [Vulkan], [Chapter]), size: 8.2pt,
    [Context, made current on a thread], [`VkInstance`, `VkDevice` and `VkQueue`, named in every call], [1.1],
    [`glGetIntegerv` limits; every extension available], [Physical device properties, limits and features; extensions enabled at creation], [1.1],
    [`glGetError`, the `KHR_debug` callback], [The validation layer and `VK_EXT_debug_utils`], [1.6],
    [`glGenBuffers` and `glBufferData` or `glBufferStorage`], [`vkCreateBuffer`, `vkAllocateMemory`, `vkBindBufferMemory`], [1.2],
    [Persistent, coherent `glMapBufferRange`], [`vkMapMemory` on `HOST_VISIBLE` and `HOST_COHERENT` memory], [1.2],
    [`glTexStorage2D` and `glTexSubImage2D`], [`vkCreateImage`, memory, a staging buffer, `vkCmdCopyBufferToImage` and layout transitions], [1.2, 4.3],
    [Texture parameters and sampler objects], [`VkSampler` and `VkImageView`], [2.4, 4.3],
    [GLSL source, `glCompileShader`, `glLinkProgram`], [SPIR-V compiled offline, `VkShaderModule`, `VkPipeline`], [1.4],
    [`glUniform*`], [Push constants, or uniform buffers through descriptors], [1.4, 1.5],
    [`glBindBufferBase`, `glBindTexture`, image units], [Descriptor sets and `vkCmdBindDescriptorSets`], [1.5],
    [`glDispatchCompute`], [`vkCmdDispatch`], [1.5],
    [`glMemoryBarrier`], [`vkCmdPipelineBarrier2` with stages and access masks], [1.3, 3.2],
    [`glFenceSync` and `glClientWaitSync`], [`VkFence`, timeline semaphores], [1.3, 3.4],
    [`glFlush` and `glFinish`], [`vkQueueSubmit2`, `vkQueueWaitIdle`], [1.3],
    [`glGetProgramBinary`], [`VkPipelineCache`], [1.4],
    [`glQueryCounter` with `GL_TIMESTAMP`], [`VkQueryPool` and `vkCmdWriteTimestamp2`], [2.5],
    [Vertex array objects, `glVertexAttribPointer`], [Vertex input state in the pipeline, `vkCmdBindVertexBuffers`], [4.1],
    [`glEnable(GL_DEPTH_TEST)`, `glBlendFunc`, `glViewport`], [Pipeline state, and dynamic state such as `vkCmdSetViewport`], [4.1],
    [Framebuffer objects and `glClear`], [Dynamic rendering: `vkCmdBeginRendering` with load and store operations], [4.1],
    [`glDrawArrays`, `glDrawElements`, indirect draws], [`vkCmdDraw`, `vkCmdDrawIndexed`, `vkCmdDrawIndexedIndirect`], [4.1, 4.4],
    [`glReadPixels`], [`vkCmdCopyImageToBuffer`, a fence, and a mapped read], [4.1],
    [The default framebuffer and `SwapBuffers`], [`VkSurfaceKHR`, `VkSwapchainKHR`, acquire and present], [4.2],
    [Shared contexts on several threads], [A command pool per thread, secondary command buffers], [4.6],
    [Hazards tracked by the driver], [Barriers you record, or a render graph that derives them], [3.2, 3.8],
  ),
  caption: [OpenGL concepts and their Vulkan counterparts],
  kind: table,
) <tbl-map>

== Costs and benefits

Vulkan's costs are real. A program is several times longer: SAXPY is about two hundred lines in Unit 1 against a few dozen in OpenGL. Mistakes that OpenGL would have reported or silently fixed become undefined behaviour, which is why this course runs validation everywhere. A program must decide its pipelines, layouts and memory up front, which takes design. And there is more to learn before the first result.

The benefits are what the cost buys. CPU cost per draw and per dispatch is low and, more importantly, predictable: nothing compiles, copies or synchronises behind your back. Recording scales across threads. Memory can be sub-allocated, aliased and placed exactly where it belongs. Explicit synchronisation lets independent work overlap, including on separate queues, which OpenGL cannot express. One API covers desktop and mobile GPUs, with SPIR-V and the validation layers shared by all of them. And because the program does what the driver used to do, the program's author can see, measure and fix it.

== When OpenGL is still the right tool

Vulkan is not the answer to every graphics problem. OpenGL remains a reasonable choice for small tools and prototypes whose CPU cost does not matter; for large OpenGL code bases that work and have no performance problem; and for hardware or platforms without a Vulkan driver. On macOS it is frozen at version 4.1, deprecated, and without compute shaders.

Between the two lie libraries that offer explicit concepts with more safety. WebGPU, the W3C standard for the web, also has native implementations such as Google's Dawn and the Rust library wgpu; SDL 3 includes a portable GPU API. And OpenGL itself increasingly runs on Vulkan: Mesa's Zink implements OpenGL on top of Vulkan, and Google's ANGLE implements OpenGL ES on Vulkan, Metal and Direct3D. Learning Vulkan teaches you what all of these do underneath.
