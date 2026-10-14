# u3 render graph: usage note

A small render graph from Chapter 3.8. Passes declare which buffers and images they read and
write. `compile()` culls unused passes, places transient resources (aliasing memory between
resources whose lifetimes do not overlap), derives every barrier and layout transition, and
splits work into per-queue batches when a pass asks for the async compute queue. Verified
with synchronisation validation on (zero messages) by `u3_rendergraph`, including
`--async` and `--graphics` (colour and depth attachments through dynamic rendering).

Files: `rendergraph.hpp` (API), `rendergraph.cpp`, `lib.cmake` (the `u3_rendergraph_lib`
static library). Depends only on vkf.

## Linking from another unit

```cmake
include(${PROJECT_SOURCE_DIR}/u3/rendergraph/lib.cmake)   # safe to include more than once
add_executable(u4_sandbox main.cpp ...)
target_link_libraries(u4_sandbox PRIVATE u3_rendergraph_lib glfw)   # brings vkf with it
vkf_warnings(u4_sandbox)
vkf_shaders(u4_sandbox ...)
```

`vkf_program()` also works, but it links vkf a second time and Apple's linker then prints
"ignoring duplicate libraries"; the form above avoids that. `#include <rendergraph.hpp>`.

## Declaring

```cpp
rg::Graph graph(ctx);
// Transients: the graph creates them in compile(); give the usage flags explicitly.
rg::Resource depth = graph.createImage("depth", {.format = VK_FORMAT_D32_SFLOAT,
    .width = w, .height = h, .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
    .aspect = VK_IMAGE_ASPECT_DEPTH_BIT});
rg::Resource args = graph.createBuffer("draw args", bytes,
    VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
// Imports: your own objects. `previous` is the resource's last use before the graph runs,
// taken to have run on the queue of the resource's first user in this graph.
rg::Resource particles = graph.importBuffer("particles", particleBuffer, rg::VertexInput);
rg::Resource target = graph.importImage("swapchain", image, view,
    {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
    {VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_NONE, VK_IMAGE_LAYOUT_UNDEFINED});

graph.addPass("simulate", [&](VkCommandBuffer cmd) { /* dispatch */ })
    .read(particles, rg::ComputeRead).write(particles, rg::ComputeWrite)
    .queue(rg::Queue::Compute);   // optional; read "Async compute" before doing this
graph.addPass("draw", [&](VkCommandBuffer cmd) { /* vkCmdBeginRendering ... */ })
    .read(particles, rg::VertexInput)
    .read(args, rg::IndirectRead)
    .write(target, rg::ColorAttachment)
    .write(depth, rg::DepthAttachment);
graph.addPass("present").read(target, rg::Present).sideEffect();
graph.compile();          // compile(false) turns memory aliasing off
graph.printPlan();        // optional: passes kept and culled, memory, batches, barriers
```

- `rg::Use{stages, access, layout}` describes one use; the layout matters only for images.
  Presets: `ComputeRead`, `ComputeWrite`, `IndirectRead`, `CopySource`, `CopyDestination`,
  `ClearDestination` (vkCmdFillBuffer/vkCmdClearColorImage run in the CLEAR stage),
  `HostRead`, `VertexInput`, `IndexInput`, `FragmentSampled`, `ColorAttachment`,
  `DepthAttachment` (DEPTH_STENCIL_ATTACHMENT_OPTIMAL), `Present`. Make your own for
  anything else, e.g. a vertex shader reading a storage buffer:
  `{VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_READ_BIT}`.
- `read()` means "needs the current contents"; `write()` means "produces new contents".
  Read-modify-write (atomics, blending, depth testing against earlier passes' depth) calls
  both. A pure `write()` is assumed to overwrite the whole resource.
- Culling: a pass survives if it is `sideEffect()` or a surviving pass reads something it
  wrote. Writing an imported resource does not by itself keep a pass, so mark passes whose
  only consumer is outside the graph (readback, present, state for the next frame) as
  `sideEffect()`.
- A kept pass that reads a transient before any pass writes it makes `compile()` throw.
- Image uses must not ask for two layouts of one image in one pass.

## After compile()

- `graph.buffer(r)`, `graph.image(r)`, `graph.view(r)` return the Vulkan objects, including
  transients; write descriptor sets after `compile()`. Record callbacks run at execution
  time, so they may capture the graph and look handles up then.
- Each image barrier covers the image's whole subresource range (all mips and layers).

## Executing

- `graph.record(cmd)`: records every pass with its barriers into your command buffer. Only
  for a graph that runs on one queue (no async pass, or no separate compute queue).
- `graph.submit(waits, signals, fence)`: records and submits one command buffer per batch.
  `waits` go on the first main-queue batch (for example the swapchain acquire semaphore at
  `COLOR_ATTACHMENT_OUTPUT`); `signals` and `fence` go on the last batch, which also waits
  for the other queue, so they cover all the graph's work. Use `ALL_COMMANDS` as the stage
  of a present semaphore so that it covers the final PRESENT_SRC transition.
- The graph reuses its command buffers, timestamp queries and transient memory, so do not
  execute it again until its previous execution has finished. For frames in flight, build
  one graph per frame slot, and wait on that slot's fence or timeline value first.
- `graph.rebind(r, buffer)` / `graph.rebind(r, VK_NULL_HANDLE, image, view)` points an
  import at another object between executions (this frame's swapchain image). The barriers
  are fixed at compile time, so the new object must have the same `previous` use.
- `graph.passTimes()`: per kept pass, GPU ms from the end of the work before it on its queue
  to its own end. Call after the execution completes.

## Async compute

`.queue(rg::Queue::Compute)` puts a pass on `ctx.computeQueue()` when
`vkf::ContextOptions::asyncCompute` found a separate queue; otherwise it runs on the main
queue and nothing else changes. The graph cuts batches so that independent work overlaps and
adds timeline-semaphore waits between queues at the consumer's stages.

- Transients used by both queue families are created with `VK_SHARING_MODE_CONCURRENT`; the
  graph never records queue family ownership transfers.
- An imported resource used on both queues must therefore be created CONCURRENT by you, or
  be used by only one queue family.
- An import's `previous` use is assumed to have run on the queue of its first user in the
  graph, earlier in submission order, so a barrier covers it. If it ran on the other queue
  (for example the previous frame drew particles on the main queue and this frame simulates
  them on the compute queue), that work must have finished first. With frames in flight,
  the simplest way is one copy of such state per frame slot: the wait on the slot's fence
  then covers the previous use, and `previous` can stay empty.

## Things validation will not catch

- Synchronisation validation (VVL 1.4.363) does not track hazards between aliased images, or
  between an image and a buffer sharing memory; it does between aliased buffers. Image
  aliasing in the graph is correct by construction (the new image's barrier starts from
  UNDEFINED with the previous owner's stages and accesses), but validation cannot confirm it.
- Its shader-access heuristic treats atomic operations as reads, so a missing barrier after
  a pass whose only writes are atomics goes unreported.
