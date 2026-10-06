#import "lib/template.typ": *
#show: course-doc.with(unit: "1", title: "The Explicit API", short: "The Explicit API",
  subtitle: "From an instance to your first compute dispatch, with nothing hidden",
  chapters: ("Instances, devices and queues", "Memory, buffers and images", "Commands and submission", "Shaders, SPIR-V and pipelines", "Descriptors and your first dispatch", "Validation, debugging and a helper layer"))
#contents()

#about-unit(unit: "1",
  intro: [Unit 1 builds a complete Vulkan compute program from nothing, one object at a time. It starts with the loader and an instance, chooses a device and a queue, allocates memory and binds buffers to it, records and submits commands, compiles a shader to SPIR-V and builds a pipeline around it, connects the shader to buffers through descriptors, and dispatches SAXPY with the barriers it needs. The last chapter turns to the tools that find mistakes, and wraps the unit's bookkeeping in `vkf`, the small helper library that the rest of the course uses. Every program in the unit uses the raw C API, so that nothing happens that you have not written.],
  rows: (
    ([1.1], [A device report and a logical device with validation and synchronisation validation], [5]),
    ([1.2], [A memory map, coherent and non-coherent round trips, a sub-allocator, a format survey], [6]),
    ([1.3], [Fill, copy and read back; staging against direct writes; the cost of a submission], [5]),
    ([1.4], [SPIR-V read by hand, pipelines with push and specialisation constants, a pipeline cache], [5]),
    ([1.5], [SAXPY and vector addition end to end, descriptor sets reused across dispatches], [6]),
    ([1.6], [Six broken programs diagnosed, a capture, shader printf, your own RAII layer], [5]),
  ),
  before: [Complete the Handbook's setup part: the SDK, a compiler, CMake and Ninja, the companion code built, and `vkf_selftest` passing. If you have never used a GPU programming API before, read the Handbook's part on how GPUs work first.],
  needs: [A GPU with a Vulkan 1.3 driver: any discrete or integrated GPU from NVIDIA, AMD or Intel from the last several years, or an Apple Silicon Mac through MoltenVK. The validation layers and the shader tools from the Vulkan SDK. On Windows and Linux, RenderDoc; on macOS, Xcode.],
)

#include "u1/ch1-devices.typ"
#include "u1/ch2-memory.typ"
#include "u1/ch3-commands.typ"
#include "u1/ch4-pipelines.typ"
#include "u1/ch5-dispatch.typ"
#include "u1/ch6-validation.typ"

#signoff(unit: "1",
  chapters: ("Instances, devices and queues", "Memory, buffers and images", "Commands and submission", "Shaders, SPIR-V and pipelines", "Descriptors and your first dispatch", "Validation, debugging and a helper layer"),
  review: (
    [From memory, write the sequence of objects SAXPY creates, from the instance to the dispatch, with one sentence each on why it exists.],
    [Explain, for your own GPU, which memory type you would use for a staging buffer, for a buffer the GPU reads every frame, and for results read back by the CPU, citing your Lab 1.2.1 output.],
    [Draw the host and device timelines of one SAXPY run, marking where the barriers and the fence act and what each makes safe.],
    [Explain how a specialised workgroup size reaches the GPU, from the GLSL declaration through SPIR-V to `VkSpecializationInfo`.],
    [Given a validation message you have not seen before, find its rule in the specification and explain the fix.],
  ),
)
