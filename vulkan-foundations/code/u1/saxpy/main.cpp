#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "basics.hpp"

namespace {

// snippet:begin push
struct Push {
    float a;
    uint32_t n;
};
// snippet:end push

}  // namespace

int main(int argc, char** argv) try {
    const uint32_t n = argc > 2 && std::string(argv[1]) == "--n"
                           ? static_cast<uint32_t>(std::stoul(argv[2]))
                           : 1u << 20;
    const int repeats = 10;
    const float a = 0.5f;

    u1::Instance instance = u1::createInstance("u1_saxpy");
    u1::Device device = u1::createDevice(u1::pickPhysicalDevice(instance.instance));
    std::printf("%s, n = %u\n", device.properties.deviceName, n);

    // snippet:begin buffers
    const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(float);
    const VkMemoryPropertyFlags hostMemory =
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    u1::Buffer x =
        u1::createBuffer(device, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, hostMemory);
    u1::Buffer y =
        u1::createBuffer(device, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, hostMemory);
    auto* xs = static_cast<float*>(x.mapped);
    auto* ys = static_cast<float*>(y.mapped);
    for (uint32_t i = 0; i < n; ++i) {
        xs[i] = float(i % 1000) * 0.25f;
        ys[i] = 1.0f;
    }
    // snippet:end buffers

    // snippet:begin set-layout
    const VkDescriptorSetLayoutBinding bindings[] = {
        {.binding = 0,
         .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
         .descriptorCount = 1,
         .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT},
        {.binding = 1,
         .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
         .descriptorCount = 1,
         .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT},
    };
    const VkDescriptorSetLayoutCreateInfo setLayoutInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 2,
        .pBindings = bindings,
    };
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    U1_CHECK(vkCreateDescriptorSetLayout(device.device, &setLayoutInfo, nullptr, &setLayout));
    // snippet:end set-layout

    // snippet:begin pool-and-set
    const VkDescriptorPoolSize poolSize{.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                        .descriptorCount = 2};
    const VkDescriptorPoolCreateInfo poolInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &poolSize,
    };
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    U1_CHECK(vkCreateDescriptorPool(device.device, &poolInfo, nullptr, &descriptorPool));

    const VkDescriptorSetAllocateInfo allocateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &setLayout,
    };
    VkDescriptorSet set = VK_NULL_HANDLE;
    U1_CHECK(vkAllocateDescriptorSets(device.device, &allocateInfo, &set));
    // snippet:end pool-and-set

    // snippet:begin write-set
    const VkDescriptorBufferInfo xInfo{
        .buffer = x.buffer, .offset = 0, .range = VK_WHOLE_SIZE};
    const VkDescriptorBufferInfo yInfo{
        .buffer = y.buffer, .offset = 0, .range = VK_WHOLE_SIZE};
    const VkWriteDescriptorSet writes[] = {
        {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
         .dstSet = set,
         .dstBinding = 0,
         .descriptorCount = 1,
         .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
         .pBufferInfo = &xInfo},
        {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
         .dstSet = set,
         .dstBinding = 1,
         .descriptorCount = 1,
         .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
         .pBufferInfo = &yInfo},
    };
    vkUpdateDescriptorSets(device.device, 2, writes, 0, nullptr);
    // snippet:end write-set

    // snippet:begin pipeline
    const VkPushConstantRange range{
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .offset = 0, .size = sizeof(Push)};
    const VkPipelineLayoutCreateInfo layoutInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &setLayout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &range,
    };
    VkPipelineLayout layout = VK_NULL_HANDLE;
    U1_CHECK(vkCreatePipelineLayout(device.device, &layoutInfo, nullptr, &layout));
    VkShaderModule module = u1::createShaderModule(
        device.device, u1::readSpirv(std::string(VKF_SHADER_DIR) + "/saxpy.comp.spv"));
    const VkComputePipelineCreateInfo pipelineInfo{
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                  .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                  .module = module,
                  .pName = "main"},
        .layout = layout,
    };
    VkPipeline pipeline = VK_NULL_HANDLE;
    U1_CHECK(vkCreateComputePipelines(device.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr,
                                      &pipeline));
    // snippet:end pipeline

    const VkCommandPoolCreateInfo commandPoolInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = device.queueFamily,
    };
    VkCommandPool commandPool = VK_NULL_HANDLE;
    U1_CHECK(vkCreateCommandPool(device.device, &commandPoolInfo, nullptr, &commandPool));
    const VkCommandBufferAllocateInfo cmdInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = commandPool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    U1_CHECK(vkAllocateCommandBuffers(device.device, &cmdInfo, &cmd));

    // snippet:begin record
    const VkCommandBufferBeginInfo begin{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    U1_CHECK(vkBeginCommandBuffer(cmd, &begin));
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                            nullptr);
    const Push push{a, n};
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    const uint32_t groups = (n + 255) / 256;
    for (int r = 0; r < repeats; ++r) {
        if (r > 0) {
            const VkMemoryBarrier2 between{
                .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                .dstAccessMask =
                    VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            };
            const VkDependencyInfo dependency{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                                              .memoryBarrierCount = 1,
                                              .pMemoryBarriers = &between};
            vkCmdPipelineBarrier2(cmd, &dependency);
        }
        vkCmdDispatch(cmd, groups, 1, 1);
    }
    const VkMemoryBarrier2 toHost{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
        .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT,
    };
    const VkDependencyInfo toHostDependency{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                                            .memoryBarrierCount = 1,
                                            .pMemoryBarriers = &toHost};
    vkCmdPipelineBarrier2(cmd, &toHostDependency);
    U1_CHECK(vkEndCommandBuffer(cmd));
    u1::submitAndWait(device, cmd);
    // snippet:end record

    // snippet:begin verify
    double worst = 0;
    for (uint32_t i = 0; i < n; ++i) {
        const double expected = 1.0 + repeats * double(a) * double(xs[i]);
        worst = std::max(worst, std::fabs(double(ys[i]) - expected) / expected);
    }
    const bool passed = worst < 1e-5;
    std::printf("y = a*x + y, %d times: largest relative error %.2e (%s)\n", repeats, worst,
                passed ? "pass" : "FAIL");
    // snippet:end verify

    vkDestroyCommandPool(device.device, commandPool, nullptr);
    vkDestroyPipeline(device.device, pipeline, nullptr);
    vkDestroyShaderModule(device.device, module, nullptr);
    vkDestroyPipelineLayout(device.device, layout, nullptr);
    vkDestroyDescriptorPool(device.device, descriptorPool, nullptr);
    vkDestroyDescriptorSetLayout(device.device, setLayout, nullptr);
    u1::destroyBuffer(device, x);
    u1::destroyBuffer(device, y);
    vkDestroyDevice(device.device, nullptr);
    u1::destroyInstance(instance);
    return u1::finish(passed);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
