add_library(u4_shared STATIC graphics.cpp)
target_include_directories(u4_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(u4_shared PUBLIC vkf)
vkf_warnings(u4_shared)
