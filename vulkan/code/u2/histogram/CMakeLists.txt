vkf_program(u2_histogram main.cpp)
target_include_directories(u2_histogram PRIVATE ../shared)
vkf_shaders(u2_histogram global.comp shared.comp)
