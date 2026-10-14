# Units that include() this file and u3 itself may both reach it in one build.
if(TARGET u3_rendergraph_lib)
  return()
endif()
add_library(u3_rendergraph_lib STATIC ${CMAKE_CURRENT_LIST_DIR}/rendergraph.cpp)
target_include_directories(u3_rendergraph_lib PUBLIC ${CMAKE_CURRENT_LIST_DIR})
target_link_libraries(u3_rendergraph_lib PUBLIC vkf)
vkf_warnings(u3_rendergraph_lib)
