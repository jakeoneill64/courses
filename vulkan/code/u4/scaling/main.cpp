#include <vkf/vkf.hpp>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <latch>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "graphics.hpp"

namespace {

constexpr VkFormat ColorFormat = VK_FORMAT_R8G8B8A8_UNORM;
constexpr VkClearColorValue Background{.float32 = {0.0f, 0.0f, 0.0f, 1.0f}};

// snippet:begin rect-constants
struct RectConstants {
    float bounds[4];
    float color[4];
    float targetSize[2];
};
// snippet:end rect-constants

class Random {
public:
    explicit Random(uint32_t seed) : state_(seed) {}
    uint32_t next() {
        state_ ^= state_ << 13;
        state_ ^= state_ >> 17;
        state_ ^= state_ << 5;
        return state_;
    }

private:
    uint32_t state_;
};

// Whole pixels and colours that 8 bits store exactly, so the CPU can paint the expected image.
std::vector<RectConstants> makeRects(uint32_t count, uint32_t size) {
    Random random(5);
    std::vector<RectConstants> rects(count);
    for (RectConstants& r : rects) {
        const auto x = float(random.next() % (size - 8));
        const auto y = float(random.next() % (size - 8));
        const uint32_t c = random.next();
        r = {{x, y, x + 8, y + 8},
             {float(c & 255) / 255, float((c >> 8) & 255) / 255, float((c >> 16) & 255) / 255,
              1.0f},
             {float(size), float(size)}};
    }
    return rects;
}

std::vector<uint8_t> paintOnCpu(const std::vector<RectConstants>& rects, uint32_t size) {
    std::vector<uint8_t> pixels(size_t(size) * size * 4, 0);
    for (size_t i = 3; i < pixels.size(); i += 4) pixels[i] = 255;
    for (const RectConstants& r : rects) {
        for (auto y = uint32_t(r.bounds[1]); y < uint32_t(r.bounds[3]); ++y) {
            for (auto x = uint32_t(r.bounds[0]); x < uint32_t(r.bounds[2]); ++x) {
                uint8_t* p = &pixels[(size_t(y) * size + x) * 4];
                for (int c = 0; c < 3; ++c) p[c] = uint8_t(std::lround(r.color[c] * 255));
            }
        }
    }
    return pixels;
}

// snippet:begin worker
// Command pools are externally synchronised, so each recording thread has its own.
struct Worker {
    vkf::Unique<VkCommandPool> pool;
    VkCommandBuffer secondary = VK_NULL_HANDLE;
};

Worker createWorker(const vkf::Context& ctx) {
    Worker worker{.pool = vkf::createCommandPool(ctx, ctx.mainQueue().family, 0)};
    const VkCommandBufferAllocateInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = worker.pool,
        .level = VK_COMMAND_BUFFER_LEVEL_SECONDARY,
        .commandBufferCount = 1,
    };
    VKF_CHECK(vkAllocateCommandBuffers(ctx.device(), &info, &worker.secondary));
    return worker;
}
// snippet:end worker

struct Scene {
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkExtent2D extent{};
    std::vector<RectConstants> rects;
};

// snippet:begin record-secondary
void recordSecondary(VkCommandBuffer cmd, const Scene& scene,
                     std::span<const RectConstants> rects) {
    const VkFormat format = ColorFormat;
    const VkCommandBufferInheritanceRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &format,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    const VkCommandBufferInheritanceInfo inheritance{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
        .pNext = &rendering,
    };
    const VkCommandBufferBeginInfo begin{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT |
                 VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT,
        .pInheritanceInfo = &inheritance,
    };
    VKF_CHECK(vkBeginCommandBuffer(cmd, &begin));
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipeline);
    u4::setViewportAndScissor(cmd, scene.extent);
    for (const RectConstants& rect : rects) {
        vkCmdPushConstants(cmd, scene.layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0,
                           sizeof(rect), &rect);
        vkCmdDraw(cmd, 6, 1, 0, 0);
    }
    VKF_CHECK(vkEndCommandBuffer(cmd));
}
// snippet:end record-secondary

