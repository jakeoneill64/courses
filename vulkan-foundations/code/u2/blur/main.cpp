#include <vkf/vkf.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <format>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "u2.hpp"

namespace {

constexpr int tile = 16;  // must equal TILE and the local size in the blur shaders

// snippet:begin pattern
std::vector<float> testPattern(uint32_t width, uint32_t height) {
    std::vector<float> rgba(size_t(width) * height * 4);
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const float u = (x + 0.5f) / width, v = (y + 0.5f) / height;
            const float r = std::hypot(u - 0.5f, v - 0.5f);
            const bool ring = int(r * 20) % 2 == 0;
            const bool square = (x / 32 + y / 32) % 2 == 0;
            const bool line = x % 128 == 64 || y % 128 == 64;
            float* p = &rgba[(size_t(y) * width + x) * 4];
            p[0] = line ? 1.0f : ring ? 0.9f * u : 0.1f;
            p[1] = line ? 1.0f : square ? 0.8f * v : 0.2f;
            p[2] = line ? 1.0f : 0.3f + 0.6f * r;
            p[3] = 1.0f;
        }
    }
    return rgba;
}
// snippet:end pattern

std::vector<float> gaussianWeights(int radius) {
    const double sigma = radius / 2.5;
    std::vector<double> w(radius + 1);
    double total = 0;
    for (int k = 0; k <= radius; ++k) {
        w[k] = std::exp(-0.5 * k * k / (sigma * sigma));
        total += k == 0 ? w[k] : 2 * w[k];
    }
    std::vector<float> weights(radius + 1);
    for (int k = 0; k <= radius; ++k) weights[k] = float(w[k] / total);
    return weights;
}

// snippet:begin reference
std::vector<float> blurReference(std::span<const float> image, int width, int height,
                                 std::span<const float> weights) {
    const int radius = int(weights.size()) - 1;
    auto pass = [&](std::span<const float> in, int dx, int dy) {
        std::vector<float> out(in.size());
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                for (int c = 0; c < 4; ++c) {
                    double sum = 0;
                    for (int k = -radius; k <= radius; ++k) {
                        const int sx = std::clamp(x + k * dx, 0, width - 1);
                        const int sy = std::clamp(y + k * dy, 0, height - 1);
                        sum += weights[std::abs(k)] *
                               double(in[(size_t(sy) * width + sx) * 4 + c]);
                    }
                    out[(size_t(y) * width + x) * 4 + c] = float(sum);
                }
            }
        }
        return out;
    };
    return pass(pass(image, 1, 0), 0, 1);
}
// snippet:end reference

std::vector<float> bilinearReference(std::span<const uint8_t> image, int width, int height,
                                     int outWidth, int outHeight) {
    auto texel = [&](int x, int y, int c) {
        x = std::clamp(x, 0, width - 1);
        y = std::clamp(y, 0, height - 1);
        return image[(size_t(y) * width + x) * 4 + c] / 255.0;
    };
    std::vector<float> out(size_t(outWidth) * outHeight * 4);
    for (int y = 0; y < outHeight; ++y) {
        for (int x = 0; x < outWidth; ++x) {
            const double sx = (x + 0.5) / outWidth * width - 0.5;
            const double sy = (y + 0.5) / outHeight * height - 0.5;
            const int x0 = int(std::floor(sx)), y0 = int(std::floor(sy));
            const double fx = sx - x0, fy = sy - y0;
            for (int c = 0; c < 4; ++c) {
                const double top = texel(x0, y0, c) * (1 - fx) + texel(x0 + 1, y0, c) * fx;
                const double bottom =
                    texel(x0, y0 + 1, c) * (1 - fx) + texel(x0 + 1, y0 + 1, c) * fx;
                out[(size_t(y) * outWidth + x) * 4 + c] = float(top * (1 - fy) + bottom * fy);
            }
        }
    }
    return out;
}

std::vector<uint8_t> toBytes(std::span<const float> values) {
    std::vector<uint8_t> bytes(values.size());
    for (size_t i = 0; i < values.size(); ++i) {
        bytes[i] = uint8_t(std::lround(std::clamp(values[i], 0.0f, 1.0f) * 255.0f));
    }
    return bytes;
}

std::vector<float> toFloats(const std::vector<uint8_t>& bytes) {
    std::vector<float> values(bytes.size() / sizeof(float));
    std::memcpy(values.data(), bytes.data(), values.size() * sizeof(float));
    return values;
}

double maxError(std::span<const float> a, std::span<const float> b) {
    double worst = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        worst = std::max(worst, std::abs(double(a[i]) - b[i]));
    }
    return worst;
}

