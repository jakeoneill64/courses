#include <vkf/vkf.hpp>

#include <algorithm>
#include <format>
#include <numeric>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include "u2.hpp"

namespace {

constexpr uint32_t tile = 16;  // must equal the local size in mandelbrot.comp

struct Push {
    float centre[2];
    float spacing;
    uint32_t maxIterations;
};

struct Kernel {
    vkf::Unique<VkDescriptorSetLayout> setLayout;
    vkf::Unique<VkPipelineLayout> layout;
    vkf::Unique<VkPipeline> pipeline;
};

struct Render {
    std::vector<uint32_t> counts;
    std::vector<uint32_t> subgroups;
    std::vector<uint8_t> pixels;
    double ms = 0;
};

// snippet:begin reference
uint32_t iterations(float cx, float cy, uint32_t maxIterations) {
    float zx = 0, zy = 0;
    uint32_t n = 0;
    while (n < maxIterations && zx * zx + zy * zy <= 256.0f) {
        const float x = zx * zx - zy * zy + cx;
        zy = 2.0f * zx * zy + cy;
        zx = x;
        ++n;
    }
    return n;
}
// snippet:end reference

Render render(const vkf::Context& ctx, const Kernel& kernel, uint32_t size, const Push& push,
              int runs) {
    vkf::Image picture = vkf::createImage(
        ctx,
        {.format = VK_FORMAT_R8G8B8A8_UNORM,
         .width = size,
         .height = size,
         .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
        "picture");
    const VkDeviceSize bytes = VkDeviceSize(size) * size * sizeof(uint32_t);
    const VkBufferUsageFlags usage =
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    vkf::Buffer counts =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "counts");
    vkf::Buffer subgroups =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "subgroups");
    vkf::DescriptorPool pool(ctx, 1, 4);
    VkDescriptorSet set = pool.allocate(kernel.setLayout);
    vkf::DescriptorWriter()
        .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, picture.view, VK_IMAGE_LAYOUT_GENERAL)
        .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, counts)
        .buffer(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, subgroups)
        .update(ctx, set);
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkf::imageBarrier(cmd, picture, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                          VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                          VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                          VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    });
    const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernel.pipeline);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernel.layout, 0, 1, &set,
                                0, nullptr);
        vkCmdPushConstants(cmd, kernel.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push),
                           &push);
        vkCmdDispatch(cmd, vkf::groupCount(size, tile), vkf::groupCount(size, tile), 1);
    });
    return {vkf::download<uint32_t>(ctx, counts, size_t(size) * size),
            vkf::download<uint32_t>(ctx, subgroups, size_t(size) * size),
            vkf::downloadImage(ctx, picture, VK_IMAGE_LAYOUT_GENERAL), ms.median};
}

