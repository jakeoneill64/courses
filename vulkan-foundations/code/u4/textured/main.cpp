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
#include "graphics.hpp"
#include "mesh.hpp"
#include "presenter.hpp"
#include "vecmath.hpp"

namespace {

using u4::Mat4;
using u4::Vec3;

constexpr VkFormat TextureFormat = VK_FORMAT_R8G8B8A8_SRGB;
constexpr VkFormat ColorFormat = VK_FORMAT_R8G8B8A8_SRGB;
constexpr uint32_t TextureSize = 256;
constexpr uint32_t TextureCount = 4;
constexpr uint32_t TableCapacity = 64;
constexpr VkClearColorValue Sky{.float32 = {0.30f, 0.45f, 0.65f, 1.0f}};
constexpr float CubeX[TextureCount] = {-2.7f, -0.9f, 0.9f, 2.7f};

// snippet:begin uniforms
struct FrameUniforms {
    Mat4 viewProjection;
};

struct DrawConstants {
    Mat4 model;
    uint32_t textureIndex;
};
// snippet:end uniforms

constexpr uint8_t Palette[TextureCount][2][3] = {
    {{255, 255, 255}, {0, 0, 0}},
    {{230, 40, 30}, {250, 200, 40}},
    {{40, 200, 60}, {10, 70, 20}},
    {{30, 60, 220}, {120, 220, 250}},
};

std::vector<uint8_t> makeTexture(uint32_t kind) {
    std::vector<uint8_t> pixels(size_t(TextureSize) * TextureSize * 4);
    for (uint32_t y = 0; y < TextureSize; ++y) {
        for (uint32_t x = 0; x < TextureSize; ++x) {
            bool first = false;
            if (kind == 0) first = (x / 32 + y / 32) % 2 == 0;
            if (kind == 1) first = int(std::hypot(x - 127.5, y - 127.5) / 16) % 2 == 0;
            if (kind == 2) first = (x / 16) % 2 == 0;
            if (kind == 3) first = x % 32 < 4 || y % 32 < 4;
            uint8_t* p = &pixels[(size_t(y) * TextureSize + x) * 4];
            std::memcpy(p, Palette[kind][first ? 0 : 1], 3);
            p[3] = 255;
        }
    }
    return pixels;
}

float toLinear(uint8_t value) {
    const float c = float(value) / 255.0f;
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

uint8_t toSrgb(float linear) {
    const float c = linear <= 0.0031308f ? linear * 12.92f
                                         : 1.055f * std::pow(linear, 1.0f / 2.4f) - 0.055f;
    return static_cast<uint8_t>(std::lround(std::clamp(c, 0.0f, 1.0f) * 255));
}

uint32_t mipLevels(uint32_t size) {
    return static_cast<uint32_t>(std::floor(std::log2(size))) + 1;
}

// snippet:begin cpu-mips
// Averages in linear light, as a blit of an _SRGB image does.
std::vector<std::vector<uint8_t>> cpuMipChain(const std::vector<uint8_t>& base) {
    std::vector<std::vector<uint8_t>> levels{base};
    for (uint32_t size = TextureSize / 2; size >= 1; size /= 2) {
        const std::vector<uint8_t>& above = levels.back();
        std::vector<uint8_t> level(size_t(size) * size * 4);
        for (uint32_t y = 0; y < size; ++y) {
            for (uint32_t x = 0; x < size; ++x) {
                for (uint32_t c = 0; c < 4; ++c) {
                    float sum = 0;
                    for (uint32_t i = 0; i < 4; ++i) {
                        const size_t texel =
                            (size_t(2 * y + i / 2) * size * 2 + 2 * x + i % 2);
                        const uint8_t v = above[texel * 4 + c];
                        sum += c < 3 ? toLinear(v) : float(v) / 255.0f;
                    }
                    const size_t at = (size_t(y) * size + x) * 4 + c;
                    level[at] = c < 3 ? toSrgb(sum / 4)
                                      : static_cast<uint8_t>(std::lround(sum / 4 * 255));
                }
            }
        }
        levels.push_back(std::move(level));
    }
    return levels;
}
// snippet:end cpu-mips

struct MeshBuffers {
    vkf::Buffer vertices;
    vkf::Buffer indices;
    uint32_t indexCount = 0;
};

// snippet:begin staging
MeshBuffers uploadThroughStaging(const vkf::Context& ctx, const u4::Mesh& mesh,
                                 const char* name) {
    const VkDeviceSize vertexBytes = mesh.vertices.size() * sizeof(u4::MeshVertex);
    const VkDeviceSize indexBytes = mesh.indices.size() * sizeof(uint16_t);
    vkf::Buffer staging =
        vkf::createBuffer(ctx, vertexBytes + indexBytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                          vkf::MemoryUse::Upload, "mesh staging");
    std::memcpy(staging.data<uint8_t>(), mesh.vertices.data(), vertexBytes);
    std::memcpy(staging.data<uint8_t>() + vertexBytes, mesh.indices.data(), indexBytes);

    MeshBuffers gpu{
        vkf::createBuffer(ctx, vertexBytes,
                          VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                          vkf::MemoryUse::DeviceLocal, name),
        vkf::createBuffer(ctx, indexBytes,
                          VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                          vkf::MemoryUse::DeviceLocal, name),
        static_cast<uint32_t>(mesh.indices.size())};
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        const VkBufferCopy vertexRegion{0, 0, vertexBytes};
        const VkBufferCopy indexRegion{vertexBytes, 0, indexBytes};
        vkCmdCopyBuffer(cmd, staging, gpu.vertices, 1, &vertexRegion);
        vkCmdCopyBuffer(cmd, staging, gpu.indices, 1, &indexRegion);
        vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                           VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT |
                               VK_PIPELINE_STAGE_2_INDEX_INPUT_BIT,
                           VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT | VK_ACCESS_2_INDEX_READ_BIT);
    });
    return gpu;
}
// snippet:end staging

