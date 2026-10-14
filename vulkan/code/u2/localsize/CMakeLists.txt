vkf_program(u2_localsize main.cpp)
target_include_directories(u2_localsize PRIVATE ../shared)
vkf_shaders(u2_localsize saxpy.comp fma_chain.comp)
