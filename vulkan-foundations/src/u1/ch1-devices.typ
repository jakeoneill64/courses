#import "../lib/template.typ": *

= Instances, devices and queues <ch-devices>

#chapter-meta(
  time: [5 hours],
  builds: [A program that lists every Vulkan device on your machine with its limits, features and queue families, then creates a logical device with validation and synchronisation validation switched on.],
  needs: [The Handbook's setup part completed: the companion code builds and `vkf_selftest` passes.],
)

#why[
  Every Vulkan program starts the same way: it connects to the loader, chooses a GPU, and asks for a device with exactly the features and queues it intends to use. Nothing is assumed. A program that enables a feature it never checked for fails on some machines and not on others, and a program that skips validation will run with bugs it cannot see. This chapter builds the start-up code that the rest of Unit 1 uses, and it is the place to form two habits that save weeks later: query before you rely on anything, and run with validation from the first line.
]

#skip-test(
  rule: [If you can answer all four without looking anything up, skim the core ideas and do Lab 1.1.3 only.],
  [What is the difference between an instance extension and a device extension, and where does each come from?],
  [Why does `vkCreateInstance` fail on a Mac unless the program enables `VK_KHR_portability_enumeration`, and what must the program then do when it creates the device?],
  [You want timeline semaphores and synchronization2. Which structures do you chain into `VkDeviceCreateInfo`, and what happens if the device lacks one of them?],
  [A device reports one queue family with graphics, compute and transfer, one with compute and transfer, and one with transfer only. Which would you use for a background upload, and why?],
)

== Core ideas

=== What kind of API Vulkan is

Vulkan is a C API for graphics and compute on GPUs, published by the Khronos Group in 2016 and descended from AMD's Mantle. Version 1.1 followed in 2018, 1.2 in 2020, 1.3 in 2022 and 1.4 in 2024; each version folded widely used extensions into the core. This course uses Vulkan 1.3, which every current desktop driver supports and which made synchronization2 and dynamic rendering part of the core.

The defining property of Vulkan is that it is _explicit_. The application creates every object the GPU uses, allocates and binds every byte of memory, records commands into buffers it submits itself, and states every ordering constraint between those commands. In exchange the driver does very little behind your back: it does not track resource state, does not insert barriers, compiles shaders when you ask it to and does not check your calls. That is why a Vulkan program can be faster and more predictable than an OpenGL one, and also why a small mistake can produce a wrong image or a hang with no error at all.

Vulkan's objects are opaque handles such as `VkInstance`, `VkDevice` and `VkBuffer`. You create them with a `vkCreate*` or `vkAllocate*` call that takes a create-info structure, and destroy them with the matching `vkDestroy*` or `vkFree*` call. Almost every structure you pass in begins with two members: `sType`, which names the structure, and `pNext`, a pointer to an optional chain of further structures that extend it. Extensions and newer versions add capabilities by defining new structures for that chain, so existing functions keep their signatures. @fig-objects shows the objects this unit introduces.

#fig("u1-objects", caption: [The objects of Unit 1. The instance and the physical device are about discovery; everything the GPU actually uses is created from the logical device. Arrows point from an object to what it is used to create or reach.]) <fig-objects>

#opengl[
  OpenGL has one implicit object, the _context_, created through the window system (WGL, GLX, EGL or CGL, usually through GLFW or SDL) and made current on a thread. The context bundles what Vulkan separates into an instance, a device and a queue, and the operating system or driver decides which GPU it runs on. Every OpenGL call acts on the current context's global state. Vulkan has no current context and no global state: every call names the objects it uses.
]

=== The loader, layers and drivers

Your program links against the _loader_, `vulkan-1.dll` on Windows and `libvulkan` on Linux and macOS. The loader reads small JSON manifest files that describe the installed _drivers_ (installable client drivers, or ICDs) and _layers_, and routes each call to the right one (@fig-loader). A layer sits between your program and the driver and can observe or change calls. The most important is `VK_LAYER_KHRONOS_validation`, which checks each call against the specification's valid-usage rules and reports violations. It is installed by the Vulkan SDK and costs nothing unless you enable it.

