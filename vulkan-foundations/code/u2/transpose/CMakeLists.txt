vkf_program(u2_transpose main.cpp)
target_include_directories(u2_transpose PRIVATE ../shared)
vkf_shaders(u2_transpose copy.comp naive.comp tiled.comp)