// snippet:begin efficiency
double laneEfficiency(const Render& r, uint32_t size) {
    struct Subgroup {
        uint32_t slowest = 0;
        uint32_t lanes = 0;
    };
    std::unordered_map<uint64_t, Subgroup> subgroups;
    const uint64_t groupsPerRow = vkf::groupCount(size, tile);
    for (uint32_t y = 0; y < size; ++y) {
        for (uint32_t x = 0; x < size; ++x) {
            const uint64_t workgroup = (y / tile) * groupsPerRow + x / tile;
            const size_t i = size_t(y) * size + x;
            Subgroup& s = subgroups[workgroup * tile * tile + r.subgroups[i]];
            s.slowest = std::max(s.slowest, r.counts[i]);
            ++s.lanes;
        }
    }
    double executed = 0;
    for (const auto& [key, s] : subgroups) executed += double(s.slowest) * s.lanes;
    return std::accumulate(r.counts.begin(), r.counts.end(), 0.0) / executed;
}
// snippet:end efficiency

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto size = static_cast<uint32_t>(args.integer("--size", 1024));
        const auto maxIterations = static_cast<uint32_t>(args.integer("--iterations", 1024));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        const std::string out = args.text("--out", "");
        if (size < tile || maxIterations == 0) {
            throw std::runtime_error("--size must be at least 16 and --iterations positive");
        }
        vkf::Context ctx({.appName = "u2_mandelbrot"});

        Kernel kernel;
        kernel.setLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
        kernel.layout = vkf::createPipelineLayout(ctx, {kernel.setLayout.get()}, {range});
        kernel.pipeline = u2::loadPipeline(ctx, kernel.layout, "mandelbrot.comp");

        // snippet:begin check
        const uint32_t grid = 256;
        const Render check =
            render(ctx, kernel, grid, {{-0.5f, 0.0f}, 1.0f / 64, maxIterations}, 1);
        auto cpu = [&](uint32_t i, uint32_t j) {
            return iterations(-0.5f + (float(i) - 128) / 64, (float(j) - 128) / 64,
                              maxIterations);
        };
        uint32_t equal = 0;
        for (uint32_t j = 0; j < grid; ++j) {
            for (uint32_t i = 0; i < grid; ++i) {
                if (check.counts[j * grid + i] == cpu(i, j)) ++equal;
            }
        }
        struct Known {
            uint32_t i, j;
            bool inside;
        };
        const Known known[] = {{160, 128, true},  {96, 128, true},   {152, 136, true},
                               {192, 128, false}, {224, 128, false}, {32, 160, false}};
        bool knownOk = true;
        for (const Known& k : known) {
            const uint32_t n = check.counts[k.j * grid + k.i];
            knownOk = knownOk && (n == maxIterations) == k.inside && n == cpu(k.i, k.j);
        }
        // snippet:end check
        vkf::print("{0} x {0} check grid, at most {1} iterations\n", grid, maxIterations);
        vkf::print("  c = 0, -1 and -0.125+0.125i stay bounded for all {} iterations\n",
                   maxIterations);
        vkf::print("  c = 0.5, 1 and -2+0.5i escape after {}, {} and {} iterations\n",
                   check.counts[128 * grid + 192], check.counts[128 * grid + 224],
                   check.counts[160 * grid + 32]);
        vkf::print("  the known points: {}\n", knownOk ? "ok" : "WRONG");
        vkf::print("  iteration counts equal the CPU's for {} of {} pixels ({:.2f}%)\n\n",
                   equal, grid * grid, 100.0 * equal / (grid * grid));

        struct View {
            const char* label;
            float x, y, width;
        };
        const View views[] = {
            {"inside the main cardioid", -0.2f, 0.0f, 0.2f},
            {"seahorse valley (the boundary)", -0.745f, 0.11f, 0.02f},
            {"the whole set", -0.5f, 0.0f, 3.0f},
        };
        vkf::print("{0} x {0} views, at most {1} iterations; median of {2} runs\n", size,
                   maxIterations, runs);
        vkf::print("{:<32}{:>8}{:>10}{:>13}{:>10}\n", "view", "ms", "G iter/s", "iterations",
                   "lane use");
        std::vector<Render> renders;
        for (const View& view : views) {
            const Push push{{view.x, view.y}, view.width / size, maxIterations};
            Render r = render(ctx, kernel, size, push, runs);
            const double total = std::accumulate(r.counts.begin(), r.counts.end(), 0.0);
            vkf::print("{:<32}{:>8.3f}{:>10.1f}{:>13.0f}{:>9.1f}%\n", view.label, r.ms,
                       total / (r.ms * 1e6), total, 100.0 * laneEfficiency(r, size));
            renders.push_back(std::move(r));
        }
        const std::string boundaryPng = out + "mandelbrot_boundary.png";
        const std::string wholePng = out + "mandelbrot.png";
        vkf::writePng(boundaryPng, size, size, renders[1].pixels);
        vkf::writePng(wholePng, size, size, renders[2].pixels);
        vkf::print("wrote {} and {}\n", wholePng, boundaryPng);

        const bool countsOk = equal >= grid * grid * 99 / 100;
        u2::finish(knownOk && countsOk, "mandelbrot: known points and iteration counts match");
    });
}
