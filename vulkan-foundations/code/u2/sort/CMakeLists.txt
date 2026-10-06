vkf_program(u2_sort main.cpp)
target_include_directories(u2_sort PRIVATE ../shared)
vkf_shaders(u2_sort sort_count.comp sort_scatter.comp ../shared/scan_blocks.comp
            ../shared/scan_add.comp)
