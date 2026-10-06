#include <vkf/vkf.hpp>
#include <vulkan/vk_enum_string_helper.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include "display.hpp"
#include "graphics.hpp"
#include "mesh.hpp"
#include "presenter.hpp"
#include "vecmath.hpp"

namespace {

using u4::Mat4;

constexpr VkClearColorValue Background{.float32 = {0.10f, 0.10f, 0.15f, 1.0f}};

VkPresentModeKHR parsePresentMode(const std::string& name) {
    if (name == "fifo") return VK_PRESENT_MODE_FIFO_KHR;
    if (name == "fifo-relaxed") return VK_PRESENT_MODE_FIFO_RELAXED_KHR;
    if (name == "mailbox") return VK_PRESENT_MODE_MAILBOX_KHR;
    if (name == "immediate") return VK_PRESENT_MODE_IMMEDIATE_KHR;
    throw std::runtime_error("--present-mode takes fifo, fifo-relaxed, mailbox or immediate");
}

struct Scene {
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    const u4::GpuMesh* cube = nullptr;
    VkImage depth = VK_NULL_HANDLE;
    VkImageView depthView = VK_NULL_HANDLE;
};

// snippet:begin acquire-barriers
void beginFrame(VkCommandBuffer cmd, const u4::Frame& frame, const Scene& scene) {
    vkf::imageBarrier(cmd, frame.image, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_NONE,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    vkf::imageBarrier(cmd, scene.depth, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
                          VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                          VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1});
}
// snippet:end acquire-barriers

void drawCube(VkCommandBuffer cmd, const u4::Frame& frame, const Scene& scene,
              const Mat4& mvp) {
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = frame.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Background},
    };
    const VkRenderingAttachmentInfo depth{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = scene.depthView,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, frame.extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
        .pDepthAttachment = &depth,
    };
    vkCmdBeginRendering(cmd, &rendering);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeline);
    u4::setViewportAndScissor(cmd, frame.extent);
    u4::bindMesh(cmd, *scene.cube);
    vkCmdPushConstants(cmd, scene.layout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(mvp), &mvp);
    vkCmdDrawIndexed(cmd, scene.cube->indexCount, 1, 0, 0, 0);
    vkCmdEndRendering(cmd);
}

// snippet:begin present-barrier
void endFrame(VkCommandBuffer cmd, const u4::Frame& frame) {
    vkf::imageBarrier(
        cmd, frame.image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE);
}
// snippet:end present-barrier

void endFrameWithReadback(VkCommandBuffer cmd, const u4::Frame& frame,
                          const vkf::Buffer& readback) {
    vkf::imageBarrier(cmd, frame.image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_TRANSFER_READ_BIT);
    const VkBufferImageCopy region{
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {frame.extent.width, frame.extent.height, 1},
    };
    vkCmdCopyImageToBuffer(cmd, frame.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback, 1,
                           &region);
    vkf::imageBarrier(cmd, frame.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE);
    vkf::bufferBarrier(cmd, readback, VK_PIPELINE_STAGE_2_COPY_BIT,
                       VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                       VK_ACCESS_2_HOST_READ_BIT);
}

int encode(float linear, bool srgb) {
    float value = std::clamp(linear, 0.0f, 1.0f);
    if (srgb) {
        value = value <= 0.0031308f ? value * 12.92f
                                    : 1.055f * std::pow(value, 1.0f / 2.4f) - 0.055f;
    }
    return static_cast<int>(std::lround(value * 255));
}

std::vector<uint8_t> toRgba(const uint8_t* pixels, VkExtent2D extent, VkFormat format) {
    std::vector<uint8_t> rgba(pixels, pixels + size_t(extent.width) * extent.height * 4);
    if (format == VK_FORMAT_B8G8R8A8_SRGB || format == VK_FORMAT_B8G8R8A8_UNORM) {
        for (size_t i = 0; i < rgba.size(); i += 4) std::swap(rgba[i], rgba[i + 2]);
    }
    return rgba;
}

