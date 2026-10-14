include(cmake/Course.cmake)

add_library(vkf STATIC
  vkf/src/check.cpp
  vkf/src/context.cpp
  vkf/src/memory.cpp
  vkf/src/commands.cpp
  vkf/src/pipeline.cpp
  vkf/src/timing.cpp
  vkf/src/image_io.cpp
  vkf/src/util.cpp)
target_include_directories(vkf PUBLIC vkf/include)
target_link_libraries(vkf PUBLIC Vulkan::Vulkan)

vkf_program(aif_kernels main.cpp)
vkf_shaders(aif_kernels matmul_naive.comp matmul_tiled.comp matmul_blocked.comp softmax.comp flash.comp)
