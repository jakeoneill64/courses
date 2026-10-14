#include <vkf/vkf.hpp>

#include <algorithm>
#include <cmath>
#include <format>
#include <fstream>
#include <random>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "u2.hpp"

namespace {

constexpr uint32_t localSize = 256;  // must equal local_size_x in every shader here

struct CountPush {
    uint32_t count;
};

struct RooflinePush {
    float a;
    float b;
    uint32_t count;
};

struct RooflinePoint {
    uint32_t fmas;
    double ms;
    double gflops;
    double gbps;
};

bool rooflineCorrect(std::span<const float> out, std::span<const float> in, RooflinePush p,
                     uint32_t fmas) {
    const double scale = std::pow(double(p.a), fmas);
    const double offset = double(p.b) * (1 - scale) / (1 - double(p.a));
    for (size_t i = 0; i < out.size(); ++i) {
        if (std::abs(out[i] - (scale * in[i] + offset)) > 2e-4) return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto mib = static_cast<uint32_t>(args.integer("--mib", 128));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        const std::string csv = args.text("--csv", "");
        if (mib < 64 || mib > 1024) throw std::runtime_error("--mib must be from 64 to 1024");
        vkf::Context ctx({.appName = "u2_bandwidth"});
        const uint32_t maxGroups = ctx.properties().core.limits.maxComputeWorkGroupCount[0];

        const uint32_t count = mib << 18;
        const VkDeviceSize bytes = VkDeviceSize(count) * sizeof(float);
        std::vector<float> input(count);
        std::mt19937 rng(23);
        std::uniform_real_distribution<float> uniform(0.0f, 1.0f);
        for (float& v : input) v = uniform(rng);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        vkf::Buffer src =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "src");
        vkf::Buffer dst =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "dst");
        vkf::upload(ctx, src, std::span<const float>(input));

