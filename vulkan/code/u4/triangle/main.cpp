#include <vkf/vkf.hpp>
#include <vulkan/vk_enum_string_helper.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "graphics.hpp"
#include "mesh.hpp"
#include "vecmath.hpp"

namespace {

using u4::Mat4;
using u4::Vec3;

constexpr VkFormat ColorFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkClearColorValue Background{.float32 = {0.10f, 0.10f, 0.15f, 1.0f}};

// snippet:begin triangle-data
struct TriangleVertex {
    float position[2];
    float color[3];
};

constexpr TriangleVertex Triangle[] = {
    {{0.0f, -0.7f}, {1.0f, 0.0f, 0.0f}},
    {{-0.7f, 0.6f}, {0.0f, 0.0f, 1.0f}},
    {{0.7f, 0.6f}, {0.0f, 1.0f, 0.0f}},
};
// snippet:end triangle-data

// snippet:begin triangle-input
constexpr VkVertexInputBindingDescription TriangleBinding{
    .binding = 0,
    .stride = sizeof(TriangleVertex),
    .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
};
constexpr VkVertexInputAttributeDescription TriangleAttributes[] = {
    {.location = 0,
     .binding = 0,
     .format = VK_FORMAT_R32G32_SFLOAT,
     .offset = offsetof(TriangleVertex, position)},
    {.location = 1,
     .binding = 0,
     .format = VK_FORMAT_R32G32B32_SFLOAT,
     .offset = offsetof(TriangleVertex, color)},
};
// snippet:end triangle-input

// snippet:begin draw-constants
struct DrawConstants {
    Mat4 mvp;
    float tint[4];
};

struct Box {
    Mat4 model;
    Vec3 tint;
};
// snippet:end draw-constants

struct Target {
    VkExtent2D extent{};
    vkf::Image color;
    vkf::Image depth;
    vkf::Buffer readback;
};

// snippet:begin attachments
Target createTarget(const vkf::Context& ctx, VkExtent2D extent, VkFormat depthFormat) {
    Target target{.extent = extent};
    target.color = vkf::createImage(
        ctx,
        {.format = ColorFormat,
         .width = extent.width,
         .height = extent.height,
         .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
        "colour attachment");
    if (depthFormat != VK_FORMAT_UNDEFINED) {
        target.depth = vkf::createImage(ctx,
                                        {.format = depthFormat,
                                         .width = extent.width,
                                         .height = extent.height,
                                         .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                         .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                                        "depth attachment");
    }
    target.readback = vkf::createBuffer(ctx, VkDeviceSize(extent.width) * extent.height * 4,
                                        VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                        vkf::MemoryUse::Readback, "readback");
    return target;
}
// snippet:end attachments

vkf::Buffer hostBuffer(const vkf::Context& ctx, const void* data, VkDeviceSize bytes,
                       VkBufferUsageFlags usage, const char* name) {
    vkf::Buffer buffer = vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::Upload, name);
    std::memcpy(buffer.mapped, data, bytes);
    return buffer;
}

// snippet:begin to-attachments
void beginAttachments(VkCommandBuffer cmd, const Target& target) {
    const VkImageMemoryBarrier2 barriers[] = {
        {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_NONE,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = target.color,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        },
        {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_NONE,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
                            VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
            .dstAccessMask = VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                             VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = target.depth,
            .subresourceRange = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1},
        },
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = target.depth.image != VK_NULL_HANDLE ? 2u : 1u,
        .pImageMemoryBarriers = barriers,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}
// snippet:end to-attachments

// snippet:begin begin-rendering
void beginRendering(VkCommandBuffer cmd, const Target& target) {
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = target.color.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Background},
    };
    const VkRenderingAttachmentInfo depth{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = target.depth.view,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo info{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, target.extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
        .pDepthAttachment = target.depth.view != VK_NULL_HANDLE ? &depth : nullptr,
    };
    vkCmdBeginRendering(cmd, &info);
}
// snippet:end begin-rendering

// snippet:begin copy-out
void copyToReadback(VkCommandBuffer cmd, const Target& target) {
    const VkBufferImageCopy region{
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {target.extent.width, target.extent.height, 1},
    };
    vkCmdCopyImageToBuffer(cmd, target.color, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           target.readback, 1, &region);
    vkf::bufferBarrier(cmd, target.readback, VK_PIPELINE_STAGE_2_COPY_BIT,
                       VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                       VK_ACCESS_2_HOST_READ_BIT);
}

void endAttachments(VkCommandBuffer cmd, const Target& target) {
    vkf::imageBarrier(cmd, target.color, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_TRANSFER_READ_BIT);
    copyToReadback(cmd, target);
}
// snippet:end copy-out

std::vector<uint8_t> pixelsOf(const Target& target) {
    target.readback.invalidate();
    const auto* bytes = target.readback.data<uint8_t>();
    return {bytes, bytes + target.readback.size};
}

// snippet:begin draw-triangle
void renderTriangle(const vkf::Context& ctx, const Target& target, VkPipeline pipeline,
                    VkBuffer vertices) {
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        beginAttachments(cmd, target);
        beginRendering(cmd, target);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        u4::setViewportAndScissor(cmd, target.extent);
        const VkDeviceSize offset = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &vertices, &offset);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRendering(cmd);
        endAttachments(cmd, target);
    });
}
// snippet:end draw-triangle

