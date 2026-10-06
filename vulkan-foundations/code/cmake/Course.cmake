function(vkf_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /permissive-)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Wno-missing-field-initializers)
  endif()
endfunction()

# Compiles GLSL to SPIR-V beside the target and tells the program where to find it.
function(vkf_shaders target)
  set(out_dir "${CMAKE_CURRENT_BINARY_DIR}/shaders")
  set(outputs)
  foreach(source IN LISTS ARGN)
    get_filename_component(name "${source}" NAME)
    set(spv "${out_dir}/${name}.spv")
    add_custom_command(
      OUTPUT "${spv}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${out_dir}"
      COMMAND ${GLSLC} --target-env=vulkan1.3 -O -g
              -I "${CMAKE_CURRENT_SOURCE_DIR}" -I "${PROJECT_SOURCE_DIR}/common/shaders"
              -MD -MF "${spv}.d" -o "${spv}" "${CMAKE_CURRENT_SOURCE_DIR}/${source}"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${source}"
      DEPFILE "${spv}.d"
      COMMENT "glslc ${source}"
      VERBATIM)
    list(APPEND outputs "${spv}")
  endforeach()
  add_custom_target(${target}_spirv DEPENDS ${outputs})
  add_dependencies(${target} ${target}_spirv)
  target_compile_definitions(${target} PRIVATE VKF_SHADER_DIR="${out_dir}")
endfunction()

# A program that uses the course's helper library. Unit 1 uses vkf_raw_program instead.
function(vkf_program target)
  add_executable(${target} ${ARGN})
  target_link_libraries(${target} PRIVATE vkf)
  vkf_warnings(${target})
endfunction()

function(vkf_raw_program target)
  add_executable(${target} ${ARGN})
  target_link_libraries(${target} PRIVATE Vulkan::Vulkan)
  vkf_warnings(${target})
endfunction()
