#include "vkf/image_io.hpp"

#include <algorithm>
#include <array>
#include <cstdio>
#include <stdexcept>
#include <vector>

namespace vkf {
namespace {

uint32_t crc32(const uint8_t* data, size_t size, uint32_t crc = 0) {
    static const std::array<uint32_t, 256> table = [] {
        std::array<uint32_t, 256> t{};
        for (uint32_t n = 0; n < 256; ++n) {
            uint32_t c = n;
            for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            t[n] = c;
        }
        return t;
    }();
    crc = ~crc;
    for (size_t i = 0; i < size; ++i) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return ~crc;
}

void putBigEndian(std::vector<uint8_t>& out, uint32_t value) {
    for (int shift = 24; shift >= 0; shift -= 8) {
        out.push_back(static_cast<uint8_t>(value >> shift));
    }
}

void chunk(std::vector<uint8_t>& out, const char type[4], const std::vector<uint8_t>& body) {
    putBigEndian(out, static_cast<uint32_t>(body.size()));
    const size_t start = out.size();
    out.insert(out.end(), type, type + 4);
    out.insert(out.end(), body.begin(), body.end());
    putBigEndian(out, crc32(out.data() + start, out.size() - start));
}

}  // namespace

void writePng(const std::string& path, uint32_t width, uint32_t height,
              std::span<const uint8_t> rgba) {
    if (rgba.size() < size_t(width) * height * 4) {
        throw std::runtime_error("writePng: too few pixels");
    }

    std::vector<uint8_t> raw;
    raw.reserve(size_t(height) * (width * 4 + 1));
    for (uint32_t y = 0; y < height; ++y) {
        raw.push_back(0);
        const uint8_t* row = rgba.data() + size_t(y) * width * 4;
        raw.insert(raw.end(), row, row + size_t(width) * 4);
    }

    // Stored (uncompressed) deflate blocks: larger files, no compression library needed.
    std::vector<uint8_t> zlib = {0x78, 0x01};
    uint32_t a = 1, b = 0;
    for (uint8_t byte : raw) {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    for (size_t offset = 0; offset < raw.size() || offset == 0;) {
        const size_t n = std::min<size_t>(65535, raw.size() - offset);
        const bool last = offset + n == raw.size();
        zlib.push_back(last ? 1 : 0);
        zlib.push_back(static_cast<uint8_t>(n & 0xFF));
        zlib.push_back(static_cast<uint8_t>(n >> 8));
        zlib.push_back(static_cast<uint8_t>(~n & 0xFF));
        zlib.push_back(static_cast<uint8_t>((~n >> 8) & 0xFF));
        zlib.insert(zlib.end(), raw.begin() + static_cast<long>(offset),
                    raw.begin() + static_cast<long>(offset + n));
        offset += n;
        if (n == 0) break;
    }
    putBigEndian(zlib, (b << 16) | a);

    std::vector<uint8_t> header;
    putBigEndian(header, width);
    putBigEndian(header, height);
    header.insert(header.end(), {8, 6, 0, 0, 0});

    std::vector<uint8_t> file = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
    chunk(file, "IHDR", header);
    chunk(file, "IDAT", zlib);
    chunk(file, "IEND", {});

    FILE* f = std::fopen(path.c_str(), "wb");
    if (f == nullptr) throw std::runtime_error("writePng: cannot open " + path);
    const size_t written = std::fwrite(file.data(), 1, file.size(), f);
    std::fclose(f);
    if (written != file.size()) throw std::runtime_error("writePng: short write to " + path);
}

}  // namespace vkf
