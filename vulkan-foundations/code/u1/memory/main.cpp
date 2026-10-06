#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <vector>

#include "basics.hpp"

namespace {

std::string memoryFlags(VkMemoryPropertyFlags f) {
    std::string s;
    if (f & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) s += " DEVICE_LOCAL";
    if (f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) s += " HOST_VISIBLE";
    if (f & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) s += " HOST_COHERENT";
    if (f & VK_MEMORY_PROPERTY_HOST_CACHED_BIT) s += " HOST_CACHED";
    if (f & VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT) s += " LAZILY_ALLOCATED";
    return s.empty() ? " (none)" : s;
}

// snippet:begin print-memory
void printMemory(const VkPhysicalDeviceMemoryProperties& memory) {
    for (uint32_t i = 0; i < memory.memoryHeapCount; ++i) {
        const VkMemoryHeap& heap = memory.memoryHeaps[i];
        std::printf("heap %u: %.1f GiB%s\n", i, double(heap.size) / (1u << 30),
                    (heap.flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) ? " device-local" : "");
    }
    for (uint32_t i = 0; i < memory.memoryTypeCount; ++i) {
        const VkMemoryType& type = memory.memoryTypes[i];
        std::printf("type %u: heap %u,%s\n", i, type.heapIndex,
                    memoryFlags(type.propertyFlags).c_str());
    }
}
// snippet:end print-memory

// snippet:begin linear-allocator
class LinearAllocator {
public:
    LinearAllocator(VkDevice device, VkDeviceSize capacity, uint32_t memoryType)
        : device_(device), capacity_(capacity), type_(memoryType) {
        const VkMemoryAllocateInfo info{
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = capacity,
            .memoryTypeIndex = memoryType,
        };
        U1_CHECK(vkAllocateMemory(device, &info, nullptr, &memory_));
    }
    ~LinearAllocator() { vkFreeMemory(device_, memory_, nullptr); }
    LinearAllocator(const LinearAllocator&) = delete;
    LinearAllocator& operator=(const LinearAllocator&) = delete;

