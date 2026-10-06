#import "../lib/template.typ": *

= The graphics pipeline <ch-graphics>

#chapter-meta(
  time: [6 hours],
  builds: [A triangle with interpolated colours, then a depth-tested cube in front of a wall, rendered offscreen with dynamic rendering, written to PNG files and checked pixel by pixel against a CPU rasteriser and a ray caster; and the same triangle drawn with a render pass and a framebuffer, as older code does.],
  needs: [Units 1 to 3. The vector and matrix algebra of 3D graphics.],
)

#why[
  Everything so far has been compute: one programmable stage, fed by descriptors. Rendering adds a pipeline of fixed-function hardware around two programmable stages, and it is still most of what GPUs are built to do. The objects are familiar, pipelines, descriptor sets, push constants, barriers and layouts, so this chapter concentrates on what is new: the stages a triangle passes through, the state each needs, the attachments it renders into, and the coordinate systems that put it on the screen. It renders offscreen and checks every result on the CPU, so that a rendering bug is a failed test, not a picture that looks slightly wrong.
]

#skip-test(
  rule: [If all five are easy, read the section on render passes and do Labs 4.1.3 and 4.1.4.],
  [Name the stages a triangle passes through between the vertex buffer and the colour attachment, and say which are programmable.],
  [What does a graphics pipeline fix when it is created, and what can you leave dynamic?],
  [What are an attachment's load and store operations, and why is a depth attachment often stored with `VK_ATTACHMENT_STORE_OP_DONT_CARE`?],
  [In Vulkan's normalised device coordinates, which way does +y point, and what is the range of depth?],
  [What does dynamic rendering replace, and why will you still meet `VkRenderPass`?],
)

== Core ideas

=== The pipeline, stage by stage

A draw call sends vertices through a fixed sequence of stages (@fig-pipeline). _Vertex input_ fetches each vertex's attributes from vertex buffers, as the pipeline's bindings and attributes describe. _Input assembly_ groups vertices into primitives, here triangles. The _vertex shader_ runs once per vertex and outputs its position in _clip space_, `gl_Position`, together with any values to pass on. Fixed hardware then clips primitives to the view, divides by the fourth coordinate, and maps the result through the _viewport_ to pixels. The _rasteriser_ determines which pixels each triangle covers, discarding triangles that face away if culling is on, and interpolates the vertex shader's outputs across the triangle. The _fragment shader_ runs once per covered pixel and computes its colour. The _depth test_ compares each fragment's depth with the depth attachment and discards hidden ones, and _colour blending_ combines the result with what the colour attachment already holds.

#fig("u4-pipeline", caption: [The graphics pipeline. Two stages run your shaders; the rest are fixed-function hardware configured by the pipeline's state.]) <fig-pipeline>

The first program draws one triangle whose vertices carry a two-dimensional position and a colour, from a host-visible vertex buffer:

#snippet("u4/triangle/main.cpp", "triangle-data", caption: [Three vertices, each with a position and a colour])

The pipeline's _vertex input state_ describes how to fetch them: one _binding_, a buffer with a stride per vertex, and one _attribute_ per shader input, with its location, format and offset within the vertex.

#snippet("u4/triangle/main.cpp", "triangle-input", caption: [Vertex input: one binding and two attributes])

The shaders read the attributes by location. The vertex shader passes the colour on, and the rasteriser interpolates it across the triangle for the fragment shader:

#listing("u4/triangle/triangle.vert", caption: [The vertex shader])

#listing("u4/triangle/triangle.frag", caption: [The fragment shader])

=== Graphics pipeline state

A graphics pipeline bakes in everything about the stages that the hardware may compile into the shaders or configure ahead of time. The course's helper, `u4::createGraphicsPipeline`, fills the structures from a description; each part maps to a stage of @fig-pipeline. There are two shader stages:

#snippet("u4/shared/graphics.cpp", "stages", caption: [The vertex and fragment stages])

The vertex input and input assembly state describe the vertices; the viewport, rasterisation and multisample state the rasteriser:

#snippet("u4/shared/graphics.cpp", "vertex-input", caption: [Vertex input and input assembly])

#snippet("u4/shared/graphics.cpp", "rasterisation", caption: [One viewport and scissor, filled polygons, back-face culling, one sample per pixel])

`frontFace` says which winding order counts as facing the viewer, counter-clockwise here, and `cullMode` discards triangles facing away, which halves the work for closed meshes. The depth and blend state configure the last two stages:

#snippet("u4/shared/graphics.cpp", "depth-state", caption: [The depth test, enabled when the pipeline has a depth attachment])

#snippet("u4/shared/graphics.cpp", "blend", caption: [Colour blending: opaque, additive, or alpha])

_Dynamic state_ is the exception to baking everything in: state named in `VkPipelineDynamicStateCreateInfo` is set by commands in the command buffer instead. Every pipeline in the course leaves the viewport and scissor dynamic, so that one pipeline serves any size of image; Vulkan 1.3 allows much more state to be dynamic, such as the cull mode and the depth test.

#snippet("u4/shared/graphics.cpp", "dynamic-state", caption: [Viewport and scissor, set at draw time])

Finally, a pipeline used with _dynamic rendering_ declares the formats of the attachments it will render into, in a `VkPipelineRenderingCreateInfo` chained into the create-info:

#snippet("u4/shared/graphics.cpp", "create-pipeline", caption: [Creating the graphics pipeline])

#opengl[
  OpenGL sets every piece of this state with separate calls, `glEnable(GL_DEPTH_TEST)`, `glBlendFunc`, `glCullFace`, `glVertexAttribPointer` and so on, at any time before a draw. The driver must then compile or patch shaders for the combination it finds at the draw, which is where OpenGL's unpredictable stalls come from. Vulkan asks for the combination up front, in the pipeline, and lets you name the few pieces of state that should vary freely.
]

