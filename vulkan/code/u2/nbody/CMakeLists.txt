vkf_program(u2_nbody main.cpp)
target_include_directories(u2_nbody PRIVATE ../shared)
vkf_shaders(u2_nbody prepare.comp forces.comp drift.comp potential.comp)
