#include <vkf/vkf.hpp>

#include <algorithm>
#include <cmath>
#include <functional>
#include <random>
#include <stdexcept>
#include <vector>

namespace {

vkf::Unique<VkDescriptorSetLayout> storageLayout(const vkf::Context& ctx, uint32_t bindings) {
    vkf::DescriptorSetLayoutBuilder builder;
    for (uint32_t b = 0; b < bindings; ++b) {
        builder.add(b, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
    }
    return builder.build(ctx);
}

VkDescriptorSet bind(const vkf::Context& ctx, vkf::DescriptorPool& pool,
                     VkDescriptorSetLayout layout, std::initializer_list<VkBuffer> buffers) {
    VkDescriptorSet set = pool.allocate(layout);
    vkf::DescriptorWriter writer;
    uint32_t binding = 0;
    for (VkBuffer b : buffers) writer.buffer(binding++, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, b);
    writer.update(ctx, set);
    return set;
}

// snippet:begin kernel
struct Kernel {
    vkf::Unique<VkPipelineLayout> layout;
    vkf::Unique<VkPipeline> pipeline;

    Kernel(const vkf::Context& ctx, VkDescriptorSetLayout set, uint32_t pushBytes,
           const char* shader) {
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, pushBytes};
        layout = vkf::createPipelineLayout(ctx, {set}, {range});
        auto module = vkf::loadShader(ctx, vkf::shaderPath(shader));
        pipeline = vkf::createComputePipeline(
            ctx, {.layout = layout.get(), .module = module.get(), .name = shader});
    }

    template <class Push>
    void record(VkCommandBuffer cmd, VkDescriptorSet set, const Push& push, uint32_t x,
                uint32_t y) const {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.get());
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout.get(), 0, 1, &set,
                                0, nullptr);
        vkCmdPushConstants(cmd, layout.get(), VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push),
                           &push);
        vkCmdDispatch(cmd, x, y, 1);
    }
};
// snippet:end kernel

double medianMs(const vkf::Context& ctx, int runs,
                const std::function<void(VkCommandBuffer)>& body) {
    vkf::GpuTimer timer(ctx, 2 * static_cast<uint32_t>(runs) + 2);
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        timer.reset(cmd);
        for (int i = 0; i < 3; ++i) body(cmd);
        for (int run = 0; run < runs; ++run) {
            vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                               VK_ACCESS_2_MEMORY_WRITE_BIT,
                               VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                               VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT);
            timer.stamp(cmd);
            body(cmd);
            timer.stamp(cmd);
        }
    });
    std::vector<double> ms;
    for (uint32_t r = 0; r < static_cast<uint32_t>(runs); ++r)
        ms.push_back(timer.elapsedMs(2 * r, 2 * r + 1));
    return vkf::summarize(ms).median;
}

std::vector<float> random(size_t n, unsigned seed, float scale = 1.0f) {
    std::mt19937 rng(seed);
    std::normal_distribution<float> normal(0.0f, scale);
    std::vector<float> v(n);
    for (float& x : v) x = normal(rng);
    return v;
}

constexpr VkBufferUsageFlags kUsage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                      VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                      VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