// snippet:begin record-in-parallel
double recordInParallel(const vkf::Context& ctx, std::vector<Worker>& workers,
                        uint32_t threads, const Scene& scene) {
    const size_t share = (scene.rects.size() + threads - 1) / threads;
    std::vector<std::exception_ptr> errors(threads);
    std::latch start(1);
    std::vector<std::thread> pool;
    for (uint32_t t = 0; t < threads; ++t) {
        pool.emplace_back([&, t] {
            start.wait();
            try {
                const size_t first = std::min(scene.rects.size(), t * share);
                const size_t count = std::min(share, scene.rects.size() - first);
                VKF_CHECK(vkResetCommandPool(ctx.device(), workers[t].pool, 0));
                recordSecondary(workers[t].secondary, scene,
                                std::span(scene.rects).subspan(first, count));
            } catch (...) {
                errors[t] = std::current_exception();
            }
        });
    }
    const vkf::CpuTimer timer;
    start.count_down();
    for (std::thread& thread : pool) thread.join();
    const double ms = timer.elapsedMs();
    for (const std::exception_ptr& error : errors) {
        if (error) std::rethrow_exception(error);
    }
    return ms;
}
// snippet:end record-in-parallel

struct Target {
    vkf::Image color;
    vkf::Buffer readback;
    VkExtent2D extent{};
};

void copyToReadback(VkCommandBuffer cmd, const Target& target);

