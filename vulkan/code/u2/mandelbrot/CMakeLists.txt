vkf_program(u2_mandelbrot main.cpp)
target_include_directories(u2_mandelbrot PRIVATE ../shared)
vkf_shaders(u2_mandelbrot mandelbrot.comp)
