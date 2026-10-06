#import "../lib/template.typ": *

= Reference library <h-library>

Each chapter's reading list names the sections to read with it. This part collects the sources in one place. Everything here is free unless it is marked as a book, and the links are to the official homes of the documents.

== Specifications

- *The Vulkan specification* (Khronos), at #link("https://docs.vulkan.org/spec/latest/index.html")[docs.vulkan.org/spec], with every published version at #link("https://registry.khronos.org/vulkan/")[registry.khronos.org/vulkan]. It is the final word on what is valid. Learn to search it by VUID (Chapter 1.6), and read the valid-usage list of every function you call for the first time.
- *The SPIR-V specification* (Khronos), at #link("https://registry.khronos.org/SPIR-V/")[registry.khronos.org/SPIR-V], with the GLSL.std.450 instruction set.
- *The OpenGL Shading Language 4.60 specification* and the *`GL_KHR_vulkan_glsl` extension* that adapts it to Vulkan, in the Khronos OpenGL registry and the KhronosGroup/GLSL repository on GitHub.
- *The OpenGL 4.6 core profile specification* (Khronos), for the comparisons, at #link("https://registry.khronos.org/OpenGL/")[registry.khronos.org/OpenGL].

== Guides and samples

- *The Vulkan Guide* (Khronos), at #link("https://docs.vulkan.org/guide/latest/index.html")[docs.vulkan.org/guide]: short, authoritative chapters on topics the specification spreads out, from the loader to synchronisation. Its "Vulkan Decoder Ring" maps Vulkan terms to those of other APIs.
- *Vulkan Samples* (Khronos), at #link("https://github.com/KhronosGroup/Vulkan-Samples")[github.com/KhronosGroup/Vulkan-Samples]: runnable samples of API features and performance practices, each with an explanation.
- *Sascha Willems' Vulkan examples*, at #link("https://github.com/SaschaWillems/Vulkan")[github.com/SaschaWillems/Vulkan]: compact examples of nearly every rendering and compute technique, kept current for many years.
- *The Vulkan hardware database* by Sascha Willems, at #link("https://vulkan.gpuinfo.org")[vulkan.gpuinfo.org]: the reported features, limits and formats of thousands of devices and drivers. Check it before relying on an optional feature.

== Synchronisation and render graphs

- Hans-Kristian Arntzen, "Yet another blog explaining Vulkan synchronization" (2019), on his blog, themaister.net. The clearest informal account of the model that Chapter 3.2 teaches.
- The "Synchronization Examples" in the Vulkan Guide, a catalogue of common cases with the barriers each needs.
- Yuriy O'Donnell, "FrameGraph: Extensible Rendering Architecture in Frostbite", GDC 2017. The talk that introduced render graphs to most of the industry.
- Hans-Kristian Arntzen, "Render graphs and Vulkan: a deep dive" (2017), on themaister.net, which works through barrier derivation and aliasing in a real renderer.

== Memory

- Adam Sawicki, "Memory management in Vulkan and DX12", GDC 2018.
- The documentation of AMD's Vulkan Memory Allocator, in particular "Choosing memory type" and "Recommended usage patterns".

== GPU computing

- Wen-mei W. Hwu, David B. Kirk and Izzat El Hajj, _Programming Massively Parallel Processors_, 4th edition, Morgan Kaufmann, 2022 (book). Written for CUDA, but its chapters on the execution model, memory, reduction, scan, histograms, sorting and stencils apply directly to Unit 2.
- Mark Harris, "Optimizing Parallel Reduction in CUDA", NVIDIA, 2007. The classic sequence of reduction kernels that Chapter 2.3 follows.
- Mark Harris, Shubhabrata Sengupta and John D. Owens, "Parallel Prefix Sum (Scan) with CUDA", _GPU Gems 3_, chapter 39, 2007.
- Duane Merrill and Michael Garland, "Single-pass Parallel Prefix Scan with Decoupled Look-back", NVIDIA technical report, 2016.
- Lars Nyland, Mark Harris and Jan Prins, "Fast N-Body Simulation with CUDA", _GPU Gems 3_, chapter 31, 2007.
- Samuel Williams, Andrew Waterman and David Patterson, "Roofline: An Insightful Visual Performance Model for Multicore Architectures", _Communications of the ACM_ 52(4), 2009.

== Ray tracing

- Peter Shirley, Trevor David Black and Steve Hollasch, the _Ray Tracing in One Weekend_ series, at #link("https://raytracing.github.io")[raytracing.github.io]. The best short introduction to the path tracing that Chapter 2.7 runs on the GPU.
- Matt Pharr, Wenzel Jakob and Greg Humphreys, _Physically Based Rendering: From Theory to Implementation_, 4th edition, MIT Press, 2023 (book, also free at #link("https://pbr-book.org")[pbr-book.org]). The reference for everything from bounding volume hierarchies to materials.

== Books on Vulkan

- Graham Sellers with John Kessenich, _Vulkan Programming Guide_, Addison-Wesley, 2016. Thorough on Vulkan 1.0; read it for the original design and check newer practice against the specification.
- Marco Castorina and Gabriel Sassone, _Mastering Graphics Programming with Vulkan_, Packt, 2023. A modern renderer, including a frame graph, multithreaded recording and GPU-driven rendering.

== Vendor guides

- NVIDIA, "Vulkan Dos and Don'ts", on the NVIDIA Developer blog.
- AMD, the _RDNA Performance Guide_, on GPUOpen.
- Arm, the _Mali GPU Best Practices Developer Guide_, for tile-based GPUs.
- Apple, the _Metal Feature Set Tables_, for the limits MoltenVK inherits on each Apple GPU.

== Tools

- *RenderDoc*, at #link("https://renderdoc.org")[renderdoc.org]: frame capture and inspection on Windows and Linux.
- *NVIDIA Nsight Graphics*, *AMD Radeon GPU Profiler* and *Intel Graphics Performance Analyzers*: vendor profilers with hardware counters.
- *Xcode's Metal debugger*, for captures on macOS through MoltenVK.
- *The Vulkan Configurator*, `vkconfig`, in the SDK: layer settings for any program.
