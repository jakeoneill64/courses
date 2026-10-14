#import "lib/template.typ": *
#show: course-doc.with(unit: "4", title: "Rendering and the Whole Frame", short: "Rendering and the Whole Frame",
  subtitle: "The graphics pipeline, presentation, compute meets graphics, and porting from OpenGL",
  chapters: ("The graphics pipeline", "Presentation", "Drawing with data", "Compute meets graphics", "From OpenGL to Vulkan", "Scaling up", "Capstone: a GPU-driven sandbox"))
#contents()

#about-unit(unit: "4",
  intro: [Unit 4 turns to rendering and to the frame as a whole. It builds the graphics pipeline from a triangle to a textured scene, presents frames through a swapchain, and joins compute and graphics in GPU-driven rendering. It ports a program from OpenGL and measures what Vulkan saves, scales recording across threads, and ends with a capstone that combines everything in the course: simulation, culling, async compute, frames in flight and a render graph, with every pass timed and synchronisation validation silent.],
  rows: (
    ([4.1], [A triangle and a depth-tested cube, offscreen, checked against a CPU rasteriser], [6]),
    ([4.2], [A presentation library and a spinning cube in a window and headless], [6]),
    ([4.3], [Textured meshes with mipmaps, uniform buffers per frame and a bindless table], [6]),
    ([4.4], [A million particles, GPU culling with indirect draws, and compute post-processing], [7]),
    ([4.5], [An OpenGL program ported to Vulkan, with the CPU cost of each measured], [6]),
    ([4.6], [Multithreaded recording, pipeline caches and memory budgets], [6]),
    ([4.7], [The GPU-driven sandbox], [10]),
  ),
  before: [Finish Units 1 to 3. Install GLFW as the Handbook describes.],
  needs: [The same machine as before, with a display for the windowed labs; every program also runs offscreen or headless.],
)

#include "u4/ch1-graphics.typ"
#include "u4/ch2-presentation.typ"
#include "u4/ch3-data.typ"
#include "u4/ch4-compute-graphics.typ"
#include "u4/ch5-port.typ"
#include "u4/ch6-scaling.typ"
#include "u4/ch7-sandbox.typ"

#signoff(unit: "4",
  chapters: ("The graphics pipeline", "Presentation", "Drawing with data", "Compute meets graphics", "From OpenGL to Vulkan", "Scaling up", "Capstone: a GPU-driven sandbox"),
  review: (
    [Trace one vertex of the textured scene from its buffer to a pixel on screen, naming every stage, transformation and image layout on the way.],
    [Explain how the swapchain, the acquire and ready semaphores and frames in flight fit together, and why the ready semaphore belongs to the image.],
    [Explain GPU culling with an indirect draw, including the barriers after the cull, and how the course checked it against the CPU.],
    [List the differences between OpenGL and Vulkan that change results in a port, and the hazards OpenGL's driver handled that a port must add.],
    [Present your final project's report: what it measures, how it was checked, and what you would change.],
  ),
)
