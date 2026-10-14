#pragma once

#include <cstdint>
#include <span>
#include <string>

namespace vkf {

// Writes 8-bit RGBA pixels, row by row from the top, as an uncompressed PNG.
void writePng(const std::string& path, uint32_t width, uint32_t height,
              std::span<const uint8_t> rgba);

}  // namespace vkf
