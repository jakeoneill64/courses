#import "../lib/template.typ": *

= Presentation <ch-presentation>

#chapter-meta(
  time: [6 hours],
  builds: [A small presentation library, a window or a headless surface, a swapchain that is recreated when the window changes, and frames in flight; and with it a spinning cube that runs in a window, or headlessly for tests, through a forced resize, with validation silent.],
  needs: [Chapter 4.1 and Chapter 3.6. GLFW.],
)

#why[
  Rendering into an image you created yourself is the easy half of putting pictures on a screen. The screen belongs to the window system, which owns the images that are shown, decides when each is shown, and can take them away when the window changes size. Vulkan's _window system integration_ makes all of that explicit: a surface, a swapchain of images that the presentation engine lends you one at a time, semaphores that order rendering against presentation, and a protocol for when the swapchain no longer fits the window. This chapter builds it once, carefully, so that the rest of the unit can simply ask for the next image.
]

#skip-test(
  rule: [If all four are easy, read the section on semaphores and do Labs 4.2.2 and 4.2.3.],
  [What do the FIFO and mailbox present modes do, and which is always available?],
  [Why does the course keep one acquire semaphore per frame in flight but one ready-to-present semaphore per swapchain image?],
  [What must a program do when `vkAcquireNextImageKHR` returns `VK_ERROR_OUT_OF_DATE_KHR`, and when it returns `VK_SUBOPTIMAL_KHR`?],
  [An acquired image is in `VK_IMAGE_LAYOUT_UNDEFINED`. Write the barrier that prepares it for rendering, and explain its source stage.],
)

== Core ideas

=== Surfaces

A _surface_, `VkSurfaceKHR`, is Vulkan's handle to something that can display images: a window, or a whole display. Surfaces come from instance extensions: `VK_KHR_surface` and one per window system, such as `VK_KHR_win32_surface`, `VK_KHR_xcb_surface`, `VK_KHR_wayland_surface` or, on macOS, `VK_EXT_metal_surface`. GLFW knows which extensions the platform needs and creates the surface for a window. The window must be created with `GLFW_NO_API`, which tells GLFW not to create an OpenGL context for it.

#snippet("u4/present/display.cpp", "window", caption: [A window for Vulkan])

For tests and for machines without a display, `VK_EXT_headless_surface` creates a surface whose images go nowhere. Everything else works as with a window, which makes it the right tool for checking a presentation loop automatically:

#snippet("u4/present/display.cpp", "surface", caption: [The instance extensions and the surface, from GLFW or headless])

`vkf::Context` accepts the extensions and a function that creates the surface, and chooses a queue family that can present to it, which it checks with `vkGetPhysicalDeviceSurfaceSupportKHR`. The window must outlive the context, which destroys the surface:

#snippet("u4/spin/main.cpp", "setup", caption: [A display, a context that presents to it, and a presenter])

=== Swapchains

A _swapchain_ is a set of images that the surface's _presentation engine_ owns and lends to the program one at a time (@fig-swapchain). Creating one starts with asking the surface what it supports: its capabilities, which include the allowed numbers of images and sizes, its formats with their colour spaces, and its present modes.

#snippet("u4/present/swapchain.cpp", "query-surface", caption: [What the surface supports])

The _format_ is usually a four-channel, 8-bit one. The course prefers an `_SRGB` format in the `VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` colour space, so that shaders output linear colours and the hardware applies the sRGB encoding that displays expect when it writes them:

#snippet("u4/present/swapchain.cpp", "surface-format", caption: [Choosing an sRGB format])

The _present mode_ decides how presented images reach the screen. `VK_PRESENT_MODE_FIFO_KHR` queues them and shows one per refresh of the display, which is vertical synchronisation; it is the only mode every implementation must support. `MAILBOX` keeps only the newest presented image waiting, replacing older ones, which lowers latency without tearing. `IMMEDIATE` shows each image at once, even mid-refresh, which tears. `FIFO_RELAXED` is FIFO that tears instead of waiting when a frame is late.

#snippet("u4/present/swapchain.cpp", "present-mode", caption: [The requested mode if supported, otherwise FIFO])

The image count must lie between the surface's minimum and maximum, where a maximum of zero means no limit. Three images let the program render one while one waits to be shown and one is on screen. The extent is the surface's current size, except on platforms that let the swapchain choose:

#snippet("u4/present/swapchain.cpp", "image-count", caption: [Image count and extent within the surface's limits])

#snippet("u4/present/swapchain.cpp", "create-swapchain", caption: [Creating the swapchain, replacing any old one])