// snippet:begin render-pass
VkRenderPass createRenderPass(const vkf::Context& ctx) {
    const VkAttachmentDescription color{
        .format = ColorFormat,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    };
    const VkAttachmentReference colorReference{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    const VkSubpassDescription subpass{
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorReference,
    };
    // snippet:end render-pass
    // snippet:begin subpass-dependencies
    const VkSubpassDependency dependencies[] = {
        {.srcSubpass = VK_SUBPASS_EXTERNAL,
         .dstSubpass = 0,
         .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
         .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
         .srcAccessMask = 0,
         .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT},
        {.srcSubpass = 0,
         .dstSubpass = VK_SUBPASS_EXTERNAL,
         .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
         .dstStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT,
         .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
         .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT},
    };
    const VkRenderPassCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 2,
        .pDependencies = dependencies,
    };
    VkRenderPass renderPass = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateRenderPass(ctx.device(), &info, nullptr, &renderPass));
    return renderPass;
}
// snippet:end subpass-dependencies

void renderTriangleWithRenderPass(const vkf::Context& ctx, const Target& target,
                                  VkPipelineLayout layout, VkShaderModule vertexShader,
                                  VkShaderModule fragmentShader, VkBuffer vertices) {
    const VkRenderPass renderPass = createRenderPass(ctx);
    // snippet:begin framebuffer
    const VkFramebufferCreateInfo framebufferInfo{
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = renderPass,
        .attachmentCount = 1,
        .pAttachments = &target.color.view,
        .width = target.extent.width,
        .height = target.extent.height,
        .layers = 1,
    };
    VkFramebuffer framebuffer = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateFramebuffer(ctx.device(), &framebufferInfo, nullptr, &framebuffer));
    // snippet:end framebuffer
    const vkf::Unique<VkPipeline> pipeline =
        u4::createGraphicsPipeline(ctx, {.layout = layout,
                                         .vertexShader = vertexShader,
                                         .fragmentShader = fragmentShader,
                                         .vertexBindings = std::span(&TriangleBinding, 1),
                                         .vertexAttributes = TriangleAttributes,
                                         .colorFormat = ColorFormat,
                                         .renderPass = renderPass,
                                         .name = "triangle (render pass)"});

    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        // snippet:begin begin-render-pass
        const VkClearValue clear{.color = Background};
        const VkRenderPassBeginInfo begin{
            .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = renderPass,
            .framebuffer = framebuffer,
            .renderArea = {{0, 0}, target.extent},
            .clearValueCount = 1,
            .pClearValues = &clear,
        };
        vkCmdBeginRenderPass(cmd, &begin, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        u4::setViewportAndScissor(cmd, target.extent);
        const VkDeviceSize offset = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &vertices, &offset);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
        copyToReadback(cmd, target);
        // snippet:end begin-render-pass
    });
    vkDestroyFramebuffer(ctx.device(), framebuffer, nullptr);
    vkDestroyRenderPass(ctx.device(), renderPass, nullptr);
}

