#include "vkf/memory.hpp"

#include <cstring>
#include <stdexcept>
#include <utility>

#include "vkf/check.hpp"
#include "vkf/commands.hpp"

namespace vkf {

Buffer::Buffer(Buffer&& other) noexcept {
    *this = std::move(other);
}

Buffer& Buffer::operator=(Buffer&& other) noexcept {
    if (this != &other) {
        reset();
        buffer = std::exchange(other.buffer, VK_NULL_HANDLE);
        memory = std::exchange(other.memory, VK_NULL_HANDLE);
        size = std::exchange(other.size, 0);
        mapped = std::exchange(other.mapped, nullptr);
        address = std::exchange(other.address, 0);
        memoryFlags = std::exchange(other.memoryFlags, 0);
        device_ = std::exchange(other.device_, VK_NULL_HANDLE);
    }
    return *this;
}

Buffer::~Buffer() {
    reset();
}

void Buffer::reset() {
    if (device_ == VK_NULL_HANDLE) return;
    if (buffer != VK_NULL_HANDLE) vkDestroyBuffer(device_, buffer, nullptr);
    if (memory != VK_NULL_HANDLE) vkFreeMemory(device_, memory, nullptr);
    buffer = VK_NULL_HANDLE;
    memory = VK_NULL_HANDLE;
    mapped = nullptr;
    address = 0;
    size = 0;
    device_ = VK_NULL_HANDLE;
}

void Buffer::flush(VkDeviceSize offset, VkDeviceSize bytes) const {
    if (memoryFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) return;
    VkMappedMemoryRange range{.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                              .memory = memory,
                              .offset = offset,
                              .size = bytes};
    VKF_CHECK(vkFlushMappedMemoryRanges(device_, 1, &range));
}

void Buffer::invalidate(VkDeviceSize offset, VkDeviceSize bytes) const {
    if (memoryFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) return;
    VkMappedMemoryRange range{.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                              .memory = memory,
                              .offset = offset,
                              .size = bytes};
    VKF_CHECK(vkInvalidateMappedMemoryRanges(device_, 1, &range));
}

uint32_t findMemoryType(const Context& ctx, uint32_t typeBits, VkMemoryPropertyFlags required,
                        VkMemoryPropertyFlags preferred) {
    const VkPhysicalDeviceMemoryProperties& memory = ctx.properties().memory;
    for (VkMemoryPropertyFlags want : {required | preferred, required}) {
        for (uint32_t i = 0; i < memory.memoryTypeCount; ++i) {
            if ((typeBits & (1u << i)) &&
                (memory.memoryTypes[i].propertyFlags & want) == want) {
                return i;
            }
        }
    }
    throw Error(VK_ERROR_OUT_OF_DEVICE_MEMORY, "no memory type has the required properties");
}

namespace {

std::pair<VkMemoryPropertyFlags, VkMemoryPropertyFlags> flagsFor(MemoryUse use) {
    switch (use) {
        case MemoryUse::DeviceLocal: return {VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 0};
        case MemoryUse::Upload:
            return {VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    0};
        case MemoryUse::Readback:
            return {VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    VK_MEMORY_PROPERTY_HOST_CACHED_BIT};
        case MemoryUse::Shared:
            return {VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT};
    }
    return {0, 0};
}

}  // namespace

Buffer createBuffer(const Context& ctx, VkDeviceSize size, VkBufferUsageFlags usage,
                    MemoryUse use, const char* name) {
    Buffer result;
    result.device_ = ctx.device();
    result.size = size;

    VkBufferCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    VKF_CHECK(vkCreateBuffer(ctx.device(), &info, nullptr, &result.buffer));

    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(ctx.device(), result.buffer, &requirements);
    const auto [required, preferred] = flagsFor(use);
    const uint32_t type =
        findMemoryType(ctx, requirements.memoryTypeBits, required, preferred);
    result.memoryFlags = ctx.properties().memory.memoryTypes[type].propertyFlags;

    const bool deviceAddress = (usage & VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) != 0;
    VkMemoryAllocateFlagsInfo flags{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
        .flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT,
    };
    VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = deviceAddress ? &flags : nullptr,
        .allocationSize = requirements.size,
        .memoryTypeIndex = type,
    };
    VKF_CHECK(vkAllocateMemory(ctx.device(), &allocate, nullptr, &result.memory));
    VKF_CHECK(vkBindBufferMemory(ctx.device(), result.buffer, result.memory, 0));

