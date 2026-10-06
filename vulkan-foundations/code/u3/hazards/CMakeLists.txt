vkf_program(u3_hazards main.cpp)
target_include_directories(u3_hazards PRIVATE ../shared)
vkf_shaders(u3_hazards fill.comp transform.comp args.comp pattern.comp)
