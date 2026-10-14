vkf_program(u2_bandwidth main.cpp)
target_include_directories(u2_bandwidth PRIVATE ../shared)
vkf_shaders(u2_bandwidth copy_float.comp copy_vec4.comp strided.comp roofline.comp)