    if (use != MemoryUse::DeviceLocal) {
        VKF_CHECK(
            vkMapMemory(ctx.device(), result.memory, 0, VK_WHOLE_SIZE, 0, &result.mapped));
    }
    if (deviceAddress) {
        VkBufferDeviceAddressInfo addressInfo{
            .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = result.buffer};
        result.address = vkGetBufferDeviceAddress(ctx.device(), &addressInfo);
    }
    if (name != nullptr) {
        ctx.name(result.buffer, name);
        ctx.name(result.memory, name);
    }
    return result;
}

Image::Image(Image&& other) noexcept {
    *this = std::move(other);
}

Image& Image::operator=(Image&& other) noexcept {
    if (this != &other) {
        reset();
        image = std::exchange(other.image, VK_NULL_HANDLE);
        memory = std::exchange(other.memory, VK_NULL_HANDLE);
        view = std::exchange(other.view, VK_NULL_HANDLE);
        desc = other.desc;
        device_ = std::exchange(other.device_, VK_NULL_HANDLE);
    }
    return *this;
}

Image::~Image() {
    reset();
}

void Image::reset() {
    if (device_ == VK_NULL_HANDLE) return;
    if (view != VK_NULL_HANDLE) vkDestroyImageView(device_, view, nullptr);
    if (image != VK_NULL_HANDLE) vkDestroyImage(device_, image, nullptr);
    if (memory != VK_NULL_HANDLE) vkFreeMemory(device_, memory, nullptr);
    view = VK_NULL_HANDLE;
    image = VK_NULL_HANDLE;
    memory = VK_NULL_HANDLE;
    device_ = VK_NULL_HANDLE;
}

Image createImage(const Context& ctx, const ImageDesc& desc, const char* name) {
    Image result;
    result.device_ = ctx.device();
    result.desc = desc;

    VkImageCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = desc.type,
        .format = desc.format,
        .extent = {desc.width, desc.height, desc.depth},
        .mipLevels = desc.mipLevels,
        .arrayLayers = desc.layers,
        .samples = desc.samples,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = desc.usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };
    VKF_CHECK(vkCreateImage(ctx.device(), &info, nullptr, &result.image));

    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(ctx.device(), result.image, &requirements);
    VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = findMemoryType(ctx, requirements.memoryTypeBits,
                                          VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };
    VKF_CHECK(vkAllocateMemory(ctx.device(), &allocate, nullptr, &result.memory));
    VKF_CHECK(vkBindImageMemory(ctx.device(), result.image, result.memory, 0));

    VkImageViewType viewType = VK_IMAGE_VIEW_TYPE_2D;
    if (desc.type == VK_IMAGE_TYPE_3D) {
        viewType = VK_IMAGE_VIEW_TYPE_3D;
    } else if (desc.type == VK_IMAGE_TYPE_1D) {
        viewType = desc.layers > 1 ? VK_IMAGE_VIEW_TYPE_1D_ARRAY : VK_IMAGE_VIEW_TYPE_1D;
    } else if (desc.layers > 1) {
        viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    }

    VkImageViewCreateInfo viewInfo{
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = result.image,
        .viewType = viewType,
        .format = desc.format,
        .subresourceRange = {desc.aspect, 0, desc.mipLevels, 0, desc.layers},
    };
    VKF_CHECK(vkCreateImageView(ctx.device(), &viewInfo, nullptr, &result.view));

    if (name != nullptr) {
        ctx.name(result.image, name);
        ctx.name(result.view, name);
        ctx.name(result.memory, name);
    }
    return result;
}

void upload(const Context& ctx, const Buffer& dst, const void* data, VkDeviceSize bytes,
            VkDeviceSize offset) {
    Buffer staging = createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                  MemoryUse::Upload, "upload staging");
    std::memcpy(staging.mapped, data, bytes);
    submitNow(ctx, [&](VkCommandBuffer cmd) {
        VkBufferCopy region{.srcOffset = 0, .dstOffset = offset, .size = bytes};
        memoryBarrier(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                      VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
        vkCmdCopyBuffer(cmd, staging.buffer, dst.buffer, 1, &region);
        memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                      VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT);
    });
}

void download(const Context& ctx, const Buffer& src, void* data, VkDeviceSize bytes,
              VkDeviceSize offset) {
    Buffer staging = createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                  MemoryUse::Readback, "download staging");
    submitNow(ctx, [&](VkCommandBuffer cmd) {
        VkBufferCopy region{.srcOffset = offset, .dstOffset = 0, .size = bytes};
        memoryBarrier(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, VK_ACCESS_2_MEMORY_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
        vkCmdCopyBuffer(cmd, src.buffer, staging.buffer, 1, &region);
        memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    });
    staging.invalidate();
    std::memcpy(data, staging.mapped, bytes);
}

