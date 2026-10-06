#include <vkf/vkf.hpp>

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstring>
#include <format>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "bvh.hpp"
#include "reference.hpp"
#include "scene.hpp"
#include "u2.hpp"

namespace {

struct Push {
    uint32_t pass;
    uint32_t maxDepth;
    uint32_t useBvh;
};

struct DebugHit {
    float t;
    uint32_t id;
};

struct Shape {
    uint32_t x;
    uint32_t y;
};

struct Layouts {
    vkf::Unique<VkDescriptorSetLayout> set;
    vkf::Unique<VkPipelineLayout> pipeline;
};

Layouts createLayouts(const vkf::Context& ctx) {
    const VkShaderStageFlags compute = VK_SHADER_STAGE_COMPUTE_BIT;
    vkf::DescriptorSetLayoutBuilder builder;
    builder.add(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, compute);
    for (uint32_t b = 1; b <= 5; ++b) {
        builder.add(b, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, compute);
    }
    builder.add(6, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, compute)
        .add(7, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, compute)
        .add(8, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, compute)
        .add(9, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, compute);
    Layouts layouts{builder.build(ctx), {}};
    const VkPushConstantRange range{compute, 0, sizeof(Push)};
    layouts.pipeline = vkf::createPipelineLayout(ctx, {layouts.set.get()}, {range});
    return layouts;
}

vkf::Unique<VkPipeline> loadShaped(const vkf::Context& ctx, const Layouts& layouts,
                                   const char* shader, Shape shape) {
    vkf::Specialization spec;
    spec.set(0, shape.x).set(1, shape.y);
    return u2::loadPipeline(ctx, layouts.pipeline, shader, spec);
}

// Buffers for one scene, images for one render size, and the set that binds them.
class GpuScene {
public:
    GpuScene(const vkf::Context& ctx, const Layouts& layouts, vkf::DescriptorPool& pool,
             const rt::Scene& scene, uint32_t width, uint32_t height, uint32_t maxSamples);

    const rt::Camera camera;
    vkf::Buffer rayCounts, hits;
    vkf::Image accumulation, picture;
    VkDescriptorSet set = VK_NULL_HANDLE;

private:
    vkf::Buffer cameraBuffer_, materials_, spheres_, quads_, triangles_, nodes_;
};

template <class T>
vkf::Buffer uploadStorage(const vkf::Context& ctx, const std::vector<T>& values,
                          const char* name) {
    vkf::Buffer buffer = vkf::createBuffer(
        ctx, std::max<size_t>(values.size(), 1) * sizeof(T),
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, name);
    if (!values.empty()) vkf::upload(ctx, buffer, std::span<const T>(values));
    return buffer;
}

GpuScene::GpuScene(const vkf::Context& ctx, const Layouts& layouts, vkf::DescriptorPool& pool,
                   const rt::Scene& scene, uint32_t width, uint32_t height,
                   uint32_t maxSamples)
    : camera(rt::makeCamera(scene, width, height)) {
    cameraBuffer_ = vkf::createBuffer(
        ctx, sizeof(rt::Camera),
        VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vkf::MemoryUse::DeviceLocal, "camera");
    vkf::upload(ctx, cameraBuffer_, &camera, sizeof(camera));
    materials_ = uploadStorage(ctx, scene.materials, "materials");
    spheres_ = uploadStorage(ctx, scene.spheres, "spheres");
    quads_ = uploadStorage(ctx, scene.quads, "quads");
    triangles_ = uploadStorage(ctx, scene.triangles, "triangles");
    nodes_ = uploadStorage(ctx, scene.nodes, "nodes");
    const VkBufferUsageFlags readable = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                        VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                        VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    rayCounts = vkf::createBuffer(ctx, maxSamples * sizeof(uint32_t), readable,
                                  vkf::MemoryUse::DeviceLocal, "ray counts");
    hits = vkf::createBuffer(ctx, size_t(width) * height * sizeof(DebugHit), readable,
                             vkf::MemoryUse::DeviceLocal, "debug hits");
    const VkImageUsageFlags usage =
        VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    accumulation = vkf::createImage(ctx,
                                    {.format = VK_FORMAT_R32G32B32A32_SFLOAT,
                                     .width = width,
                                     .height = height,
                                     .usage = usage},
                                    "accumulation");
    picture = vkf::createImage(
        ctx,
        {.format = VK_FORMAT_R8G8B8A8_UNORM, .width = width, .height = height, .usage = usage},
        "picture");
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        for (VkImage image : {accumulation.image, picture.image}) {
            vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                              VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                              VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                              VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
        }
    });
    set = pool.allocate(layouts.set, "scene");
    vkf::DescriptorWriter()
        .buffer(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, cameraBuffer_)
        .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, materials_)
        .buffer(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, spheres_)
        .buffer(3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, quads_)
        .buffer(4, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, triangles_)
        .buffer(5, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, nodes_)
        .image(6, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, accumulation.view, VK_IMAGE_LAYOUT_GENERAL)
        .buffer(7, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, rayCounts)
        .buffer(8, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, hits)
        .image(9, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, picture.view, VK_IMAGE_LAYOUT_GENERAL)
        .update(ctx, set);
}