// snippet:begin blit-support
bool canBlitLinear(const vkf::Context& ctx, VkFormat format) {
    VkFormatProperties properties;
    vkGetPhysicalDeviceFormatProperties(ctx.physicalDevice(), format, &properties);
    const VkFormatFeatureFlags needed = VK_FORMAT_FEATURE_BLIT_SRC_BIT |
                                        VK_FORMAT_FEATURE_BLIT_DST_BIT |
                                        VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT;
    return (properties.optimalTilingFeatures & needed) == needed;
}
// snippet:end blit-support

// snippet:begin mipmaps
// Leaves the last level in TRANSFER_DST_OPTIMAL and the others in TRANSFER_SRC_OPTIMAL.
void generateMipmaps(VkCommandBuffer cmd, VkImage image, uint32_t levels) {
    for (uint32_t level = 1; level < levels; ++level) {
        vkf::imageBarrier(
            cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            level == 1 ? VK_PIPELINE_STAGE_2_COPY_BIT : VK_PIPELINE_STAGE_2_BLIT_BIT,
            VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_BLIT_BIT,
            VK_ACCESS_2_TRANSFER_READ_BIT, vkf::colorRange(level - 1, 1));
        const auto above = static_cast<int32_t>(TextureSize >> (level - 1));
        const auto size = static_cast<int32_t>(TextureSize >> level);
        const VkImageBlit blit{
            .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 0, 1},
            .srcOffsets = {{0, 0, 0}, {above, above, 1}},
            .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1},
            .dstOffsets = {{0, 0, 0}, {size, size, 1}},
        };
        vkCmdBlitImage(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image,
                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
    }
}
// snippet:end mipmaps

