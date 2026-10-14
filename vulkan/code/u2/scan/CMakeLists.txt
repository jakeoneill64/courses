vkf_program(u2_scan main.cpp)
target_include_directories(u2_scan PRIVATE ../shared)
vkf_shaders(u2_scan hillis_steele.comp blelloch.comp compact_flags.comp compact_scatter.comp
            ../shared/scan_blocks.comp ../shared/scan_add.comp)