struct Render {
    double msPerPass = 0;
    double totalMs = 0;
    uint64_t rays = 0;
};

void bind(VkCommandBuffer cmd, const Layouts& layouts, VkPipeline pipeline,
          VkDescriptorSet set) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layouts.pipeline, 0, 1, &set,
                            0, nullptr);
}

Render render(const vkf::Context& ctx, const Layouts& layouts, GpuScene& gpu,
              VkPipeline pipeline, Shape shape, uint32_t samples, uint32_t depth, bool bvh) {
    const uint32_t batch = 32;
    std::vector<double> passMs;
    for (uint32_t first = 0; first < samples; first += batch) {
        const uint32_t last = std::min(samples, first + batch);
        vkf::GpuTimer timer(ctx, 2 * batch);
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            timer.reset(cmd);
            if (first == 0) {
                vkCmdFillBuffer(cmd, gpu.rayCounts, 0, VK_WHOLE_SIZE, 0);
                vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_CLEAR_BIT,
                                   VK_ACCESS_2_TRANSFER_WRITE_BIT,
                                   VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                   VK_ACCESS_2_SHADER_STORAGE_READ_BIT |
                                       VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
            }
            bind(cmd, layouts, pipeline, gpu.set);
            // snippet:begin passes
            for (uint32_t pass = first; pass < last; ++pass) {
                if (pass > 0) {
                    vkf::imageBarrier(cmd, gpu.accumulation, VK_IMAGE_LAYOUT_GENERAL,
                                      VK_IMAGE_LAYOUT_GENERAL,
                                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                      VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                                      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                      VK_ACCESS_2_SHADER_STORAGE_READ_BIT |
                                          VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
                }
                const Push push{pass, depth, bvh ? 1u : 0u};
                vkCmdPushConstants(cmd, layouts.pipeline, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                   sizeof(push), &push);
                timer.stamp(cmd);
                vkCmdDispatch(cmd, vkf::groupCount(gpu.camera.width, shape.x),
                              vkf::groupCount(gpu.camera.height, shape.y), 1);
                timer.stamp(cmd);
            }
            // snippet:end passes
        });
        for (uint32_t i = 0; i < last - first; ++i) {
            passMs.push_back(timer.elapsedMs(2 * i, 2 * i + 1));
        }
    }
    Render result;
    for (double ms : passMs) result.totalMs += ms;
    result.msPerPass = vkf::summarize(passMs).median;
    for (uint32_t count : vkf::download<uint32_t>(ctx, gpu.rayCounts, samples)) {
        result.rays += count;
    }
    return result;
}

// snippet:begin resolve-pass
std::vector<uint8_t> resolve(const vkf::Context& ctx, const Layouts& layouts, GpuScene& gpu,
                             VkPipeline pipeline) {
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkf::imageBarrier(
            cmd, gpu.accumulation, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_GENERAL,
            VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_READ_BIT);
        bind(cmd, layouts, pipeline, gpu.set);
        vkCmdDispatch(cmd, vkf::groupCount(gpu.camera.width, 8),
                      vkf::groupCount(gpu.camera.height, 8), 1);
    });
    return vkf::downloadImage(ctx, gpu.picture, VK_IMAGE_LAYOUT_GENERAL);
}
// snippet:end resolve-pass

