add_library(vkf STATIC
  src/check.cpp
  src/context.cpp
  src/memory.cpp
  src/commands.cpp
  src/pipeline.cpp
  src/timing.cpp
  src/image_io.cpp
  src/util.cpp)
target_include_directories(vkf PUBLIC include)
target_link_libraries(vkf PUBLIC Vulkan::Vulkan)
vkf_warnings(vkf)

vkf_program(vkf_selftest test/selftest.cpp)
vkf_shaders(vkf_selftest test/scale.comp test/gradient.comp)
