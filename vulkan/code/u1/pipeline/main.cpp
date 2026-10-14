#include <chrono>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "basics.hpp"

namespace {

std::vector<char> readCache(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    return std::vector<char>((std::istreambuf_iterator<char>(file)),
                             std::istreambuf_iterator<char>());
}

// snippet:begin cache-header
bool cacheMatches(const std::vector<char>& data,
                  const VkPhysicalDeviceProperties& properties) {
    if (data.size() < sizeof(VkPipelineCacheHeaderVersionOne)) return false;
    VkPipelineCacheHeaderVersionOne header;
    std::memcpy(&header, data.data(), sizeof(header));
    return header.headerVersion == VK_PIPELINE_CACHE_HEADER_VERSION_ONE &&
           header.vendorID == properties.vendorID && header.deviceID == properties.deviceID &&
           std::memcmp(header.pipelineCacheUUID, properties.pipelineCacheUUID, VK_UUID_SIZE) ==
               0;
}
// snippet:end cache-header

}  // namespace

int main(int argc, char** argv) try {
    const std::string cachePath =
        argc > 2 && std::string(argv[1]) == "--cache" ? argv[2] : "u1_pipeline.cache";
    u1::Instance instance = u1::createInstance("u1_pipeline");
    u1::Device device = u1::createDevice(u1::pickPhysicalDevice(instance.instance));

    // snippet:begin module
    const std::vector<uint32_t> spirv =
        u1::readSpirv(std::string(VKF_SHADER_DIR) + "/fill.comp.spv");
    VkShaderModule module = u1::createShaderModule(device.device, spirv);
    // snippet:end module
    std::printf("fill.comp.spv: %zu words, magic number 0x%08x\n", spirv.size(), spirv[0]);

    // snippet:begin layouts
    const VkDescriptorSetLayoutBinding binding{
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
    };
    const VkDescriptorSetLayoutCreateInfo setInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding,
    };
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    U1_CHECK(vkCreateDescriptorSetLayout(device.device, &setInfo, nullptr, &setLayout));

    const VkPushConstantRange push{
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .offset = 0, .size = 8};
    const VkPipelineLayoutCreateInfo layoutInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &setLayout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push,
    };
    VkPipelineLayout layout = VK_NULL_HANDLE;
    U1_CHECK(vkCreatePipelineLayout(device.device, &layoutInfo, nullptr, &layout));
    // snippet:end layouts

    std::vector<char> initial = readCache(cachePath);
    const bool warm = cacheMatches(initial, device.properties);
    if (!warm) initial.clear();
    // snippet:begin cache
    const VkPipelineCacheCreateInfo cacheInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .initialDataSize = initial.size(),
        .pInitialData = initial.data(),
    };
    VkPipelineCache cache = VK_NULL_HANDLE;
    U1_CHECK(vkCreatePipelineCache(device.device, &cacheInfo, nullptr, &cache));
    // snippet:end cache
    std::printf("pipeline cache: %s (%zu bytes loaded from %s)\n", warm ? "warm" : "cold",
                initial.size(), cachePath.c_str());

    std::vector<VkPipeline> pipelines;
    for (uint32_t localSize : {64u, 128u, 256u}) {
        // snippet:begin pipeline
        const VkSpecializationMapEntry entry{
            .constantID = 0, .offset = 0, .size = sizeof(uint32_t)};
        const VkSpecializationInfo specialization{
            .mapEntryCount = 1,
            .pMapEntries = &entry,
            .dataSize = sizeof(localSize),
            .pData = &localSize,
        };
        const VkComputePipelineCreateInfo info{
            .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .stage =
                {
                    .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                    .module = module,
                    .pName = "main",
                    .pSpecializationInfo = &specialization,
                },
            .layout = layout,
        };
        VkPipeline pipeline = VK_NULL_HANDLE;
        const auto start = std::chrono::steady_clock::now();
        U1_CHECK(vkCreateComputePipelines(device.device, cache, 1, &info, nullptr, &pipeline));
        // snippet:end pipeline
        const double ms =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
                .count();
        std::printf("local size %3u: pipeline created in %.2f ms\n", localSize, ms);
        pipelines.push_back(pipeline);
    }

    // snippet:begin save-cache
    size_t size = 0;
    U1_CHECK(vkGetPipelineCacheData(device.device, cache, &size, nullptr));
    std::vector<char> data(size);
    U1_CHECK(vkGetPipelineCacheData(device.device, cache, &size, data.data()));
    std::ofstream(cachePath, std::ios::binary)
        .write(data.data(), static_cast<std::streamsize>(size));
    // snippet:end save-cache
    std::printf("saved %zu bytes of pipeline cache to %s\n", size, cachePath.c_str());

    for (VkPipeline pipeline : pipelines) vkDestroyPipeline(device.device, pipeline, nullptr);
    vkDestroyPipelineCache(device.device, cache, nullptr);
    vkDestroyPipelineLayout(device.device, layout, nullptr);
    vkDestroyDescriptorSetLayout(device.device, setLayout, nullptr);
    vkDestroyShaderModule(device.device, module, nullptr);
    vkDestroyDevice(device.device, nullptr);
    u1::destroyInstance(instance);
    return u1::finish(true);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
