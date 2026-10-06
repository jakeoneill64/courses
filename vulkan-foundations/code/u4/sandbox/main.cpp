#include <vkf/vkf.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <functional>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include "display.hpp"
#include "galaxy.hpp"
#include "graphics.hpp"
#include "mesh.hpp"
#include "presenter.hpp"
#include "rendergraph.hpp"
#include "vecmath.hpp"

namespace {

using u4::Mat4;
using u4::Particle;
using u4::Vec3;

constexpr VkFormat HdrFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
constexpr VkFormat DisplayFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkClearColorValue Black{.float32 = {0.0f, 0.0f, 0.0f, 1.0f}};
constexpr u4::Gravity Gravity;

// snippet:begin frame-params
struct FrameParams {
    Mat4 viewProjection;
    u4::Vec4 planes[6];
    uint32_t instanceCount;
};

struct SimulationConstants {
    float dt;
    float strength;
    float softening;
    uint32_t count;
};
// snippet:end frame-params

// snippet:begin uses
// vkCmdUpdateBuffer executes in the CLEAR stage.
constexpr rg::Use BufferUpdate{VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT};
constexpr rg::Use VertexStorageRead{VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
                                    VK_ACCESS_2_SHADER_STORAGE_READ_BIT};
constexpr rg::Use DepthTest{
    VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};

constexpr rg::Use BlitRead{VK_PIPELINE_STAGE_2_BLIT_BIT, VK_ACCESS_2_TRANSFER_READ_BIT,
                           VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL};
constexpr rg::Use BlitWrite{VK_PIPELINE_STAGE_2_BLIT_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL};
// A freshly acquired image: its first barrier must wait at the stage of the acquire semaphore.
constexpr rg::Use Acquired{VK_PIPELINE_STAGE_2_BLIT_BIT, VK_ACCESS_2_NONE,
                           VK_IMAGE_LAYOUT_UNDEFINED};
// snippet:end uses

// snippet:begin shared-buffer
// Both queue families use the particles: CONCURRENT buffers need no ownership transfers.
struct SharedBuffer {
    vkf::Unique<VkDeviceMemory> memory;
    vkf::Unique<VkBuffer> buffer;
};

SharedBuffer createSharedBuffer(const vkf::Context& ctx, VkDeviceSize size,
                                VkBufferUsageFlags usage) {
    const uint32_t families[] = {ctx.mainQueue().family, ctx.computeQueue().family};
    const bool concurrent = families[0] != families[1];
    const VkBufferCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = concurrent ? VK_SHARING_MODE_CONCURRENT : VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = concurrent ? 2u : 0u,
        .pQueueFamilyIndices = families,
    };
    VkBuffer buffer = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateBuffer(ctx.device(), &info, nullptr, &buffer));
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(ctx.device(), buffer, &requirements);
    const VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = vkf::findMemoryType(ctx, requirements.memoryTypeBits,
                                               VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateMemory(ctx.device(), &allocate, nullptr, &memory));
    VKF_CHECK(vkBindBufferMemory(ctx.device(), buffer, memory, 0));
    ctx.name(buffer, "particles");
    return {{ctx.device(), memory}, {ctx.device(), buffer}};
}
// snippet:end shared-buffer

void copyBuffer(const vkf::Context& ctx, VkBuffer from, VkBuffer to, VkDeviceSize bytes) {
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                           VK_ACCESS_2_MEMORY_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                           VK_ACCESS_2_TRANSFER_READ_BIT | VK_ACCESS_2_TRANSFER_WRITE_BIT);
        const VkBufferCopy region{0, 0, bytes};
        vkCmdCopyBuffer(cmd, from, to, 1, &region);
        vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                           VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT | VK_PIPELINE_STAGE_2_HOST_BIT,
                           VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_HOST_READ_BIT);
    });
}

struct World {
    uint32_t particleCount = 0;
    uint32_t instanceCount = 0;
    VkExtent2D extent{};
    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    // One copy of the particle state per frame slot: slot s reads copy s - 1, writes copy s.
    std::vector<SharedBuffer> particles;
    vkf::Buffer instances;
    u4::GpuMesh cube;
    vkf::Image display;
    bool present = false;
    VkExtent2D presentExtent{};
};