// snippet:begin format-check
void requireFormat(const vkf::Context& ctx, VkFormat format, VkFormatFeatureFlags features) {
    VkFormatProperties properties;
    vkGetPhysicalDeviceFormatProperties(ctx.physicalDevice(), format, &properties);
    if ((properties.optimalTilingFeatures & features) != features) {
        throw std::runtime_error("this device lacks a format feature the blur needs");
    }
}
// snippet:end format-check

// snippet:begin sampler
vkf::Unique<VkSampler> createLinearSampler(const vkf::Context& ctx) {
    const VkSamplerCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_LINEAR,
        .minFilter = VK_FILTER_LINEAR,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .maxLod = 0.0f,
    };
    VkSampler sampler = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateSampler(ctx.device(), &info, nullptr, &sampler));
    return {ctx.device(), sampler};
}
// snippet:end sampler

void dispatch(VkCommandBuffer cmd, VkPipeline pipeline, VkPipelineLayout layout,
              VkDescriptorSet set, uint32_t width, uint32_t height) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                            nullptr);
    vkCmdDispatch(cmd, vkf::groupCount(width, tile), vkf::groupCount(height, tile), 1);
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto size = static_cast<uint32_t>(args.integer("--size", 1024));
        const auto radius = static_cast<int>(args.integer("--radius", 8));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        const std::string out = args.text("--out", "");
        vkf::Context ctx({.appName = "u2_blur"});
        const VkPhysicalDeviceLimits& limits = ctx.properties().core.limits;
        const size_t tileBytes = size_t(tile + 2 * radius) * tile * 4 * sizeof(float);
        if (size < 8 || radius < 1 || tileBytes > limits.maxComputeSharedMemorySize) {
            throw std::runtime_error("--size or --radius is out of range for this device");
        }
        requireFormat(ctx, VK_FORMAT_R32G32B32A32_SFLOAT, VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT);
        requireFormat(ctx, VK_FORMAT_R8G8B8A8_UNORM,
                      VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT |
                          VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT);

        const std::vector<float> pattern = testPattern(size, size);
        const std::vector<float> weights = gaussianWeights(radius);

        // snippet:begin create-images
        const vkf::ImageDesc desc{
            .format = VK_FORMAT_R32G32B32A32_SFLOAT,
            .width = size,
            .height = size,
            .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                     VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        };
        vkf::Image source = vkf::createImage(ctx, desc, "source");
        vkf::Image middle = vkf::createImage(ctx, desc, "rows blurred");
        vkf::Image blurred = vkf::createImage(ctx, desc, "blurred");
        vkf::Image naive = vkf::createImage(ctx, desc, "naive 2D");
        vkf::uploadImage(ctx, source, pattern.data(), pattern.size() * sizeof(float),
                         VK_IMAGE_LAYOUT_GENERAL);
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            for (VkImage image : {middle.image, blurred.image, naive.image}) {
                vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED,
                                  VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_2_NONE,
                                  VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                  VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
            }
        });
        // snippet:end create-images
        vkf::Buffer weightBuffer = vkf::createBuffer(
            ctx, weights.size() * sizeof(float),
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "weights");
        vkf::upload(ctx, weightBuffer, std::span<const float>(weights));

        auto setLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()});
        vkf::Specialization spec;
        spec.set(0, radius);
        auto rows = u2::loadPipeline(ctx, layout, "blur_rows.comp", spec);
        auto columns = u2::loadPipeline(ctx, layout, "blur_columns.comp", spec);
        auto naive2d = u2::loadPipeline(ctx, layout, "blur_2d.comp", spec);
        vkf::DescriptorPool pool(ctx);
        auto imageSet = [&](const vkf::Image& from, const vkf::Image& to) {
            VkDescriptorSet set = pool.allocate(setLayout);
            vkf::DescriptorWriter()
                .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, from.view, VK_IMAGE_LAYOUT_GENERAL)
                .image(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, to.view, VK_IMAGE_LAYOUT_GENERAL)
                .buffer(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, weightBuffer)
                .update(ctx, set);
            return set;
        };
        VkDescriptorSet rowsSet = imageSet(source, middle);
        VkDescriptorSet columnsSet = imageSet(middle, blurred);
        VkDescriptorSet naiveSet = imageSet(source, naive);

        // snippet:begin separable
        const vkf::Stats separableMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            dispatch(cmd, rows, layout, rowsSet, size, size);
            vkf::imageBarrier(
                cmd, middle, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_GENERAL,
                VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_READ_BIT);
            dispatch(cmd, columns, layout, columnsSet, size, size);
        });
        // snippet:end separable
        const vkf::Stats rowsMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            dispatch(cmd, rows, layout, rowsSet, size, size);
        });
        const vkf::Stats columnsMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            dispatch(cmd, columns, layout, columnsSet, size, size);
        });
        const vkf::Stats naiveMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            dispatch(cmd, naive2d, layout, naiveSet, size, size);
        });

        const std::vector<float> expected =
            blurReference(pattern, int(size), int(size), weights);
        const std::vector<float> separableResult =
            toFloats(vkf::downloadImage(ctx, blurred, VK_IMAGE_LAYOUT_GENERAL));
        const std::vector<float> naiveResult =
            toFloats(vkf::downloadImage(ctx, naive, VK_IMAGE_LAYOUT_GENERAL));
        const double blurTolerance = 1e-4;
        const double separableError = maxError(separableResult, expected);
        const double naiveError = maxError(naiveResult, expected);

        // snippet:begin sampled
        const uint32_t small = size * 3 / 8;
        const std::vector<uint8_t> pattern8 = toBytes(pattern);
        vkf::Image sampled = vkf::createImage(
            ctx,
            {.format = VK_FORMAT_R8G8B8A8_UNORM,
             .width = size,
             .height = size,
             .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT},
            "sampled source");
        vkf::uploadImage(ctx, sampled, pattern8.data(), pattern8.size(),
                         VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        vkf::Image downscaled = vkf::createImage(
            ctx,
            {.format = VK_FORMAT_R8G8B8A8_UNORM,
             .width = small,
             .height = small,
             .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
            "downscaled");
        auto sampler = createLinearSampler(ctx);
        auto sampledSetLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        auto sampledLayout = vkf::createPipelineLayout(ctx, {sampledSetLayout.get()});
        auto downscale = u2::loadPipeline(ctx, sampledLayout, "downscale.comp");
        VkDescriptorSet sampledSet = pool.allocate(sampledSetLayout);
        vkf::DescriptorWriter()
            .image(0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, sampled.view,
                   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, sampler)
            .image(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, downscaled.view,
                   VK_IMAGE_LAYOUT_GENERAL)
            .update(ctx, sampledSet);
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            vkf::imageBarrier(cmd, downscaled, VK_IMAGE_LAYOUT_UNDEFINED,
                              VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_2_NONE,
                              VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                              VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
            dispatch(cmd, downscale, sampledLayout, sampledSet, small, small);
        });
        // snippet:end sampled
        const std::vector<uint8_t> downscaledBytes =
            vkf::downloadImage(ctx, downscaled, VK_IMAGE_LAYOUT_GENERAL);
        std::vector<float> downscaledValues(downscaledBytes.size());
        for (size_t i = 0; i < downscaledBytes.size(); ++i) {
            downscaledValues[i] = downscaledBytes[i] / 255.0f;
        }
        const double samplerTolerance = 1.0 / (1u << limits.subTexelPrecisionBits) + 2.0 / 255;
        const double samplerError = maxError(
            downscaledValues,
            bilinearReference(pattern8, int(size), int(size), int(small), int(small)));

        const std::string inputPng = out + "blur_input.png";
        const std::string blurPng = out + "blur_separable.png";
        const std::string smallPng = out + "blur_downscaled.png";
        vkf::writePng(inputPng, size, size, pattern8);
        vkf::writePng(blurPng, size, size, toBytes(separableResult));
        vkf::writePng(smallPng, small, small, downscaledBytes);

        const double pixels = double(size) * size;
        vkf::print(
            "{0} x {0} rgba32f image, Gaussian radius {1} ({2} taps); median of {3} runs\n\n",
            size, radius, 2 * radius + 1, runs);
        vkf::print("{:<34}{:>8}{:>11}{:>12}\n", "blur", "ms", "Mpixel/s", "max error");
        vkf::print("{:<34}{:>8.3f}{:>11.1f}{:>12.1e}\n", "separable, two tiled passes",
                   separableMs.median, pixels / (separableMs.median * 1e3), separableError);
        vkf::print("{:<34}{:>8.3f}{:>11.1f}\n", "  the rows pass alone", rowsMs.median,
                   pixels / (rowsMs.median * 1e3));
        vkf::print("{:<34}{:>8.3f}{:>11.1f}\n", "  the columns pass alone", columnsMs.median,
                   pixels / (columnsMs.median * 1e3));
        vkf::print(
            "{:<34}{:>8.3f}{:>11.1f}{:>12.1e}\n",
            std::format("naive 2D kernel, {} taps", (2 * radius + 1) * (2 * radius + 1)),
            naiveMs.median, pixels / (naiveMs.median * 1e3), naiveError);
        vkf::print(
            "bilinear downscale to {0} x {0} through a sampler: max error {1:.4f} "
            "(tolerance {2:.4f})\n",
            small, samplerError, samplerTolerance);
        vkf::print("wrote {}, {} and {}\n", inputPng, blurPng, smallPng);
        u2::finish(separableError < blurTolerance && naiveError < blurTolerance &&
                       samplerError < samplerTolerance,
                   "blur: both blurs and the downscale match the CPU references");
    });
}