#fig("u1-loader", caption: [How a call reaches a GPU. The loader picks the driver for the device you choose and, if you enable it, sends every call through the validation layer first.]) <fig-loader>

Functionality beyond the core arrives as _extensions_. An _instance extension_ adds instance-level features, such as `VK_EXT_debug_utils` for debug callbacks and object names, and comes from the loader, a layer or a driver. A _device extension_ adds device-level features, such as `VK_KHR_swapchain` for presenting images, and comes from the driver of one particular GPU. You must enable every extension you use, at instance or device creation.

=== Creating the instance

The instance is your program's connection to the loader. Creating it means naming the Vulkan version you write against, the layers and the instance extensions you want, and optionally chaining structures that configure them. The course's start-up code lives in `code/u1/shared/basics.hpp`, which every Unit 1 program includes. It begins with error checking: every Vulkan function that can fail returns a `VkResult`, negative values are errors, and the companion code turns them into exceptions with the result's name.

#snippet("u1/shared/basics.hpp", "check", caption: [Turning a negative `VkResult` into an exception that names the call and the error])

Instance creation starts by asking the loader what is installed. `vkEnumerateInstanceLayerProperties` lists the layers. Like most Vulkan queries it is called twice: once with a null array to learn the count, then again with an array of that size. The program enables validation when the layer is present, unless the environment variable `VKF_VALIDATION` is `0`.

#snippet("u1/shared/basics.hpp", "instance-layers", caption: [Finding the validation layer])

The same two-call pattern lists the instance extensions. The program asks only for extensions that exist: `VK_KHR_portability_enumeration` when the loader offers it, which is the case on macOS (see below); `VK_EXT_debug_utils` for the messenger that reports validation messages; and `VK_EXT_layer_settings`, which lets a program configure a layer from code.

#snippet("u1/shared/basics.hpp", "instance-extensions", caption: [Enabling only the instance extensions the loader offers])

`VkApplicationInfo` names the program and, in `apiVersion`, the highest Vulkan version it is written to use. That field is a statement of intent: instance creation does not fail when a driver is older, and the version you may use with a device is the lower of `apiVersion` and the device's own version. The settings that follow configure the validation layer. `validate_sync` turns on synchronisation validation, which is off by default because it is slower. `syncval_shader_accesses_heuristic` makes it account for the memory that shaders read and write, which it works out by analysing the SPIR-V. Without it, the version of the layer used to write this course missed a conflict between two dispatches that wrote the same buffer; Chapter 1.6 shows the difference, and Unit 3 relies on it.

#snippet("u1/shared/basics.hpp", "instance-app", caption: [The application info and the validation layer's settings])

Everything comes together in `VkInstanceCreateInfo`. The `pNext` chain starts with the layer settings, which point in turn at a description of the debug messenger. A messenger chained here reports messages produced while the instance itself is being created and destroyed. The flag `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` accompanies the portability extension.

#snippet("u1/shared/basics.hpp", "instance-info", caption: [Creating the instance])

Once the instance exists, the program creates a second messenger from the same description, which reports everything between creation and destruction. `vkCreateDebugUtilsMessengerEXT` belongs to an extension, and the loader does not export extension functions from its library, so the program asks the instance for its address with `vkGetInstanceProcAddr`.

#snippet("u1/shared/basics.hpp", "instance-messenger", caption: [The messenger for the instance's lifetime])

The messenger's callback counts errors, so that every program can fail when validation reports one, and prints each message. Returning `VK_FALSE` tells the layer to let the call proceed.

#snippet("u1/shared/basics.hpp", "messenger", caption: [The debug messenger: count errors, print everything])

