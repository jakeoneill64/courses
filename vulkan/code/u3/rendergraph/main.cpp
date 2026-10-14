#include <vkf/vkf.hpp>

#include <algorithm>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>

#include "pipeline.hpp"
#include "rendergraph.hpp"

namespace {

struct Options {
    uint32_t side = 512;
    bool async = false;
    bool orphan = false;
};

struct Ids {
    rg::Resource field, blurred, edges, mask, stats, list, command, results;
};

Ids declare(rg::Graph& graph, std::optional<demo::Pipeline>& p, VkBuffer results,
            const Options& options) {
    // snippet:begin declare-resources
    const uint32_t side = options.side;
    const VkDeviceSize bytes = VkDeviceSize(side) * side * 4;
    const auto grid = [side](VkImageUsageFlags usage) {
        return vkf::ImageDesc{
            .format = VK_FORMAT_R32_UINT, .width = side, .height = side, .usage = usage};
    };
    constexpr VkBufferUsageFlags Storage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    constexpr VkBufferUsageFlags CopyBoth =
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    const Ids r{
        .field = graph.createImage("field", grid(VK_IMAGE_USAGE_STORAGE_BIT)),
        .blurred =
            graph.createBuffer("blurred", bytes, Storage | VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
        .edges = graph.createBuffer("edges", bytes, Storage),
        .mask = graph.createImage(
            "mask", grid(VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT)),
        .stats = graph.createBuffer("stats", sizeof(demo::Stats), Storage | CopyBoth),
        .list = graph.createBuffer("list", bytes, Storage),
        .command = graph.createBuffer("command", sizeof(VkDispatchIndirectCommand),
                                      Storage | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT),
        .results = graph.importBuffer("results", results),
    };
    const rg::Resource scratch =
        graph.createBuffer("scratch", bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    // snippet:end declare-resources

    // snippet:begin declare-early-passes
    graph.addPass("clear-stats", [&p](VkCommandBuffer cmd) { p->clearStats(cmd); })
        .write(r.stats, rg::ClearDestination);
    graph.addPass("generate", [&p](VkCommandBuffer cmd) { p->generate(cmd); })
        .write(r.field, rg::ComputeWrite);
    graph.addPass("blur", [&p](VkCommandBuffer cmd) { p->blur(cmd); })
        .read(r.field, rg::ComputeRead)
        .write(r.blurred, rg::ComputeWrite);
    graph.addPass("edges", [&p](VkCommandBuffer cmd) { p->edges(cmd); })
        .read(r.field, rg::ComputeRead)
        .write(r.edges, rg::ComputeWrite)
        .queue(options.async ? rg::Queue::Compute : rg::Queue::Main);
    const auto debugCopy = [&graph, r, scratch, bytes](VkCommandBuffer cmd) {
        const VkBufferCopy region{.size = bytes};
        vkCmdCopyBuffer(cmd, graph.buffer(r.blurred), graph.buffer(scratch), 1, &region);
    };
    graph.addPass("debug-copy", debugCopy)
        .read(r.blurred, rg::CopySource)
        .write(scratch, rg::CopyDestination);
    // snippet:end declare-early-passes

    // snippet:begin declare-late-passes
    graph.addPass("select", [&p](VkCommandBuffer cmd) { p->select(cmd); })
        .read(r.blurred, rg::ComputeRead)
        .read(r.edges, rg::ComputeRead)
        .read(r.stats, rg::ComputeRead)
        .write(r.stats, rg::ComputeWrite)
        .write(r.list, rg::ComputeWrite)
        .write(r.mask, rg::ComputeWrite);
    graph.addPass("command", [&p](VkCommandBuffer cmd) { p->command(cmd); })
        .read(r.stats, rg::ComputeRead)
        .write(r.command, rg::ComputeWrite);
    graph.addPass("score", [&p](VkCommandBuffer cmd) { p->score(cmd); })
        .read(r.command, rg::IndirectRead)
        .read(r.list, rg::ComputeRead)
        .read(r.blurred, rg::ComputeRead)
        .read(r.stats, rg::ComputeRead)
        .write(r.stats, rg::ComputeWrite);
    graph.addPass("readback", [&p](VkCommandBuffer cmd) { p->readback(cmd); })
        .read(r.stats, rg::CopySource)
        .read(r.mask, rg::CopySource)
        .write(r.results, rg::CopyDestination);
    graph.addPass("host").read(r.results, rg::HostRead).sideEffect();
    // snippet:end declare-late-passes
    if (options.orphan) {
        const rg::Resource unwritten = graph.createBuffer("unwritten", bytes, Storage);
        graph.addPass("orphan").read(unwritten, rg::ComputeRead).sideEffect();
    }
    return r;
}

demo::Targets targetsOf(const rg::Graph& graph, const Ids& ids) {
    return {
        .field = graph.image(ids.field),
        .fieldView = graph.view(ids.field),
        .blurred = graph.buffer(ids.blurred),
        .edges = graph.buffer(ids.edges),
        .mask = graph.image(ids.mask),
        .maskView = graph.view(ids.mask),
        .stats = graph.buffer(ids.stats),
        .list = graph.buffer(ids.list),
        .command = graph.buffer(ids.command),
        .results = graph.buffer(ids.results),
    };
}

std::vector<rg::Barriers> runByHand(const vkf::Context& ctx, const demo::Kernels& kernels,
                                    const vkf::Buffer& results, uint32_t side) {
    const VkDeviceSize bytes = VkDeviceSize(side) * side * 4;
    const auto image = [&](VkImageUsageFlags usage, const char* name) {
        return vkf::createImage(
            ctx, {.format = VK_FORMAT_R32_UINT, .width = side, .height = side, .usage = usage},
            name);
    };
    const auto buffer = [&](VkDeviceSize size, VkBufferUsageFlags usage, const char* name) {
        return vkf::createBuffer(ctx, size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | usage,
                                 vkf::MemoryUse::DeviceLocal, name);
    };
    const vkf::Image field = image(VK_IMAGE_USAGE_STORAGE_BIT, "field");
    const vkf::Image mask =
        image(VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, "mask");
    const vkf::Buffer blurred = buffer(bytes, 0, "blurred");
    const vkf::Buffer edges = buffer(bytes, 0, "edges");
    const vkf::Buffer stats =
        buffer(sizeof(demo::Stats),
               VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, "stats");
    const vkf::Buffer list = buffer(bytes, 0, "list");
    const vkf::Buffer command = buffer(sizeof(VkDispatchIndirectCommand),
                                       VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, "command");
    const demo::Targets targets{.field = field,
                                .fieldView = field.view,
                                .blurred = blurred,
                                .edges = edges,
                                .mask = mask,
                                .maskView = mask.view,
                                .stats = stats,
                                .list = list,
                                .command = command,
                                .results = results};
    const demo::Pipeline pipeline(ctx, kernels, targets, side);
    std::vector<rg::Barriers> barriers;
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        barriers = demo::recordByHand(cmd, pipeline, targets);
    });
    demo::Stats got{};
    const bool ok = demo::verify(results, side, got);
    const auto calls = std::count_if(
        barriers.begin(), barriers.end(),
        [](const rg::Barriers& b) { return !b.memory.empty() || !b.images.empty(); });
    vkf::print("by hand: {} passes, {} vkCmdPipelineBarrier2 calls, results {}\n",
               barriers.size(), calls, ok ? "match the CPU" : "WRONG");
    if (!ok) throw std::runtime_error("the hand-written pipeline gave wrong results");
    return barriers;
}

// snippet:begin compare
bool sameBarriers(const std::vector<rg::Barriers>& a, const std::vector<rg::Barriers>& b) {
    const auto memory = [](const VkMemoryBarrier2& m) {
        return std::tuple(m.srcStageMask, m.srcAccessMask, m.dstStageMask, m.dstAccessMask);
    };
    const auto image = [](const VkImageMemoryBarrier2& m) {
        return std::tuple(m.srcStageMask, m.srcAccessMask, m.dstStageMask, m.dstAccessMask,
                          m.oldLayout, m.newLayout);
    };
    const auto keys = [](const auto& barriers, auto key) {
        std::vector<decltype(key(barriers[0]))> out;
        for (const auto& barrier : barriers) out.push_back(key(barrier));
        std::sort(out.begin(), out.end());
        return out;
    };
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (keys(a[i].memory, memory) != keys(b[i].memory, memory)) return false;
        if (keys(a[i].images, image) != keys(b[i].images, image)) return false;
    }
    return true;
}
// snippet:end compare

