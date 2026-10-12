#include "vkf/util.hpp"

#include <fstream>
#include <stdexcept>

namespace vkf {

std::vector<char> readFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) throw std::runtime_error("cannot open " + path);
    const std::streamsize size = file.tellg();
    std::vector<char> bytes(static_cast<size_t>(size));
    file.seekg(0);
    if (!file.read(bytes.data(), size)) throw std::runtime_error("cannot read " + path);
    return bytes;
}

Args::Args(int argc, char** argv) : args_(argv + 1, argv + argc) {}

bool Args::flag(std::string_view name) const {
    for (const std::string& a : args_) {
        if (a == name) return true;
    }
    return false;
}

const std::string* Args::value(std::string_view name) const {
    for (size_t i = 0; i + 1 < args_.size(); ++i) {
        if (args_[i] == name) return &args_[i + 1];
    }
    return nullptr;
}

std::string Args::text(std::string_view name, std::string fallback) const {
    const std::string* v = value(name);
    return v != nullptr ? *v : fallback;
}

long long Args::integer(std::string_view name, long long fallback) const {
    const std::string* v = value(name);
    return v != nullptr ? std::stoll(*v, nullptr, 0) : fallback;
}

double Args::number(std::string_view name, double fallback) const {
    const std::string* v = value(name);
    return v != nullptr ? std::stod(*v) : fallback;
}

}  // namespace vkf