struct Pipelines {
    vkf::Unique<VkDescriptorSetLayout> setLayout;
    vkf::Unique<VkPipelineLayout> layout;
    vkf::Unique<VkPipeline> simulate, cull, post, cubes, particles;
};

struct Slot {
    uint32_t index = 0;
    vkf::Buffer visible;
    vkf::Buffer command;
    std::unique_ptr<rg::Graph> graph;
    VkDescriptorSet set = VK_NULL_HANDLE;
    rg::Resource swapchainImage = 0;
};

void beginDraw(VkCommandBuffer cmd, VkImageView color, VkImageView depth, VkExtent2D extent,
               bool clear) {
    const VkRenderingAttachmentInfo colorAttachment{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = color,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Black},
    };
    const VkRenderingAttachmentInfo depthAttachment{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = depth,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = clear ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_NONE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachment,
        .pDepthAttachment = &depthAttachment,
    };
    vkCmdBeginRendering(cmd, &rendering);
    u4::setViewportAndScissor(cmd, extent);
}

// snippet:begin frame-graph
std::unique_ptr<rg::Graph> buildFrameGraph(const vkf::Context& ctx, const World& w,
                                           const Pipelines& p, Slot& slot,
                                           const FrameParams& params) {
    auto graph = std::make_unique<rg::Graph>(ctx);
    rg::Graph& g = *graph;
    const rg::Resource frame =
        g.createBuffer("frame params", sizeof(FrameParams),
                       VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    const uint32_t slots = static_cast<uint32_t>(w.particles.size());
    const rg::Resource previous =
        g.importBuffer("previous particles",
                       w.particles[(slot.index + slots - 1) % slots].buffer, rg::ComputeWrite);
    const rg::Resource particles =
        g.importBuffer("particles", w.particles[slot.index].buffer, rg::ComputeRead);
    const rg::Resource instances = g.importBuffer("instances", w.instances);
    const rg::Resource visible = g.importBuffer("visible", slot.visible, VertexStorageRead);
    const rg::Resource command =
        g.importBuffer("draw command", slot.command, rg::IndirectRead);
    const rg::Resource hdr = g.createImage(
        "hdr", {.format = HdrFormat,
                .width = w.extent.width,
                .height = w.extent.height,
                .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_STORAGE_BIT});
    const rg::Resource depth =
        g.createImage("depth", {.format = w.depthFormat,
                                .width = w.extent.width,
                                .height = w.extent.height,
                                .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                .aspect = VK_IMAGE_ASPECT_DEPTH_BIT});
    const rg::Resource display =
        g.importImage("display", w.display, w.display.view, vkf::colorRange(),
                      w.present ? BlitRead : rg::ComputeWrite);
    // snippet:end frame-graph

    // snippet:begin compute-passes
    g.addPass("update", [&g, frame, &params](VkCommandBuffer cmd) {
         vkCmdUpdateBuffer(cmd, g.buffer(frame), 0, sizeof(params), &params);
     }).write(frame, BufferUpdate);
    g.addPass("simulate",
              [&w, &p, &slot](VkCommandBuffer cmd) {
                  const SimulationConstants constants{Gravity.dt, Gravity.strength,
                                                      Gravity.softening, w.particleCount};
                  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.simulate);
                  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.layout, 0, 1,
                                          &slot.set, 0, nullptr);
                  vkCmdPushConstants(cmd, p.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                     sizeof(constants), &constants);
                  vkCmdDispatch(cmd, vkf::groupCount(w.particleCount, 256), 1, 1);
              })
        .read(previous, rg::ComputeRead)
        .write(particles, rg::ComputeWrite)
        .queue(rg::Queue::Compute);
    g.addPass("reset command", [&g, command, &w](VkCommandBuffer cmd) {
         const VkDrawIndexedIndirectCommand reset{w.cube.indexCount, 0, 0, 0, 0};
         vkCmdUpdateBuffer(cmd, g.buffer(command), 0, sizeof(reset), &reset);
     }).write(command, BufferUpdate);
    g.addPass("cull",
              [&w, &p, &slot](VkCommandBuffer cmd) {
                  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.cull);
                  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.layout, 0, 1,
                                          &slot.set, 0, nullptr);
                  vkCmdDispatch(cmd, vkf::groupCount(w.instanceCount, 256), 1, 1);
              })
        .read(frame, rg::ComputeRead)
        .read(instances, rg::ComputeRead)
        .read(command, rg::ComputeRead)
        .write(command, rg::ComputeWrite)
        .write(visible, rg::ComputeWrite);
    // snippet:end compute-passes

    // snippet:begin draw-passes
    g.addPass("draw cubes",
              [&g, &w, &p, &slot, hdr, depth, command](VkCommandBuffer cmd) {
                  beginDraw(cmd, g.view(hdr), g.view(depth), w.extent, true);
                  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.cubes);
                  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.layout, 0, 1,
                                          &slot.set, 0, nullptr);
                  u4::bindMesh(cmd, w.cube);
                  vkCmdDrawIndexedIndirect(cmd, g.buffer(command), 0, 1,
                                           sizeof(VkDrawIndexedIndirectCommand));
                  vkCmdEndRendering(cmd);
              })
        .read(frame, VertexStorageRead)
        .read(instances, VertexStorageRead)
        .read(visible, VertexStorageRead)
        .read(command, rg::IndirectRead)
        .write(hdr, rg::ColorAttachment)
        .write(depth, rg::DepthAttachment);
    // snippet:end draw-passes
    // snippet:begin particle-passes
    g.addPass("draw particles",
              [&g, &w, &p, &slot, hdr, depth](VkCommandBuffer cmd) {
                  beginDraw(cmd, g.view(hdr), g.view(depth), w.extent, false);
                  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.particles);
                  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, p.layout, 0, 1,
                                          &slot.set, 0, nullptr);
                  const VkDeviceSize offset = 0;
                  vkCmdBindVertexBuffers(cmd, 0, 1, w.particles[slot.index].buffer.ptr(),
                                         &offset);
                  vkCmdDraw(cmd, w.particleCount, 1, 0, 0);
                  vkCmdEndRendering(cmd);
              })
        .read(frame, VertexStorageRead)
        .read(particles, rg::VertexInput)
        .read(hdr, rg::ColorAttachment)
        .write(hdr, rg::ColorAttachment)
        .read(depth, DepthTest);
    g.addPass("post-process",
              [&w, &p, &slot](VkCommandBuffer cmd) {
                  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.post);
                  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p.layout, 0, 1,
                                          &slot.set, 0, nullptr);
                  vkCmdDispatch(cmd, vkf::groupCount(w.extent.width, 16),
                                vkf::groupCount(w.extent.height, 16), 1);
              })
        .read(hdr, rg::ComputeRead)
        .write(display, rg::ComputeWrite)
        .sideEffect();
    // snippet:end particle-passes
    if (w.present) {
        // snippet:begin present-passes
        slot.swapchainImage = g.importImage("swapchain image", VK_NULL_HANDLE, VK_NULL_HANDLE,
                                            vkf::colorRange(), Acquired);
        g.addPass(
             "blit to swapchain",
             [&g, &w, display, target = slot.swapchainImage](VkCommandBuffer cmd) {
                 const VkImageBlit blit{
                     .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
                     .srcOffsets = {{0, 0, 0},
                                    {int32_t(w.extent.width), int32_t(w.extent.height), 1}},
                     .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
                     .dstOffsets = {{0, 0, 0},
                                    {int32_t(w.presentExtent.width),
                                     int32_t(w.presentExtent.height), 1}},
                 };
                 vkCmdBlitImage(cmd, g.image(display), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                g.image(target), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
                                &blit, VK_FILTER_LINEAR);
             })
            .read(display, BlitRead)
            .write(slot.swapchainImage, BlitWrite);
        g.addPass("present").read(slot.swapchainImage, rg::Present).sideEffect();
        // snippet:end present-passes
    }
    g.compile();

    vkf::DescriptorWriter()
        .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, g.buffer(frame))
        .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                w.particles[(slot.index + slots - 1) % slots].buffer)
        .buffer(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, w.instances)
        .buffer(3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, slot.visible)
        .buffer(4, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, slot.command)
        .image(5, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, g.view(hdr), VK_IMAGE_LAYOUT_GENERAL)
        .image(6, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, w.display.view, VK_IMAGE_LAYOUT_GENERAL)
        .buffer(7, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, w.particles[slot.index].buffer)
        .update(ctx, slot.set);
    return graph;
}

