#pragma once

#include <vkf/vkf.hpp>

#include <algorithm>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace u3 {

// Collects message IDs such as SYNC-HAZARD-READ-AFTER-WRITE; vkf's own messenger prints them.
class MessageLog {
public:
    explicit MessageLog(const vkf::Context& ctx) : instance_(ctx.instance()) {
        auto create = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(instance_, "vkCreateDebugUtilsMessengerEXT"));
        destroy_ = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(instance_, "vkDestroyDebugUtilsMessengerEXT"));
        if (create == nullptr || destroy_ == nullptr) return;
        const VkDebugUtilsMessengerCreateInfoEXT info{
            .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                               VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                           VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
            .pfnUserCallback = onMessage,
            .pUserData = this,
        };
        VKF_CHECK(create(instance_, &info, nullptr, &messenger_));
    }
    ~MessageLog() {
        if (messenger_ != VK_NULL_HANDLE) destroy_(instance_, messenger_, nullptr);
    }
    MessageLog(const MessageLog&) = delete;
    MessageLog& operator=(const MessageLog&) = delete;

    // The identifiers recorded since the last call, each once, in order of arrival.
    std::vector<std::string> take() {
        std::lock_guard lock(mutex_);
        return std::exchange(ids_, {});
    }

private:
    static VKAPI_ATTR VkBool32 VKAPI_CALL
    onMessage(VkDebugUtilsMessageSeverityFlagBitsEXT, VkDebugUtilsMessageTypeFlagsEXT,
              const VkDebugUtilsMessengerCallbackDataEXT* data, void* user) {
        auto* self = static_cast<MessageLog*>(user);
        const std::string id =
            data->pMessageIdName != nullptr ? data->pMessageIdName : "unnamed";
        std::lock_guard lock(self->mutex_);
        if (std::find(self->ids_.begin(), self->ids_.end(), id) == self->ids_.end()) {
            self->ids_.push_back(id);
        }
        return VK_FALSE;
    }

    VkInstance instance_;
    VkDebugUtilsMessengerEXT messenger_ = VK_NULL_HANDLE;
    PFN_vkDestroyDebugUtilsMessengerEXT destroy_ = nullptr;
    std::mutex mutex_;
    std::vector<std::string> ids_;
};

}  // namespace u3
