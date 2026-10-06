#import "../lib/template.typ": *

= Setup <h-setup>

The course needs five things: a GPU driver with Vulkan 1.3, the Vulkan SDK's loader, layers and shader tools, a C++20 compiler, CMake with Ninja, and, for Unit 4, GLFW. This part sets them up on Windows, Linux and macOS, builds the companion code and checks it with `vkf_selftest`. Allow two hours.

== Hardware

Any GPU whose driver reports Vulkan 1.3 will do. As a rough guide that means NVIDIA GeForce 900 series and later, AMD Radeon RX 400 series and later, Intel graphics from 6th-generation Core processors on, and every Apple Silicon Mac through MoltenVK; Lab 1.1.1 checks your own. A discrete GPU makes the performance chapters more instructive, because its memory and bus behave very differently from the CPU's, but every lab works on integrated graphics. The course's code was run on an Apple M2 Pro, and its console listings come from that machine.

== Windows

+ *Driver.* Install the current driver from NVIDIA, AMD or Intel. The drivers that Windows Update installs sometimes lack Vulkan.
+ *Vulkan SDK.* Install the current SDK from LunarG at #link("https://vulkan.lunarg.com")[vulkan.lunarg.com]. It includes the loader, the validation layers, `glslc`, the SPIR-V tools, `vulkaninfo` and the Vulkan Configurator, and sets the `VULKAN_SDK` environment variable that CMake uses to find them.
+ *Compiler and build tools.* Install Visual Studio 2022 with the "Desktop development with C++" workload, which includes MSVC, CMake and Ninja. Build from an "x64 Native Tools Command Prompt" so that they are on the path.
+ *GLFW,* for Unit 4. The simplest route is vcpkg: `vcpkg install glfw3 opengl-registry`, then add `-DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake` when you configure the code below. The second package supplies Khronos' OpenGL headers, which only Chapter 4.5's port needs.
+ *RenderDoc,* from #link("https://renderdoc.org")[renderdoc.org].

== Linux

+ *Driver.* Mesa provides Vulkan for AMD (RADV) and Intel (ANV); keep it current, since newer versions add features and fix bugs. For NVIDIA, install the proprietary driver.
+ *Vulkan SDK.* Download the Linux tarball from LunarG, extract it, and run `source <sdk>/setup-env.sh` in each shell, or add that line to your shell's start-up file. Distribution packages are an alternative; on Ubuntu 24.04, `sudo apt install libvulkan-dev vulkan-tools vulkan-validationlayers glslc spirv-tools glslang-tools`. They may lag behind the SDK, as explained under "Validation layer versions" below.
+ *Compiler and build tools.* GCC 13 or Clang 17 or later, CMake 3.24 or later, and Ninja: `sudo apt install g++ cmake ninja-build`.
+ *GLFW,* for Unit 4: `sudo apt install libglfw3-dev libgl-dev`. The second package supplies the OpenGL headers that Chapter 4.5's port needs.
+ *RenderDoc,* from your distribution or renderdoc.org.

== macOS

Apple's GPUs have no native Vulkan driver. MoltenVK implements Vulkan on top of Metal, as Chapter 1.1 explains, and the rest of the toolchain is the same as elsewhere.

+ *Compiler.* Install the Xcode Command Line Tools with `xcode-select --install`. Install Xcode itself as well if you want to capture GPU work (Chapter 1.6).
+ *Vulkan SDK, recommended.* Install the macOS SDK from LunarG, which includes MoltenVK, the loader, the layers and the tools. Run `source ~/VulkanSDK/<version>/setup-env.sh` in each shell, or add it to `~/.zshrc`.
+ *Build tools and GLFW:* `brew install cmake ninja glfw`.

Homebrew can also supply the whole toolchain instead of the SDK. This is the configuration the course was written on:

```sh
brew install molten-vk vulkan-loader vulkan-headers vulkan-validationlayers \
  vulkan-tools shaderc glslang spirv-tools glfw cmake ninja
```

Homebrew's validation layer has one problem. Its manifest names the layer's library without a directory, and the loader cannot find it, so creating an instance with validation fails with `VK_ERROR_LAYER_NOT_PRESENT`. Setting `DYLD_LIBRARY_PATH` to the layer's directory works in an interactive shell, but macOS removes `DYLD_` variables whenever a protected system program such as `/bin/sh` starts, so it fails as soon as a script runs your program. The robust fix is a copy of the manifest that names the library by its full path, and `VK_LAYER_PATH` pointing at it:

```sh
layers=$(brew --prefix vulkan-validationlayers)
mkdir -p "$HOME/.local/share/vulkan-layers"
sed "s|\"library_path\": \"|\"library_path\": \"$layers/lib/|" \
  "$layers/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json" \
  > "$HOME/.local/share/vulkan-layers/VkLayer_khronos_validation.json"
export VK_LAYER_PATH="$HOME/.local/share/vulkan-layers"   # add this line to ~/.zshrc
```

On every Mac, remember what MoltenVK lacks. It is a portability implementation, so programs must enable portability enumeration and the portability subset (Chapter 1.1). It has no `shaderFloat64` and no pipeline statistics queries. It translates shaders to Metal, which keeps its own shader cache (Chapter 1.4) and rejects names that collide with Metal's standard library. RenderDoc does not run on macOS; Xcode's Metal debugger takes its place (Chapter 1.6).

== Check the installation

Run `vulkaninfo --summary`. It should list your GPU with an API version of 1.3 or later. On macOS it should name MoltenVK as the driver. If it reports no devices, the driver is missing or, on macOS, the SDK's environment is not set up in this shell.

== The companion code

The code arrives as `Vulkan-Foundations-Code.zip` in your library on the course website. It unpacks into `vulkan-foundations/code`; the volumes call this folder `code/`, and every command in them runs from inside it.

```sh
cd vulkan-foundations/code
cmake -S . -B build -G Ninja
cmake --build build
```

The build compiles the helper library `vkf`, its self-test, and every project of every unit, with each project's shaders compiled to SPIR-V beside it; the programs land in `build/bin`. To build only some units, configure with `-DVKF_UNITS="u1;u2"`. Unit 4 is skipped with a message if CMake cannot find GLFW. Then run the self-test:

#console(read("/src/console/h-selftest.txt"), caption: [`vkf_selftest` on an Apple M2 Pro: a compute kernel checked on the CPU, an image written to a PNG file, and a dispatch on a second queue])

The first two lines name the device and driver `vkf` chose and confirm that validation and synchronisation validation are on. The last line must read `selftest passed`, and the program must exit with status 0.

Every `vkf` program reads four environment variables:

#tbl(columns: (auto, 1fr), header: ([Variable], [Effect]),
  [`VKF_VALIDATION=0`], [Runs without the validation layer, for timing. Every measurement in the course uses it.],
  [`VKF_SYNC_VALIDATION=0`], [Keeps the validation layer but turns off synchronisation validation, which is the slowest part.],
  [`VKF_DEVICE=<n>`], [Uses device `n` in the order `vulkaninfo` lists them, instead of the first discrete GPU.],
  [`VKF_QUIET=1`], [Suppresses the two start-up lines.],
)

Unit 1's programs use the raw API instead of `vkf`, and read only `VKF_VALIDATION`.

=== Validation layer versions

The course was written with the validation layer from SDK version 1.4.363. Older layers ignore settings they do not know, and their synchronisation validation may find less. In particular, the code enables a setting called `syncval_shader_accesses_heuristic`, without which the layer used for this course missed hazards between dispatches. If an older layer stays silent about a hazard the text says it reports, update the SDK.

== Troubleshooting

#tbl(columns: (1fr, 1.4fr), header: ([Symptom], [Cause and fix]),
  [`vkCreateInstance` fails with `VK_ERROR_INCOMPATIBLE_DRIVER`], [No Vulkan driver was found. Install or update the GPU driver. On macOS, the program must enable portability enumeration, which the course's code does, and MoltenVK must be installed.],
  [`VK_ERROR_LAYER_NOT_PRESENT`], [The validation layer is missing or its library cannot be loaded. Install the SDK; with Homebrew on macOS, apply the manifest fix above.],
  [`no device supports Vulkan 1.3`, or `VKF_DEVICE ... is not a usable device`], [The driver is too old, or the GPU predates Vulkan 1.3. Update the driver, or choose another device with `VKF_DEVICE`.],
  [CMake cannot find `glslc` or Vulkan], [The SDK's environment is not set in this shell. Run its `setup-env.sh`, or on Windows reopen the prompt after installing.],
  [Unit 4 targets are missing], [CMake did not find GLFW. Install it and configure again; on Windows pass vcpkg's toolchain file.],
  [Only `u4_glport` is missing], [CMake did not find `GL/glcorearb.h`. Install the OpenGL headers as above; macOS needs nothing.],
  [A pipeline fails to compile only on macOS], [A name in a shader collides with Metal's standard library. Rename it (Chapter 1.4).],
  [Validation messages you did not expect], [Read them, as Chapter 1.6 shows. Programs exit with a non-zero status when the layer reports an error.],
)