uint32_t formatSize(VkFormat format) {
    switch (format) {
        case VK_FORMAT_R8_UNORM:
        case VK_FORMAT_R8_UINT:
        case VK_FORMAT_R8_SNORM: return 1;
        case VK_FORMAT_R8G8_UNORM:
        case VK_FORMAT_R16_SFLOAT:
        case VK_FORMAT_R16_UINT:
        case VK_FORMAT_R16_UNORM: return 2;
        case VK_FORMAT_R8G8B8A8_UNORM:
        case VK_FORMAT_R8G8B8A8_SRGB:
        case VK_FORMAT_R8G8B8A8_UINT:
        case VK_FORMAT_B8G8R8A8_UNORM:
        case VK_FORMAT_B8G8R8A8_SRGB:
        case VK_FORMAT_A2B10G10R10_UNORM_PACK32:
        case VK_FORMAT_B10G11R11_UFLOAT_PACK32:
        case VK_FORMAT_R16G16_SFLOAT:
        case VK_FORMAT_R32_SFLOAT:
        case VK_FORMAT_R32_UINT:
        case VK_FORMAT_R32_SINT:
        case VK_FORMAT_D32_SFLOAT: return 4;
        case VK_FORMAT_R16G16B16A16_SFLOAT:
        case VK_FORMAT_R16G16B16A16_UNORM:
        case VK_FORMAT_R32G32_SFLOAT:
        case VK_FORMAT_R32G32_UINT: return 8;
        case VK_FORMAT_R32G32B32A32_SFLOAT:
        case VK_FORMAT_R32G32B32A32_UINT: return 16;
        default:
            throw Error(VK_ERROR_FORMAT_NOT_SUPPORTED, "formatSize does not know this format");
    }
}

void uploadImage(const Context& ctx, const Image& dst, const void* pixels, VkDeviceSize bytes,
                 VkImageLayout finalLayout) {
    Buffer staging = createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                  MemoryUse::Upload, "image upload staging");
    std::memcpy(staging.mapped, pixels, bytes);
    submitNow(ctx, [&](VkCommandBuffer cmd) {
        const VkImageSubresourceRange all{dst.desc.aspect, 0, VK_REMAINING_MIP_LEVELS, 0,
                                          VK_REMAINING_ARRAY_LAYERS};
        imageBarrier(cmd, dst.image, VK_IMAGE_LAYOUT_UNDEFINED,
                     VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                     VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                     VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, all);
        VkBufferImageCopy region{
            .imageSubresource = {dst.desc.aspect, 0, 0, 1},
            .imageExtent = dst.extent(),
        };
        vkCmdCopyBufferToImage(cmd, staging.buffer, dst.image,
                               VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        imageBarrier(cmd, dst.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, finalLayout,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                     VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT, all);
    });
}

std::vector<uint8_t> downloadImage(const Context& ctx, const Image& src,
                                   VkImageLayout currentLayout) {
    if (currentLayout == VK_IMAGE_LAYOUT_UNDEFINED) {
        throw Error(
            VK_ERROR_UNKNOWN,
            "downloadImage needs the image's current layout; UNDEFINED has no contents");
    }
    const VkDeviceSize bytes = VkDeviceSize(src.desc.width) * src.desc.height *
                               src.desc.depth * formatSize(src.desc.format);
    Buffer staging = createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                  MemoryUse::Readback, "image download staging");
    submitNow(ctx, [&](VkCommandBuffer cmd) {
        const VkImageSubresourceRange first{src.desc.aspect, 0, 1, 0, 1};
        imageBarrier(cmd, src.image, currentLayout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                     VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, VK_ACCESS_2_MEMORY_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT, first);
        VkBufferImageCopy region{
            .imageSubresource = {src.desc.aspect, 0, 0, 1},
            .imageExtent = src.extent(),
        };
        vkCmdCopyImageToBuffer(cmd, src.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               staging.buffer, 1, &region);
        imageBarrier(cmd, src.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, currentLayout,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_NONE,
                     VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                     VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT, first);
        memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    });
    staging.invalidate();
    std::vector<uint8_t> pixels(bytes);
    std::memcpy(pixels.data(), staging.mapped, bytes);
    return pixels;
}

}  // namespace vkf
