vkf_program(u3_frames main.cpp)
target_include_directories(u3_frames PRIVATE ../shared)
vkf_shaders(u3_frames simulate.comp)
