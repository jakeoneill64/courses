#include "vkf/check.hpp"

#include <vulkan/vk_enum_string_helper.h>

#include <string>

namespace vkf {

Error::Error(VkResult result, const std::string& message)
    : std::runtime_error(message), result_(result) {}

const char* toString(VkResult result) {
    return string_VkResult(result);
}

VkResult check(VkResult result, const char* call, std::source_location where) {
    if (result < 0) {
        throw Error(result, std::string(call) + " returned " + toString(result) + " at " +
                                where.file_name() + ":" + std::to_string(where.line()));
    }
    return result;
}

}  // namespace vkf
