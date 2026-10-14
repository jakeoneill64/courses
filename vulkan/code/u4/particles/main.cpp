#include <vkf/vkf.hpp>
#include <vulkan/vk_enum_string_helper.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include "display.hpp"
#include "frames.hpp"
#include "galaxy.hpp"
#include "graphics.hpp"
#include "mesh.hpp"
#include "presenter.hpp"
#include "vecmath.hpp"

namespace {

using u4::Mat4;
using u4::Vec3;

constexpr VkFormat HdrFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
constexpr VkFormat DisplayFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkClearColorValue Black{.float32 = {0.0f, 0.0f, 0.0f, 1.0f}};

// snippet:begin push-constants
struct SimulationConstants {
    float dt;
    float strength;
    float softening;
    uint32_t count;
};

struct FrustumConstants {
    u4::Vec4 planes[6];
    uint32_t count;
};
// snippet:end push-constants

using u4::Particle;
constexpr u4::Gravity Gravity;

float halfToFloat(uint16_t h) {
    const int exponent = (h >> 10) & 0x1F;
    const int mantissa = h & 0x3FF;
    const float sign = (h & 0x8000) ? -1.0f : 1.0f;
    if (exponent == 0) return sign * std::ldexp(float(mantissa), -24);
    if (exponent == 31) return sign * INFINITY;
    return sign * std::ldexp(float(mantissa + 1024), exponent - 25);
}

int encodeSrgb(float linear) {
    const float c = linear <= 0.0031308f ? linear * 12.92f
                                         : 1.055f * std::pow(linear, 1.0f / 2.4f) - 0.055f;
    return static_cast<int>(std::lround(std::clamp(c, 0.0f, 1.0f) * 255));
}

struct Resources {
    uint32_t particleCount = 0;
    uint32_t instanceCount = 0;
    VkExtent2D extent{};
    vkf::Buffer particles;
    vkf::Buffer instances;
    vkf::Buffer visible;
    vkf::Buffer drawCommand;
    vkf::Image hdr;
    vkf::Image depth;
    vkf::Image display;
    u4::GpuMesh cube;
};

struct Pipelines {
    vkf::Unique<VkPipelineLayout> simulateLayout, cullLayout, cubeLayout, particleLayout,
        postLayout;
    vkf::Unique<VkPipeline> simulate, cull, cubes, particles, post;
    VkDescriptorSet simulateSet = VK_NULL_HANDLE, cullSet = VK_NULL_HANDLE,
                    cubeSet = VK_NULL_HANDLE, postSet = VK_NULL_HANDLE;
};

struct Readback {
    vkf::Buffer particles;
    vkf::Buffer visible;
    vkf::Buffer drawCommand;
    vkf::Buffer hdr;
    vkf::Buffer display;
};

// snippet:begin simulate-pass
void simulatePass(VkCommandBuffer cmd, const Resources& r, const Pipelines& p) {
    vkf::bufferBarrier(
        cmd, r.particles,
        VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT |
            VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.simulate);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.simulateLayout, 0, 1,
                            &p.simulateSet, 0, nullptr);
    const SimulationConstants constants{Gravity.dt, Gravity.strength, Gravity.softening,
                                        r.particleCount};
    vkCmdPushConstants(cmd, p.simulateLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                       sizeof(constants), &constants);
    vkCmdDispatch(cmd, vkf::groupCount(r.particleCount, 256), 1, 1);
    vkf::bufferBarrier(cmd, r.particles, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                       VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                       VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT,
                       VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT);
}
// snippet:end simulate-pass

// snippet:begin cull-pass
void cullPass(VkCommandBuffer cmd, const Resources& r, const Pipelines& p,
              const FrustumConstants& frustum) {
    vkf::bufferBarrier(cmd, r.drawCommand, VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
                       VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_CLEAR_BIT,
                       VK_ACCESS_2_TRANSFER_WRITE_BIT);
    const VkDrawIndexedIndirectCommand reset{r.cube.indexCount, 0, 0, 0, 0};
    vkCmdUpdateBuffer(cmd, r.drawCommand, 0, sizeof(reset), &reset);
    vkf::bufferBarrier(
        cmd, r.drawCommand, VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
        VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    vkf::bufferBarrier(cmd, r.visible, VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT, VK_ACCESS_2_NONE,
                       VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                       VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.cull);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.cullLayout, 0, 1,
                            &p.cullSet, 0, nullptr);
    vkCmdPushConstants(cmd, p.cullLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(frustum),
                       &frustum);
    vkCmdDispatch(cmd, vkf::groupCount(r.instanceCount, 256), 1, 1);
}
// snippet:end cull-pass

