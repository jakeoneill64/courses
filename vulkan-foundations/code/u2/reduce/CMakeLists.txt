vkf_program(u2_reduce main.cpp)
target_include_directories(u2_reduce PRIVATE ../shared)
vkf_shaders(u2_reduce interleaved.comp sequential.comp coarse.comp subgroup.comp)