std::vector<DebugHit> primaryHits(const vkf::Context& ctx, const Layouts& layouts,
                                  GpuScene& gpu, VkPipeline pipeline, Shape shape, bool bvh) {
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        bind(cmd, layouts, pipeline, gpu.set);
        const Push push{0, 0, bvh ? 1u : 0u};
        vkCmdPushConstants(cmd, layouts.pipeline, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push),
                           &push);
        vkCmdDispatch(cmd, vkf::groupCount(gpu.camera.width, shape.x),
                      vkf::groupCount(gpu.camera.height, shape.y), 1);
    });
    return vkf::download<DebugHit>(ctx, gpu.hits,
                                   size_t(gpu.camera.width) * gpu.camera.height);
}

struct PrimaryCheck {
    uint32_t agree = 0;
    uint32_t edges = 0;
    uint32_t wrong = 0;
    double largestDifference = 0;
};

// snippet:begin check-primary
PrimaryCheck checkPrimaryRays(const rt::Scene& scene, const rt::Camera& camera,
                              std::span<const DebugHit> hits) {
    const double margin = 1e-4, distanceTolerance = 1e-3;
    PrimaryCheck check;
    for (uint32_t y = 0; y < camera.height; ++y) {
        for (uint32_t x = 0; x < camera.width; ++x) {
            const DebugHit gpu = hits[y * camera.width + x];
            const rt::ReferenceRay ray = rt::primaryRay(camera, x, y);
            const rt::ReferenceHit exact = rt::closestHit(scene, ray, 0.0);
            bool acceptable = false;
            if (gpu.id == exact.id) {
                const double difference =
                    gpu.id == rt::missId ? 0 : std::abs(gpu.t - exact.t) / exact.t;
                check.largestDifference = std::max(check.largestDifference, difference);
                acceptable = difference <= distanceTolerance;
                if (acceptable) ++check.agree;
            } else {
                const rt::ReferenceHit shrunk = rt::closestHit(scene, ray, -margin);
                acceptable = shrunk.id == rt::missId;
                if (gpu.id != rt::missId) {
                    const double grown = rt::hitPrimitive(scene, gpu.id, ray, margin);
                    acceptable = std::abs(grown - gpu.t) <= distanceTolerance * gpu.t &&
                                 shrunk.t >= gpu.t * (1 - distanceTolerance);
                }
                if (acceptable) ++check.edges;
            }
            if (!acceptable) ++check.wrong;
        }
    }
    return check;
}
// snippet:end check-primary

struct Furnace {
    double mean = 0;
    double standardError = 0;
    double expected = 0;
    bool finite = true;
};

// snippet:begin furnace
Furnace furnaceStatistics(const vkf::Context& ctx, GpuScene& gpu, float albedo, float emission,
                          uint32_t depth) {
    const std::vector<uint8_t> bytes =
        vkf::downloadImage(ctx, gpu.accumulation, VK_IMAGE_LAYOUT_GENERAL);
    std::vector<float> sums(bytes.size() / sizeof(float));
    std::memcpy(sums.data(), bytes.data(), bytes.size());
    Furnace f;
    double total = 0, squares = 0;
    const size_t pixels = sums.size() / 4;
    for (size_t i = 0; i < pixels; ++i) {
        const double mean =
            (sums[4 * i] + sums[4 * i + 1] + sums[4 * i + 2]) / (3 * sums[4 * i + 3]);
        f.finite = f.finite && std::isfinite(mean);
        total += mean;
        squares += mean * mean;
    }
    f.mean = total / pixels;
    const double variance = (squares / pixels - f.mean * f.mean) * pixels / (pixels - 1);
    f.standardError = std::sqrt(std::max(variance, 0.0) / pixels);
    f.expected = emission * (1 - std::pow(albedo, depth)) / (1 - albedo);
    return f;
}
// snippet:end furnace

bool furnaceHolds(const Furnace& f) {
    return f.finite && std::abs(f.mean - f.expected) <= 5 * f.standardError &&
           f.standardError < 0.01 * f.expected;
}

void printFurnace(const Furnace& f) {
    vkf::print("  mean radiance {:.5f}, expected {:.5f}, standard error {:.1e}: {}\n", f.mean,
               f.expected, f.standardError, furnaceHolds(f) ? "ok" : "WRONG");
}

struct Options {
    uint32_t width, height, samples, depth;
    bool bvh;
    Shape shape;
    std::string scene;
    std::string out;
};

