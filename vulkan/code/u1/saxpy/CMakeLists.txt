vkf_raw_program(u1_saxpy main.cpp)
target_include_directories(u1_saxpy PRIVATE ../shared)
vkf_shaders(u1_saxpy saxpy.comp)