// snippet:begin to-sampled
void finishMipmaps(VkCommandBuffer cmd, VkImage image, uint32_t levels) {
    const VkImageMemoryBarrier2 barriers[] = {
        {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_BLIT_BIT,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = vkf::colorRange(0, levels - 1),
        },
        {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_BLIT_BIT,
            .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = vkf::colorRange(levels - 1, 1),
        },
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 2,
        .pImageMemoryBarriers = barriers,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}
// snippet:end to-sampled

// Every level of every texture ends in VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL.
std::vector<vkf::Image> uploadTextures(
    const vkf::Context& ctx, const std::vector<std::vector<std::vector<uint8_t>>>& chains,
    bool blit) {
    const uint32_t levels = mipLevels(TextureSize);
    std::vector<vkf::Image> textures;
    VkDeviceSize bytes = 0;
    for (const auto& chain : chains) {
        for (uint32_t level = 0; level < (blit ? 1 : levels); ++level) {
            bytes += chain[level].size();
        }
    }
    vkf::Buffer staging = vkf::createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                            vkf::MemoryUse::Upload, "texture staging");
    std::vector<std::vector<VkBufferImageCopy>> regions(chains.size());
    VkDeviceSize offset = 0;
    for (size_t t = 0; t < chains.size(); ++t) {
        for (uint32_t level = 0; level < (blit ? 1 : levels); ++level) {
            std::memcpy(staging.data<uint8_t>() + offset, chains[t][level].data(),
                        chains[t][level].size());
            const uint32_t size = TextureSize >> level;
            regions[t].push_back({.bufferOffset = offset,
                                  .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1},
                                  .imageExtent = {size, size, 1}});
            offset += chains[t][level].size();
        }
        textures.push_back(vkf::createImage(
            ctx,
            {.format = TextureFormat,
             .width = TextureSize,
             .height = TextureSize,
             .mipLevels = levels,
             .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                      VK_IMAGE_USAGE_TRANSFER_DST_BIT},
            ("texture " + std::to_string(t)).c_str()));
    }
    // snippet:begin texture-upload
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        for (size_t t = 0; t < textures.size(); ++t) {
            vkf::imageBarrier(cmd, textures[t], VK_IMAGE_LAYOUT_UNDEFINED,
                              VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_2_NONE,
                              VK_ACCESS_2_NONE,
                              VK_PIPELINE_STAGE_2_COPY_BIT | VK_PIPELINE_STAGE_2_BLIT_BIT,
                              VK_ACCESS_2_TRANSFER_WRITE_BIT, vkf::colorRange(0, levels));
            vkCmdCopyBufferToImage(
                cmd, staging, textures[t], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                static_cast<uint32_t>(regions[t].size()), regions[t].data());
            if (blit) {
                generateMipmaps(cmd, textures[t], levels);
                finishMipmaps(cmd, textures[t], levels);
            } else {
                vkf::imageBarrier(
                    cmd, textures[t], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_PIPELINE_STAGE_2_COPY_BIT,
                    VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                    VK_ACCESS_2_SHADER_SAMPLED_READ_BIT, vkf::colorRange(0, levels));
            }
        }
    });
    // snippet:end texture-upload
    return textures;
}

std::vector<std::vector<uint8_t>> readMipLevels(const vkf::Context& ctx, VkImage image) {
    const uint32_t levels = mipLevels(TextureSize);
    std::vector<VkBufferImageCopy> regions;
    VkDeviceSize bytes = 0;
    for (uint32_t level = 0; level < levels; ++level) {
        const uint32_t size = TextureSize >> level;
        regions.push_back({.bufferOffset = bytes,
                           .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1},
                           .imageExtent = {size, size, 1}});
        bytes += VkDeviceSize(size) * size * 4;
    }
    vkf::Buffer readback = vkf::createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                             vkf::MemoryUse::Readback, "mip readback");
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                          VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                          VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, VK_ACCESS_2_NONE,
                          VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
        vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback,
                               static_cast<uint32_t>(regions.size()), regions.data());
        vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                          VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                          VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_NONE,
                          VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                          VK_ACCESS_2_SHADER_SAMPLED_READ_BIT);
        vkf::bufferBarrier(cmd, readback, VK_PIPELINE_STAGE_2_COPY_BIT,
                           VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                           VK_ACCESS_2_HOST_READ_BIT);
    });
    readback.invalidate();
    std::vector<std::vector<uint8_t>> result;
    for (const VkBufferImageCopy& region : regions) {
        const uint8_t* first = readback.data<uint8_t>() + region.bufferOffset;
        result.emplace_back(
            first, first + size_t(region.imageExtent.width) * region.imageExtent.height * 4);
    }
    return result;
}