Passing the current swapchain as `oldSwapchain` lets the presentation engine hand over to the new one smoothly. Finally the program fetches the images, creates a view of each, and creates one semaphore per image for presentation, for reasons the next section gives:

#snippet("u4/present/swapchain.cpp", "per-image", caption: [The images, a view of each, and a semaphore for each])

#fig("u4-swapchain", caption: [Acquire, render and present. The presentation engine lends an image; a submission renders into it; presentation hands it back.]) <fig-swapchain>

=== Acquire, render, present

A frame has three steps. `vkAcquireNextImageKHR` returns the index of the next image the program may use and signals a semaphore when the image is really free, which may be later than the call returns. The frame's submission waits for that semaphore before writing the image, and signals a second semaphore when it has finished. `vkQueuePresentKHR` waits for the second semaphore and gives the image back to the presentation engine.

#snippet("u4/present/presenter.cpp", "acquire", caption: [Acquiring an image, recreating the swapchain if it is out of date])

#snippet("u4/present/presenter.cpp", "present", caption: [Submitting with the two semaphores, then presenting])

The submission waits for the acquire semaphore only at `VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT`: work before that stage, such as vertex processing, can start while the image is still being displayed. The first barrier on the image must therefore have the same stage as its source, which chains it to the semaphore wait, as Chapter 3.2 explained. It transitions the image from `UNDEFINED`, because its previous contents do not matter:

#snippet("u4/spin/main.cpp", "acquire-barriers", caption: [Preparing the acquired image and the depth buffer for rendering])

The depth buffer is shared by every frame, so its barrier also waits for the previous frame's depth writes. After rendering, the image goes to `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR`, the layout presentation requires; the semaphore signalled at the end of the submission makes the writes visible to the presentation engine, so the barrier needs no destination scope:

#snippet("u4/spin/main.cpp", "present-barrier", caption: [Handing the image to presentation])

#keyidea[
  A semaphore waited on by `vkQueuePresentKHR` is in use until the presentation engine has finished with the image, and nothing tells the program when that is, except that the same image can be acquired again. Tie each present semaphore to its image, not to the frame, and it is never reused too early.
]

The acquire semaphores, by contrast, belong to frames in flight: a frame's acquire semaphore is free again once that frame's submission has completed, which the frame ring already waits for.

=== Frames in flight

The presenter keeps two frames in flight, as Chapter 3.6 taught, with a command pool for each slot and a timeline semaphore that each submission signals with its frame number. Starting a frame waits until the frame that last used the slot has finished, then resets the slot's pool:

#snippet("u4/present/frames.cpp", "begin-frame", caption: [Waiting for the slot's previous frame, then beginning its command buffer])

#snippet("u4/present/frames.cpp", "submit-frame", caption: [Submitting, with the timeline signal added to the frame's own])

=== When the swapchain no longer fits

A swapchain is created for one size of surface. When the window is resized, acquiring or presenting returns `VK_ERROR_OUT_OF_DATE_KHR`, which means the swapchain can no longer be used, or `VK_SUBOPTIMAL_KHR`, which means it can be used but no longer matches the surface exactly. Window systems differ in which they report and when, so the presenter also listens for GLFW's resize event. In each case it waits for the device to go idle, recreates the swapchain at the new size, and calls back into the program to recreate anything that depends on it. A minimised window has a size of zero, for which no swapchain can be created, so the presenter waits for events until the window is restored.

#snippet("u4/present/presenter.cpp", "recreate", caption: [Recreating the swapchain])

#snippet("u4/spin/main.cpp", "on-recreate", caption: [The depth buffer follows the swapchain's size, and the pipeline its format])

Waiting for the whole device to go idle is the simplest correct approach and fine for a resize, which is rare.

=== The loop

The spinning cube's loop asks the presenter for a frame, records the barriers and the draw into the frame's command buffer, and hands the frame back:

#snippet("u4/spin/main.cpp", "loop", caption: [The frame loop])

#console(read("/src/console/u4-spin.txt"), caption: [Two seconds in a window on the M2 Pro's 120 Hz display, with validation on])

#console(read("/src/console/u4-spin-headless.txt"), caption: [The same headless, with a forced resize after thirty frames])

In the window, with FIFO, the frame time settles at the display's 120 Hz refresh, 8.3 ms, and almost all of it is spent submitting and presenting: the presentation engine accepts a new image only as fast as the display shows them. Headless, nothing waits for a display, and a frame takes 0.2 ms. The program reads back the last image in both cases and checks that its centre shows the cube and its corners the background.