#keyidea[
  The validation layer is not a debugging tool you reach for when something breaks. It is how you find out that something is broken at all. Invalid Vulkan usage is undefined behaviour: it may work on your GPU and fail on the next one, or work today and fail after a driver update. Every program in this course runs with validation on and fails if the layer reports an error.
]

=== Portability and macOS

Apple's GPUs do not have native Vulkan drivers. MoltenVK implements Vulkan on top of Metal and is installed with the Vulkan SDK. Because Metal cannot express every Vulkan behaviour, MoltenVK is a _portability_ implementation: conformant for everything it supports, but missing a few features that a full implementation must have. Since 2022 the loader hides portability drivers from programs that have not said they can cope with them. To see MoltenVK you must enable `VK_KHR_portability_enumeration` and set `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`, as the code above does. Without both, on a Mac whose only driver is MoltenVK, `vkCreateInstance` finds no driver at all and fails with `VK_ERROR_INCOMPATIBLE_DRIVER`. A device that offers the `VK_KHR_portability_subset` extension must then have it enabled when the logical device is created; the extension's feature structure tells you exactly what is missing.

=== Physical devices

A _physical device_ is a GPU as the driver presents it. You do not create physical devices; you enumerate them, and they live as long as the instance. Each one reports three kinds of information, all of which a careful program reads before relying on anything:

- *Properties*, from `vkGetPhysicalDeviceProperties`: the name, vendor, device type, the highest Vulkan version supported, and the _limits_, more than a hundred numbers such as the largest workgroup or the smallest alignment for a buffer offset.
- *Features*, from `vkGetPhysicalDeviceFeatures2`: optional capabilities such as 64-bit floats in shaders or timeline semaphores, each a `VkBool32`. The Vulkan 1.1, 1.2 and 1.3 features are reported by chaining one structure per version into `pNext`.
- *Queue families*, from `vkGetPhysicalDeviceQueueFamilyProperties`: groups of queues with the same capabilities, described next.

#snippet("u1/devices/main.cpp", "feature-chain", caption: [Reading features through a `pNext` chain: one call fills all three structures])

Choosing a device is a policy decision. The course's code prefers a discrete GPU, then an integrated one, and requires Vulkan 1.3. Production code would also check that every feature and extension it needs is supported, and might let the user override the choice.

#snippet("u1/shared/basics.hpp", "pick-device", caption: [Picking a device: Vulkan 1.3 at least, discrete GPUs first])

=== Queues and queue families

A _queue_ is where you submit work, and a GPU runs work from several queues at once. Queues come in _families_, each with a set of capabilities: graphics, compute, transfer (copies), and some rarer ones such as sparse binding and video. Every family that supports graphics or compute also supports transfer commands, whether or not it sets the transfer flag.

A typical discrete GPU exposes one family that does everything, with one or more queues; a compute-only family with several queues, which runs alongside graphics (_async compute_, Chapter 3.5); and a transfer-only family that drives the copy engines, ideal for uploads that should not disturb rendering. The exact arrangement varies by vendor and driver, which is why programs search for the family they need instead of assuming an index. Apple's GPU, through MoltenVK, reports four identical families of one queue each:

#console(read("/src/console/u1-devices.txt"), caption: [The device report from Lab 1.1.1 on an Apple M2 Pro])

#snippet("u1/shared/basics.hpp", "queue-family", caption: [The first family that has every capability we need])

=== The logical device

The _logical device_, `VkDevice`, is your program's session with one physical device. Creating it is where you commit to what you will use:

- *Queues.* Which queues, from which families, each with a priority between 0 and 1 that the driver may use to schedule between them.
- *Features.* Which features to enable. Features you do not enable may not be used, even if the hardware has them, and asking for one the device lacks makes creation fail with `VK_ERROR_FEATURE_NOT_PRESENT`.
- *Device extensions.* Which device extensions to enable, including `VK_KHR_portability_subset` where the device offers it.

