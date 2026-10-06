vkf_program(u3_bugs main.cpp)
target_include_directories(u3_bugs PRIVATE ../shared)
vkf_shaders(u3_bugs fill.comp transform.comp pattern.comp)
