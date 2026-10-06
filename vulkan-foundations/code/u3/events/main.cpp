#include <vkf/vkf.hpp>

#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"

namespace {

constexpr uint32_t Threads = 256;
constexpr uint32_t Groups = Threads / 64;

struct StepsPush {
    uint32_t steps;
};

enum class Sync { BarrierAtSet, BarrierAtWait, Event };

struct Work {
    explicit Work(const vkf::Context& ctx)
        : spin(u3::makeKernel(
              ctx, "spin.comp",
              {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
              sizeof(StepsPush))),
          pool(ctx),
          seeds(buffer(ctx, "seeds")),
          x(buffer(ctx, "x")),
          y(buffer(ctx, "y")),
          z(buffer(ctx, "z")),
          a(u3::bufferSet(ctx, pool, spin, {seeds, x})),
          b(u3::bufferSet(ctx, pool, spin, {seeds, y})),
          c(u3::bufferSet(ctx, pool, spin, {x, z})) {
        std::vector<uint32_t> values(Threads);
        for (uint32_t i = 0; i < Threads; ++i) values[i] = 7 * i + 1;
        vkf::upload(ctx, seeds, std::span<const uint32_t>(values));
    }

    static vkf::Buffer buffer(const vkf::Context& ctx, const char* name) {
        return vkf::createBuffer(ctx, Threads * 4,
                                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                 vkf::MemoryUse::DeviceLocal, name);
    }

    u3::Kernel spin;
    vkf::DescriptorPool pool;
    vkf::Buffer seeds, x, y, z;
    VkDescriptorSet a, b, c;
};

// snippet:begin split
void record(VkCommandBuffer cmd, const Work& w, VkEvent event, Sync sync, uint32_t steps) {
    const VkMemoryBarrier2 produced{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &produced,
    };
    u3::dispatch(cmd, w.spin, w.a, StepsPush{steps}, Groups);
    if (sync == Sync::Event) vkCmdSetEvent2(cmd, event, &dependency);
    if (sync == Sync::BarrierAtSet) vkCmdPipelineBarrier2(cmd, &dependency);
    u3::dispatch(cmd, w.spin, w.b, StepsPush{2 * steps}, Groups);
    if (sync == Sync::Event) vkCmdWaitEvents2(cmd, 1, &event, &dependency);
    if (sync == Sync::BarrierAtWait) vkCmdPipelineBarrier2(cmd, &dependency);
    u3::dispatch(cmd, w.spin, w.c, StepsPush{steps}, Groups);
}
// snippet:end split

// snippet:begin event
vkf::Unique<VkEvent> createEvent(const vkf::Context& ctx) {
    // Device-only events are never set, reset or read by the host, which helps some drivers.
    const VkEventCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_EVENT_CREATE_INFO,
        .flags = VK_EVENT_CREATE_DEVICE_ONLY_BIT,
    };
    VkEvent event = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateEvent(ctx.device(), &info, nullptr, &event));
    return {ctx.device(), event};
}
// snippet:end event

bool verify(const vkf::Context& ctx, const Work& w, uint32_t steps) {
    const auto x = vkf::download<uint32_t>(ctx, w.x, Threads);
    const auto y = vkf::download<uint32_t>(ctx, w.y, Threads);
    const auto z = vkf::download<uint32_t>(ctx, w.z, Threads);
    for (uint32_t i = 0; i < Threads; ++i) {
        const uint32_t seed = 7 * i + 1;
        if (x[i] != u3::lcgJump(seed, steps) || y[i] != u3::lcgJump(seed, 2ull * steps) ||
            z[i] != u3::lcgJump(x[i], steps)) {
            return false;
        }
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto steps = uint32_t(args.integer("--steps", 100000));
        const auto repeats = int(args.integer("--repeats", 10));
        vkf::Context ctx({.appName = "u3_events"});
        const Work work(ctx);
        vkf::GpuTimer timer(ctx, 2);

        struct Variant {
            Sync sync;
            const char* name;
        };
        const Variant variants[] = {
            {Sync::BarrierAtSet, "barrier where the set goes (B waits for A)"},
            {Sync::BarrierAtWait, "barrier where the wait goes (C waits for B)"},
            {Sync::Event, "split barrier with an event (C waits for A)"},
        };
        vkf::print("A: {} threads, {} steps; B: independent, {} steps; C: reads A's output\n",
                   Threads, steps, 2 * steps);
        bool ok = true;
        for (const Variant& v : variants) {
            std::vector<double> samples;
            for (int r = 0; r <= repeats; ++r) {
                const auto event =
                    v.sync == Sync::Event ? createEvent(ctx) : vkf::Unique<VkEvent>();
                vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
                    timer.reset(cmd);
                    timer.stamp(cmd);
                    record(cmd, work, event, v.sync, steps);
                    timer.stamp(cmd);
                });
                if (r > 0) samples.push_back(timer.read()[1]);
            }
            const bool correct = verify(ctx, work, steps);
            ok = ok && correct;
            vkf::print("  {:<46} {:7.3f} ms{}\n", v.name, vkf::summarize(samples).median,
                       correct ? "" : "  WRONG");
        }
        if (!ok) throw std::runtime_error("results differ from the CPU");
        vkf::print("PASS: every variant matches the CPU (GPU time, median of {} runs)\n",
                   repeats);
    });
}