The course enables three Vulkan 1.3 and 1.2 features from the start. _Synchronization2_ is the modern form of barriers and submission that Unit 3 teaches. _Timeline semaphores_ appear in Chapter 3.4. _Maintenance4_ allows, among other things, the `LocalSizeId` execution mode, which the shader compiler emits for the workgroup sizes set by specialisation constants in Chapter 1.4. All three are required to be supported by any Vulkan 1.3 device, so enabling them without checking is safe once the device's version is known.

Each queue the program wants is described by a `VkDeviceQueueCreateInfo`: a family, a count and one priority per queue. Unit 1 needs a single queue that can run compute and graphics work.

#snippet("u1/shared/basics.hpp", "device-queue", caption: [One queue from the chosen family])

Features are enabled with the same structures that reported them, chained into `pNext`. Only the members set to `VK_TRUE` are enabled; everything else stays off.

#snippet("u1/shared/basics.hpp", "device-features", caption: [Enabling exactly three features])

The device extensions are found with the two-call pattern again. The only one Unit 1 needs is `VK_KHR_portability_subset`, which must be enabled whenever the device offers it.

#snippet("u1/shared/basics.hpp", "device-create", caption: [Enabling the portability subset where it exists, then creating the device])

Queues are not created separately: `vkGetDeviceQueue` hands you the queues that device creation made. Objects are destroyed in reverse order of creation: everything made from the device, then the device, then the debug messenger and the instance. The validation layer reports anything you forget, as Chapter 1.6 demonstrates.

#hazard(title: [Pitfall])[
  It is tempting to query features into a `VkPhysicalDeviceFeatures2` chain and pass the same chain to `vkCreateDevice`. That enables every feature the device supports, including ones with a cost: `robustBufferAccess`, for example, adds a bounds check to every buffer access in every shader. Keep the queried structures and the enabled structures separate, and enable only what you use.
]

#opengl[
  OpenGL reports capabilities through `glGetString(GL_RENDERER)`, `glGetIntegerv` for limits such as `GL_MAX_COMPUTE_WORK_GROUP_SIZE`, and `glGetStringi(GL_EXTENSIONS, i)` for extensions. Every extension the driver supports is available as soon as the context exists; there is nothing to enable. OpenGL also checks every call as part of the specification and records failures for `glGetError`, which costs time on every call, even in a finished program. Vulkan moves that checking into a layer that you enable while developing and leave out when you ship.
]

#reading(
  [The Vulkan specification, chapters "Initialization", "Devices and Queues" and "Extending Vulkan" (#link("https://docs.vulkan.org/spec/latest/index.html")[docs.vulkan.org/spec]). Read the sections on `vkCreateInstance` and `vkCreateDevice` with their valid-usage lists.],
  [The Vulkan Guide (#link("https://docs.vulkan.org/guide/latest/index.html")[docs.vulkan.org/guide]): "Loader", "Layers", "pNext and sType", "Querying Properties, Extensions, Features, Limits, and Formats" and "Portability Initiative".],
  [The output of `vulkaninfo` for your own GPU, read alongside the specification's "Limits" chapter.],
)

== Labs

#lab([Read your machine], goal: [Build Unit 1, run the device report, and check it against `vulkaninfo`.], time: [45 minutes], code: "code/u1/devices")[
  + Build the companion code as the Handbook describes, then run `build/bin/u1_devices` from the code folder. On macOS with the Homebrew validation layer, export `DYLD_LIBRARY_PATH` first, as the Handbook explains.
  + Run `vulkaninfo --summary` and compare the device name, API version, and the number of queue families with the report.
  + Run the report with `VKF_VALIDATION=0` and note the first line that changes.
  #done-when(
    [The program exits with status 0 and prints `created a device`.],
    [Every number in the report agrees with `vulkaninfo`.],
  )
  #evidence([The full report, saved to your notebook.], [A sentence on what the queue families tell you about your GPU.])
]

#lab([Break the instance on purpose], goal: [See how creation fails, and what each failure means.], time: [45 minutes], code: "code/u1/devices")[
  + In `createInstance`, push the name of an extension that does not exist, such as `"VK_EXT_not_real"`, onto `extensions` just before the create-info is filled in. Run the program and record the error it reports.
  + Undo that. Now set `enabledLayerCount` to 1 unconditionally and point `ppEnabledLayerNames` at a misspelt name such as `"VK_LAYER_KHRONOS_validaton"`. Record the result.
  + Undo that. On macOS, leave the extension list alone but set `flags` to 0, so that portability enumeration is enabled but not requested. Record the result. On other systems, explain what you would expect.
  + Restore the file from the original code archive and rebuild.
  #done-when(
    [You have recorded `VK_ERROR_EXTENSION_NOT_PRESENT` and `VK_ERROR_LAYER_NOT_PRESENT`, and can say which check in `createInstance` would have prevented each.],
    [On macOS, you have recorded `VK_ERROR_INCOMPATIBLE_DRIVER` and can explain it in one sentence.],
  )
  #evidence([Each change and the error it produced.])
]