struct Camera {
    Vec3 eye{0, 0, 5};
    Vec3 target{0, 0, 0};
    float fovY = u4::Pi / 4;

    Mat4 viewProjection(VkExtent2D extent) const {
        const float aspect = float(extent.width) / float(extent.height);
        return u4::perspective(fovY, aspect, 0.1f, 100.0f) *
               u4::lookAt(eye, target, {0, 1, 0});
    }
};

struct Mesh {
    vkf::Buffer vertices;
    vkf::Buffer indices;
    uint32_t indexCount = 0;
};

// snippet:begin draw-boxes
void renderBoxes(const vkf::Context& ctx, const Target& target, VkPipeline pipeline,
                 VkPipelineLayout layout, const Mesh& cube, std::span<const Box> boxes,
                 const Camera& camera) {
    const Mat4 viewProjection = camera.viewProjection(target.extent);
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        beginAttachments(cmd, target);
        beginRendering(cmd, target);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        u4::setViewportAndScissor(cmd, target.extent);
        const VkDeviceSize offset = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &cube.vertices.buffer, &offset);
        vkCmdBindIndexBuffer(cmd, cube.indices, 0, VK_INDEX_TYPE_UINT16);
        for (const Box& box : boxes) {
            const DrawConstants constants{viewProjection * box.model,
                                          {box.tint.x, box.tint.y, box.tint.z, 1.0f}};
            vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(constants),
                               &constants);
            vkCmdDrawIndexed(cmd, cube.indexCount, 1, 0, 0, 0);
        }
        vkCmdEndRendering(cmd);
        endAttachments(cmd, target);
    });
}
// snippet:end draw-boxes

int toByte(float value) {
    return static_cast<int>(std::lround(std::clamp(value, 0.0f, 1.0f) * 255));
}

int difference(const uint8_t* pixel, Vec3 expected) {
    return std::max({std::abs(pixel[0] - toByte(expected.x)),
                     std::abs(pixel[1] - toByte(expected.y)),
                     std::abs(pixel[2] - toByte(expected.z))});
}

const Vec3 BackgroundColor{Background.float32[0], Background.float32[1],
                           Background.float32[2]};

struct Tally {
    int compared = 0;
    int wrong = 0;
    int worst = 0;

    void add(int diff, int tolerance) {
        ++compared;
        worst = std::max(worst, diff);
        if (diff > tolerance) ++wrong;
    }
};

// snippet:begin check-triangle
bool checkTriangle(const std::vector<uint8_t>& pixels, VkExtent2D extent) {
    float x[3], y[3];
    for (int i = 0; i < 3; ++i) {
        x[i] = (Triangle[i].position[0] + 1) / 2 * float(extent.width);
        y[i] = (Triangle[i].position[1] + 1) / 2 * float(extent.height);
    }
    auto edge = [&](int a, int b, float px, float py) {
        return (x[b] - x[a]) * (py - y[a]) - (y[b] - y[a]) * (px - x[a]);
    };
    const float area = edge(0, 1, x[2], y[2]);
    const float side[3] = {std::hypot(x[2] - x[1], y[2] - y[1]),
                           std::hypot(x[0] - x[2], y[0] - y[2]),
                           std::hypot(x[1] - x[0], y[1] - y[0])};
    Tally inside, outside;
    for (uint32_t row = 0; row < extent.height; ++row) {
        for (uint32_t column = 0; column < extent.width; ++column) {
            const float px = float(column) + 0.5f, py = float(row) + 0.5f;
            const float weight[3] = {edge(1, 2, px, py) / area, edge(2, 0, px, py) / area,
                                     edge(0, 1, px, py) / area};
            float nearestEdge = std::numeric_limits<float>::infinity();
            Vec3 expected;
            for (int i = 0; i < 3; ++i) {
                nearestEdge = std::min(nearestEdge, weight[i] * std::abs(area) / side[i]);
                const float* c = Triangle[i].color;
                expected = expected + Vec3{c[0], c[1], c[2]} * weight[i];
            }
            const uint8_t* pixel = &pixels[(size_t(row) * extent.width + column) * 4];
            if (nearestEdge >= 1.0f) inside.add(difference(pixel, expected), 2);
            if (nearestEdge <= -1.0f) outside.add(difference(pixel, BackgroundColor), 1);
        }
    }
    vkf::print(
        "  inside: {} pixels, {} more than 2 from the interpolated colour (largest {})\n",
        inside.compared, inside.wrong, inside.worst);
    vkf::print("  outside: {} pixels, {} differ from the background\n", outside.compared,
               outside.wrong);
    return inside.compared > 1000 && inside.wrong == 0 && outside.wrong == 0;
}
// snippet:end check-triangle