// snippet:begin to-indirect
void cullToDraw(VkCommandBuffer cmd, const Resources& r) {
    const VkBufferMemoryBarrier2 barriers[] = {
        {.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
         .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
         .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
         .dstStageMask = VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
         .dstAccessMask = VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT,
         .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
         .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
         .buffer = r.drawCommand,
         .size = VK_WHOLE_SIZE},
        {.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
         .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
         .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
         .dstStageMask = VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
         .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
         .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
         .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
         .buffer = r.visible,
         .size = VK_WHOLE_SIZE},
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .bufferMemoryBarrierCount = 2,
        .pBufferMemoryBarriers = barriers,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}
// snippet:end to-indirect

void drawPass(VkCommandBuffer cmd, const Resources& r, const Pipelines& p,
              const Mat4& viewProjection) {
    vkf::imageBarrier(
        cmd, r.hdr, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_COPY_BIT,
        VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    vkf::imageBarrier(cmd, r.depth, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
                          VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                          VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1});
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = r.hdr.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Black},
    };
    const VkRenderingAttachmentInfo depth{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = r.depth.view,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, r.extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
        .pDepthAttachment = &depth,
    };
    vkCmdBeginRendering(cmd, &rendering);
    u4::setViewportAndScissor(cmd, r.extent);

    // snippet:begin draw-indirect
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.cubes);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.cubeLayout, 0, 1,
                            &p.cubeSet, 0, nullptr);
    vkCmdPushConstants(cmd, p.cubeLayout, VK_SHADER_STAGE_VERTEX_BIT, 0,
                       sizeof(viewProjection), &viewProjection);
    u4::bindMesh(cmd, r.cube);
    vkCmdDrawIndexedIndirect(cmd, r.drawCommand, 0, 1, sizeof(VkDrawIndexedIndirectCommand));
    // snippet:end draw-indirect

    // snippet:begin draw-points
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.particles);
    vkCmdPushConstants(cmd, p.particleLayout, VK_SHADER_STAGE_VERTEX_BIT, 0,
                       sizeof(viewProjection), &viewProjection);
    const VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &r.particles.buffer, &offset);
    vkCmdDraw(cmd, r.particleCount, 1, 0, 0);
    // snippet:end draw-points
    vkCmdEndRendering(cmd);
}

// snippet:begin post-pass
void postPass(VkCommandBuffer cmd, const Resources& r, const Pipelines& p) {
    vkf::imageBarrier(cmd, r.hdr, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                      VK_ACCESS_2_SHADER_STORAGE_READ_BIT);
    vkf::imageBarrier(cmd, r.display, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_COPY_BIT |
                          VK_PIPELINE_STAGE_2_BLIT_BIT,
                      VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                      VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.post);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.postLayout, 0, 1,
                            &p.postSet, 0, nullptr);
    const float exposure = 1.0f;
    vkCmdPushConstants(cmd, p.postLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(exposure),
                       &exposure);
    vkCmdDispatch(cmd, vkf::groupCount(r.extent.width, 16),
                  vkf::groupCount(r.extent.height, 16), 1);
}
// snippet:end post-pass

// snippet:begin to-transfer
void displayToTransferSource(VkCommandBuffer cmd, const Resources& r) {
    vkf::imageBarrier(
        cmd, r.display, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        VK_PIPELINE_STAGE_2_COPY_BIT | VK_PIPELINE_STAGE_2_BLIT_BIT,
        VK_ACCESS_2_TRANSFER_READ_BIT);
}
// snippet:end to-transfer

