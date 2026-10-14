if(NOT TARGET glfw)
  message(STATUS "u4_sandbox: skipped, GLFW was not found")
  return()
endif()
# Unit 3's render graph; lib.cmake defines the target once, whichever unit includes it first.
include(${PROJECT_SOURCE_DIR}/u3/rendergraph/lib.cmake)
vkf_program(u4_sandbox main.cpp)
target_link_libraries(u4_sandbox PRIVATE u3_rendergraph_lib u4_present u4_shared)
set_target_properties(u4_sandbox PROPERTIES LINK_LIBRARIES_STRATEGY REORDER_FREELY)
vkf_shaders(u4_sandbox simulate.comp cull.comp post.comp cube.vert cube.frag particle.vert
            particle.frag)