=== Attachments and dynamic rendering

The images a draw renders into are _attachments_: a colour attachment, and optionally a depth attachment. The program creates both as optimally tiled images, with the usage flags that rendering and the readback copy need:

#snippet("u4/triangle/main.cpp", "attachments", caption: [A colour attachment, a depth attachment, and a buffer to read the result into])

Before rendering, both images move from `UNDEFINED` to their attachment layouts. The barriers name the stages that will touch them: colour attachment output for the colour image, and the early and late fragment tests for depth, which both read and write it.

#snippet("u4/triangle/main.cpp", "to-attachments", caption: [Transitions into the attachment layouts])

`vkCmdBeginRendering` starts rendering into them. Each attachment has a _load operation_, what happens to its contents when rendering starts, and a _store operation_, what happens when it ends. `VK_ATTACHMENT_LOAD_OP_CLEAR` fills it with a clear value, `LOAD` keeps its contents and `DONT_CARE` makes no promise; `STORE_OP_STORE` writes the results to memory and `DONT_CARE` lets them be discarded. The depth attachment is needed only during rendering, so its results are not stored. On tile-based GPUs, such as Apple's and most mobile GPUs, which render each region of the screen in on-chip memory, a discarded attachment need never be written to memory at all.

#snippet("u4/triangle/main.cpp", "begin-rendering", caption: [Clearing both attachments and keeping only the colour])

Inside, the program binds the pipeline, sets the dynamic viewport and scissor, binds the vertex buffer and draws three vertices. `vkCmdDraw` takes a vertex count, an instance count, and the first vertex and instance:

#snippet("u4/triangle/main.cpp", "draw-triangle", caption: [Recording the triangle])

After rendering, a barrier from colour attachment writes to transfer reads, with a transition to `TRANSFER_SRC_OPTIMAL`, lets a copy move the image into the readback buffer:

#snippet("u4/triangle/main.cpp", "copy-out", caption: [From the colour attachment to the host])

=== Checking a rendering

Pixels are less forgiving than they look: a rendering can be wrong in ways nobody notices. The program therefore checks its triangle against what the rasteriser must produce. For every pixel whose centre lies at least one pixel inside the triangle, it computes the _barycentric weights_ of the centre, applies them to the three vertex colours, and requires the rendered colour to be within two levels of 8 bits. Every pixel at least one pixel outside the triangle must be exactly the background. Pixels on the edges are skipped, because which of them a triangle covers depends on the rasteriser's fill rules, which the check does not model.

#snippet("u4/triangle/main.cpp", "check-triangle", caption: [The CPU's rasteriser: barycentric interpolation at every pixel centre])

