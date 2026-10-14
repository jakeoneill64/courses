vkf_raw_program(u1_pipeline main.cpp)
target_include_directories(u1_pipeline PRIVATE ../shared)
vkf_shaders(u1_pipeline fill.comp)