// snippet:begin blit-to-swapchain
void blitToSwapchain(VkCommandBuffer cmd, const Resources& r, const u4::Frame& frame) {
    vkf::imageBarrier(cmd, frame.image, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_2_BLIT_BIT,
                      VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_BLIT_BIT,
                      VK_ACCESS_2_TRANSFER_WRITE_BIT);
    const VkImageBlit blit{
        .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .srcOffsets = {{0, 0, 0}, {int32_t(r.extent.width), int32_t(r.extent.height), 1}},
        .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .dstOffsets = {{0, 0, 0},
                       {int32_t(frame.extent.width), int32_t(frame.extent.height), 1}},
    };
    vkCmdBlitImage(cmd, r.display, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, frame.image,
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
    vkf::imageBarrier(cmd, frame.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                      VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_PIPELINE_STAGE_2_BLIT_BIT,
                      VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_NONE,
                      VK_ACCESS_2_NONE);
}
// snippet:end blit-to-swapchain

// The display image must already be in TRANSFER_SRC_OPTIMAL.
void recordReadback(VkCommandBuffer cmd, const Resources& r, const Readback& out) {
    vkf::memoryBarrier(cmd,
                       VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT |
                           VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT |
                           VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT |
                           VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
                       VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                       VK_ACCESS_2_TRANSFER_READ_BIT);
    vkf::imageBarrier(cmd, r.hdr, VK_IMAGE_LAYOUT_GENERAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_NONE,
                      VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
    const VkBufferCopy particles{0, 0, out.particles.size};
    const VkBufferCopy visible{0, 0, out.visible.size};
    const VkBufferCopy command{0, 0, out.drawCommand.size};
    vkCmdCopyBuffer(cmd, r.particles, out.particles, 1, &particles);
    vkCmdCopyBuffer(cmd, r.visible, out.visible, 1, &visible);
    vkCmdCopyBuffer(cmd, r.drawCommand, out.drawCommand, 1, &command);
    const VkBufferImageCopy region{
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {r.extent.width, r.extent.height, 1},
    };
    vkCmdCopyImageToBuffer(cmd, r.hdr, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, out.hdr, 1,
                           &region);
    vkCmdCopyImageToBuffer(cmd, r.display, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, out.display,
                           1, &region);
    vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                       VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
}

struct PassTimes {
    std::vector<double> simulate, cull, draw, post, total;

    void add(const std::vector<double>& stamps) {
        if (stamps.size() < 5) return;
        simulate.push_back(stamps[1] - stamps[0]);
        cull.push_back(stamps[2] - stamps[1]);
        draw.push_back(stamps[3] - stamps[2]);
        post.push_back(stamps[4] - stamps[3]);
        total.push_back(stamps[4] - stamps[0]);
    }
};

// snippet:begin record-frame
void recordFrame(VkCommandBuffer cmd, vkf::GpuTimer& timer, const Resources& r,
                 const Pipelines& p, const Mat4& viewProjection) {
    timer.reset(cmd);
    timer.stamp(cmd);
    simulatePass(cmd, r, p);
    timer.stamp(cmd);
    FrustumConstants frustum{.count = r.instanceCount};
    const std::array<u4::Vec4, 6> planes = u4::frustumPlanes(viewProjection);
    std::copy(planes.begin(), planes.end(), frustum.planes);
    cullPass(cmd, r, p, frustum);
    cullToDraw(cmd, r);
    timer.stamp(cmd);
    drawPass(cmd, r, p, viewProjection);
    timer.stamp(cmd);
    postPass(cmd, r, p);
    timer.stamp(cmd);
}
// snippet:end record-frame

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool headless = args.flag("--headless");
        const bool window = args.flag("--window") || headless;
        const auto particleCount = static_cast<uint32_t>(args.integer("--n", 1'000'000));
        const auto instanceCount = static_cast<uint32_t>(args.integer("--instances", 50'000));
        const auto frames =
            static_cast<uint32_t>(args.integer("--frames", window && !headless ? 0 : 60));
        const auto framesInFlight =
            static_cast<uint32_t>(args.integer("--frames-in-flight", 2));
        const VkExtent2D extent{static_cast<uint32_t>(args.integer("--width", 1280)),
                                static_cast<uint32_t>(args.integer("--height", 720))};
        const std::string out = args.text("--out", "particles.png");

        std::optional<u4::Display> display;
        if (window) {
            display.emplace(u4::DisplayOptions{.title = "u4_particles",
                                               .width = extent.width / 2,
                                               .height = extent.height / 2,
                                               .headless = headless});
        }
        vkf::Context ctx({
            .appName = "u4_particles",
            .instanceExtensions =
                display ? display->instanceExtensions() : std::vector<const char*>{},
            .createSurface = display
                                 ? std::function<VkSurfaceKHR(VkInstance)>(
                                       [&](VkInstance i) { return display->createSurface(i); })
                                 : nullptr,
        });

        VkFormatProperties hdrSupport;
        vkGetPhysicalDeviceFormatProperties(ctx.physicalDevice(), HdrFormat, &hdrSupport);
        const VkFormatFeatureFlags hdrNeeds =
            VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT | VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT;
        if ((hdrSupport.optimalTilingFeatures & hdrNeeds) != hdrNeeds) {
            throw std::runtime_error(
                "this device cannot blend into and load from an RGBA16F "
                "storage image");
        }

        Resources r{
            .particleCount = particleCount, .instanceCount = instanceCount, .extent = extent};
        const std::vector<Particle> initial = u4::makeGalaxy(particleCount, Gravity);
        const std::vector<u4::Vec4> instances = u4::makeCubeField(instanceCount);
        // snippet:begin buffers
        r.particles = vkf::createBuffer(
            ctx, initial.size() * sizeof(Particle),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vkf::MemoryUse::DeviceLocal, "particles");
        r.drawCommand = vkf::createBuffer(
            ctx, sizeof(VkDrawIndexedIndirectCommand),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
                VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vkf::MemoryUse::DeviceLocal, "draw command");
        // snippet:end buffers
        r.instances = vkf::createBuffer(
            ctx, instances.size() * sizeof(u4::Vec4),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "instances");
        r.visible = vkf::createBuffer(
            ctx, VkDeviceSize(instanceCount) * sizeof(uint32_t),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vkf::MemoryUse::DeviceLocal, "visible instances");
        vkf::upload(ctx, r.particles, std::span<const Particle>(initial));
        vkf::upload(ctx, r.instances, std::span<const u4::Vec4>(instances));
        r.cube = u4::uploadMesh(ctx, u4::cubeMesh(), "cube");
        const VkFormat depthFormat = u4::chooseDepthFormat(ctx);
        r.hdr = vkf::createImage(
            ctx,
            {.format = HdrFormat,
             .width = extent.width,
             .height = extent.height,
             .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_STORAGE_BIT |
                      VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
            "hdr");
        r.depth = vkf::createImage(ctx,
                                   {.format = depthFormat,
                                    .width = extent.width,
                                    .height = extent.height,
                                    .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                    .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                                   "depth");
        r.display = vkf::createImage(
            ctx,
            {.format = DisplayFormat,
             .width = extent.width,
             .height = extent.height,
             .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
            "display");

        Pipelines p;
        vkf::DescriptorPool pool(ctx);
        const auto simulateSetLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        const auto cullSetLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        const auto cubeSetLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT)
                .build(ctx);
        const auto postSetLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        p.simulateSet = pool.allocate(simulateSetLayout, "simulate");
        p.cullSet = pool.allocate(cullSetLayout, "cull");
        p.cubeSet = pool.allocate(cubeSetLayout, "cubes");
        p.postSet = pool.allocate(postSetLayout, "post");
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.particles)
            .update(ctx, p.simulateSet);
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.instances)
            .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.visible)
            .buffer(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.drawCommand)
            .update(ctx, p.cullSet);
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.instances)
            .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, r.visible)
            .update(ctx, p.cubeSet);
        vkf::DescriptorWriter()
            .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, r.hdr.view, VK_IMAGE_LAYOUT_GENERAL)
            .image(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, r.display.view,
                   VK_IMAGE_LAYOUT_GENERAL)
            .update(ctx, p.postSet);

        const VkPushConstantRange simulatePush{VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                               sizeof(SimulationConstants)};
        const VkPushConstantRange cullPush{VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                           sizeof(FrustumConstants)};
        const VkPushConstantRange cameraPush{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(Mat4)};
        const VkPushConstantRange postPush{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(float)};
        p.simulateLayout =
            vkf::createPipelineLayout(ctx, {simulateSetLayout.get()}, {simulatePush});
        p.cullLayout = vkf::createPipelineLayout(ctx, {cullSetLayout.get()}, {cullPush});
        p.cubeLayout = vkf::createPipelineLayout(ctx, {cubeSetLayout.get()}, {cameraPush});
        p.particleLayout = vkf::createPipelineLayout(ctx, {}, {cameraPush});
        p.postLayout = vkf::createPipelineLayout(ctx, {postSetLayout.get()}, {postPush});

        const auto simulateShader = vkf::loadShader(ctx, vkf::shaderPath("simulate.comp"));
        const auto cullShader = vkf::loadShader(ctx, vkf::shaderPath("cull.comp"));
        const auto postShader = vkf::loadShader(ctx, vkf::shaderPath("post.comp"));
        const auto cubeVert = vkf::loadShader(ctx, vkf::shaderPath("cube.vert"));
        const auto cubeFrag = vkf::loadShader(ctx, vkf::shaderPath("cube.frag"));
        const auto particleVert = vkf::loadShader(ctx, vkf::shaderPath("particle.vert"));
        const auto particleFrag = vkf::loadShader(ctx, vkf::shaderPath("particle.frag"));
        p.simulate = vkf::createComputePipeline(
            ctx, {.layout = p.simulateLayout, .module = simulateShader, .name = "simulate"});
        p.cull = vkf::createComputePipeline(
            ctx, {.layout = p.cullLayout, .module = cullShader, .name = "cull"});
        p.post = vkf::createComputePipeline(
            ctx, {.layout = p.postLayout, .module = postShader, .name = "post-process"});
        const u4::MeshInput cubeInput = u4::meshInput({0, 1});
        p.cubes = u4::createGraphicsPipeline(
            ctx, {.layout = p.cubeLayout,
                  .vertexShader = cubeVert,
                  .fragmentShader = cubeFrag,
                  .vertexBindings = std::span(&cubeInput.binding, 1),
                  .vertexAttributes = cubeInput.attributes,
                  .colorFormat = HdrFormat,
                  .depthFormat = depthFormat,
                  .name = "cubes"});
        // snippet:begin particle-pipeline
        const VkVertexInputBindingDescription particleBinding{0, sizeof(Particle),
                                                              VK_VERTEX_INPUT_RATE_VERTEX};
        const VkVertexInputAttributeDescription particleAttributes[] = {
            {0, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Particle, position)},
            {1, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Particle, velocity)},
        };
        p.particles =
            u4::createGraphicsPipeline(ctx, {.layout = p.particleLayout,
                                             .vertexShader = particleVert,
                                             .fragmentShader = particleFrag,
                                             .vertexBindings = std::span(&particleBinding, 1),
                                             .vertexAttributes = particleAttributes,
                                             .topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
                                             .cullMode = VK_CULL_MODE_NONE,
                                             .colorFormat = HdrFormat,
                                             .depthFormat = depthFormat,
                                             .depthWrite = false,
                                             .blend = u4::Blend::Additive,
                                             .name = "particles"});
        // snippet:end particle-pipeline

        const float aspect = float(extent.width) / float(extent.height);
        const Mat4 viewProjection = u4::perspective(50 * u4::Pi / 180, aspect, 0.1f, 100.0f) *
                                    u4::lookAt({0, 5, 8}, {0, -0.5f, 0}, {0, 1, 0});
        Readback readback{
            vkf::createBuffer(ctx, r.particles.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "particles readback"),
            vkf::createBuffer(ctx, r.visible.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "visible readback"),
            vkf::createBuffer(ctx, r.drawCommand.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "command readback"),
            vkf::createBuffer(ctx, VkDeviceSize(extent.width) * extent.height * 8,
                              VK_BUFFER_USAGE_TRANSFER_DST_BIT, vkf::MemoryUse::Readback,
                              "hdr readback"),
            vkf::createBuffer(ctx, VkDeviceSize(extent.width) * extent.height * 4,
                              VK_BUFFER_USAGE_TRANSFER_DST_BIT, vkf::MemoryUse::Readback,
                              "display readback")};

        vkf::print("{} particles ({:.0f} MB), {} cubes to cull, {}x{}, {} frames in flight\n",
                   particleCount, double(r.particles.size) / (1 << 20), instanceCount,
                   extent.width, extent.height, framesInFlight);

        std::vector<vkf::GpuTimer> timers;
        for (uint32_t i = 0; i < framesInFlight; ++i) timers.emplace_back(ctx, 8);
        PassTimes times;
        std::vector<double> frameMs;
        uint32_t recorded = 0;
        bool readbackRecorded = false;

        if (window) {
            // snippet:begin presenter
            u4::Presenter presenter(
                ctx, *display,
                {.swapchain = {.srgb = false, .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT},
                 .framesInFlight = framesInFlight,
                 .imageWaitStage = VK_PIPELINE_STAGE_2_BLIT_BIT});
            // snippet:end presenter
            vkf::CpuTimer frameTimer;
            while ((frames == 0 || recorded < frames) && !display->closeRequested()) {
                display->pollEvents();
                const std::optional<u4::Frame> frame = presenter.begin();
                if (!frame) break;
                if (frame->number >= framesInFlight) times.add(timers[frame->slot].read());
                recordFrame(frame->cmd, timers[frame->slot], r, p, viewProjection);
                displayToTransferSource(frame->cmd, r);
                blitToSwapchain(frame->cmd, r, *frame);
                if (frames != 0 && recorded + 1 == frames) {
                    recordReadback(frame->cmd, r, readback);
                    readbackRecorded = true;
                }
                presenter.end(*frame);
                ++recorded;
                frameMs.push_back(frameTimer.elapsedMs());
                frameTimer.restart();
            }
            presenter.drain();
            for (uint32_t i = 0; i < std::min(recorded, framesInFlight); ++i) {
                times.add(timers[i].read());
            }
        } else {
            // snippet:begin offscreen-loop
            u4::FrameRing ring(ctx, ctx.mainQueue().family, framesInFlight);
            vkf::CpuTimer frameTimer;
            for (; recorded < frames; ++recorded) {
                const VkCommandBuffer cmd = ring.begin();
                vkf::GpuTimer& timer = timers[ring.slot()];
                if (recorded >= framesInFlight) times.add(timer.read());
                recordFrame(cmd, timer, r, p, viewProjection);
                if (recorded + 1 == frames) {
                    displayToTransferSource(cmd, r);
                    recordReadback(cmd, r, readback);
                }
                ring.submit(ctx.mainQueue());
                frameMs.push_back(frameTimer.elapsedMs());
                frameTimer.restart();
            }
            ring.drain();
            // snippet:end offscreen-loop
            readbackRecorded = frames > 0;
            for (uint32_t i = 0; i < std::min(recorded, framesInFlight); ++i) {
                times.add(timers[i].read());
            }
        }

        vkf::print("{} frames: CPU frame time median {:.2f} ms\n", recorded,
                   vkf::summarize(frameMs).median);
        vkf::print("GPU time per pass, median of {} frames:\n", times.total.size());
        vkf::print("  simulate      {:7.3f} ms\n", vkf::summarize(times.simulate).median);
        vkf::print("  cull          {:7.3f} ms\n", vkf::summarize(times.cull).median);
        vkf::print("  draw          {:7.3f} ms\n", vkf::summarize(times.draw).median);
        vkf::print("  post-process  {:7.3f} ms\n", vkf::summarize(times.post).median);
        vkf::print("  frame         {:7.3f} ms\n", vkf::summarize(times.total).median);
        if (!readbackRecorded) {
            vkf::print("PASS (no checks: the window was closed before a final frame)\n");
            return;
        }

        // snippet:begin check-particles
        readback.particles.invalidate();
        const Particle* gpu = readback.particles.data<Particle>();
        double worstMomentum = 0;
        for (uint32_t i = 0; i < particleCount; ++i) {
            const Vec3 before = u4::angularMomentum(initial[i]);
            const Vec3 after = u4::angularMomentum(gpu[i]);
            worstMomentum = std::max(worstMomentum, double(u4::length(after - before)) /
                                                        double(u4::length(before)));
        }
        double worstPosition = 0;
        const uint32_t stride = std::max(1u, particleCount / 1000);
        for (uint32_t i = 0; i < particleCount; i += stride) {
            Particle reference = initial[i];
            for (uint32_t step = 0; step < recorded; ++step) u4::stepOnCpu(reference, Gravity);
            const Vec3 a{gpu[i].position[0], gpu[i].position[1], gpu[i].position[2]};
            const Vec3 b{reference.position[0], reference.position[1], reference.position[2]};
            worstPosition = std::max(worstPosition, double(u4::length(a - b)));
        }
        const bool particlesOk = worstMomentum < 1e-3 && worstPosition < 1e-3;
        vkf::print("particles: angular momentum kept to {:.1e} (largest relative change)\n",
                   worstMomentum);
        vkf::print("  sampled orbits within {:.1e} of the CPU's\n", worstPosition);
        // snippet:end check-particles

        // snippet:begin check-cull
        readback.drawCommand.invalidate();
        readback.visible.invalidate();
        const auto* command = readback.drawCommand.data<VkDrawIndexedIndirectCommand>();
        std::vector<uint32_t> gpuVisible(
            readback.visible.data<uint32_t>(),
            readback.visible.data<uint32_t>() + command->instanceCount);
        std::sort(gpuVisible.begin(), gpuVisible.end());
        const std::array<u4::Vec4, 6> planes = u4::frustumPlanes(viewProjection);
        uint32_t cpuCount = 0, disagree = 0, borderline = 0;
        for (uint32_t i = 0; i < instanceCount; ++i) {
            const Vec3 centre{instances[i].x, instances[i].y, instances[i].z};
            const float radius = instances[i].w * 1.7320508f;
            const bool cpu = u4::sphereVisible(planes, centre, radius);
            const bool onGpu = std::binary_search(gpuVisible.begin(), gpuVisible.end(), i);
            cpuCount += cpu ? 1 : 0;
            bool nearPlane = false;
            for (const u4::Vec4& q : planes) {
                const float d =
                    q.x * centre.x + q.y * centre.y + q.z * centre.z + q.w + radius;
                nearPlane = nearPlane || std::abs(d) < 1e-4f;
            }
            if (cpu != onGpu) ++disagree;
            if (cpu != onGpu && nearPlane) ++borderline;
        }
        const bool cullOk = command->indexCount == r.cube.indexCount && disagree == borderline;
        vkf::print("culling: {} of {} cubes visible on the GPU, {} on the CPU\n",
                   command->instanceCount, instanceCount, cpuCount);
        vkf::print("  {} disagree ({} of them touching a frustum plane)\n", disagree,
                   borderline);
        // snippet:end check-cull

        readback.hdr.invalidate();
        readback.display.invalidate();
        const auto* hdr = readback.hdr.data<uint16_t>();
        const auto* shown = readback.display.data<uint8_t>();
        int worstPost = 0;
        uint32_t lit = 0;
        const size_t pixels = size_t(extent.width) * extent.height;
        for (size_t i = 0; i < pixels; ++i) {
            for (int c = 0; c < 3; ++c) {
                const float value = halfToFloat(hdr[i * 4 + c]);
                const int expected = encodeSrgb(value / (1.0f + value));
                worstPost = std::max(worstPost, std::abs(expected - int(shown[i * 4 + c])));
            }
            lit += (shown[i * 4] | shown[i * 4 + 1] | shown[i * 4 + 2]) != 0 ? 1 : 0;
        }
        const bool postOk = worstPost <= 2 && lit > pixels / 10;
        vkf::print(
            "post-process: every pixel within {} of the CPU's tone map; {:.0f}% of pixels "
            "lit\n",
            worstPost, 100.0 * double(lit) / double(pixels));
        vkf::writePng(out, extent.width, extent.height, std::span(shown, pixels * 4));
        vkf::print("wrote {}\n", out);

        const bool passed = particlesOk && cullOk && postOk;
        vkf::print("{} particles, GPU culling and post-processing\n",
                   passed ? "PASS" : "FAIL");
        if (!passed) throw std::runtime_error("the particle checks failed");
    });
}