=== Into three dimensions

A 3D scene needs a chain of transformations (@fig-spaces). A _model matrix_ places an object in the world; a _view matrix_ places the world in front of the camera; a _projection matrix_ maps the camera's view volume to clip space, from which the fixed hardware divides by w and applies the viewport.

#fig("u4-spaces", caption: [From an object's coordinates to the framebuffer. Vulkan's normalised device coordinates differ from OpenGL's in two ways that every projection matrix must respect.]) <fig-spaces>

Vulkan's conventions differ from OpenGL's, and matrices written for one give wrong pictures in the other. In Vulkan's normalised device coordinates, +y points down the image, and depth runs from 0 at the near plane to 1 at the far plane. The course's projection matrix flips y and maps depth to that range:

#snippet("u4/shared/vecmath.hpp", "perspective", caption: [A perspective projection for Vulkan's clip space])

#snippet("u4/shared/vecmath.hpp", "look-at", caption: [The view matrix of a camera looking at a point])

The scene is a cube in front of a wall, and the wall is the same cube mesh, scaled flat. The cube's vertices carry a position and a normal, and each face has its own four vertices so that its normal is constant across it:

#snippet("u4/shared/mesh.hpp", "cube", caption: [A cube with a separate quadrilateral for each face])

Each box gets its own model matrix and tint, and the product of the camera's view and projection with the model matrix reaches the vertex shader as a push constant, written before each draw. The draws are _indexed_: an index buffer lists the vertices of each triangle, so that the four vertices of a face serve its two triangles.

#snippet("u4/triangle/main.cpp", "draw-boxes", caption: [One indexed draw per box, with its matrix in push constants])

#listing("u4/triangle/cube.vert", caption: [The cube's vertex shader colours each face by its normal])

=== The depth test

The cube stands in front of the wall, but the program draws the cube first. Without a depth test the wall, drawn second, would cover it. With one, each fragment's depth is compared with the depth already stored at its pixel, and only a nearer fragment is drawn and its depth stored. The depth attachment's format is the first of three common formats that the device supports for depth attachments:

#snippet("u4/shared/graphics.cpp", "depth-format", caption: [Choosing a depth format the device can render into])

To check the cube, the program casts a ray through the centre of every fourth pixel and finds the nearest face it hits, by intersecting the ray with each box in the box's own coordinates. Where a pixel and its four neighbours see the same face, the rendered colour must be that face's colour. Where the ray passes through the cube and on to the wall, the pixel must show the cube, which tests the depth test.

#snippet("u4/triangle/main.cpp", "ray-cast", caption: [The ray caster that checks the rasteriser])

#console(read("/src/console/u4-triangle.txt"), caption: [The triangle and the cube, both checked, on the M2 Pro])

#fig("/src/figures/u4-triangle-images.png", caption: [The two images the program wrote, `triangle.png` and `cube.png`.]) <fig-triangle-images>

=== Render passes, for reading older code

Before Vulkan 1.3 made dynamic rendering core, every draw happened inside a _render pass_: an object created in advance that lists the attachments with their formats, load and store operations and layouts, divides rendering into _subpasses_, and declares the dependencies between them and the outside. A _framebuffer_ binds actual image views to a render pass's attachments, and every pipeline must be created for a particular render pass. Most existing Vulkan code, and many tutorials, still use them, so the program can draw the triangle that way too:

#snippet("u4/triangle/main.cpp", "render-pass", caption: [A render pass with one colour attachment and one subpass])

#snippet("u4/triangle/main.cpp", "subpass-dependencies", caption: [Subpass dependencies: the barriers into and out of the render pass, declared in advance])

#snippet("u4/triangle/main.cpp", "framebuffer", caption: [A framebuffer binds the image view to the attachment])

#snippet("u4/triangle/main.cpp", "begin-render-pass", caption: [Recording the same triangle inside the render pass])

#console(read("/src/console/u4-triangle-render-pass.txt"), caption: [The render-pass version produces an identical image])

Render passes let the driver plan the use of tile memory across subpasses, which matters on tile-based GPUs, at the cost of objects that must match each other exactly. Dynamic rendering trades that planning for simplicity; Vulkan 1.4's local-read feature gives dynamic rendering the ability to read the previous pass's attachments from tile memory, which recovers most of what subpasses offered.

