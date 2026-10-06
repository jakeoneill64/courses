vkf_program(u4_scaling main.cpp)
target_link_libraries(u4_scaling PRIVATE u4_shared)
set_target_properties(u4_scaling PROPERTIES LINK_LIBRARIES_STRATEGY REORDER_FREELY)
vkf_shaders(u4_scaling rect.vert rect.frag variant.frag)
