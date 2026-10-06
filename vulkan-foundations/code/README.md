# Vulkan Foundations: companion code

Every lab project of the course, and `vkf`, the helper library that Unit 1 builds up to. The volumes call this folder `code/`.

## Building

```sh
cmake -S . -B build -G Ninja
cmake --build build
./build/bin/vkf_selftest
```

You need a Vulkan 1.3 driver, the Vulkan SDK (or the loader, headers, validation layers and `glslc`), a C++20 compiler, CMake 3.24 or later and Ninja. Unit 4 also needs GLFW 3.3 or later; without it, Unit 4's targets are skipped. Build some units only with `-DVKF_UNITS="u1;u2"`. The programs are written to `build/bin`.

## Running

Every program checks its own results, prints a result line, and exits with a non-zero status if a check fails or the validation layer reports an error. Validation and synchronisation validation are on by default. These environment variables change that:

| Variable | Effect |
|---|---|
| `VKF_VALIDATION=0` | Run without the validation layer, for timing |
| `VKF_SYNC_VALIDATION=0` | Keep validation, without synchronisation validation |
| `VKF_DEVICE=n` | Use device `n`, in the order `vulkaninfo` lists them |
| `VKF_QUIET=1` | Suppress the two start-up lines |

Unit 1's programs use the raw API and read only `VKF_VALIDATION`.

## Layout

| Path | What it holds |
|---|---|
| `common/` | `vkf`: the context, memory, commands, pipelines, descriptors, timing and PNG output |
| `u1/` | Unit 1, against the raw C API |
| `u2/` to `u4/` | Units 2 to 4, one directory per project, with shared code in each unit's `shared/` |
| `cmake/Course.cmake` | `vkf_program`, `vkf_raw_program` and `vkf_shaders` |