#hazard(title: [Pitfall])[
  A swapchain image's format may be `B8G8R8A8` rather than `R8G8B8A8`, depending on the platform. Anything that reads swapchain images back, as this program does to check them, must swap the channels for the format it actually got, and a pipeline that renders to them must be created for that format.
]

#opengl[
  OpenGL presents the _default framebuffer_ with `SwapBuffers`, through the window system's binding: `glfwSwapBuffers`, `wglSwapBuffers` or `glXSwapBuffers`. The driver keeps the back buffers, synchronises rendering against display, and resizes the default framebuffer with the window. Vertical synchronisation is a swap interval, set with `glfwSwapInterval`. Every piece of that, the images, their ownership, the waits and the resize, is a Vulkan object or call you manage.
]

#reading(
  [The Vulkan specification, chapter "Window System Integration (WSI)", in particular "Surface Queries" and "WSI Swapchain".],
  [The Vulkan Guide, "Window System Integration (WSI)" and "Swapchain Semaphore Reuse".],
  [The GLFW documentation, "Vulkan guide".],
)

== Labs

#lab([In a window and headless], goal: [Run the presentation loop both ways.], time: [45 minutes], code: "code/u4/spin")[
  + Run `build/bin/u4_spin`, then with `--headless --resize-at 30`.
  + Resize the window by hand while the windowed version runs with `--frames 0`, minimise it, restore it and close it.
  #done-when(
    [Every run exits with status 0 and validation silent.],
    [You can account for the difference in frame time between the two runs.],
  )
  #evidence([The outputs.])
]

#lab([Present modes, image counts and latency], goal: [Measure how the presentation settings change frame timing.], time: [1.5 hours], code: "code/u4/spin")[
  + Run in a window with `--present-mode` set to `fifo`, `mailbox` and `immediate`; the program reports which it got.
  + With FIFO, run with `--images 2`, `3` and `4` and `--frames-in-flight 1`, `2` and `3`.
  + Record the frame time and the median waits for each combination.
  #done-when(
    [You have a table of every combination your platform supports.],
    [You can explain, for one combination, how many frames separate recording a frame and its appearance on screen.],
  )
  #evidence([The table and the explanation.])
]

#lab([Break the semaphores], goal: [See why the semaphore arrangement matters.], time: [1.5 hours], code: "code/u4/present")[
  + In a copy of the presenter, use one ready-to-present semaphore per frame slot instead of per image, and run with validation on, in a window and headless.
  + Then make the acquire semaphores per image instead of per slot, and run again.
  + Record what validation reports, and explain each arrangement's flaw from the specification.
  #done-when(
    [You have the validation output for both variants.],
    [Your explanation says, for each, which semaphore could be reused while still in use, and by what.],
  )
  #evidence([The outputs and explanations.])
]

#lab([Resize without stalling], goal: [Find what a resize costs.], time: [1.5 hours], code: "code/u4/present")[
  + Time the recreation in `Presenter::recreate`, including `vkDeviceWaitIdle`, during a series of window resizes.
  + Replace the idle wait with waiting for the frame ring's timeline, so that only this queue's frames must finish, and confirm with validation that it is still correct.
  #done-when(
    [Both versions survive repeated resizes with validation silent.],
    [You have the cost of a recreation in both versions.],
  )
  #evidence([The timings and the changed code.])
]

#problems(
  [A surface reports `minImageCount` 2 and `maxImageCount` 0. The program asks for three images. How many does it get, and what does the maximum of zero mean?],
  [Why does the submission wait for the acquire semaphore at `COLOR_ATTACHMENT_OUTPUT` and not at `ALL_COMMANDS`? What would change if it waited at the top of the pipeline?],
  [The acquire barrier transitions the image from `UNDEFINED`. Why is that correct even though the image was presented with contents a moment ago?],
  [With FIFO, three images and two frames in flight on a 60 Hz display, the GPU takes 2 ms per frame. Describe the steady state: where does the CPU wait, and how old is a frame when it appears?],
  [Why does the program need a separate path for headless surfaces at all, given that it never looks at what is presented?],
)

#checklist(
  [I can create a surface from a window or headlessly, and choose a swapchain's format, present mode, image count and extent.],
  [I can acquire, render and present with the right semaphores and barriers, and explain why each semaphore belongs where it does.],
  [I can recreate a swapchain on resize, out-of-date and suboptimal results, and minimised windows.],
  [I can measure and reason about frame timing and latency under each present mode.],
  [Lab 4.2.1–4.2.4 done-when criteria all hold, with evidence filed.],
)