#lab([Read more of the feature chain], goal: [Extend the report with the properties a compute programmer needs.], time: [1.5 hours], code: "code/u1/devices")[
  + Chain `VkPhysicalDeviceSubgroupProperties` into `vkGetPhysicalDeviceProperties2` and print the subgroup size, the supported stages and the supported operations.
  + Chain `VkPhysicalDeviceVulkan11Features` and print `storageBuffer16BitAccess` and `shaderDrawParameters`.
  + Print `maxComputeWorkGroupCount` and `minStorageBufferOffsetAlignment` from the limits.
  #done-when(
    [The new lines match `vulkaninfo` for your device.],
    [The program still exits 0 with no validation messages.],
  )
  #evidence([The extended output, and the subgroup size, which Chapter 2.1 relies on.])
]

#lab([Ask for something the device lacks], goal: [Learn what happens when a program assumes a feature.], time: [45 minutes], code: "code/u1/devices")[
  + Find a feature your device does not support in the report, such as `shaderFloat64` on Apple GPUs or `pipelineStatisticsQuery` where it is absent.
  + Enable it in `createDevice` by setting the member in `features.features` (make `features` non-const) and run. Record the result, and the message in which the validation layer names the missing feature.
  + Change `createDevice` so that it checks support first and enables the feature only when present, printing which way it went.
  #done-when(
    [The unchecked version fails with `VK_ERROR_FEATURE_NOT_PRESENT`, or, if your device supports every candidate, you have explained why from the report.],
    [The checked version runs cleanly on your device.],
  )
  #evidence([The failing and the fixed code, and the output of each.])
]

#problems(
  [Explain why physical devices are enumerated and logical devices are created. What would go wrong if an application could create a physical device?],
  [A program sets `VkApplicationInfo::apiVersion` to `VK_API_VERSION_1_2` and runs on a device that reports 1.3. May it call `vkCmdPipelineBarrier2`? If not, what would it have to do to use synchronization2 on that device? Find the passage in the specification that decides this.],
  [A device has families G|C|T (1 queue), C|T (2 queues) and T (2 queues). Write the `VkDeviceQueueCreateInfo` array for a program that wants one queue for rendering, one for async compute and one for uploads.],
  [Why must the debug messenger be destroyed before the instance? What does the validation layer report if you forget?],
  [A colleague passes the `VkPhysicalDeviceFeatures2` chain they used to query support straight into `vkCreateDevice`. Name two consequences, one for correctness and one for performance.],
)

#checklist(
  [I can create an instance with validation, synchronisation validation and portability enumeration, and say what each part does.],
  [I can enumerate physical devices and read their properties, limits, features and queue families.],
  [I can create a logical device that enables only the features and extensions I use.],
  [Lab 1.1.1–1.1.4 done-when criteria all hold, with evidence filed.],
)
