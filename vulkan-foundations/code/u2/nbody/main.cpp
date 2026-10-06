#include <vkf/vkf.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <format>
#include <numbers>
#include <random>
#include <span>
#include <stdexcept>
#include <vector>

#include "u2.hpp"

namespace {

// snippet:begin push
struct Push {
    VkDeviceAddress positions;
    VkDeviceAddress velocities;
    VkDeviceAddress accelerations;
    VkDeviceAddress potentials;
    VkDeviceAddress params;
    float dt;
    float halfDt;
    float softening2;
};

struct PreparePush {
    VkDeviceAddress params;
    VkDeviceAddress dispatch;
    uint32_t localSize;
    uint32_t maxGroupsX;
};
// snippet:end push

struct Particles {
    std::vector<float> positions;
    std::vector<float> velocities;
};

// snippet:begin plummer
// Aarseth, Henon and Wielen (1974): radii from the cumulative mass, speeds by rejection.
Particles plummer(uint32_t n) {
    std::mt19937 rng(29);
    std::uniform_real_distribution<double> uniform(0.0, 1.0);
    auto direction = [&] {
        const double z = 2 * uniform(rng) - 1, phi = 2 * std::numbers::pi * uniform(rng);
        const double s = std::sqrt(1 - z * z);
        return std::array<double, 3>{s * std::cos(phi), s * std::sin(phi), z};
    };
    std::vector<std::array<double, 6>> state(n);
    std::array<double, 6> mean{};
    for (auto& particle : state) {
        double r = 0, q = 0, y = 0;
        do {
            r = 1 / std::sqrt(std::pow(uniform(rng), -2.0 / 3.0) - 1);
        } while (r > 10);
        do {
            q = uniform(rng);
            y = 0.1 * uniform(rng);
        } while (y > q * q * std::pow(1 - q * q, 3.5));
        const double speed = q * std::sqrt(2.0) * std::pow(1 + r * r, -0.25);
        const auto position = direction(), velocity = direction();
        for (int c = 0; c < 3; ++c) {
            particle[c] = r * position[c];
            particle[3 + c] = speed * velocity[c];
        }
        for (int c = 0; c < 6; ++c) mean[c] += particle[c] / n;
    }
    Particles p{std::vector<float>(4 * size_t(n)), std::vector<float>(4 * size_t(n))};
    for (uint32_t i = 0; i < n; ++i) {
        for (int c = 0; c < 3; ++c) {
            p.positions[4 * i + c] = float(state[i][c] - mean[c]);
            p.velocities[4 * i + c] = float(state[i][3 + c] - mean[3 + c]);
        }
        p.positions[4 * i + 3] = 1.0f / n;
    }
    return p;
}
// snippet:end plummer

// snippet:begin energy
double energy(std::span<const float> positions, std::span<const float> velocities,
              std::span<const float> potentials) {
    double kinetic = 0, potential = 0;
    for (size_t i = 0; i < potentials.size(); ++i) {
        const double mass = positions[4 * i + 3];
        const double vx = velocities[4 * i], vy = velocities[4 * i + 1],
                     vz = velocities[4 * i + 2];
        kinetic += 0.5 * mass * (vx * vx + vy * vy + vz * vz);
        potential += 0.5 * mass * potentials[i];
    }
    return kinetic + potential;
}
// snippet:end energy

struct Result {
    double startEnergy = 0;
    double endEnergy = 0;
    double ms = 0;
    std::array<uint32_t, 3> groups{};
    std::vector<float> positions;
};

class Simulation {
public:
    Simulation(const vkf::Context& ctx, uint32_t n, uint32_t localSize);
    Result run(uint32_t steps, float dt, uint32_t maxGroupsX);

private:
    const vkf::Context& ctx_;
    uint32_t n_, localSize_;
    Particles initial_;
    vkf::Buffer positions_, velocities_, accelerations_, potentials_, params_, dispatch_;
    vkf::Unique<VkPipelineLayout> layout_, prepareLayout_;
    vkf::Unique<VkPipeline> prepare_, forces_, drift_, potential_;
};

Simulation::Simulation(const vkf::Context& ctx, uint32_t n, uint32_t localSize)
    : ctx_(ctx), n_(n), localSize_(localSize), initial_(plummer(n)) {
    // snippet:begin buffers
    const VkBufferUsageFlags usage = VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    auto buffer = [&](VkDeviceSize bytes, VkBufferUsageFlags extra, const char* name) {
        return vkf::createBuffer(ctx, bytes, usage | extra, vkf::MemoryUse::DeviceLocal, name);
    };
    const VkDeviceSize vec4s = VkDeviceSize(n) * 4 * sizeof(float);
    positions_ = buffer(vec4s, 0, "positions");
    velocities_ = buffer(vec4s, 0, "velocities");
    accelerations_ = buffer(vec4s, 0, "accelerations");
    potentials_ = buffer(VkDeviceSize(n) * sizeof(float), 0, "potentials");
    params_ = buffer(sizeof(uint32_t), 0, "params");
    dispatch_ = buffer(sizeof(VkDispatchIndirectCommand), VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT,
                       "dispatch");
    // snippet:end buffers

    const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
    const VkPushConstantRange prepareRange{VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                           sizeof(PreparePush)};
    layout_ = vkf::createPipelineLayout(ctx, {}, {range});
    prepareLayout_ = vkf::createPipelineLayout(ctx, {}, {prepareRange});
    vkf::Specialization spec;
    spec.set(0, localSize);
    prepare_ = u2::loadPipeline(ctx, prepareLayout_, "prepare.comp");
    forces_ = u2::loadPipeline(ctx, layout_, "forces.comp", spec);
    drift_ = u2::loadPipeline(ctx, layout_, "drift.comp", spec);
    potential_ = u2::loadPipeline(ctx, layout_, "potential.comp", spec);
}

Result Simulation::run(uint32_t steps, float dt, uint32_t maxGroupsX) {
    vkf::upload(ctx_, positions_, std::span<const float>(initial_.positions));
    vkf::upload(ctx_, velocities_, std::span<const float>(initial_.velocities));
    vkf::upload(ctx_, params_, &n_, sizeof(n_));

    const float softening = 0.05f;
    const Push step{positions_.address,  velocities_.address,  accelerations_.address,
                    potentials_.address, params_.address,      dt,
                    0.5f * dt,           softening * softening};
    Push start = step;
    start.halfDt = 0.0f;
    const PreparePush prepare{params_.address, dispatch_.address, localSize_, maxGroupsX};
    auto dispatch = [&](VkCommandBuffer cmd, VkPipeline pipeline, const Push& push) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdPushConstants(cmd, layout_, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
        vkCmdDispatchIndirect(cmd, dispatch_, 0);
    };
    auto measureEnergy = [&] {
        vkf::submitNow(ctx_, [&](VkCommandBuffer cmd) { dispatch(cmd, potential_, step); });
        return energy(vkf::download<float>(ctx_, positions_, 4 * size_t(n_)),
                      vkf::download<float>(ctx_, velocities_, 4 * size_t(n_)),
                      vkf::download<float>(ctx_, potentials_, n_));
    };

    // snippet:begin indirect
    vkf::submitNow(ctx_, [&](VkCommandBuffer cmd) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, prepare_);
        vkCmdPushConstants(cmd, prepareLayout_, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                           sizeof(prepare), &prepare);
        vkCmdDispatch(cmd, 1, 1, 1);
        vkf::memoryBarrier(
            cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT, VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT);
        dispatch(cmd, forces_, start);
    });
    // snippet:end indirect
    Result result;
    const auto groups = vkf::download<uint32_t>(ctx_, dispatch_, 3);
    std::copy(groups.begin(), groups.end(), result.groups.begin());
    result.startEnergy = measureEnergy();

    // snippet:begin steps
    vkf::GpuTimer timer(ctx_, 2);
    vkf::submitNow(ctx_, [&](VkCommandBuffer cmd) {
        timer.reset(cmd);
        timer.stamp(cmd);
        for (uint32_t s = 0; s < steps; ++s) {
            dispatch(cmd, drift_, step);
            u2::computeBarrier(cmd);
            dispatch(cmd, forces_, step);
            u2::computeBarrier(cmd);
        }
        timer.stamp(cmd);
    });
    // snippet:end steps
    result.ms = timer.elapsedMs(0, 1);
    result.endEnergy = measureEnergy();
    result.positions = vkf::download<float>(ctx_, positions_, 4 * size_t(n_));
    return result;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 16384));
        const auto steps = static_cast<uint32_t>(args.integer("--steps", 200));
        const auto dt = static_cast<float>(args.number("--dt", 0.01));
        const auto forcedLimit = static_cast<uint32_t>(args.integer("--max-groups", 0));
        const double tolerance = 1e-4;
        if (n < 2 || steps == 0) {
            throw std::runtime_error("--n must be at least 2 and --steps positive");
        }
        vkf::Context ctx({.appName = "u2_nbody"});
        if (!ctx.features().v12.bufferDeviceAddress) {
            throw std::runtime_error("u2_nbody needs the bufferDeviceAddress feature");
        }
        const uint32_t localSize = 256;
        const uint32_t deviceLimit = ctx.properties().core.limits.maxComputeWorkGroupCount[0];

        Simulation simulation(ctx, n, localSize);
        const Result r = simulation.run(steps, dt, deviceLimit);
        const double drift = std::abs((r.endEnergy - r.startEnergy) / r.startEnergy);
        const double interactions = double(n) * n * steps;
        vkf::print("{} particles in a Plummer sphere; {} leapfrog steps of {}\n", n, steps,
                   dt);
        vkf::print("indirect dispatch from a GPU-side count: {} x {} x {} workgroups of {}\n",
                   r.groups[0], r.groups[1], r.groups[2], localSize);
        vkf::print("{:.3f} ms per step, {:.1f} billion interactions per second\n",
                   r.ms / steps, interactions / (r.ms * 1e6));
        vkf::print("total energy {:.7f} at the start, {:.7f} at the end\n", r.startEnergy,
                   r.endEnergy);
        vkf::print("relative energy drift {:.2e} (limit {:.0e})\n", drift, tolerance);

        bool identical = true;
        if (forcedLimit != 0) {
            // snippet:begin forced
            const Result forced = simulation.run(steps, dt, forcedLimit);
            identical = forced.positions == r.positions;
            vkf::print(
                "maxComputeWorkGroupCount[0] forced to {}: {} x {} x {} workgroups, "
                "{} positions\n",
                forcedLimit, forced.groups[0], forced.groups[1], forced.groups[2],
                identical ? "bit-identical" : "DIFFERENT");
            // snippet:end forced
        }
        u2::finish(drift < tolerance && identical,
                   std::format("nbody: energy conserved to {:.1e}", drift));
    });
}
