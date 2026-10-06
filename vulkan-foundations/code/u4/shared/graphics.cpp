#include "graphics.hpp"

#include <cstddef>

namespace u4 {

// snippet:begin depth-format
VkFormat chooseDepthFormat(const vkf::Context& ctx) {
    const VkFormat candidates[] = {VK_FORMAT_D32_SFLOAT, VK_FORMAT_X8_D24_UNORM_PACK32,
                                   VK_FORMAT_D16_UNORM};
    for (VkFormat format : candidates) {
        VkFormatProperties properties;
        vkGetPhysicalDeviceFormatProperties(ctx.physicalDevice(), format, &properties);
        if (properties.optimalTilingFeatures &
            VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            return format;
        }
    }
    throw vkf::Error(VK_ERROR_FORMAT_NOT_SUPPORTED, "no depth format is renderable");
}
// snippet:end depth-format

vkf::Unique<VkPipeline> createGraphicsPipeline(const vkf::Context& ctx,
                                               const GraphicsPipelineDesc& desc) {
    // snippet:begin stages
    const VkPipelineShaderStageCreateInfo stages[] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT,
         .module = desc.vertexShader,
         .pName = "main",
         .pSpecializationInfo = desc.specialization},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
         .module = desc.fragmentShader,
         .pName = "main",
         .pSpecializationInfo = desc.specialization},
    };
    // snippet:end stages

    // snippet:begin vertex-input
    const VkPipelineVertexInputStateCreateInfo vertexInput{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = static_cast<uint32_t>(desc.vertexBindings.size()),
        .pVertexBindingDescriptions = desc.vertexBindings.data(),
        .vertexAttributeDescriptionCount = static_cast<uint32_t>(desc.vertexAttributes.size()),
        .pVertexAttributeDescriptions = desc.vertexAttributes.data(),
    };
    const VkPipelineInputAssemblyStateCreateInfo inputAssembly{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = desc.topology,
    };
    // snippet:end vertex-input

    // snippet:begin rasterisation
    const VkPipelineViewportStateCreateInfo viewport{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    const VkPipelineRasterizationStateCreateInfo rasterization{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .cullMode = desc.cullMode,
        .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0f,
    };
    const VkPipelineMultisampleStateCreateInfo multisample{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    // snippet:end rasterisation

    // snippet:begin depth-state
    const bool depth = desc.depthFormat != VK_FORMAT_UNDEFINED;
    const VkPipelineDepthStencilStateCreateInfo depthStencil{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = depth,
        .depthWriteEnable = depth && desc.depthWrite,
        .depthCompareOp = desc.depthCompare,
    };
    // snippet:end depth-state

    // snippet:begin blend
    VkPipelineColorBlendAttachmentState attachment{
        .blendEnable = desc.blend != Blend::Opaque,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    if (desc.blend == Blend::Additive) {
        attachment.srcColorBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    } else if (desc.blend == Blend::Alpha) {
        attachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        attachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    }
    const VkPipelineColorBlendStateCreateInfo blend{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &attachment,
    };
    // snippet:end blend

    // snippet:begin dynamic-state
    const VkDynamicState dynamicStates[] = {VK_DYNAMIC_STATE_VIEWPORT,
                                            VK_DYNAMIC_STATE_SCISSOR};
    const VkPipelineDynamicStateCreateInfo dynamic{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2,
        .pDynamicStates = dynamicStates,
    };
    // snippet:end dynamic-state

    // snippet:begin create-pipeline
    const VkPipelineRenderingCreateInfo rendering{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &desc.colorFormat,
        .depthAttachmentFormat = desc.depthFormat,
    };
    const VkGraphicsPipelineCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = desc.renderPass == VK_NULL_HANDLE ? &rendering : nullptr,
        .stageCount = 2,
        .pStages = stages,
        .pVertexInputState = &vertexInput,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewport,
        .pRasterizationState = &rasterization,
        .pMultisampleState = &multisample,
        .pDepthStencilState = &depthStencil,
        .pColorBlendState = &blend,
        .pDynamicState = &dynamic,
        .layout = desc.layout,
        .renderPass = desc.renderPass,
    };
    VkPipeline pipeline = VK_NULL_HANDLE;
    VKF_CHECK(
        vkCreateGraphicsPipelines(ctx.device(), desc.cache, 1, &info, nullptr, &pipeline));
    // snippet:end create-pipeline
    if (desc.name != nullptr) ctx.name(pipeline, desc.name);
    return {ctx.device(), pipeline};
}

void setViewportAndScissor(VkCommandBuffer cmd, VkExtent2D extent) {
    const VkViewport viewport{
        .width = static_cast<float>(extent.width),
        .height = static_cast<float>(extent.height),
        .maxDepth = 1.0f,
    };
    const VkRect2D scissor{.extent = extent};
    vkCmdSetViewport(cmd, 0, 1, &viewport);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
}

MeshInput meshInput(std::initializer_list<uint32_t> locations) {
    MeshInput input{.binding = {0, sizeof(MeshVertex), VK_VERTEX_INPUT_RATE_VERTEX}};
    const VkVertexInputAttributeDescription all[] = {
        {0, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(MeshVertex, position)},
        {1, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(MeshVertex, normal)},
        {2, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(MeshVertex, u)},
    };
    for (uint32_t location : locations) input.attributes.push_back(all[location]);
    return input;
}

GpuMesh uploadMesh(const vkf::Context& ctx, const Mesh& mesh, const char* name) {
    GpuMesh gpu;
    const VkDeviceSize vertexBytes = mesh.vertices.size() * sizeof(MeshVertex);
    const VkDeviceSize indexBytes = mesh.indices.size() * sizeof(uint16_t);
    gpu.vertices = vkf::createBuffer(
        ctx, vertexBytes, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, name);
    gpu.indices = vkf::createBuffer(
        ctx, indexBytes, VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, name);
    vkf::upload(ctx, gpu.vertices, mesh.vertices.data(), vertexBytes);
    vkf::upload(ctx, gpu.indices, mesh.indices.data(), indexBytes);
    gpu.indexCount = static_cast<uint32_t>(mesh.indices.size());
    return gpu;
}

void bindMesh(VkCommandBuffer cmd, const GpuMesh& mesh) {
    const VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &mesh.vertices.buffer, &offset);
    vkCmdBindIndexBuffer(cmd, mesh.indices, 0, VK_INDEX_TYPE_UINT16);
}

}  // namespace u4
