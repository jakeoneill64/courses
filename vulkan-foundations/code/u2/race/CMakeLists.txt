vkf_program(u2_race main.cpp)
target_include_directories(u2_race PRIVATE ../shared)
vkf_shaders(u2_race counter.comp tree_sum.comp)
