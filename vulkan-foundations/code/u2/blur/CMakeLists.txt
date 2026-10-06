vkf_program(u2_blur main.cpp)
target_include_directories(u2_blur PRIVATE ../shared)
vkf_shaders(u2_blur blur_rows.comp blur_columns.comp blur_2d.comp downscale.comp)