struct Pipelines {
    vkf::Unique<VkPipeline> render;
    vkf::Unique<VkPipeline> debug;
    vkf::Unique<VkPipeline> resolve;
};

const float albedo = 0.5f, emission = 0.5f;

bool runChecks(const vkf::Context& ctx, const Layouts& layouts, const Pipelines& pipelines,
               vkf::DescriptorPool& pool, const rt::Scene& showcase, const rt::Scene& furnace,
               const Options& o) {
    // snippet:begin checks
    GpuScene view(ctx, layouts, pool, showcase, 128, 72, 1);
    const auto withBvh = primaryHits(ctx, layouts, view, pipelines.debug, o.shape, true);
    const auto bruteForce = primaryHits(ctx, layouts, view, pipelines.debug, o.shape, false);
    const PrimaryCheck primary = checkPrimaryRays(showcase, view.camera, withBvh);
    uint32_t same = 0, ties = 0;
    for (size_t i = 0; i < withBvh.size(); ++i) {
        const bool sameT =
            std::bit_cast<uint32_t>(withBvh[i].t) == std::bit_cast<uint32_t>(bruteForce[i].t);
        if (sameT && withBvh[i].id == bruteForce[i].id) {
            ++same;
        } else if (sameT) {
            ++ties;
        }
    }
    // snippet:end checks
    const auto pixels = uint32_t(withBvh.size());
    vkf::print("check 1: primary rays at 128 x 72 against a double-precision CPU reference\n");
    vkf::print(
        "  {} agree (largest distance difference {:.1e}), {} at edges or ties, {} wrong\n",
        primary.agree, primary.largestDifference, primary.edges, primary.wrong);
    vkf::print("check 2: BVH and brute force agree on {} of {} primary rays ({} exact ties)\n",
               same + ties, pixels, ties);

    const uint32_t furnaceDepth = 16, furnaceSamples = 64;
    GpuScene closed(ctx, layouts, pool, furnace, 128, 72, furnaceSamples);
    render(ctx, layouts, closed, pipelines.render, o.shape, furnaceSamples, furnaceDepth,
           o.bvh);
    const Furnace f = furnaceStatistics(ctx, closed, albedo, emission, furnaceDepth);
    vkf::print(
        "check 3: white furnace, albedo {} and emission {}, at most {} bounces, {} "
        "samples\n",
        albedo, emission, furnaceDepth, furnaceSamples);
    printFurnace(f);
    return primary.wrong == 0 && primary.edges <= pixels / 100 && same + ties == pixels &&
           furnaceHolds(f);
}

void runBenchmark(const vkf::Context& ctx, const Layouts& layouts, const Pipelines& pipelines,
                  vkf::DescriptorPool& pool, const rt::Scene& scene, const Options& o) {
    struct Configuration {
        const char* label;
        Shape shape;
        uint32_t depth;
        bool bvh;
    };
    const Configuration configurations[] = {
        {"BVH, 8 x 8, full paths", {8, 8}, o.depth, true},
        {"BVH, 16 x 16, full paths", {16, 16}, o.depth, true},
        {"BVH, 64 x 1, full paths", {64, 1}, o.depth, true},
        {"BVH, 8 x 8, primary rays only", {8, 8}, 1, true},
        {"brute force, 8 x 8, full paths", {8, 8}, o.depth, false},
    };
    vkf::print("\n{} x {}, {} samples per configuration\n", o.width, o.height, o.samples);
    vkf::print("{:<34}{:>11}{:>14}{:>11}\n", "configuration", "ms/pass", "rays/pass",
               "Mrays/s");
    GpuScene gpu(ctx, layouts, pool, scene, o.width, o.height, std::max(o.samples, 16u));
    render(ctx, layouts, gpu, pipelines.render, o.shape, 16, o.depth, true);
    for (const Configuration& c : configurations) {
        const auto pipeline = loadShaped(ctx, layouts, "render.comp", c.shape);
        const Render r =
            render(ctx, layouts, gpu, pipeline, c.shape, o.samples, c.depth, c.bvh);
        vkf::print("{:<34}{:>11.3f}{:>14.0f}{:>11.1f}\n", c.label, r.msPerPass,
                   double(r.rays) / o.samples, r.rays / (r.totalMs * 1e3));
    }
}