Mat4 cameraAt(uint64_t frame, VkExtent2D extent) {
    const float orbit = 0.004f * float(frame);
    const Vec3 eye{8 * std::sin(orbit), 5, 8 * std::cos(orbit)};
    const float aspect = float(extent.width) / float(extent.height);
    return u4::perspective(50 * u4::Pi / 180, aspect, 0.1f, 100.0f) *
           u4::lookAt(eye, {0, -0.5f, 0}, {0, 1, 0});
}

void waitFor(const vkf::Context& ctx, VkSemaphore timeline, uint64_t value) {
    const VkSemaphoreWaitInfo wait{
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &timeline,
        .pValues = &value,
    };
    VKF_CHECK(vkWaitSemaphores(ctx.device(), &wait, UINT64_MAX));
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto particleCount = static_cast<uint32_t>(args.integer("--n", 1'000'000));
        const auto instanceCount = static_cast<uint32_t>(args.integer("--instances", 50'000));
        const auto framesInFlight =
            static_cast<uint32_t>(args.integer("--frames-in-flight", 3));
        const VkExtent2D extent{static_cast<uint32_t>(args.integer("--width", 1280)),
                                static_cast<uint32_t>(args.integer("--height", 720))};
        const std::string out = args.text("--out", "sandbox.png");
        const bool headless = args.flag("--headless");
        const bool window = args.flag("--window") || headless;
        const auto frames =
            static_cast<uint64_t>(args.integer("--frames", window && !headless ? 0 : 120));
        if (frames == 0 && !(window && !headless)) {
            throw std::runtime_error(
                "--frames 0 runs until the window closes: it needs --window");
        }

        std::optional<u4::Display> display;
        if (window) {
            display.emplace(u4::DisplayOptions{.title = "u4_sandbox",
                                               .width = extent.width / 2,
                                               .height = extent.height / 2,
                                               .headless = headless});
        }
        vkf::Context ctx({
            .appName = "u4_sandbox",
            .asyncCompute = !args.flag("--no-async"),
            .instanceExtensions =
                display ? display->instanceExtensions() : std::vector<const char*>{},
            .createSurface = display
                                 ? std::function<VkSurfaceKHR(VkInstance)>(
                                       [&](VkInstance i) { return display->createSurface(i); })
                                 : nullptr,
        });
        std::optional<u4::Presenter> presenter;
        if (window) {
            presenter.emplace(
                ctx, *display,
                u4::PresenterOptions{
                    .swapchain = {.srgb = false, .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT},
                    .framesInFlight = framesInFlight});
        }

        World w{.particleCount = particleCount,
                .instanceCount = instanceCount,
                .extent = extent,
                .depthFormat = u4::chooseDepthFormat(ctx),
                .present = window};
        const std::vector<Particle> initial = u4::makeGalaxy(particleCount, Gravity);
        const std::vector<u4::Vec4> instances = u4::makeCubeField(instanceCount);
        const VkDeviceSize particleBytes = initial.size() * sizeof(Particle);
        const VkBufferUsageFlags particleUsage =
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        for (uint32_t i = 0; i < framesInFlight; ++i) {
            w.particles.push_back(createSharedBuffer(ctx, particleBytes, particleUsage));
        }
        {
            vkf::Buffer staging =
                vkf::createBuffer(ctx, particleBytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                  vkf::MemoryUse::Upload, "particle staging");
            std::memcpy(staging.mapped, initial.data(), particleBytes);
            copyBuffer(ctx, staging, w.particles.back().buffer, particleBytes);
        }
        w.instances = vkf::createBuffer(
            ctx, instances.size() * sizeof(u4::Vec4),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "instances");
        vkf::upload(ctx, w.instances, std::span<const u4::Vec4>(instances));
        w.cube = u4::uploadMesh(ctx, u4::cubeMesh(), "cube");
        w.display = vkf::createImage(
            ctx,
            {.format = DisplayFormat,
             .width = extent.width,
             .height = extent.height,
             .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
            "display");
        // The graphs expect the display image as an earlier frame's last pass left it.
        const VkImageLayout displayLayout =
            window ? VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL : VK_IMAGE_LAYOUT_GENERAL;
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            vkf::imageBarrier(cmd, w.display, VK_IMAGE_LAYOUT_UNDEFINED, displayLayout,
                              VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                              VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                              VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT);
        });

        Pipelines p;
        const VkShaderStageFlags buffers =
            VK_SHADER_STAGE_COMPUTE_BIT | VK_SHADER_STAGE_VERTEX_BIT;
        p.setLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffers)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffers)
                .add(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffers)
                .add(3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffers)
                .add(4, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffers)
                .add(5, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(6, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(7, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        const VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                       sizeof(SimulationConstants)};
        p.layout = vkf::createPipelineLayout(ctx, {p.setLayout.get()}, {push});
        const auto simulateShader = vkf::loadShader(ctx, vkf::shaderPath("simulate.comp"));
        const auto cullShader = vkf::loadShader(ctx, vkf::shaderPath("cull.comp"));
        const auto postShader = vkf::loadShader(ctx, vkf::shaderPath("post.comp"));
        const auto cubeVert = vkf::loadShader(ctx, vkf::shaderPath("cube.vert"));
        const auto cubeFrag = vkf::loadShader(ctx, vkf::shaderPath("cube.frag"));
        const auto particleVert = vkf::loadShader(ctx, vkf::shaderPath("particle.vert"));
        const auto particleFrag = vkf::loadShader(ctx, vkf::shaderPath("particle.frag"));
        p.simulate = vkf::createComputePipeline(
            ctx, {.layout = p.layout, .module = simulateShader, .name = "simulate"});
        p.cull = vkf::createComputePipeline(
            ctx, {.layout = p.layout, .module = cullShader, .name = "cull"});
        p.post = vkf::createComputePipeline(
            ctx, {.layout = p.layout, .module = postShader, .name = "post-process"});
        const u4::MeshInput cubeInput = u4::meshInput({0, 1});
        p.cubes = u4::createGraphicsPipeline(
            ctx, {.layout = p.layout,
                  .vertexShader = cubeVert,
                  .fragmentShader = cubeFrag,
                  .vertexBindings = std::span(&cubeInput.binding, 1),
                  .vertexAttributes = cubeInput.attributes,
                  .colorFormat = HdrFormat,
                  .depthFormat = w.depthFormat,
                  .name = "cubes"});
        const VkVertexInputBindingDescription particleBinding{0, sizeof(Particle),
                                                              VK_VERTEX_INPUT_RATE_VERTEX};
        const VkVertexInputAttributeDescription particleAttributes[] = {
            {0, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Particle, position)},
            {1, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Particle, velocity)},
        };
        p.particles =
            u4::createGraphicsPipeline(ctx, {.layout = p.layout,
                                             .vertexShader = particleVert,
                                             .fragmentShader = particleFrag,
                                             .vertexBindings = std::span(&particleBinding, 1),
                                             .vertexAttributes = particleAttributes,
                                             .topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
                                             .cullMode = VK_CULL_MODE_NONE,
                                             .colorFormat = HdrFormat,
                                             .depthFormat = w.depthFormat,
                                             .depthWrite = false,
                                             .blend = u4::Blend::Additive,
                                             .name = "particles"});

        FrameParams params{.instanceCount = instanceCount};
        vkf::DescriptorPool pool(ctx);
        std::vector<Slot> slots(framesInFlight);
        for (uint32_t i = 0; i < framesInFlight; ++i) {
            Slot& slot = slots[i];
            slot.visible = vkf::createBuffer(
                ctx, VkDeviceSize(instanceCount) * sizeof(uint32_t),
                VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                vkf::MemoryUse::DeviceLocal, "visible");
            slot.command = vkf::createBuffer(
                ctx, sizeof(VkDrawIndexedIndirectCommand),
                VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
                    VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                vkf::MemoryUse::DeviceLocal, "draw command");
            slot.set = pool.allocate(p.setLayout, "frame");
            slot.index = i;
            slot.graph = buildFrameGraph(ctx, w, p, slot, params);
        }
        if (args.flag("--plan")) slots[0].graph->printPlan();

        vkf::print("sandbox: {} particles, {} cubes, {}x{}, {} frames in flight\n",
                   particleCount, instanceCount, extent.width, extent.height, framesInFlight);
        vkf::print("simulation on {}\n", ctx.hasSeparateComputeQueue()
                                             ? "an async compute queue, family " +
                                                   std::to_string(ctx.computeQueue().family)
                                             : std::string("the main queue"));

        // snippet:begin frame-loop
        const vkf::Unique<VkSemaphore> timeline = vkf::createTimelineSemaphore(ctx, 0);
        std::vector<std::vector<std::pair<std::string, double>>> passTimes;
        std::vector<double> frameMs;
        vkf::CpuTimer frameTimer;
        uint64_t frame = 0;
        for (; (frames == 0 || frame < frames) && !(display && display->closeRequested());
             ++frame) {
            Slot& slot = slots[frame % framesInFlight];
            if (frame >= framesInFlight) {
                waitFor(ctx, timeline, frame + 1 - framesInFlight);
                passTimes.push_back(slot.graph->passTimes());
            }
            params.viewProjection = cameraAt(frame, extent);
            const auto planes = u4::frustumPlanes(params.viewProjection);
            std::copy(planes.begin(), planes.end(), params.planes);
            const vkf::SemaphoreSubmit done{timeline, frame + 1,
                                            VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
            if (!presenter) {
                slot.graph->submit({}, std::span(&done, 1));
            } else {
                display->pollEvents();
                const auto image = presenter->acquire(frame % framesInFlight);
                if (!image) break;
                slot.graph->rebind(slot.swapchainImage, VK_NULL_HANDLE, image->image,
                                   image->view);
                w.presentExtent = image->extent;
                const vkf::SemaphoreSubmit acquired{image->acquired, 0,
                                                    VK_PIPELINE_STAGE_2_BLIT_BIT};
                const vkf::SemaphoreSubmit signals[] = {
                    {image->ready, 0, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT}, done};
                slot.graph->submit(std::span(&acquired, 1), signals);
                presenter->present(*image);
            }
            frameMs.push_back(frameTimer.elapsedMs());
            frameTimer.restart();
        }
        waitFor(ctx, timeline, frame);
        // snippet:end frame-loop
        const uint64_t ran = frame;
        for (uint64_t f = ran > framesInFlight ? ran - framesInFlight : 0; f < ran; ++f) {
            passTimes.push_back(slots[f % framesInFlight].graph->passTimes());
        }
        if (ran < 1) throw std::runtime_error("no frames ran");

        const vkf::Stats period = vkf::summarize(frameMs);
        vkf::print(
            "{} frames: frame time median {:.2f} ms ({:.0f} frames per second), "
            "mean {:.2f} ms\n",
            ran, period.median, 1000.0 / period.median, period.mean);
        vkf::print("GPU time per pass, median of {} frames:\n", passTimes.size());
        for (size_t pass = 0; !passTimes.empty() && pass < passTimes[0].size(); ++pass) {
            std::vector<double> samples;
            for (const auto& times : passTimes) samples.push_back(times[pass].second);
            const std::string& name = passTimes[0][pass].first;
            const bool async = name == "simulate" && ctx.hasSeparateComputeQueue();
            vkf::print("  {:<18}{:8.3f} ms{}\n", name, vkf::summarize(samples).median,
                       async ? "  (compute queue)" : "");
        }

        const Slot& last = slots[(ran - 1) % framesInFlight];
        vkf::Buffer particleReadback =
            vkf::createBuffer(ctx, particleBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "particle readback");
        vkf::Buffer visibleReadback =
            vkf::createBuffer(ctx, last.visible.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "visible readback");
        vkf::Buffer commandReadback =
            vkf::createBuffer(ctx, last.command.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              vkf::MemoryUse::Readback, "command readback");
        copyBuffer(ctx, w.particles[(ran - 1) % framesInFlight].buffer, particleReadback,
                   particleBytes);
        copyBuffer(ctx, last.visible, visibleReadback, last.visible.size);
        copyBuffer(ctx, last.command, commandReadback, last.command.size);
        const std::vector<uint8_t> image = vkf::downloadImage(ctx, w.display, displayLayout);

        // snippet:begin check-particles
        particleReadback.invalidate();
        const Particle* gpu = particleReadback.data<Particle>();
        uint32_t bound = 0;
        double worstMomentum = 0;
        for (uint32_t i = 0; i < particleCount; ++i) {
            const Vec3 r{gpu[i].position[0], gpu[i].position[1], gpu[i].position[2]};
            if (std::isfinite(u4::length(r)) && u4::length(r) < 50) ++bound;
            const Vec3 before = u4::angularMomentum(initial[i]);
            const Vec3 after = u4::angularMomentum(gpu[i]);
            worstMomentum = std::max(worstMomentum, double(u4::length(after - before)) /
                                                        double(u4::length(before)));
        }
        double worstPosition = 0;
        for (uint32_t i = 0; i < particleCount; i += std::max(1u, particleCount / 1000)) {
            Particle reference = initial[i];
            for (uint64_t step = 0; step < ran; ++step) u4::stepOnCpu(reference, Gravity);
            const Vec3 a{gpu[i].position[0], gpu[i].position[1], gpu[i].position[2]};
            const Vec3 b{reference.position[0], reference.position[1], reference.position[2]};
            worstPosition = std::max(worstPosition, double(u4::length(a - b)));
        }
        const bool particlesOk =
            bound == particleCount && worstMomentum < 1e-3 && worstPosition < 1e-3;
        vkf::print(
            "particles: {} of {} still bound after {} steps; angular momentum kept to "
            "{:.1e}\n",
            bound, particleCount, ran, worstMomentum);
        vkf::print("  sampled orbits within {:.1e} of the CPU's\n", worstPosition);
        // snippet:end check-particles

        commandReadback.invalidate();
        visibleReadback.invalidate();
        const auto* command = commandReadback.data<VkDrawIndexedIndirectCommand>();
        std::vector<uint32_t> visible(
            visibleReadback.data<uint32_t>(),
            visibleReadback.data<uint32_t>() + command->instanceCount);
        std::sort(visible.begin(), visible.end());
        const auto planes = u4::frustumPlanes(cameraAt(ran - 1, extent));
        uint32_t cpuCount = 0, disagree = 0, borderline = 0;
        for (uint32_t i = 0; i < instanceCount; ++i) {
            const Vec3 centre{instances[i].x, instances[i].y, instances[i].z};
            const float radius = instances[i].w * 1.7320508f;
            const bool cpu = u4::sphereVisible(planes, centre, radius);
            const bool onGpu = std::binary_search(visible.begin(), visible.end(), i);
            cpuCount += cpu ? 1 : 0;
            bool nearPlane = false;
            for (const u4::Vec4& q : planes) {
                const float d =
                    q.x * centre.x + q.y * centre.y + q.z * centre.z + q.w + radius;
                nearPlane = nearPlane || std::abs(d) < 1e-4f;
            }
            disagree += cpu != onGpu ? 1 : 0;
            borderline += cpu != onGpu && nearPlane ? 1 : 0;
        }
        const bool cullOk = disagree == borderline;
        vkf::print("culling, last frame: {} cubes visible on the GPU, {} on the CPU\n",
                   command->instanceCount, cpuCount);
        vkf::print("  {} disagree ({} of them touching a frustum plane)\n", disagree,
                   borderline);

        uint32_t lit = 0, bright = 0;
        const size_t pixels = size_t(extent.width) * extent.height;
        for (size_t i = 0; i < pixels; ++i) {
            const uint8_t brightest =
                std::max({image[i * 4], image[i * 4 + 1], image[i * 4 + 2]});
            lit += brightest > 0 ? 1 : 0;
            bright += brightest >= 128 ? 1 : 0;
        }
        const bool imageOk = lit > pixels / 10 && bright > pixels / 100;
        vkf::print("image: {:.0f}% of pixels lit, {:.1f}% bright (the particle disc)\n",
                   100.0 * double(lit) / double(pixels),
                   100.0 * double(bright) / double(pixels));
        vkf::writePng(out, extent.width, extent.height, image);
        vkf::print("wrote {}\n", out);

        const bool passed = particlesOk && cullOk && imageOk;
        vkf::print("{} GPU-driven sandbox\n", passed ? "PASS" : "FAIL");
        if (!passed) throw std::runtime_error("the sandbox checks failed");
    });
}