        auto setLayout = u2::storageBufferLayout(ctx, 2);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(RooflinePush)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "src dst");
        u2::writeStorageBuffers(ctx, set, {src, dst});
        auto record = [&](VkCommandBuffer cmd, VkPipeline pipeline, const void* push,
                          uint32_t pushBytes, uint32_t items) {
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                    nullptr);
            vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, pushBytes, push);
            vkCmdDispatch(cmd, std::min(vkf::groupCount(items, localSize), maxGroups), 1, 1);
        };
        auto output = [&](uint32_t n) { return vkf::download<float>(ctx, dst, n); };
        int checks = 0, correct = 0;
        auto tally = [&](bool ok) {
            ++checks;
            correct += ok ? 1 : 0;
            return ok ? "exact" : "WRONG";
        };

        // snippet:begin copies
        const CountPush all{count};
        auto copyFloat = u2::loadPipeline(ctx, layout, "copy_float.comp");
        auto copyVec4 = u2::loadPipeline(ctx, layout, "copy_vec4.comp");
        const vkf::Stats copyBuffer = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            const VkBufferCopy region{.srcOffset = 0, .dstOffset = 0, .size = bytes};
            vkCmdCopyBuffer(cmd, src, dst, 1, &region);
        });
        const bool copyBufferOk = output(count) == input;
        const vkf::Stats floats = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            record(cmd, copyFloat, &all, sizeof(all), count);
        });
        const bool floatsOk = output(count) == input;
        const vkf::Stats vec4s = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
            record(cmd, copyVec4, &all, sizeof(all), count / 4);
        });
        const bool vec4sOk = output(count) == input;
        // snippet:end copies
        vkf::print("copies of {} MiB; median of {} runs\n", mib, runs);
        vkf::print("{:<28}{:>8}{:>9}   result\n", "copy", "ms", "GB/s");
        double peakGbps = 0;
        const std::pair<const char*, std::pair<const vkf::Stats*, bool>> copies[] = {
            {"vkCmdCopyBuffer", {&copyBuffer, copyBufferOk}},
            {"shader, float loads", {&floats, floatsOk}},
            {"shader, vec4 loads", {&vec4s, vec4sOk}},
        };
        for (const auto& [label, result] : copies) {
            const double gbps = u2::gbPerSecond(2.0 * bytes, result.first->median);
            peakGbps = std::max(peakGbps, gbps);
            vkf::print("{:<28}{:>8.3f}{:>9.1f}   {}\n", label, result.first->median, gbps,
                       tally(result.second));
        }

        const uint32_t part = std::min(count, 1u << 24);
        vkf::print(
            "\nstrided reads of {} MiB: neighbouring invocations read floats a stride "
            "apart\n",
            part >> 18);
        vkf::print("{:>6}{:>10}{:>9}   result\n", "stride", "ms", "GB/s");
        for (uint32_t stride = 1; stride <= 32; stride *= 2) {
            vkf::Specialization spec;
            spec.set(0, stride);
            auto strided = u2::loadPipeline(ctx, layout, "strided.comp", spec);
            const CountPush push{part};
            const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                record(cmd, strided, &push, sizeof(push), part);
            });
            const std::vector<float> result = output(part);
            const uint32_t rows = part / stride;
            bool ok = true;
            for (uint32_t i = 0; i < part && ok; ++i) {
                ok = result[i] == input[(i % rows) * stride + i / rows];
            }
            vkf::print("{:>6}{:>10.3f}{:>9.1f}   {}\n", stride, ms.median,
                       u2::gbPerSecond(2.0 * part * sizeof(float), ms.median), tally(ok));
        }

        vkf::print("\nroofline: {} floats, each read, put through k FMAs and written\n", part);
        vkf::print("{:>6}{:>11}{:>10}{:>10}{:>9}   result\n", "k", "FLOP/byte", "ms",
                   "GFLOP/s", "GB/s");
        const RooflinePush rooflinePush{0.999f, 0.001f, part};
        std::vector<RooflinePoint> points;
        for (uint32_t fmas = 1; fmas <= 1024; fmas *= 2) {
            // snippet:begin roofline-point
            vkf::Specialization spec;
            spec.set(0, fmas);
            auto kernel = u2::loadPipeline(ctx, layout, "roofline.comp", spec);
            const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                record(cmd, kernel, &rooflinePush, sizeof(rooflinePush), part / 4);
            });
            const double flops = 2.0 * fmas * part;
            const double moved = 2.0 * part * sizeof(float);
            points.push_back({fmas, ms.median, flops / (ms.median * 1e6),
                              u2::gbPerSecond(moved, ms.median)});
            // snippet:end roofline-point
            const bool ok = rooflineCorrect(output(part), std::span(input).first(part),
                                            rooflinePush, fmas);
            vkf::print("{:>6}{:>11.2f}{:>10.3f}{:>10.1f}{:>9.1f}   {}\n", fmas, flops / moved,
                       points.back().ms, points.back().gflops, points.back().gbps, tally(ok));
        }

        double peakGflops = 0;
        for (const RooflinePoint& p : points) peakGflops = std::max(peakGflops, p.gflops);
        vkf::print(
            "\nmeasured peaks: {:.1f} GB/s (best copy), {:.1f} GFLOP/s (best roofline "
            "point)\n",
            peakGbps, peakGflops);
        vkf::print("ridge point: {:.1f} FLOP/byte\n", peakGflops / peakGbps);
        if (!csv.empty()) {
            std::ofstream file(csv);
            file << "fmas_per_float,flop_per_byte,ms,gflops,gbps\n";
            for (const RooflinePoint& p : points) {
                file << std::format("{},{:.4f},{:.6f},{:.3f},{:.3f}\n", p.fmas, p.fmas / 4.0,
                                    p.ms, p.gflops, p.gbps);
            }
            vkf::print("wrote {}\n", csv);
        }
        u2::finish(correct == checks,
                   std::format("bandwidth: {} of {} results verified", correct, checks));
    });
}