#reading(
  [The Vulkan specification, chapters "Graphics Pipelines" (in "Pipelines"), "Fixed-Function Vertex Processing", "Rasterization", "Fragment Operations", "The Framebuffer" and "Render Pass".],
  [The Vulkan Guide, "Pipeline Dynamic State", "Primitive Topology", "Depth" and "Vertex Input Data Processing".],
  [Any treatment of 3D transformations, for example chapter 2 of Pharr, Jakob and Humphreys, _Physically Based Rendering_, with Vulkan's clip-space conventions in mind.],
)

== Labs

#lab([Read the triangle's pixels], goal: [Run the first rendering and understand its check.], time: [1 hour], code: "code/u4/triangle")[
  + Run `build/bin/u4_triangle` and open `triangle.png` and `cube.png`.
  + Change the second vertex's colour to white and confirm that the check still passes, then change the CPU's copy of the colour only and confirm that it fails.
  + Explain why the check skips the pixels on the triangle's edges.
  #done-when(
    [The program passes with your new colour and fails when the CPU's expectation is wrong.],
    [Your explanation names the fill rules.],
  )
  #evidence([Both outputs and the explanation.])
]

#lab([State you can change], goal: [See which state the pipeline fixes and which it does not.], time: [1.5 hours], code: "code/u4/triangle")[
  + Reverse the triangle's winding order with back-face culling on, and record what is drawn.
  + Make the cull mode dynamic with `VK_DYNAMIC_STATE_CULL_MODE` and set it per draw with `vkCmdSetCullMode`.
  + Render the cube with `VK_POLYGON_MODE_LINE`, after checking that `fillModeNonSolid` is enabled.
  #done-when(
    [Each variant renders as you predicted, with validation silent.],
    [You can say which of the three changes needed a new pipeline and which did not.],
  )
  #evidence([The three images and your notes.])
]

#lab([Break the depth test], goal: [Connect the depth state to what the image shows.], time: [1.5 hours], code: "code/u4/triangle")[
  + Disable the depth test and run: record which checks fail and why.
  + Restore it, change the compare operation to `VK_COMPARE_OP_GREATER` and the clear value to 0, and explain the result.
  + Use an OpenGL-style projection matrix, with depth from −1 to 1 and y up, and describe what happens to the image.
  #done-when(
    [You have the output of all three runs.],
    [Each explanation refers to the stage and the state involved.],
  )
  #evidence([The images and explanations.])
]

#lab([Render passes and dynamic rendering], goal: [Translate between the two APIs.], time: [2 hours], code: "code/u4/triangle")[
  + Run with `--render-pass` and confirm the images match.
  + Extend the render-pass version to draw the cube with its depth attachment: a second attachment, its reference in the subpass, and its dependencies.
  + List every piece of information the render pass holds that dynamic rendering supplies at `vkCmdBeginRendering` instead.
  #done-when(
    [The render-pass cube matches the dynamic-rendering cube exactly.],
    [Your list covers attachments, layouts, load and store operations, and dependencies.],
  )
  #evidence([The extended code and the list.])
]

#problems(
  [A vertex has a position of three floats, a normal of three floats and a texture coordinate of two. Write its binding and attribute descriptions.],
  [Why does the course's projection matrix negate the y scale? Show what happens to a point at the top of the view without it.],
  [The depth attachment is cleared to 1.0 and compared with `LESS`. What would a clear value of 0.0 do? Why is depth often stored reversed, with 1 at the near plane?],
  [Explain why the triangle check compares only pixels at least one pixel from an edge, and how a check of edge pixels would have to work.],
  [Which of the render pass's two subpass dependencies corresponds to which of the dynamic-rendering version's barriers?],
)

#checklist(
  [I can name every stage of the graphics pipeline and the state that configures it.],
  [I can create a graphics pipeline with vertex input, depth testing, blending and dynamic state.],
  [I can render offscreen with dynamic rendering, with the right attachments, layouts, load and store operations and barriers.],
  [I can transform a scene into Vulkan's clip space, and read code that uses render passes.],
  [Lab 4.1.1–4.1.4 done-when criteria all hold, with evidence filed.],
)
