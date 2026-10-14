vkf_program(u2_raytrace main.cpp)
target_include_directories(u2_raytrace PRIVATE ../shared)
vkf_shaders(u2_raytrace render.comp resolve.comp debug.comp)