// snippet:begin sampler
vkf::Unique<VkSampler> createSampler(const vkf::Context& ctx, bool mipmaps) {
    const bool anisotropy = mipmaps && ctx.features().core.samplerAnisotropy;
    const float maxAnisotropy =
        std::min(16.0f, ctx.properties().core.limits.maxSamplerAnisotropy);
    const VkSamplerCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_LINEAR,
        .minFilter = VK_FILTER_LINEAR,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .anisotropyEnable = anisotropy,
        .maxAnisotropy = anisotropy ? maxAnisotropy : 1.0f,
        .minLod = 0.0f,
        .maxLod = mipmaps ? VK_LOD_CLAMP_NONE : 0.0f,
    };
    VkSampler sampler = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateSampler(ctx.device(), &info, nullptr, &sampler));
    return {ctx.device(), sampler};
}
// snippet:end sampler

struct Object {
    const MeshBuffers* mesh = nullptr;
    Mat4 model;
    uint32_t textureIndex = 0;
};

struct Scene {
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    std::vector<Object> objects;
};

struct Targets {
    VkImage color = VK_NULL_HANDLE;
    VkImageView colorView = VK_NULL_HANDLE;
    VkImage depth = VK_NULL_HANDLE;
    VkImageView depthView = VK_NULL_HANDLE;
    VkExtent2D extent{};
};

Mat4 cameraAt(float orbit, VkExtent2D extent) {
    const Vec3 eye{7.5f * std::sin(orbit), 2.5f, 7.5f * std::cos(orbit)};
    const float aspect = float(extent.width) / float(extent.height);
    return u4::perspective(u4::Pi / 4, aspect, 0.1f, 200.0f) *
           u4::lookAt(eye, {0, 0, 0}, {0, 1, 0});
}

void beginTargets(VkCommandBuffer cmd, const Targets& targets) {
    vkf::imageBarrier(cmd, targets.color, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    vkf::imageBarrier(cmd, targets.depth, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                      VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
                          VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                      VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                          VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                      {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1});
}

void beginRendering(VkCommandBuffer cmd, const Targets& targets) {
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = targets.colorView,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Sky},
    };
    const VkRenderingAttachmentInfo depth{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = targets.depthView,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = {.depthStencil = {1.0f, 0}},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, targets.extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
        .pDepthAttachment = &depth,
    };
    vkCmdBeginRendering(cmd, &rendering);
}

// snippet:begin draw-scene
void drawScene(VkCommandBuffer cmd, const Scene& scene, VkDescriptorSet frameSet,
               VkDescriptorSet tableSet, const Targets& targets) {
    beginRendering(cmd, targets);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeline);
    u4::setViewportAndScissor(cmd, targets.extent);
    const VkDescriptorSet sets[] = {frameSet, tableSet};
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.layout, 0, 2, sets, 0,
                            nullptr);
    for (const Object& object : scene.objects) {
        const VkDeviceSize offset = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &object.mesh->vertices.buffer, &offset);
        vkCmdBindIndexBuffer(cmd, object.mesh->indices, 0, VK_INDEX_TYPE_UINT16);
        const DrawConstants constants{object.model, object.textureIndex};
        vkCmdPushConstants(cmd, scene.layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0,
                           sizeof(constants), &constants);
        vkCmdDrawIndexed(cmd, object.mesh->indexCount, 1, 0, 0, 0);
    }
    vkCmdEndRendering(cmd);
}
// snippet:end draw-scene

void copyToReadback(VkCommandBuffer cmd, const Targets& targets, const vkf::Buffer& readback) {
    vkf::imageBarrier(cmd, targets.color, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_TRANSFER_READ_BIT);
    const VkBufferImageCopy region{
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {targets.extent.width, targets.extent.height, 1},
    };
    vkCmdCopyImageToBuffer(cmd, targets.color, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback,
                           1, &region);
    vkf::bufferBarrier(cmd, readback, VK_PIPELINE_STAGE_2_COPY_BIT,
                       VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                       VK_ACCESS_2_HOST_READ_BIT);
}

struct OffscreenTarget {
    vkf::Image color;
    vkf::Image depth;
    vkf::Buffer readback;
    Targets targets;
};

