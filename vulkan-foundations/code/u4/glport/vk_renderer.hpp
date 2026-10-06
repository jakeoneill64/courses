#pragma once

#include <vkf/vkf.hpp>

#include <cstdint>
#include <span>
#include <vector>

#include "graphics.hpp"
#include "mesh.hpp"
#include "scene.hpp"

namespace glport {

class VkRenderer {
public:
    VkRenderer(const vkf::Context& ctx, uint32_t width, uint32_t height, const u4::Mesh& mesh);

    FrameTiming renderFrame(std::span<const DrawData> draws);
    std::vector<uint8_t> readPixels();

private:
    void beginRendering();

    const vkf::Context* ctx_;
    VkExtent2D extent_;
    vkf::Buffer vertices_, indices_;
    uint32_t indexCount_ = 0;
    vkf::Unique<VkPipelineLayout> layout_;
    vkf::Unique<VkPipeline> pipeline_;
    vkf::Image color_, depth_;
    vkf::Buffer readback_;
    vkf::Unique<VkCommandPool> pool_;
    VkCommandBuffer cmd_ = VK_NULL_HANDLE;
    vkf::Unique<VkFence> fence_;
};

}  // namespace glport
