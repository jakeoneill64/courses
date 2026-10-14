#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <cstdio>
#include <format>
#include <string>
#include <string_view>
#include <vector>

namespace vkf {

constexpr uint32_t groupCount(uint32_t items, uint32_t groupSize) {
    return (items + groupSize - 1) / groupSize;
}
constexpr VkDeviceSize alignUp(VkDeviceSize value, VkDeviceSize alignment) {
    return (value + alignment - 1) / alignment * alignment;
}

std::vector<char> readFile(const std::string& path);

template <class... A>
void print(std::format_string<A...> format, A&&... args) {
    std::fputs(std::format(format, std::forward<A>(args)...).c_str(), stdout);
}

// Options of the form --name value or --flag.
class Args {
public:
    Args(int argc, char** argv);
    bool flag(std::string_view name) const;
    std::string text(std::string_view name, std::string fallback) const;
    long long integer(std::string_view name, long long fallback) const;
    double number(std::string_view name, double fallback) const;

private:
    std::vector<std::string> args_;
    const std::string* value(std::string_view name) const;
};

}  // namespace vkf