    VkDeviceSize bind(VkBuffer buffer) {
        VkMemoryRequirements r;
        vkGetBufferMemoryRequirements(device_, buffer, &r);
        if ((r.memoryTypeBits & (1u << type_)) == 0) {
            throw std::runtime_error("buffer cannot use this memory type");
        }
        const VkDeviceSize offset = (next_ + r.alignment - 1) / r.alignment * r.alignment;
        if (offset + r.size > capacity_) throw std::runtime_error("the block is full");
        U1_CHECK(vkBindBufferMemory(device_, buffer, memory_, offset));
        next_ = offset + r.size;
        return offset;
    }
    VkDeviceSize used() const { return next_; }

private:
    VkDevice device_;
    VkDeviceMemory memory_ = VK_NULL_HANDLE;
    VkDeviceSize capacity_;
    VkDeviceSize next_ = 0;
    uint32_t type_;
};
// snippet:end linear-allocator

// snippet:begin flush
bool flushHostWrites(const u1::Device& device, const u1::Buffer& buffer) {
    const VkMemoryType& type = device.memory.memoryTypes[buffer.memoryType];
    if (type.propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) return false;
    const VkMappedMemoryRange range{
        .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = buffer.memory,
        .offset = 0,
        .size = VK_WHOLE_SIZE,
    };
    U1_CHECK(vkFlushMappedMemoryRanges(device.device, 1, &range));
    return true;
}
// snippet:end flush

bool roundTrip(const u1::Device& device) {
    // snippet:begin mapped
    const VkDeviceSize bytes = 4 << 20;
    u1::Buffer buffer = u1::createBuffer(device, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
    auto* words = static_cast<uint32_t*>(buffer.mapped);
    for (uint32_t i = 0; i < bytes / 4; ++i) words[i] = i * 2654435761u;
    const bool flushed = flushHostWrites(device, buffer);
    // snippet:end mapped
    bool ok = true;
    for (uint32_t i = 0; i < bytes / 4; ++i) ok = ok && words[i] == i * 2654435761u;
    std::printf("mapped %llu bytes in memory type %u (%s): %s\n",
                static_cast<unsigned long long>(bytes), buffer.memoryType,
                flushed ? "flushed" : "coherent, no flush", ok ? "ok" : "MISMATCH");
    u1::destroyBuffer(device, buffer);
    return ok;
}

bool subAllocate(const u1::Device& device) {
    const VkDeviceSize capacity = 64 << 20;
    VkBuffer probe = VK_NULL_HANDLE;
    const VkBufferCreateInfo probeInfo{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = 256,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    U1_CHECK(vkCreateBuffer(device.device, &probeInfo, nullptr, &probe));
    VkMemoryRequirements r;
    vkGetBufferMemoryRequirements(device.device, probe, &r);
    vkDestroyBuffer(device.device, probe, nullptr);
    const uint32_t type = u1::findMemoryType(device.memory, r.memoryTypeBits,
                                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    LinearAllocator block(device.device, capacity, type);
    std::mt19937 random(7);
    std::uniform_int_distribution<int> size(256, 64 << 10);
    std::vector<VkBuffer> buffers;
    std::vector<std::pair<VkDeviceSize, VkDeviceSize>> ranges;
    VkDeviceSize requested = 0;
    for (int i = 0; i < 1000; ++i) {
        VkBufferCreateInfo info = probeInfo;
        info.size = static_cast<VkDeviceSize>(size(random));
        VkBuffer buffer = VK_NULL_HANDLE;
        U1_CHECK(vkCreateBuffer(device.device, &info, nullptr, &buffer));
        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(device.device, buffer, &req);
        const VkDeviceSize offset = block.bind(buffer);
        if (offset % req.alignment != 0) throw std::runtime_error("misaligned placement");
        ranges.emplace_back(offset, offset + req.size);
        buffers.push_back(buffer);
        requested += info.size;
    }
    bool ok = true;
    for (size_t i = 1; i < ranges.size(); ++i) {
        ok = ok && ranges[i].first >= ranges[i - 1].second;
    }
    std::printf("1000 buffers, %.1f MiB requested, in one allocation: %.1f MiB used, %s\n",
                double(requested) / (1 << 20), double(block.used()) / (1 << 20),
                ok ? "no overlaps" : "OVERLAP");
    for (VkBuffer buffer : buffers) vkDestroyBuffer(device.device, buffer, nullptr);
    return ok;
}

void imageRequirements(const u1::Device& device) {
    // snippet:begin image
    const VkImageCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .extent = {1024, 1024, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };
    VkImage image = VK_NULL_HANDLE;
    U1_CHECK(vkCreateImage(device.device, &info, nullptr, &image));
    VkMemoryRequirements r;
    vkGetImageMemoryRequirements(device.device, image, &r);
    // snippet:end image
    std::printf("optimal 1024 x 1024 RGBA8 image: %llu bytes, alignment %llu (pixels: %u)\n",
                static_cast<unsigned long long>(r.size),
                static_cast<unsigned long long>(r.alignment), 1024u * 1024u * 4u);
    vkDestroyImage(device.device, image, nullptr);

    // snippet:begin format-support
    for (VkFormat format : {VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R8G8B8A8_SRGB,
                            VK_FORMAT_R32_SFLOAT, VK_FORMAT_R16G16B16A16_SFLOAT}) {
        VkFormatProperties properties;
        vkGetPhysicalDeviceFormatProperties(device.physical, format, &properties);
        const VkFormatFeatureFlags f = properties.optimalTilingFeatures;
        std::printf("%-30s storage %-3s sampled %-3s colour attachment %s\n",
                    string_VkFormat(format),
                    (f & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT) ? "yes" : "no",
                    (f & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) ? "yes" : "no",
                    (f & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT) ? "yes" : "no");
    }
    // snippet:end format-support
}

}  // namespace

int main() try {
    u1::Instance instance = u1::createInstance("u1_memory");
    u1::Device device = u1::createDevice(u1::pickPhysicalDevice(instance.instance));
    std::printf("%s\n", device.properties.deviceName);
    printMemory(device.memory);
    const bool ok = roundTrip(device) && subAllocate(device);
    imageRequirements(device);
    vkDestroyDevice(device.device, nullptr);
    u1::destroyInstance(instance);
    return u1::finish(ok);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
