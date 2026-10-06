include(${CMAKE_CURRENT_SOURCE_DIR}/lib.cmake)
# vkf comes through the library; listing it again makes Apple's linker warn about a duplicate.
add_executable(u3_rendergraph main.cpp pipeline.cpp byhand.cpp)
target_link_libraries(u3_rendergraph PRIVATE u3_rendergraph_lib)
target_include_directories(u3_rendergraph PRIVATE ../shared)
vkf_warnings(u3_rendergraph)
vkf_shaders(u3_rendergraph generate.comp blur.comp edges.comp select.comp command.comp score.comp)
