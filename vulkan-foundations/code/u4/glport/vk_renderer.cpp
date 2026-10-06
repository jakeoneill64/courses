#include "vk_renderer.hpp"

#include <algorithm>

namespace glport {

constexpr VkFormat ColorFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkClearColorValue Background{.float32 = {0.10f, 0.10f, 0.15f, 1.0f}};

VkRenderer::VkRenderer(const vkf::Context& ctx, uint32_t width, uint32_t height,
                       const u4::Mesh& mesh)
    : ctx_(&ctx), extent_{width, height} {
    // snippet:begin buffers
    const VkDeviceSize vertexBytes = mesh.vertices.size() * sizeof(u4::MeshVertex);
    const VkDeviceSize indexBytes = mesh.indices.size() * sizeof(uint16_t);
    vertices_ = vkf::createBuffer(
        ctx, vertexBytes, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, "cube vertices");
    indices_ = vkf::createBuffer(
        ctx, indexBytes, VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, "cube indices");
    vkf::upload(ctx, vertices_, mesh.vertices.data(), vertexBytes);
    vkf::upload(ctx, indices_, mesh.indices.data(), indexBytes);
    indexCount_ = static_cast<uint32_t>(mesh.indices.size());
    // snippet:end buffers

    // snippet:begin pipeline
    const VkPushConstantRange push{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(DrawData)};
    layout_ = vkf::createPipelineLayout(ctx, {}, {push});
    const auto vertexShader = vkf::loadShader(ctx, vkf::shaderPath("scene.vert"));
    const auto fragmentShader = vkf::loadShader(ctx, vkf::shaderPath("scene.frag"));
    const u4::MeshInput input = u4::meshInput({0, 1});
    const VkFormat depthFormat = u4::chooseDepthFormat(ctx);
    pipeline_ =
        u4::createGraphicsPipeline(ctx, {.layout = layout_,
                                         .vertexShader = vertexShader,
                                         .fragmentShader = fragmentShader,
                                         .vertexBindings = std::span(&input.binding, 1),
                                         .vertexAttributes = input.attributes,
                                         .colorFormat = ColorFormat,
                                         .depthFormat = depthFormat,
                                         .name = "scene"});
    // snippet:end pipeline

    // snippet:begin targets
    color_ = vkf::createImage(
        ctx,
        {.format = ColorFormat,
         .width = width,
         .height = height,
         .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
        "colour");
    depth_ = vkf::createImage(ctx,
                              {.format = depthFormat,
                               .width = width,
                               .height = height,
                               .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                               .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                              "depth");
    pool_ = vkf::createCommandPool(ctx, ctx.mainQueue().family, 0);
    cmd_ = vkf::allocateCommandBuffer(ctx, pool_);
    fence_ = vkf::createFence(ctx);
    // snippet:end targets
    readback_ = vkf::createBuffer(ctx, VkDeviceSize(width) * height * 4,
                                  VK_BUFFER_USAGE_TRANSFER_DST_BIT, vkf::MemoryUse::Readback,
                                  "readback");
}

void VkRenderer::beginRendering() {
    // snippet:begin attachment-barriers
    vkf::imageBarrier(
        cmd_, color_, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_2_COPY_BIT,
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    vkf::imageBarrier(cmd_, depth_, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
                          VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                          VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1});
    // snippet:end attachment-barriers
    // snippet:begin begin-rendering
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = color_.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Background},
    };
    const VkRenderingAttachmentInfo depth{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = depth_.view,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, extent_},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
        .pDepthAttachment = &depth,
    };
    vkCmdBeginRendering(cmd_, &rendering);
    // snippet:end begin-rendering
}

FrameTiming VkRenderer::renderFrame(std::span<const DrawData> draws) {
    FrameTiming timing;
    const vkf::CpuTimer timer;
    // snippet:begin frame
    VKF_CHECK(vkResetCommandPool(ctx_->device(), pool_, 0));
    vkf::beginCommands(cmd_);
    beginRendering();
    u4::setViewportAndScissor(cmd_, extent_);
    // snippet:begin per-draw
    vkCmdBindPipeline(cmd_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_);
    const VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd_, 0, 1, &vertices_.buffer, &offset);
    vkCmdBindIndexBuffer(cmd_, indices_, 0, VK_INDEX_TYPE_UINT16);
    for (const DrawData& draw : draws) {
        vkCmdPushConstants(cmd_, layout_, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(draw), &draw);
        vkCmdDrawIndexed(cmd_, indexCount_, 1, 0, 0, 0);
    }
    // snippet:end per-draw
    vkCmdEndRendering(cmd_);
    vkf::endCommands(cmd_);
    // snippet:end frame
    timing.issueMs = timer.elapsedMs();

    // snippet:begin sync
    vkf::submit(ctx_->mainQueue(), std::span(&cmd_, 1), {}, {}, fence_);
    timing.submitMs = timer.elapsedMs() - timing.issueMs;
    vkf::waitFence(*ctx_, fence_);
    VKF_CHECK(vkResetFences(ctx_->device(), 1, fence_.ptr()));
    // snippet:end sync
    timing.totalMs = timer.elapsedMs();
    return timing;
}

std::vector<uint8_t> VkRenderer::readPixels() {
    // snippet:begin readback
    vkf::submitNow(*ctx_, [&](VkCommandBuffer cmd) {
        vkf::imageBarrier(cmd, color_, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                          VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                          VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                          VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                          VK_ACCESS_2_TRANSFER_READ_BIT);
        const VkBufferImageCopy region{
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {extent_.width, extent_.height, 1},
        };
        vkCmdCopyImageToBuffer(cmd, color_, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback_, 1,
                               &region);
        vkf::bufferBarrier(cmd, readback_, VK_PIPELINE_STAGE_2_COPY_BIT,
                           VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                           VK_ACCESS_2_HOST_READ_BIT);
    });
    readback_.invalidate();
    return {readback_.data<uint8_t>(), readback_.data<uint8_t>() + readback_.size};
    // snippet:end readback
}

}  // namespace glport
