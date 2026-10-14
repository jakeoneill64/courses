#pragma once

#include <vkf/vkf.hpp>

#include <cstdint>
#include <initializer_list>
#include <span>
#include <vector>

#include "mesh.hpp"

namespace u4 {

VkFormat chooseDepthFormat(const vkf::Context& ctx);

enum class Blend { Opaque, Additive, Alpha };

struct GraphicsPipelineDesc {
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkShaderModule vertexShader = VK_NULL_HANDLE;
    VkShaderModule fragmentShader = VK_NULL_HANDLE;
    const VkSpecializationInfo* specialization = nullptr;
    std::span<const VkVertexInputBindingDescription> vertexBindings;
    std::span<const VkVertexInputAttributeDescription> vertexAttributes;
    VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkCullModeFlags cullMode = VK_CULL_MODE_BACK_BIT;
    VkFormat colorFormat = VK_FORMAT_UNDEFINED;
    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    bool depthWrite = true;
    VkCompareOp depthCompare = VK_COMPARE_OP_LESS;
    Blend blend = Blend::Opaque;
    // Only for the render-pass style of older code; otherwise dynamic rendering is used.
    VkRenderPass renderPass = VK_NULL_HANDLE;
    VkPipelineCache cache = VK_NULL_HANDLE;
    const char* name = nullptr;
};

// One colour attachment, an optional depth attachment, and a dynamic viewport and scissor.
vkf::Unique<VkPipeline> createGraphicsPipeline(const vkf::Context& ctx,
                                               const GraphicsPipelineDesc& desc);

void setViewportAndScissor(VkCommandBuffer cmd, VkExtent2D extent);

// Locations 0, 1 and 2 are position, normal and uv; list only those the shader reads.
struct MeshInput {
    VkVertexInputBindingDescription binding;
    std::vector<VkVertexInputAttributeDescription> attributes;
};
MeshInput meshInput(std::initializer_list<uint32_t> locations);

struct GpuMesh {
    vkf::Buffer vertices;
    vkf::Buffer indices;
    uint32_t indexCount = 0;
};
GpuMesh uploadMesh(const vkf::Context& ctx, const Mesh& mesh, const char* name);
void bindMesh(VkCommandBuffer cmd, const GpuMesh& mesh);

}  // namespace u4
