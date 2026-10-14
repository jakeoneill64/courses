#pragma once

#include <vulkan/vulkan.h>

#include <source_location>
#include <stdexcept>
#include <string>

namespace vkf {

class Error : public std::runtime_error {
public:
    Error(VkResult result, const std::string& message);
    VkResult result() const noexcept { return result_; }

private:
    VkResult result_;
};

const char* toString(VkResult result);

// Throws on negative results; returns positive ones such as VK_TIMEOUT to the caller.
VkResult check(VkResult result, const char* call,
               std::source_location where = std::source_location::current());

}  // namespace vkf

#define VKF_CHECK(call) ::vkf::check((call), #call)
