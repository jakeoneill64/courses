#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <span>
#include <vector>

#include "vkf/context.hpp"

namespace vkf {

// snippet:begin memory-use
enum class MemoryUse {
    DeviceLocal,  // fastest for the GPU; not mapped
    Upload,       // host-visible and coherent, written by the CPU and read by the GPU
    Readback,     // host-visible, and cached where the device offers it
    Shared,       // device-local and host-visible if available, otherwise like Upload
};
// snippet:end memory-use

// One allocation per buffer: simple, but real programs sub-allocate (Chapter 1.2).
class Buffer {
public:
    Buffer() = default;
    Buffer(Buffer&& other) noexcept;
    Buffer& operator=(Buffer&& other) noexcept;
    Buffer(const Buffer&) = delete;
    Buffer& operator=(const Buffer&) = delete;
    ~Buffer();

    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkDeviceSize size = 0;
    void* mapped = nullptr;       // set for every use except DeviceLocal
    VkDeviceAddress address = 0;  // set only with SHADER_DEVICE_ADDRESS usage
    VkMemoryPropertyFlags memoryFlags = 0;

    template <class T>
    T* data() const {
        return static_cast<T*>(mapped);
    }
    operator VkBuffer() const { return buffer; }
    // Needed only when memoryFlags lacks VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.
    void flush(VkDeviceSize offset = 0, VkDeviceSize bytes = VK_WHOLE_SIZE) const;
    void invalidate(VkDeviceSize offset = 0, VkDeviceSize bytes = VK_WHOLE_SIZE) const;
    void reset();

private:
    friend Buffer createBuffer(const Context&, VkDeviceSize, VkBufferUsageFlags, MemoryUse,
                               const char*);
    VkDevice device_ = VK_NULL_HANDLE;
};

Buffer createBuffer(const Context& ctx, VkDeviceSize size, VkBufferUsageFlags usage,
                    MemoryUse use = MemoryUse::DeviceLocal, const char* name = nullptr);

struct ImageDesc {
    VkFormat format = VK_FORMAT_R8G8B8A8_UNORM;
    uint32_t width = 1;
    uint32_t height = 1;
    uint32_t depth = 1;
    uint32_t mipLevels = 1;
    uint32_t layers = 1;
    VkImageUsageFlags usage = VK_IMAGE_USAGE_STORAGE_BIT;
    VkImageType type = VK_IMAGE_TYPE_2D;
    VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT;
    VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT;
};

// One optimal-tiling image in device-local memory, with a view of every mip level and layer.
class Image {
public:
    Image() = default;
    Image(Image&& other) noexcept;
    Image& operator=(Image&& other) noexcept;
    Image(const Image&) = delete;
    Image& operator=(const Image&) = delete;
    ~Image();

    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    ImageDesc desc;

    operator VkImage() const { return image; }
    VkExtent3D extent() const { return {desc.width, desc.height, desc.depth}; }
    void reset();

private:
    friend Image createImage(const Context&, const ImageDesc&, const char*);
    VkDevice device_ = VK_NULL_HANDLE;
};

Image createImage(const Context& ctx, const ImageDesc& desc, const char* name = nullptr);

// Prefers a type that also has the preferred flags.
uint32_t findMemoryType(const Context& ctx, uint32_t typeBits, VkMemoryPropertyFlags required,
                        VkMemoryPropertyFlags preferred = 0);

// Both stage through a temporary buffer on the main queue and wait for completion.
void upload(const Context& ctx, const Buffer& dst, const void* data, VkDeviceSize bytes,
            VkDeviceSize offset = 0);
void download(const Context& ctx, const Buffer& src, void* data, VkDeviceSize bytes,
              VkDeviceSize offset = 0);

template <class T>
void upload(const Context& ctx, const Buffer& dst, std::span<const T> values,
            VkDeviceSize offset = 0) {
    upload(ctx, dst, values.data(), values.size_bytes(), offset);
}

template <class T>
std::vector<T> download(const Context& ctx, const Buffer& src, size_t count,
                        VkDeviceSize offset = 0) {
    std::vector<T> values(count);
    download(ctx, src, values.data(), count * sizeof(T), offset);
    return values;
}

// Mip 0 of layer 0, tightly packed. Uploads leave the image in finalLayout; downloads return
// it to currentLayout.
void uploadImage(const Context& ctx, const Image& dst, const void* pixels, VkDeviceSize bytes,
                 VkImageLayout finalLayout);
std::vector<uint8_t> downloadImage(const Context& ctx, const Image& src,
                                   VkImageLayout currentLayout);

uint32_t formatSize(VkFormat format);

}  // namespace vkf
