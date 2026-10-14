#include <cstdio>
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include "basics.hpp"

namespace {

PFN_vkSetDebugUtilsObjectNameEXT setObjectName = nullptr;

// snippet:begin name
void name(VkDevice device, VkObjectType type, uint64_t handle, const char* label) {
    if (setObjectName == nullptr) return;
    const VkDebugUtilsObjectNameInfoEXT info{
        .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        .objectType = type,
        .objectHandle = handle,
        .pObjectName = label,
    };
    setObjectName(device, &info);
}
// snippet:end name

}  // namespace

int main(int argc, char** argv) try {
    const std::string bug = argc > 2 && std::string(argv[1]) == "--bug" ? argv[2] : "none";
    const std::vector<std::string> bugs = {"none", "usage",   "descriptor-type", "push-range",
                                           "leak", "barrier", "unbound"};
    if (std::find(bugs.begin(), bugs.end(), bug) == bugs.end()) {
        std::fprintf(stderr, "unknown --bug %s\n", bug.c_str());
        return 2;
    }
    std::printf("bug: %s\n", bug.c_str());

    u1::Instance instance = u1::createInstance("u1_broken");
    u1::Device device = u1::createDevice(u1::pickPhysicalDevice(instance.instance));
    if (instance.validation) {
        setObjectName = reinterpret_cast<PFN_vkSetDebugUtilsObjectNameEXT>(
            vkGetInstanceProcAddr(instance.instance, "vkSetDebugUtilsObjectNameEXT"));
    }

    const uint32_t n = 1 << 16;
    // snippet:begin usage-bug
    const VkBufferUsageFlags usage =
        bug == "usage" ? VK_BUFFER_USAGE_TRANSFER_DST_BIT : VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    // snippet:end usage-bug
    u1::Buffer values = u1::createBuffer(
        device, n * sizeof(float), usage,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    name(device.device, VK_OBJECT_TYPE_BUFFER, reinterpret_cast<uint64_t>(values.buffer),
         "values");
    auto* data = static_cast<float*>(values.mapped);
    for (uint32_t i = 0; i < n; ++i) data[i] = float(i);

    const VkDescriptorSetLayoutBinding binding{
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
    const VkDescriptorSetLayoutCreateInfo setLayoutInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding};
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    U1_CHECK(vkCreateDescriptorSetLayout(device.device, &setLayoutInfo, nullptr, &setLayout));
    const VkDescriptorPoolSize poolSizes[] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1},
                                              {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}};
    const VkDescriptorPoolCreateInfo poolInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 2,
        .pPoolSizes = poolSizes};
    VkDescriptorPool pool = VK_NULL_HANDLE;
    U1_CHECK(vkCreateDescriptorPool(device.device, &poolInfo, nullptr, &pool));
    const VkDescriptorSetAllocateInfo allocateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &setLayout};
    VkDescriptorSet set = VK_NULL_HANDLE;
    U1_CHECK(vkAllocateDescriptorSets(device.device, &allocateInfo, &set));
    // snippet:begin descriptor-bug
    const VkDescriptorBufferInfo bufferInfo{
        .buffer = values.buffer, .offset = 0, .range = VK_WHOLE_SIZE};
    const VkWriteDescriptorSet write{
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = bug == "descriptor-type" ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
                                                   : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .pBufferInfo = &bufferInfo,
    };
    vkUpdateDescriptorSets(device.device, 1, &write, 0, nullptr);
    // snippet:end descriptor-bug

    const VkPushConstantRange range{
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .offset = 0, .size = sizeof(uint32_t)};
    const VkPipelineLayoutCreateInfo layoutInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &setLayout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &range};
    VkPipelineLayout layout = VK_NULL_HANDLE;
    U1_CHECK(vkCreatePipelineLayout(device.device, &layoutInfo, nullptr, &layout));
    VkShaderModule module = u1::createShaderModule(
        device.device, u1::readSpirv(std::string(VKF_SHADER_DIR) + "/twice.comp.spv"));
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
    name(device.device, VK_OBJECT_TYPE_PIPELINE, reinterpret_cast<uint64_t>(pipeline),
         "double the values");

    const VkCommandPoolCreateInfo commandPoolInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = device.queueFamily};
    VkCommandPool commandPool = VK_NULL_HANDLE;
    U1_CHECK(vkCreateCommandPool(device.device, &commandPoolInfo, nullptr, &commandPool));
    const VkCommandBufferAllocateInfo cmdInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = commandPool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1};
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    U1_CHECK(vkAllocateCommandBuffers(device.device, &cmdInfo, &cmd));

    const VkCommandBufferBeginInfo begin{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                         .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
    U1_CHECK(vkBeginCommandBuffer(cmd, &begin));
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    if (bug != "unbound") {
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                nullptr);
    }
    // snippet:begin push-bug
    const uint32_t constants[2] = {n, 0};
    const uint32_t pushBytes = bug == "push-range" ? sizeof(constants) : sizeof(uint32_t);
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, pushBytes, constants);
    // snippet:end push-bug
    vkCmdDispatch(cmd, (n + 255) / 256, 1, 1);
    // snippet:begin barrier-bug
    if (bug != "barrier") {
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
    vkCmdDispatch(cmd, (n + 255) / 256, 1, 1);
    // snippet:end barrier-bug
    const VkMemoryBarrier2 toHost{.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                                  .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                  .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                                  .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
                                  .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT};
    const VkDependencyInfo hostDependency{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                                          .memoryBarrierCount = 1,
                                          .pMemoryBarriers = &toHost};
    vkCmdPipelineBarrier2(cmd, &hostDependency);
    U1_CHECK(vkEndCommandBuffer(cmd));
    u1::submitAndWait(device, cmd);

    bool correct = true;
    for (uint32_t i = 0; i < n; ++i) correct = correct && data[i] == float(i) * 4.0f;
    std::printf("values multiplied by four: %s\n", correct ? "yes" : "no");

    vkDestroyCommandPool(device.device, commandPool, nullptr);
    vkDestroyPipeline(device.device, pipeline, nullptr);
    vkDestroyShaderModule(device.device, module, nullptr);
    vkDestroyPipelineLayout(device.device, layout, nullptr);
    vkDestroyDescriptorPool(device.device, pool, nullptr);
    vkDestroyDescriptorSetLayout(device.device, setLayout, nullptr);
    // snippet:begin leak-bug
    if (bug != "leak") u1::destroyBuffer(device, values);
    vkDestroyDevice(device.device, nullptr);
    // snippet:end leak-bug
    u1::destroyInstance(instance);
    return u1::finish(correct);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