struct Hit {
    int box = -1;
    int face = -1;
    int boxesHit = 0;
    float t = std::numeric_limits<float>::infinity();
};

// snippet:begin ray-cast
// Faces are numbered +x, -x, +y, -y, +z, -z.
Hit castRay(Vec3 origin, Vec3 direction, std::span<const Box> boxes) {
    Hit nearest;
    for (size_t i = 0; i < boxes.size(); ++i) {
        const Mat4 toBox = u4::inverseAffine(boxes[i].model);
        const Vec3 o = u4::transformPoint(toBox, origin);
        const Vec3 d = u4::transformDirection(toBox, direction);
        const float os[3] = {o.x, o.y, o.z}, ds[3] = {d.x, d.y, d.z};
        float enter = -std::numeric_limits<float>::infinity();
        float leave = std::numeric_limits<float>::infinity();
        int face = -1;
        for (int axis = 0; axis < 3; ++axis) {
            const float t0 = (-1 - os[axis]) / ds[axis], t1 = (1 - os[axis]) / ds[axis];
            if (std::min(t0, t1) > enter) {
                enter = std::min(t0, t1);
                face = axis * 2 + (t0 < t1 ? 1 : 0);
            }
            leave = std::min(leave, std::max(t0, t1));
        }
        if (enter > leave || enter <= 0) continue;
        ++nearest.boxesHit;
        if (enter < nearest.t) nearest = {int(i), face, nearest.boxesHit, enter};
    }
    return nearest;
}
// snippet:end ray-cast

constexpr const char* FaceNames[] = {"+x", "-x", "+y", "-y", "+z", "-z"};

Vec3 colorOf(const Hit& hit, std::span<const Box> boxes) {
    if (hit.box < 0) return BackgroundColor;
    const float sign = hit.face % 2 == 0 ? 1.0f : -1.0f;
    const float normal[3] = {hit.face / 2 == 0 ? sign : 0, hit.face / 2 == 1 ? sign : 0,
                             hit.face / 2 == 2 ? sign : 0};
    const Vec3 tint = boxes[size_t(hit.box)].tint;
    return {(normal[0] * 0.5f + 0.5f) * tint.x, (normal[1] * 0.5f + 0.5f) * tint.y,
            (normal[2] * 0.5f + 0.5f) * tint.z};
}

Hit castPixel(const Camera& camera, VkExtent2D extent, float px, float py,
              std::span<const Box> boxes) {
    const float aspect = float(extent.width) / float(extent.height);
    const float tanHalf = std::tan(camera.fovY / 2);
    const Vec3 forward = u4::normalize(camera.target - camera.eye);
    const Vec3 right = u4::normalize(u4::cross(forward, {0, 1, 0}));
    const Vec3 up = u4::cross(right, forward);
    const float x = (2 * px / float(extent.width) - 1) * tanHalf * aspect;
    const float y = (1 - 2 * py / float(extent.height)) * tanHalf;
    return castRay(camera.eye, right * x + up * y + forward, boxes);
}