bool renderImage(const vkf::Context& ctx, const Layouts& layouts, const Pipelines& pipelines,
                 vkf::DescriptorPool& pool, const rt::Scene& scene, const Options& o) {
    GpuScene gpu(ctx, layouts, pool, scene, o.width, o.height, o.samples);
    const Render r =
        render(ctx, layouts, gpu, pipelines.render, o.shape, o.samples, o.depth, o.bvh);
    const std::vector<uint8_t> image = resolve(ctx, layouts, gpu, pipelines.resolve);
    const std::string png =
        o.out + (o.scene == "furnace" ? "raytrace-furnace.png" : "raytrace.png");
    vkf::writePng(png, o.width, o.height, image);
    vkf::print(
        "\nrender: {} x {}, {} samples, at most {} bounces, BVH {}, workgroups of {} x {}\n",
        o.width, o.height, o.samples, o.depth, o.bvh ? "on" : "off", o.shape.x, o.shape.y);
    vkf::print("  {:.3f} ms per pass (median), {:.0f} rays per pass, {:.1f} Mrays/s\n",
               r.msPerPass, double(r.rays) / o.samples, r.rays / (r.totalMs * 1e3));
    bool ok = true;
    if (o.scene == "furnace") {
        const Furnace f = furnaceStatistics(ctx, gpu, albedo, emission, o.depth);
        printFurnace(f);
        ok = furnaceHolds(f);
    }
    vkf::print("wrote {}\n", png);
    return ok;
}

Shape parseShape(const std::string& text) {
    const size_t x = text.find('x');
    if (x == std::string::npos) throw std::runtime_error("--local takes WxH, such as 8x8");
    return {uint32_t(std::stoul(text.substr(0, x))), uint32_t(std::stoul(text.substr(x + 1)))};
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool benchmark = args.flag("--benchmark");
        const Options o{
            .width = static_cast<uint32_t>(args.integer("--width", 640)),
            .height = static_cast<uint32_t>(args.integer("--height", 360)),
            .samples = static_cast<uint32_t>(args.integer("--spp", benchmark ? 8 : 64)),
            .depth = static_cast<uint32_t>(args.integer("--depth", 8)),
            .bvh = args.text("--bvh", "on") != "off",
            .shape = parseShape(args.text("--local", "8x8")),
            .scene = args.text("--scene", "showcase"),
            .out = args.text("--out", ""),
        };
        if (o.scene != "showcase" && o.scene != "furnace") {
            throw std::runtime_error("--scene is showcase or furnace");
        }
        if (o.width == 0 || o.height == 0 || o.samples == 0 || o.depth == 0) {
            throw std::runtime_error("--width, --height, --spp and --depth must be positive");
        }
        vkf::Context ctx({.appName = "u2_raytrace"});
        if (o.shape.x * o.shape.y >
            ctx.properties().core.limits.maxComputeWorkGroupInvocations) {
            throw std::runtime_error("--local exceeds maxComputeWorkGroupInvocations");
        }

        rt::Scene showcase = rt::cornellBox(false, albedo, emission);
        rt::Scene furnace = rt::cornellBox(true, albedo, emission);
        rt::buildBvh(showcase);
        rt::buildBvh(furnace);
        vkf::print(
            "scene: {} spheres, {} quads and {} triangles in a BVH of {} nodes, depth {}\n",
            showcase.spheres.size(), showcase.quads.size(), showcase.triangles.size(),
            showcase.nodes.size(), showcase.bvhDepth);

        const Layouts layouts = createLayouts(ctx);
        const Pipelines pipelines{
            loadShaped(ctx, layouts, "render.comp", o.shape),
            loadShaped(ctx, layouts, "debug.comp", o.shape),
            u2::loadPipeline(ctx, layouts.pipeline, "resolve.comp"),
        };
        vkf::DescriptorPool pool(ctx, 16, 64);
        bool passed = runChecks(ctx, layouts, pipelines, pool, showcase, furnace, o);
        const rt::Scene& scene = o.scene == "furnace" ? furnace : showcase;
        if (benchmark) {
            runBenchmark(ctx, layouts, pipelines, pool, scene, o);
        } else {
            passed = renderImage(ctx, layouts, pipelines, pool, scene, o) && passed;
        }
        u2::finish(passed, "raytrace: primary hits, BVH and furnace checks hold");
    });
}
