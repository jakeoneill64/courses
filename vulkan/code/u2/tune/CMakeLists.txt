vkf_program(u2_tune main.cpp)
target_include_directories(u2_tune PRIVATE ../shared)
vkf_shaders(u2_tune ../reduce/subgroup.comp)
