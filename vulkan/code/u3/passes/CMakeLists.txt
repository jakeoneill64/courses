vkf_program(u3_passes main.cpp)
target_include_directories(u3_passes PRIVATE ../shared)
vkf_shaders(u3_passes generate.comp blur.comp edges.comp select.comp command.comp score.comp
            step.comp)
