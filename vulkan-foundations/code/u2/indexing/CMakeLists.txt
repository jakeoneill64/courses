vkf_program(u2_indexing main.cpp)
target_include_directories(u2_indexing PRIVATE ../shared)
vkf_shaders(u2_indexing indexing.comp)
