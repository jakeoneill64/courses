if(NOT TARGET glfw)
  message(STATUS "u4_particles: skipped, GLFW was not found")
  return()
endif()
vkf_program(u4_particles main.cpp)
target_link_libraries(u4_particles PRIVATE u4_present u4_shared)
set_target_properties(u4_particles PROPERTIES LINK_LIBRARIES_STRATEGY REORDER_FREELY)
vkf_shaders(u4_particles simulate.comp cull.comp post.comp cube.vert cube.frag particle.vert
            particle.frag)
