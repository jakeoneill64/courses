vkf_program(u3_queues main.cpp)
target_include_directories(u3_queues PRIVATE ../shared)
vkf_shaders(u3_queues use.comp work.comp)