OffscreenTarget createOffscreen(const vkf::Context& ctx, VkExtent2D extent,
                                VkFormat depthFormat) {
    OffscreenTarget t;
    t.color = vkf::createImage(
        ctx,
        {.format = ColorFormat,
         .width = extent.width,
         .height = extent.height,
         .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
        "colour");
    t.depth = vkf::createImage(ctx,
                               {.format = depthFormat,
                                .width = extent.width,
                                .height = extent.height,
                                .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                               "depth");
    t.readback = vkf::createBuffer(ctx, VkDeviceSize(extent.width) * extent.height * 4,
                                   VK_BUFFER_USAGE_TRANSFER_DST_BIT, vkf::MemoryUse::Readback,
                                   "readback");
    t.targets = {t.color, t.color.view, t.depth, t.depth.view, extent};
    return t;
}

std::vector<uint8_t> pixelsOf(const vkf::Buffer& readback) {
    readback.invalidate();
    return {readback.data<uint8_t>(), readback.data<uint8_t>() + readback.size};
}

struct Band {
    double mean = 0;
    double deviation = 0;
};

Band measure(const std::vector<uint8_t>& rgba, VkExtent2D extent, uint32_t firstRow,
             uint32_t lastRow) {
    double sum = 0, squares = 0, n = 0;
    for (uint32_t y = firstRow; y <= lastRow; ++y) {
        for (uint32_t x = extent.width / 4; x < extent.width * 3 / 4; ++x) {
            const uint8_t* p = &rgba[(size_t(y) * extent.width + x) * 4];
            const double grey = (p[0] + p[1] + p[2]) / 3.0;
            sum += grey;
            squares += grey * grey;
            n += 1;
        }
    }
    if (n == 0) return {};
    const double mean = sum / n;
    return {mean, std::sqrt(std::max(0.0, squares / n - mean * mean))};
}

int classify(const uint8_t* p) {
    const int r = p[0], g = p[1], b = p[2];
    if (std::abs(r - g) <= 12 && std::abs(g - b) <= 12) return 0;
    if (r > 150 && b < 100) return 1;
    if (g > r + 40 && g > b + 40) return 2;
    if (b > r + 60) return 3;
    return -1;
}

uint32_t rowOf(const Mat4& viewProjection, Vec3 point, VkExtent2D extent) {
    const u4::Vec4 clip = viewProjection * u4::Vec4{point.x, point.y, point.z, 1.0f};
    const float ndcY = clip.y / clip.w;
    return static_cast<uint32_t>(
        std::clamp((ndcY + 1) / 2 * float(extent.height), 0.0f, float(extent.height - 1)));
}

uint32_t columnOf(const Mat4& viewProjection, Vec3 point, VkExtent2D extent) {
    const u4::Vec4 clip = viewProjection * u4::Vec4{point.x, point.y, point.z, 1.0f};
    const float ndcX = clip.x / clip.w;
    return static_cast<uint32_t>(
        std::clamp((ndcX + 1) / 2 * float(extent.width), 0.0f, float(extent.width - 1)));
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool headless = args.flag("--headless");
        const bool window = args.flag("--window") || headless;
        const VkExtent2D extent{static_cast<uint32_t>(args.integer("--width", 800)),
                                static_cast<uint32_t>(args.integer("--height", 600))};
        const auto frames = static_cast<uint32_t>(args.integer("--frames", headless ? 60
                                                                           : window ? 0
                                                                                    : 8));
        const auto framesInFlight =
            static_cast<uint32_t>(args.integer("--frames-in-flight", 2));
        const std::string out = args.text("--out", "textured.png");
        const std::string compareOut = args.text("--compare-out", "textured-no-mips.png");

        std::optional<u4::Display> display;
        if (window) {
            display.emplace(u4::DisplayOptions{.title = "u4_textured",
                                               .width = extent.width,
                                               .height = extent.height,
                                               .headless = headless});
        }
        vkf::Context ctx({
            .appName = "u4_textured",
            .instanceExtensions =
                display ? display->instanceExtensions() : std::vector<const char*>{},
            .createSurface = display
                                 ? std::function<VkSurfaceKHR(VkInstance)>(
                                       [&](VkInstance i) { return display->createSurface(i); })
                                 : nullptr,
        });
        bool passed = true;

        // snippet:begin features
        const VkPhysicalDeviceVulkan12Features& f12 = ctx.features().v12;
        const bool bindless = !args.flag("--no-bindless") && f12.runtimeDescriptorArray &&
                              f12.descriptorBindingPartiallyBound &&
                              f12.shaderSampledImageArrayNonUniformIndexing;
        const bool blit = !args.flag("--cpu-mips") && canBlitLinear(ctx, TextureFormat);
        // snippet:end features

        const uint32_t levels = mipLevels(TextureSize);
        std::vector<std::vector<std::vector<uint8_t>>> chains;
        for (uint32_t t = 0; t < TextureCount; ++t) {
            chains.push_back(cpuMipChain(makeTexture(t)));
        }
        const std::vector<vkf::Image> textures = uploadTextures(ctx, chains, blit);
        vkf::print("textures: {} x {}x{} {}, {} mip levels {}\n", TextureCount, TextureSize,
                   TextureSize, string_VkFormat(TextureFormat), levels,
                   blit                                ? "blitted on the GPU"
                   : canBlitLinear(ctx, TextureFormat) ? "made on the CPU (--cpu-mips)"
                                                       : "made on the CPU: no linear blits");
        int worst = 0;
        for (uint32_t t = 0; t < TextureCount; ++t) {
            const auto gpu = readMipLevels(ctx, textures[t]);
            for (uint32_t level = 0; level < levels; ++level) {
                for (size_t i = 0; i < gpu[level].size(); ++i) {
                    worst =
                        std::max(worst, std::abs(int(gpu[level][i]) - chains[t][level][i]));
                }
            }
            if (t == 0) {
                const uint8_t* texel = gpu[levels - 1].data();
                vkf::print(
                    "  checker's 1x1 level: ({}, {}, {}); averaging sRGB bytes gives 128\n",
                    texel[0], texel[1], texel[2]);
            }
        }
        vkf::print("  every level matches the CPU's linear-light box filter within {}\n",
                   worst);
        passed = passed && worst <= 2;

        const MeshBuffers cube = uploadThroughStaging(ctx, u4::cubeMesh(), "cube");
        const MeshBuffers ground = uploadThroughStaging(ctx, u4::groundMesh(100), "ground");
        const auto sampler = createSampler(ctx, true);
        const auto flatSampler = createSampler(ctx, false);
        const float anisotropy =
            std::min(16.0f, ctx.properties().core.limits.maxSamplerAnisotropy);
        if (ctx.features().core.samplerAnisotropy) {
            vkf::print("sampler: trilinear with {}x anisotropic filtering\n", anisotropy);
        } else {
            vkf::print("sampler: trilinear; anisotropic filtering is unavailable\n");
        }

        // snippet:begin set-layouts
        const VkPhysicalDeviceLimits& limits = ctx.properties().core.limits;
        const auto frameLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_VERTEX_BIT)
                .build(ctx);
        const uint32_t capacity =
            bindless ? std::min(TableCapacity, limits.maxPerStageDescriptorSampledImages)
                     : TextureCount;
        const auto tableLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, VK_SHADER_STAGE_FRAGMENT_BIT,
                     capacity, bindless ? VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT : 0)
                .add(1, VK_DESCRIPTOR_TYPE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT)
                .build(ctx);
        const VkPushConstantRange push{
            VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0,
            sizeof(DrawConstants)};
        const auto layout =
            vkf::createPipelineLayout(ctx, {frameLayout.get(), tableLayout.get()}, {push});
        // snippet:end set-layouts
        if (bindless) {
            vkf::print(
                "descriptors: a bindless table of {} sampled images, {} written, "
                "and one sampler\n",
                capacity, TextureCount);
        } else {
            vkf::print("descriptors: a fixed array of {} sampled images and one sampler\n",
                       TextureCount);
        }

        // snippet:begin table-writes
        vkf::DescriptorPool pool(ctx);
        auto writeTable = [&](VkSampler tableSampler, const char* name) {
            const VkDescriptorSet set = pool.allocate(tableLayout, name);
            vkf::DescriptorWriter writer;
            for (uint32_t t = 0; t < TextureCount; ++t) {
                writer.image(0, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, textures[t].view,
                             VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_NULL_HANDLE, t);
            }
            writer.image(1, VK_DESCRIPTOR_TYPE_SAMPLER, VK_NULL_HANDLE,
                         VK_IMAGE_LAYOUT_UNDEFINED, tableSampler);
            writer.update(ctx, set);
            return set;
        };
        const VkDescriptorSet tableSet = writeTable(sampler, "texture table");
        const VkDescriptorSet flatTableSet = writeTable(flatSampler, "texture table, level 0");
        // snippet:end table-writes

        // snippet:begin frame-uniforms
        std::vector<vkf::Buffer> uniforms;
        std::vector<VkDescriptorSet> frameSets;
        for (uint32_t slot = 0; slot < framesInFlight; ++slot) {
            uniforms.push_back(vkf::createBuffer(ctx, sizeof(FrameUniforms),
                                                 VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                                                 vkf::MemoryUse::Upload, "frame uniforms"));
            frameSets.push_back(pool.allocate(frameLayout, "frame uniforms"));
            vkf::DescriptorWriter()
                .buffer(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, uniforms.back())
                .update(ctx, frameSets.back());
        }
        // snippet:end frame-uniforms

        const auto vertexShader = vkf::loadShader(ctx, vkf::shaderPath("textured.vert"));
        const auto fragmentShader =
            vkf::loadShader(ctx, vkf::shaderPath(bindless ? "bindless.frag" : "fixed.frag"));
        const u4::MeshInput input = u4::meshInput({0, 2});
        const VkFormat depthFormat = u4::chooseDepthFormat(ctx);
        auto makePipeline = [&](VkFormat colorFormat) {
            return u4::createGraphicsPipeline(ctx,
                                              {.layout = layout,
                                               .vertexShader = vertexShader,
                                               .fragmentShader = fragmentShader,
                                               .vertexBindings = std::span(&input.binding, 1),
                                               .vertexAttributes = input.attributes,
                                               .colorFormat = colorFormat,
                                               .depthFormat = depthFormat,
                                               .name = "textured"});
        };

        Scene scene{.layout = layout};
        scene.objects.push_back(
            {&ground, u4::translate({0, -1, -40}) * u4::scale({100, 1, 100}), 0});
        for (uint32_t i = 0; i < TextureCount; ++i) {
            const Mat4 model =
                u4::translate({CubeX[i], 0, 0}) * u4::scale({0.55f, 0.55f, 0.55f});
            scene.objects.push_back({&cube, model, i});
        }

        if (window) {
            u4::Presenter presenter(ctx, *display, {.framesInFlight = framesInFlight});
            vkf::Image depth;
            vkf::Unique<VkPipeline> pipeline;
            presenter.onRecreate([&](const u4::Swapchain& swapchain) {
                depth = vkf::createImage(ctx,
                                         {.format = depthFormat,
                                          .width = swapchain.extent().width,
                                          .height = swapchain.extent().height,
                                          .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                          .aspect = VK_IMAGE_ASPECT_DEPTH_BIT},
                                         "depth");
                if (!pipeline) pipeline = makePipeline(swapchain.surfaceFormat().format);
                scene.pipeline = pipeline;
            });
            const vkf::CpuTimer clock;
            uint32_t presented = 0;
            while ((frames == 0 || presented < frames) && !display->closeRequested()) {
                display->pollEvents();
                const std::optional<u4::Frame> frame = presenter.begin();
                if (!frame) break;
                const float orbit = float(clock.elapsedMs() / 1000) * 0.3f;
                *uniforms[frame->slot].data<FrameUniforms>() = {
                    cameraAt(orbit, frame->extent)};
                const Targets targets{frame->image, frame->view, depth, depth.view,
                                      frame->extent};
                beginTargets(frame->cmd, targets);
                drawScene(frame->cmd, scene, frameSets[frame->slot], tableSet, targets);
                vkf::imageBarrier(frame->cmd, frame->image,
                                  VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                                  VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                                  VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                                  VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                                  VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE);
                presenter.end(*frame);
                ++presented;
            }
            presenter.drain();
            vkf::print("{} {} frames presented to a {}\n", passed ? "PASS" : "FAIL", presented,
                       headless ? "headless surface" : "window");
            if (!passed) throw std::runtime_error("the texture checks failed");
            return;
        }

        const auto pipeline = makePipeline(ColorFormat);
        scene.pipeline = pipeline;
        const OffscreenTarget target = createOffscreen(ctx, extent, depthFormat);

        // snippet:begin frame-loop
        u4::FrameRing ring(ctx, ctx.mainQueue().family, framesInFlight);
        std::string slotsUsed;
        for (uint32_t f = 0; f < frames; ++f) {
            const VkCommandBuffer cmd = ring.begin();
            const float orbit = 2 * u4::Pi * float(f) / float(std::max(frames - 1, 1u));
            *uniforms[ring.slot()].data<FrameUniforms>() = {cameraAt(orbit, extent)};
            slotsUsed += " " + std::to_string(ring.slot());
            beginTargets(cmd, target.targets);
            drawScene(cmd, scene, frameSets[ring.slot()], tableSet, target.targets);
            if (f + 1 == frames) copyToReadback(cmd, target.targets, target.readback);
            ring.submit(ctx.mainQueue());
        }
        ring.drain();
        // snippet:end frame-loop
        vkf::print("{} frames, {} in flight, frame uniform buffers used:{}\n", frames,
                   framesInFlight, slotsUsed);

        const OffscreenTarget flat = createOffscreen(ctx, extent, depthFormat);
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            beginTargets(cmd, flat.targets);
            drawScene(cmd, scene, frameSets[ring.slot()], flatTableSet, flat.targets);
            copyToReadback(cmd, flat.targets, flat.readback);
        });

        const std::vector<uint8_t> pixels = pixelsOf(target.readback);
        const std::vector<uint8_t> flatPixels = pixelsOf(flat.readback);
        vkf::writePng(out, extent.width, extent.height, pixels);
        vkf::writePng(compareOut, extent.width, extent.height, flatPixels);
        vkf::print("wrote {} and, sampling level 0 only, {}\n", out, compareOut);

        const Mat4 viewProjection = cameraAt(0, extent);
        std::string seen;
        bool cubesOk = true;
        for (uint32_t i = 0; i < TextureCount; ++i) {
            const Vec3 faceCentre{CubeX[i], 0, 0.55f};
            const uint32_t x = columnOf(viewProjection, faceCentre, extent);
            const uint32_t y = rowOf(viewProjection, faceCentre, extent);
            const int found = classify(&pixels[(size_t(y) * extent.width + x) * 4]);
            seen += " " + std::to_string(found);
            cubesOk = cubesOk && found == int(i);
        }
        vkf::print("  cube faces show textures{}: {}\n", seen, cubesOk ? "as drawn" : "WRONG");

        const uint32_t farTop = rowOf(viewProjection, {0, -1, -80}, extent);
        const uint32_t farBottom = rowOf(viewProjection, {0, -1, -25}, extent);
        const uint32_t nearTop = rowOf(viewProjection, {0, -1, 1.2f}, extent);
        const Band far = measure(pixels, extent, farTop, farBottom);
        const Band near = measure(pixels, extent, nearTop, extent.height - 1);
        const Band flatFar = measure(flatPixels, extent, farTop, farBottom);
        vkf::print("  far ground, rows {}-{}: mean {:.1f}, deviation {:.1f}\n", farTop,
                   farBottom, far.mean, far.deviation);
        vkf::print("  near ground, rows {}-{}: mean {:.1f}, deviation {:.1f}\n", nearTop,
                   extent.height - 1, near.mean, near.deviation);
        vkf::print("  far ground with level 0 only: mean {:.1f}, deviation {:.1f}\n",
                   flatFar.mean, flatFar.deviation);
        const bool mipsOk = std::abs(far.mean - 188) < 20 && far.deviation < 25 &&
                            near.deviation > 80 && flatFar.deviation > 2 * far.deviation;
        passed = passed && cubesOk && mipsOk;
        vkf::print("{} textured meshes with mipmaps and {} textures\n",
                   passed ? "PASS" : "FAIL", bindless ? "bindless" : "fixed-array");
        if (!passed) throw std::runtime_error("the textured image checks failed");
    });
}