bool checkFinalImage(const std::vector<uint8_t>& rgba, VkExtent2D extent, VkFormat format) {
    const bool srgb = format == VK_FORMAT_B8G8R8A8_SRGB || format == VK_FORMAT_R8G8B8A8_SRGB;
    const int background[3] = {encode(Background.float32[0], srgb),
                               encode(Background.float32[1], srgb),
                               encode(Background.float32[2], srgb)};
    auto isBackground = [&](uint32_t x, uint32_t y) {
        const uint8_t* p = &rgba[(size_t(y) * extent.width + x) * 4];
        for (int c = 0; c < 3; ++c) {
            if (std::abs(p[c] - background[c]) > 2) return false;
        }
        return true;
    };
    const uint32_t w = extent.width - 1, h = extent.height - 1;
    const bool corners =
        isBackground(0, 0) && isBackground(w, 0) && isBackground(0, h) && isBackground(w, h);
    const bool centre = !isBackground(extent.width / 2, extent.height / 2);
    vkf::print("final image {}x{}: centre {} the cube, corners {} the background\n",
               extent.width, extent.height, centre ? "shows" : "DOES NOT show",
               corners ? "show" : "DO NOT show");
    return corners && centre;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool headless = args.flag("--headless");
        const long long frames = args.integer("--frames", 240);
        const long long resizeAt = args.integer("--resize-at", -1);
        const auto width = static_cast<uint32_t>(args.integer("--width", 800));
        const auto height = static_cast<uint32_t>(args.integer("--height", 600));
        const VkPresentModeKHR wantedMode =
            parsePresentMode(args.text("--present-mode", "fifo"));
        const std::string out = args.text("--out", "");

        // snippet:begin setup
        u4::Display display(
            {.title = "u4_spin", .width = width, .height = height, .headless = headless});
        vkf::Context ctx({
            .appName = "u4_spin",
            .instanceExtensions = display.instanceExtensions(),
            .createSurface =
                [&](VkInstance instance) { return display.createSurface(instance); },
        });
        u4::Presenter presenter(
            ctx, display,
            {.swapchain = {.presentMode = wantedMode,
                           .imageCount = static_cast<uint32_t>(args.integer("--images", 3)),
                           .optionalUsage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
             .framesInFlight = static_cast<uint32_t>(args.integer("--frames-in-flight", 2))});
        // snippet:end setup

        const u4::GpuMesh cube = u4::uploadMesh(ctx, u4::cubeMesh(), "cube");
        const VkPushConstantRange push{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(Mat4)};
        const auto layout = vkf::createPipelineLayout(ctx, {}, {push});
        const auto vertexShader = vkf::loadShader(ctx, vkf::shaderPath("spin.vert"));
        const auto fragmentShader = vkf::loadShader(ctx, vkf::shaderPath("spin.frag"));
        const u4::MeshInput input = u4::meshInput({0, 1});
        const VkFormat depthFormat = u4::chooseDepthFormat(ctx);

        vkf::print("surface: {}, {}, {}\n", headless ? "headless" : "window",
                   string_VkFormat(presenter.swapchain().surfaceFormat().format),
                   string_VkColorSpaceKHR(presenter.swapchain().surfaceFormat().colorSpace));
        vkf::Image depth;
        vkf::Unique<VkPipeline> pipeline;
        VkFormat pipelineFormat = VK_FORMAT_UNDEFINED;
        // snippet:begin on-recreate
        presenter.onRecreate([&](const u4::Swapchain& swapchain) {
            const VkExtent2D extent = swapchain.extent();
            depth = vkf::createImage(ctx,
                                     {.format = depthFormat,
                                      .width = extent.width,
                                      .height = extent.height,
                                      .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                      .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                                     "depth");
            if (swapchain.surfaceFormat().format != pipelineFormat) {
                pipelineFormat = swapchain.surfaceFormat().format;
                pipeline = u4::createGraphicsPipeline(
                    ctx, {.layout = layout,
                          .vertexShader = vertexShader,
                          .fragmentShader = fragmentShader,
                          .vertexBindings = std::span(&input.binding, 1),
                          .vertexAttributes = input.attributes,
                          .colorFormat = pipelineFormat,
                          .depthFormat = depthFormat,
                          .name = "spinning cube"});
            }
            vkf::print("swapchain {}x{}: {} images, {}, {} frames in flight\n", extent.width,
                       extent.height, swapchain.imageCount(),
                       string_VkPresentModeKHR(swapchain.presentMode()),
                       presenter.framesInFlight());
        });
        // snippet:end on-recreate

        const u4::Swapchain& swapchain = presenter.swapchain();
        if (swapchain.presentMode() != wantedMode) {
            vkf::print("{} is not supported here; using {}\n",
                       string_VkPresentModeKHR(wantedMode),
                       string_VkPresentModeKHR(swapchain.presentMode()));
        }
        const bool canRead = (swapchain.usage() & VK_IMAGE_USAGE_TRANSFER_SRC_BIT) != 0;
        vkf::Buffer readback;

        std::vector<double> frameMs, slotWaitMs, acquireMs, presentMs;
        const vkf::CpuTimer clock;
        vkf::CpuTimer frameTimer;
        long long presented = 0;
        // snippet:begin loop
        while ((frames == 0 || presented < frames) && !display.closeRequested()) {
            display.pollEvents();
            if (presented == resizeAt) {
                vkf::print("frame {}: resizing to {}x{}\n", presented, width * 4 / 5,
                           height * 3 / 5);
                display.resize(width * 4 / 5, height * 3 / 5);
            }
            const std::optional<u4::Frame> frame = presenter.begin();
            if (!frame) break;
            const float seconds = static_cast<float>(clock.elapsedMs() / 1000);
            const float aspect = float(frame->extent.width) / float(frame->extent.height);
            const Mat4 mvp = u4::perspective(u4::Pi / 4, aspect, 0.1f, 100.0f) *
                             u4::lookAt({0, 1.5f, 6}, {0, 0, 0}, {0, 1, 0}) *
                             u4::rotateY(seconds * 0.9f) * u4::rotateX(seconds * 0.4f);

            const Scene scene{layout, pipeline, &cube, depth, depth.view};
            beginFrame(frame->cmd, *frame, scene);
            drawCube(frame->cmd, *frame, scene, mvp);
            const bool last = frames != 0 && presented + 1 == frames;
            if (last && canRead) {
                readback = vkf::createBuffer(
                    ctx, VkDeviceSize(frame->extent.width) * frame->extent.height * 4,
                    VK_BUFFER_USAGE_TRANSFER_DST_BIT, vkf::MemoryUse::Readback, "readback");
                endFrameWithReadback(frame->cmd, *frame, readback);
            } else {
                endFrame(frame->cmd, *frame);
            }
            presenter.end(*frame);
            ++presented;

            frameMs.push_back(frameTimer.elapsedMs());
            frameTimer.restart();
            slotWaitMs.push_back(frame->slotWaitMs);
            acquireMs.push_back(frame->acquireMs);
            presentMs.push_back(presenter.lastPresentMs());
        }
        presenter.drain();
        // snippet:end loop

        const double seconds = clock.elapsedMs() / 1000;
        const auto skip = std::min<size_t>(frameMs.size(), 5);
        const vkf::Stats period =
            vkf::summarize({frameMs.begin() + long(skip), frameMs.end()});
        vkf::print(
            "{} frames in {:.2f} s: frame time median {:.2f} ms (min {:.2f}, mean {:.2f}, "
            "max {:.2f})\n",
            presented, seconds, period.median, period.min, period.mean, period.max);
        vkf::print(
            "  median wait: frame slot {:.3f} ms, acquire {:.3f} ms, submit and present "
            "{:.3f} ms\n",
            vkf::summarize(slotWaitMs).median, vkf::summarize(acquireMs).median,
            vkf::summarize(presentMs).median);

        const bool closed = display.closeRequested();
        bool passed = frames == 0 || presented == frames || closed;
        if (resizeAt >= 0 && resizeAt < presented) {
            const VkExtent2D expected = display.framebufferExtent();
            const VkExtent2D actual = presenter.swapchain().extent();
            const bool resized = presenter.recreations() >= 1 &&
                                 actual.width == expected.width &&
                                 actual.height == expected.height;
            vkf::print("swapchain recreated {} time(s); extent {}x{} {} the display's {}x{}\n",
                       presenter.recreations(), actual.width, actual.height,
                       resized ? "matches" : "DOES NOT match", expected.width,
                       expected.height);
            passed = passed && resized;
        }
        if (readback.buffer != VK_NULL_HANDLE) {
            readback.invalidate();
            const VkExtent2D extent = presenter.swapchain().extent();
            const std::vector<uint8_t> rgba =
                toRgba(readback.data<uint8_t>(), extent,
                       presenter.swapchain().surfaceFormat().format);
            passed =
                checkFinalImage(rgba, extent, presenter.swapchain().surfaceFormat().format) &&
                passed;
            if (!out.empty()) {
                vkf::writePng(out, extent.width, extent.height, rgba);
                vkf::print("wrote {}\n", out);
            }
        } else if (closed) {
            vkf::print("the window was closed early, so the final image is not checked\n");
        } else if (frames != 0) {
            vkf::print(
                "the swapchain images cannot be copied here, so the image is not checked\n");
        }
        vkf::print("{} {} frames presented, {} swapchain recreation(s)\n",
                   passed ? "PASS" : "FAIL", presented, presenter.recreations());
        if (!passed) throw std::runtime_error("the presentation checks failed");
    });
}