// snippet:begin check-boxes
bool checkBoxes(const std::vector<uint8_t>& pixels, VkExtent2D extent, const Camera& camera,
                std::span<const Box> boxes) {
    Tally sampled;
    int skipped = 0, occluded = 0, occludedWrong = 0;
    for (uint32_t row = 1; row + 1 < extent.height; row += 4) {
        for (uint32_t column = 1; column + 1 < extent.width; column += 4) {
            const float px = float(column) + 0.5f, py = float(row) + 0.5f;
            const Hit hit = castPixel(camera, extent, px, py, boxes);
            bool interior = true;
            for (auto [dx, dy] : {std::pair{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
                const Hit near =
                    castPixel(camera, extent, px + float(dx), py + float(dy), boxes);
                interior = interior && near.box == hit.box && near.face == hit.face;
            }
            if (!interior) {
                ++skipped;
                continue;
            }
            const uint8_t* pixel = &pixels[(size_t(row) * extent.width + column) * 4];
            const int diff = difference(pixel, colorOf(hit, boxes));
            sampled.add(diff, 1);
            if (hit.boxesHit == 2) {
                ++occluded;
                if (diff > 1) ++occludedWrong;
            }
        }
    }
    vkf::print("  ray cast: {} sampled pixels compared, {} differ ({} near edges skipped)\n",
               sampled.compared, sampled.wrong, skipped);
    vkf::print("  depth order: {} of them see the wall behind the cube, {} show the wall\n",
               occluded, occludedWrong);
    return sampled.wrong == 0 && occluded > 100 && occludedWrong == 0;
}
// snippet:end check-boxes

bool checkPixel(const std::vector<uint8_t>& pixels, VkExtent2D extent, uint32_t column,
                uint32_t row, Vec3 expected) {
    return difference(&pixels[(size_t(row) * extent.width + column) * 4], expected) <= 1;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const VkExtent2D extent{static_cast<uint32_t>(args.integer("--width", 640)),
                                static_cast<uint32_t>(args.integer("--height", 480))};
        const std::string triangleOut = args.text("--out", "triangle.png");
        const std::string cubeOut = args.text("--cube-out", "cube.png");
        const bool renderPass = args.flag("--render-pass");

        vkf::Context ctx({.appName = "u4_triangle"});
        bool passed = true;

        // snippet:begin triangle-pipeline
        const vkf::Buffer triangleVertices =
            hostBuffer(ctx, Triangle, sizeof(Triangle), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                       "triangle vertices");
        const auto triangleLayout =
            vkf::createPipelineLayout(ctx, std::span<const VkDescriptorSetLayout>());
        const auto triangleVert = vkf::loadShader(ctx, vkf::shaderPath("triangle.vert"));
        const auto triangleFrag = vkf::loadShader(ctx, vkf::shaderPath("triangle.frag"));
        const auto trianglePipeline =
            u4::createGraphicsPipeline(ctx, {.layout = triangleLayout,
                                             .vertexShader = triangleVert,
                                             .fragmentShader = triangleFrag,
                                             .vertexBindings = std::span(&TriangleBinding, 1),
                                             .vertexAttributes = TriangleAttributes,
                                             .colorFormat = ColorFormat,
                                             .name = "triangle"});
        // snippet:end triangle-pipeline

        const Target triangleTarget = createTarget(ctx, extent, VK_FORMAT_UNDEFINED);
        renderTriangle(ctx, triangleTarget, trianglePipeline, triangleVertices);
        const std::vector<uint8_t> trianglePixels = pixelsOf(triangleTarget);
        vkf::writePng(triangleOut, extent.width, extent.height, trianglePixels);
        vkf::print("triangle: {}x{} VK_FORMAT_R8G8B8A8_UNORM, wrote {}\n", extent.width,
                   extent.height, triangleOut);
        passed = checkTriangle(trianglePixels, extent) && passed;

        if (renderPass) {
            const Target passTarget = createTarget(ctx, extent, VK_FORMAT_UNDEFINED);
            renderTriangleWithRenderPass(ctx, passTarget, triangleLayout, triangleVert,
                                         triangleFrag, triangleVertices);
            const std::vector<uint8_t> passPixels = pixelsOf(passTarget);
            const bool same = passPixels == trianglePixels;
            vkf::print("triangle with VkRenderPass and VkFramebuffer: {}\n",
                       same ? "identical to dynamic rendering" : "DIFFERENT");
            passed = same && passed;
        }

        // snippet:begin cube-pipeline
        const u4::Mesh cubeMesh = u4::cubeMesh();
        const Mesh cube{hostBuffer(ctx, cubeMesh.vertices.data(),
                                   cubeMesh.vertices.size() * sizeof(u4::MeshVertex),
                                   VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, "cube vertices"),
                        hostBuffer(ctx, cubeMesh.indices.data(),
                                   cubeMesh.indices.size() * sizeof(uint16_t),
                                   VK_BUFFER_USAGE_INDEX_BUFFER_BIT, "cube indices"),
                        static_cast<uint32_t>(cubeMesh.indices.size())};
        const VkFormat depthFormat = u4::chooseDepthFormat(ctx);
        const VkPushConstantRange pushRange{VK_SHADER_STAGE_VERTEX_BIT, 0,
                                            sizeof(DrawConstants)};
        const auto cubeLayout = vkf::createPipelineLayout(ctx, {}, {pushRange});
        const auto cubeVert = vkf::loadShader(ctx, vkf::shaderPath("cube.vert"));
        const auto cubeFrag = vkf::loadShader(ctx, vkf::shaderPath("cube.frag"));
        const u4::MeshInput input = u4::meshInput({0, 1});
        const auto cubePipeline =
            u4::createGraphicsPipeline(ctx, {.layout = cubeLayout,
                                             .vertexShader = cubeVert,
                                             .fragmentShader = cubeFrag,
                                             .vertexBindings = std::span(&input.binding, 1),
                                             .vertexAttributes = input.attributes,
                                             .colorFormat = ColorFormat,
                                             .depthFormat = depthFormat,
                                             .name = "cube"});
        // snippet:end cube-pipeline

        // snippet:begin scene
        const Camera camera;
        const Box boxes[] = {
            {u4::rotateX(0.35f) * u4::rotateY(-0.5f), {1.0f, 1.0f, 1.0f}},
            {u4::translate({0, 0, -3}) * u4::scale({3.5f, 2.5f, 0.1f}), {0.8f, 0.5f, 0.4f}},
        };
        // snippet:end scene
        const Target cubeTarget = createTarget(ctx, extent, depthFormat);
        renderBoxes(ctx, cubeTarget, cubePipeline, cubeLayout, cube, boxes, camera);
        const std::vector<uint8_t> cubePixels = pixelsOf(cubeTarget);
        vkf::writePng(cubeOut, extent.width, extent.height, cubePixels);
        vkf::print("cube: {}x{}, depth {}, wrote {}\n", extent.width, extent.height,
                   string_VkFormat(depthFormat), cubeOut);
        const Hit centre = castPixel(camera, extent, float(extent.width / 2) + 0.5f,
                                     float(extent.height / 2) + 0.5f, boxes);
        const uint32_t cx = extent.width / 2, cy = extent.height / 2;
        const bool centreOk = checkPixel(cubePixels, extent, cx, cy, colorOf(centre, boxes));
        const uint8_t* c = &cubePixels[(size_t(cy) * extent.width + cx) * 4];
        vkf::print("  centre ({}, {}) is ({}, {}, {}), face {} of the cube: {}\n", cx, cy,
                   c[0], c[1], c[2], FaceNames[centre.face],
                   centreOk ? "as expected" : "WRONG");
        bool cornersOk = true;
        for (auto [column, row] : {std::pair{0u, 0u},
                                   {extent.width - 1, 0u},
                                   {0u, extent.height - 1},
                                   {extent.width - 1, extent.height - 1}}) {
            cornersOk =
                checkPixel(cubePixels, extent, column, row, BackgroundColor) && cornersOk;
        }
        vkf::print("  corners: {}\n", cornersOk ? "background" : "NOT BACKGROUND");
        passed = passed && centreOk && cornersOk;
        passed = checkBoxes(cubePixels, extent, camera, boxes) && passed;

        vkf::print("{} triangle and depth-tested cube\n", passed ? "PASS" : "FAIL");
        if (!passed) throw std::runtime_error("the images do not match their CPU references");
    });
}