vkf::Buffer upload(const vkf::Context& ctx, const std::vector<float>& values) {
    vkf::Buffer b = vkf::createBuffer(ctx, values.size() * sizeof(float), kUsage);
    vkf::upload(ctx, b, std::span<const float>(values));
    return b;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool validate = args.flag("--validate");
        vkf::Context ctx({.appName = "AI Foundations kernels",
                          .validation = validate,
                          .syncValidation = validate});
        vkf::DescriptorPool pool(ctx);
        auto three = storageLayout(ctx, 3), two = storageLayout(ctx, 2),
             four = storageLayout(ctx, 4);
        int failures = 0;

        struct Sizes {
            uint32_t n, k, m;
        };
        Kernel naive(ctx, three.get(), sizeof(Sizes), "matmul_naive.comp");
        Kernel tiled(ctx, three.get(), sizeof(Sizes), "matmul_tiled.comp");
        Kernel blocked(ctx, three.get(), sizeof(Sizes), "matmul_blocked.comp");
        vkf::print("{:<20}{:>13}{:>13}{:>13}   (GFLOP/s)\n", "matrix product", "n = 1024",
                   "n = 2048", "n = 4096");
        std::vector<std::vector<double>> rates(3);
        for (uint32_t n : {1024u, 2048u, 4096u}) {
            const std::vector<float> a = random(size_t(n) * n, 1),
                                     b = random(size_t(n) * n, 2);
            vkf::Buffer ba = upload(ctx, a), bb = upload(ctx, b);
            vkf::Buffer bc = vkf::createBuffer(ctx, size_t(n) * n * sizeof(float), kUsage);
            VkDescriptorSet set = bind(ctx, pool, three.get(), {ba, bb, bc});
            const Sizes sizes{n, n, n};
            // snippet:begin dispatch
            const std::vector<std::pair<const Kernel*, uint32_t>> variants = {
                {&naive, vkf::groupCount(n, 16)},
                {&tiled, vkf::groupCount(n, 16)},
                {&blocked, vkf::groupCount(n, 64)}};
            // snippet:end dispatch
            for (size_t v = 0; v < variants.size(); ++v) {
                auto [kernel, groups] = variants[v];
                auto body = [&](VkCommandBuffer cmd) {
                    kernel->record(cmd, set, sizes, groups, groups);
                };
                vkf::submitNow(ctx, body);
                const std::vector<float> c = vkf::download<float>(ctx, bc, size_t(n) * n);
                std::mt19937 rng(7);
                double worst = 0.0;
                for (int s = 0; s < 64; ++s) {
                    size_t i = rng() % n, j = rng() % n;
                    double want = 0.0;
                    for (size_t p = 0; p < n; ++p) want += double(a[i * n + p]) * b[p * n + j];
                    worst = std::max(worst,
                                     std::abs(c[i * n + j] - want) / (std::abs(want) + 1.0));
                }
                if (worst > 1e-3) {
                    vkf::print("variant {} at n = {}: error {:.2e}\n", v, n, worst);
                    ++failures;
                }
                rates[v].push_back(2.0 * n * n * double(n) / (medianMs(ctx, 10, body) * 1e6));
            }
        }
        const char* names[] = {"naive", "tiled", "register-blocked"};
        for (size_t v = 0; v < 3; ++v) {
            vkf::print("{:<20}{:>13.0f}{:>13.0f}{:>13.0f}\n", names[v], rates[v][0],
                       rates[v][1], rates[v][2]);
        }

        const uint32_t rows = 4096, cols = 8192;
        const std::vector<float> x = random(size_t(rows) * cols, 3, 4.0f);
        vkf::Buffer bx = upload(ctx, x),
                    by = vkf::createBuffer(ctx, x.size() * sizeof(float), kUsage);
        Kernel softmax(ctx, two.get(), sizeof(uint32_t), "softmax.comp");
        VkDescriptorSet sset = bind(ctx, pool, two.get(), {bx, by});
        auto run = [&](VkCommandBuffer cmd) { softmax.record(cmd, sset, cols, rows, 1); };
        vkf::submitNow(ctx, run);
        const std::vector<float> y = vkf::download<float>(ctx, by, cols);
        double peak = *std::max_element(x.begin(), x.begin() + cols), total = 0.0, worst = 0.0;
        for (uint32_t i = 0; i < cols; ++i) total += std::exp(x[i] - peak);
        for (uint32_t i = 0; i < cols; ++i)
            worst = std::max(worst, std::abs(y[i] - std::exp(x[i] - peak) / total));
        failures += worst > 1e-6;
        const double ms = medianMs(ctx, 10, run);
        vkf::print("softmax over {} rows of {}: {:.0f} GB/s (largest error {:.1e})\n", rows,
                   cols, 2.0 * x.size() * sizeof(float) / (ms * 1e6), worst);

        struct Attention {
            uint32_t len;
            float scale;
        };
        Kernel flash(ctx, four.get(), sizeof(Attention), "flash.comp");
        const uint32_t heads = 8, head = 64;
        vkf::print("causal flash attention, {} heads of {}:\n", heads, head);
        for (uint32_t len : {512u, 1024u, 2048u, 4096u}) {
            const std::vector<float> q = random(size_t(heads) * len * head, 4),
                                     k = random(q.size(), 5), v = random(q.size(), 6);
            vkf::Buffer bq = upload(ctx, q), bk = upload(ctx, k), bv = upload(ctx, v);
            vkf::Buffer bo = vkf::createBuffer(ctx, q.size() * sizeof(float), kUsage);
            VkDescriptorSet aset = bind(ctx, pool, four.get(), {bq, bk, bv, bo});
            const Attention push{len, 1.0f / std::sqrt(float(head))};
            auto body = [&](VkCommandBuffer cmd) {
                flash.record(cmd, aset, push, vkf::groupCount(len, 64), heads);
            };
            vkf::submitNow(ctx, body);
            const std::vector<float> o = vkf::download<float>(ctx, bo, q.size());
            double err = 0.0;
            for (uint32_t row : {0u, len / 2, len - 1}) {
                std::vector<double> s(row + 1), out(head, 0.0);
                double best = -1e30, sum = 0.0;
                for (uint32_t j = 0; j <= row; ++j) {
                    double dot = 0.0;
                    for (uint32_t d = 0; d < head; ++d)
                        dot += double(q[row * head + d]) * k[j * head + d];
                    s[j] = dot * push.scale;
                    best = std::max(best, s[j]);
                }
                for (uint32_t j = 0; j <= row; ++j) sum += (s[j] = std::exp(s[j] - best));
                for (uint32_t j = 0; j <= row; ++j)
                    for (uint32_t d = 0; d < head; ++d) out[d] += s[j] / sum * v[j * head + d];
                for (uint32_t d = 0; d < head; ++d)
                    err = std::max(err, std::abs(o[row * head + d] - out[d]));
            }
            failures += err > 1e-4;
            vkf::print("  length {:4}: {:7.2f} ms (largest error {:.1e})\n", len,
                       medianMs(ctx, 5, body), err);
        }
        if (failures) throw std::runtime_error("a kernel's results are wrong");
        vkf::print("PASS every kernel matches its CPU reference\n");
    });
}