// snippet:begin execute-secondaries
void recordPrimary(VkCommandBuffer cmd, const Target& target,
                   std::span<const VkCommandBuffer> secondaries) {
    vkf::beginCommands(cmd);
    vkf::imageBarrier(cmd, target.color, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_NONE, VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    const VkRenderingAttachmentInfo color{
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = target.color.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = {.color = Background},
    };
    const VkRenderingInfo rendering{
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .flags = VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT,
        .renderArea = {{0, 0}, target.extent},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
    };
    vkCmdBeginRendering(cmd, &rendering);
    vkCmdExecuteCommands(cmd, static_cast<uint32_t>(secondaries.size()), secondaries.data());
    vkCmdEndRendering(cmd);
    copyToReadback(cmd, target);
    vkf::endCommands(cmd);
}
// snippet:end execute-secondaries

void copyToReadback(VkCommandBuffer cmd, const Target& target) {
    vkf::imageBarrier(cmd, target.color, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                      VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, VK_PIPELINE_STAGE_2_COPY_BIT,
                      VK_ACCESS_2_TRANSFER_READ_BIT);
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

struct Measurement {
    double record = 0;
    double submit = 0;
    bool identical = false;
};

Measurement measureThreads(const vkf::Context& ctx, uint32_t threads, uint32_t repeats,
                           const Scene& scene, const Target& target,
                           const std::vector<uint8_t>& expected) {
    std::vector<Worker> workers;
    for (uint32_t t = 0; t < threads; ++t) workers.push_back(createWorker(ctx));
    std::vector<VkCommandBuffer> secondaries;
    for (const Worker& worker : workers) secondaries.push_back(worker.secondary);
    const vkf::Unique<VkCommandPool> pool =
        vkf::createCommandPool(ctx, ctx.mainQueue().family, 0);
    const VkCommandBuffer primary = vkf::allocateCommandBuffer(ctx, pool);
    const vkf::Unique<VkFence> fence = vkf::createFence(ctx);

    std::vector<double> record, submit;
    bool identical = true;
    for (uint32_t r = 0; r < repeats; ++r) {
        record.push_back(recordInParallel(ctx, workers, threads, scene));
        VKF_CHECK(vkResetCommandPool(ctx.device(), pool, 0));
        recordPrimary(primary, target, secondaries);
        const vkf::CpuTimer timer;
        vkf::submit(ctx.mainQueue(), std::span(&primary, 1), {}, {}, fence);
        submit.push_back(timer.elapsedMs());
        vkf::waitFence(ctx, fence);
        VKF_CHECK(vkResetFences(ctx.device(), 1, fence.ptr()));
        target.readback.invalidate();
        identical = identical &&
                    std::memcmp(target.readback.mapped, expected.data(), expected.size()) == 0;
    }
    return {vkf::summarize(record).median, vkf::summarize(submit).median, identical};
}

// snippet:begin create-variants
double createVariants(const vkf::Context& ctx, const u4::GraphicsPipelineDesc& base,
                      VkPipelineCache cache, uint32_t first, uint32_t count, float salt) {
    std::vector<vkf::Unique<VkPipeline>> pipelines;
    const vkf::CpuTimer timer;
    for (uint32_t v = first; v < first + count; ++v) {
        vkf::Specialization specialization;
        specialization.set(0, int32_t(1 + v % 8)).set(1, float(v) * 0.37f + salt);
        u4::GraphicsPipelineDesc desc = base;
        desc.specialization = specialization.info();
        desc.cache = cache;
        pipelines.push_back(u4::createGraphicsPipeline(ctx, desc));
    }
    return timer.elapsedMs();
}
// snippet:end create-variants

// snippet:begin cache-file
vkf::Unique<VkPipelineCache> createCache(const vkf::Context& ctx,
                                         const std::vector<char>& data) {
    const VkPipelineCacheCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .initialDataSize = data.size(),
        .pInitialData = data.empty() ? nullptr : data.data(),
    };
    VkPipelineCache cache = VK_NULL_HANDLE;
    VKF_CHECK(vkCreatePipelineCache(ctx.device(), &info, nullptr, &cache));
    return {ctx.device(), cache};
}

// A cache made by another device or driver is useless; its header says which made it.
bool cacheMatchesDevice(const vkf::Context& ctx, const std::vector<char>& data) {
    VkPipelineCacheHeaderVersionOne header{};
    if (data.size() < sizeof(header)) return false;
    std::memcpy(&header, data.data(), sizeof(header));
    const VkPhysicalDeviceProperties& device = ctx.properties().core;
    return header.headerVersion == VK_PIPELINE_CACHE_HEADER_VERSION_ONE &&
           header.vendorID == device.vendorID && header.deviceID == device.deviceID &&
           std::memcmp(header.pipelineCacheUUID, device.pipelineCacheUUID, VK_UUID_SIZE) == 0;
}

std::vector<char> cacheData(const vkf::Context& ctx, VkPipelineCache cache) {
    size_t size = 0;
    VKF_CHECK(vkGetPipelineCacheData(ctx.device(), cache, &size, nullptr));
    std::vector<char> data(size);
    VKF_CHECK(vkGetPipelineCacheData(ctx.device(), cache, &size, data.data()));
    data.resize(size);
    return data;
}
// snippet:end cache-file

// snippet:begin memory-budget
void printBudget(const vkf::Context& ctx, const char* when) {
    VkPhysicalDeviceMemoryBudgetPropertiesEXT budget{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT,
    };
    VkPhysicalDeviceMemoryProperties2 memory{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
        .pNext = &budget,
    };
    vkGetPhysicalDeviceMemoryProperties2(ctx.physicalDevice(), &memory);
    for (uint32_t h = 0; h < memory.memoryProperties.memoryHeapCount; ++h) {
        const VkMemoryHeap& heap = memory.memoryProperties.memoryHeaps[h];
        vkf::print("  {}: heap {}{}, {:.1f} GiB: budget {:.2f} GiB, in use {:.3f} GiB\n", when,
                   h, heap.flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT ? " (device local)" : "",
                   double(heap.size) / (1 << 30), double(budget.heapBudget[h]) / (1 << 30),
                   double(budget.heapUsage[h]) / (1 << 30));
    }
}
// snippet:end memory-budget

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto draws = static_cast<uint32_t>(args.integer("--draws", 20'000));
        const auto repeats = static_cast<uint32_t>(args.integer("--repeat", 5));
        const auto size = static_cast<uint32_t>(args.integer("--size", 1024));
        const auto variants = static_cast<uint32_t>(args.integer("--pipelines", 16));
        const std::string cachePath = args.text("--cache", "pipeline-cache.bin");
        const bool fresh = args.flag("--fresh");

        vkf::Context ctx({.appName = "u4_scaling"});
        bool passed = true;

        const VkPushConstantRange push{
            VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0,
            sizeof(RectConstants)};
        const auto layout = vkf::createPipelineLayout(ctx, {}, {push});
        const auto rectVert = vkf::loadShader(ctx, vkf::shaderPath("rect.vert"));
        const auto rectFrag = vkf::loadShader(ctx, vkf::shaderPath("rect.frag"));
        const u4::GraphicsPipelineDesc rectDesc{.layout = layout,
                                                .vertexShader = rectVert,
                                                .fragmentShader = rectFrag,
                                                .cullMode = VK_CULL_MODE_NONE,
                                                .colorFormat = ColorFormat,
                                                .name = "rectangles"};
        const auto pipeline = u4::createGraphicsPipeline(ctx, rectDesc);

        Scene scene{pipeline, layout, {size, size}, makeRects(draws, size)};
        const std::vector<uint8_t> expected = paintOnCpu(scene.rects, size);
        Target target{vkf::createImage(ctx,
                                       {.format = ColorFormat,
                                        .width = size,
                                        .height = size,
                                        .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                                                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
                                       "rectangles"),
                      vkf::createBuffer(ctx, expected.size(), VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                        vkf::MemoryUse::Readback, "readback"),
                      {size, size}};

        vkf::print("multithreaded recording: {} draws into {}x{}, median of {} frames\n",
                   draws, size, size, repeats);
        const char* validation = std::getenv("VKF_VALIDATION");
        if (validation == nullptr || std::string(validation) != "0") {
            vkf::print(
                "  (the validation layers slow recording on several threads: measure "
                "with VKF_VALIDATION=0)\n");
        }
        vkf::print("  threads   record ms   speed-up   submit ms   image\n");
        double single = 0;
        const uint32_t cores = std::max(1u, std::thread::hardware_concurrency());
        for (uint32_t threads : {1u, 2u, 4u, 8u}) {
            if (threads > cores) break;
            const Measurement m =
                measureThreads(ctx, threads, repeats, scene, target, expected);
            if (threads == 1) single = m.record;
            vkf::print("  {:7}   {:9.2f}   {:8.2f}   {:9.2f}   {}\n", threads, m.record,
                       single / m.record, m.submit,
                       m.identical ? "matches the CPU painting" : "WRONG");
            passed = passed && m.identical;
        }

        const auto variantFrag = vkf::loadShader(ctx, vkf::shaderPath("variant.frag"));
        u4::GraphicsPipelineDesc variantDesc = rectDesc;
        variantDesc.fragmentShader = variantFrag;
        variantDesc.name = nullptr;
        const float salt =
            fresh ? float(std::chrono::steady_clock::now().time_since_epoch().count() % 9973) /
                        7.0f
                  : 0.0f;
        vkf::print("pipeline cache: {} pipeline variants{}\n", variants,
                   fresh ? ", specialised differently from any earlier run" : "");

        // snippet:begin cache-modes
        const double none =
            createVariants(ctx, variantDesc, VK_NULL_HANDLE, 0, variants, salt);
        const vkf::Unique<VkPipelineCache> cache = createCache(ctx, {});
        const double first = createVariants(ctx, variantDesc, cache, variants, variants, salt);
        const double again = createVariants(ctx, variantDesc, cache, variants, variants, salt);
        // snippet:end cache-modes
        vkf::print("  no cache                     {:8.1f} ms\n", none);
        vkf::print("  empty cache, new variants    {:8.1f} ms\n", first);
        vkf::print("  the same cache, same variants{:8.1f} ms\n", again);

        std::vector<char> saved;
        if (std::ifstream file{cachePath, std::ios::binary}) {
            saved.assign(std::istreambuf_iterator<char>(file), {});
        }
        if (saved.empty()) {
            vkf::print("  cache from disk              (no {} yet: run again to use it)\n",
                       cachePath);
        } else if (!cacheMatchesDevice(ctx, saved)) {
            vkf::print("  cache from disk              ({} is for another device or driver)\n",
                       cachePath);
        } else {
            const vkf::Unique<VkPipelineCache> loaded = createCache(ctx, saved);
            const double fromDisk =
                createVariants(ctx, variantDesc, loaded, 2 * variants, variants, salt);
            vkf::print("  cache from disk, new variants{:8.1f} ms\n", fromDisk);
        }
        const std::vector<char> data = cacheData(ctx, cache);
        const bool headerOk = cacheMatchesDevice(ctx, data);
        std::ofstream(cachePath, std::ios::binary)
            .write(data.data(), std::streamsize(data.size()));
        vkf::print("  wrote {} bytes to {}; its header {} this device\n", data.size(),
                   cachePath, headerOk ? "matches" : "DOES NOT match");
        passed = passed && headerOk;

        if (ctx.extensionEnabled(VK_EXT_MEMORY_BUDGET_EXTENSION_NAME)) {
            vkf::print("memory budget (VK_EXT_memory_budget):\n");
            printBudget(ctx, "before");
            const vkf::Buffer block = vkf::createBuffer(ctx, VkDeviceSize(256) << 20,
                                                        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                                        vkf::MemoryUse::DeviceLocal, "256 MB");
            printBudget(ctx, "with 256 MB more");
        } else {
            vkf::print("memory budget: VK_EXT_memory_budget is not available here\n");
        }

        vkf::print("{} multithreaded recording and pipeline caches\n",
                   passed ? "PASS" : "FAIL");
        if (!passed) throw std::runtime_error("the scaling checks failed");
    });
}
