vkf_program(u4_triangle main.cpp)
target_link_libraries(u4_triangle PRIVATE u4_shared)
# Lets CMake list libvkf.a once; Apple's linker warns when an archive appears twice.
set_target_properties(u4_triangle PROPERTIES LINK_LIBRARIES_STRATEGY REORDER_FREELY)
vkf_shaders(u4_triangle triangle.vert triangle.frag cube.vert cube.frag)