void printTimes(const std::vector<std::vector<double>>& samples,
                const std::vector<std::pair<std::string, double>>& names, int repeats) {
    std::string line = std::format("GPU ms per pass, median of {}:", repeats);
    for (size_t i = 0; i < names.size(); ++i) {
        const std::string item =
            std::format(" {} {:.3f}", names[i].first, vkf::summarize(samples[i]).median);
        if (line.size() + item.size() + 1 > 90) {
            vkf::print("{}\n", line);
            line = " ";
        }
        line += item + (i + 1 < names.size() ? "," : "");
    }
    vkf::print("{}\n", line);
}

// Exercises the attachment presets: clears colour and depth, then copies the colour out.
bool runGraphics(const vkf::Context& ctx) {
    constexpr uint32_t Side = 64;
    const vkf::Buffer pixels =
        vkf::createBuffer(ctx, Side * Side * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                          vkf::MemoryUse::Readback, "pixels");
    rg::Graph graph(ctx);
    // snippet:begin graphics-resources
    const rg::Resource colour = graph.createImage(
        "colour",
        {.format = VK_FORMAT_R8G8B8A8_UNORM,
         .width = Side,
         .height = Side,
         .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT});
    const rg::Resource depth =
        graph.createImage("depth", {.format = VK_FORMAT_D32_SFLOAT,
                                    .width = Side,
                                    .height = Side,
                                    .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                                    .aspect = VK_IMAGE_ASPECT_DEPTH_BIT});
    const rg::Resource output = graph.importBuffer("pixels", pixels);
    // snippet:end graphics-resources
    // snippet:begin graphics-draw
    const auto draw = [&](VkCommandBuffer cmd) {
        const VkRenderingAttachmentInfo colourTarget{
            .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = graph.view(colour),
            .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = {.color = {{0.2f, 0.4f, 0.6f, 1.0f}}},
        };
        const VkRenderingAttachmentInfo depthTarget{
            .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = graph.view(depth),
            .imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .clearValue = {.depthStencil = {1.0f, 0}},
        };
        const VkRenderingInfo rendering{
            .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
            .renderArea = {{0, 0}, {Side, Side}},
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &colourTarget,
            .pDepthAttachment = &depthTarget,
        };
        vkCmdBeginRendering(cmd, &rendering);
        vkCmdEndRendering(cmd);
    };
    graph.addPass("draw", draw)
        .write(colour, rg::ColorAttachment)
        .write(depth, rg::DepthAttachment);
    // snippet:end graphics-draw
    const auto copy = [&](VkCommandBuffer cmd) {
        const VkBufferImageCopy region{
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {Side, Side, 1},
        };
        vkCmdCopyImageToBuffer(cmd, graph.image(colour), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               graph.buffer(output), 1, &region);
    };
    graph.addPass("copy", copy)
        .read(colour, rg::CopySource)
        .write(output, rg::CopyDestination);
    graph.addPass("host").read(output, rg::HostRead).sideEffect();
    graph.compile();
    graph.printPlan();
    const auto fence = vkf::createFence(ctx);
    graph.submit({}, {}, fence);
    vkf::waitFence(ctx, fence);
    pixels.invalidate();
    const uint8_t* rgba = pixels.data<uint8_t>();
    for (uint32_t i = 0; i < Side * Side; ++i) {
        if (rgba[4 * i] != 51 || rgba[4 * i + 1] != 102 || rgba[4 * i + 2] != 153) {
            return false;
        }
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        Options options;
        options.side = uint32_t(args.integer("--side", 512));
        options.async = args.flag("--async");
        options.orphan = args.text("--bug", "") == "read-unwritten";
        const bool alias = !args.flag("--no-alias");
        const int repeats = int(args.integer("--repeats", 10));
        const std::string dot = args.text("--dot", "");
        vkf::Context ctx({.appName = "u3_rendergraph", .asyncCompute = options.async});
        if (args.flag("--graphics")) {
            if (!runGraphics(ctx)) throw std::runtime_error("the cleared colour is wrong");
            vkf::print("PASS: the colour attachment holds the clear colour\n");
            return;
        }
        const demo::Kernels kernels(ctx);
        const vkf::Buffer results = vkf::createBuffer(ctx, demo::resultsSize(options.side),
                                                      VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                                      vkf::MemoryUse::Readback, "results");

        const std::vector<rg::Barriers> byHand =
            runByHand(ctx, kernels, results, options.side);
        {
            std::optional<demo::Pipeline> unused;
            rg::Graph plain(ctx);
            declare(plain, unused, results, {.side = options.side});
            plain.compile(false);
            const bool same = sameBarriers(plain.barriers(), byHand);
            vkf::print("graph without aliasing: {} barriers as by hand at every pass\n",
                       same ? "the same" : "DIFFERENT");
            if (!same) throw std::runtime_error("the graph derived different barriers");
        }

        // snippet:begin run
        std::optional<demo::Pipeline> pipeline;
        rg::Graph graph(ctx);
        const Ids ids = declare(graph, pipeline, results, options);
        graph.compile(alias);
        graph.printPlan();
        pipeline.emplace(ctx, kernels, targetsOf(graph, ids), options.side);
        const auto fence = vkf::createFence(ctx);
        // snippet:end run
        if (!dot.empty()) {
            graph.writeDot(dot);
            vkf::print("wrote {}\n", dot);
        }

        std::vector<std::vector<double>> passSamples;
        std::vector<double> wall;
        demo::Stats got{};
        bool ok = true;
        for (int r = 0; r <= repeats; ++r) {
            std::fill_n(results.data<uint8_t>(), results.size, uint8_t{0xff});
            vkf::CpuTimer timer;
            if (r == 0 && !options.async) {
                vkf::submitNow(ctx, [&](VkCommandBuffer cmd) { graph.record(cmd); });
            } else {
                graph.submit({}, {}, fence);
                vkf::waitFence(ctx, fence);
                VKF_CHECK(vkResetFences(ctx.device(), 1, fence.ptr()));
            }
            const double ms = timer.elapsedMs();
            ok = demo::verify(results, options.side, got) && ok;
            if (r == 0) continue;
            wall.push_back(ms);
            const auto times = graph.passTimes();
            passSamples.resize(times.size());
            for (size_t i = 0; i < times.size(); ++i) {
                passSamples[i].push_back(times[i].second);
            }
        }
        printTimes(passSamples, graph.passTimes(), repeats);
        vkf::print("CPU ms per execution (record, submit, wait), median of {}: {:.3f}\n",
                   repeats, vkf::summarize(wall).median);
        if (!ok) throw std::runtime_error("the graph's results differ from the CPU reference");
        vkf::print("PASS: {} executions match the CPU ({} cells selected)\n", repeats + 1,
                   got.selected);
    });
}
