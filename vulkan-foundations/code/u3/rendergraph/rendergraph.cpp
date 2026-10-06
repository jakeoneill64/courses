#include "rendergraph.hpp"

#include <vulkan/vk_enum_string_helper.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <numeric>
#include <stdexcept>

namespace rg {
namespace {

constexpr VkAccessFlags2 WriteAccess =
    VK_ACCESS_2_SHADER_WRITE_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT |
    VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT |
    VK_ACCESS_2_TRANSFER_WRITE_BIT | VK_ACCESS_2_HOST_WRITE_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT;

std::string shorten(std::string names, const std::string& prefix) {
    for (const std::string& cut : {prefix, std::string("_BIT")}) {
        for (size_t at; (at = names.find(cut)) != std::string::npos;) {
            names.erase(at, cut.size());
        }
    }
    return names;
}

std::string stageNames(VkPipelineStageFlags2 stages) {
    if (stages == 0) return "NONE";
    return shorten(string_VkPipelineStageFlags2(stages), "VK_PIPELINE_STAGE_2_");
}

std::string accessNames(VkAccessFlags2 access) {
    return access == 0 ? "NONE" : shorten(string_VkAccessFlags2(access), "VK_ACCESS_2_");
}

}  // namespace

// snippet:begin sim
// A resource's memory between two passes, as compilation sees it on each queue.
struct Graph::Sim {
    struct OnQueue {
        VkPipelineStageFlags2 writeStages = 0, readStages = 0, waitedStages = 0;
        VkAccessFlags2 writeAccess = 0;
        int writeBatch = -1, readBatch = -1;
        std::vector<Use> seenBy;

        bool sees(const Use& use) const {
            return std::any_of(seenBy.begin(), seenBy.end(), [&](const Use& s) {
                return (use.stages & ~s.stages) == 0 && (use.access & ~s.access) == 0;
            });
        }
    };
    OnQueue queue[2];
    VkImageLayout layout = VK_IMAGE_LAYOUT_UNDEFINED;

    // Takes on the uses of a resource whose memory this one now occupies.
    void absorb(const Sim& old) {
        for (int q = 0; q < 2; ++q) {
            queue[q].writeStages |= old.queue[q].writeStages;
            queue[q].writeAccess |= old.queue[q].writeAccess;
            queue[q].readStages |= old.queue[q].readStages;
            queue[q].waitedStages |= old.queue[q].waitedStages;
            queue[q].writeBatch = std::max(queue[q].writeBatch, old.queue[q].writeBatch);
            queue[q].readBatch = std::max(queue[q].readBatch, old.queue[q].readBatch);
        }
    }
};
// snippet:end sim

PassBuilder& PassBuilder::read(Resource resource, Use use) {
    graph_.addAccess(pass_, resource, use, true, false);
    return *this;
}

PassBuilder& PassBuilder::write(Resource resource, Use use) {
    graph_.addAccess(pass_, resource, use, false, true);
    return *this;
}

PassBuilder& PassBuilder::sideEffect() {
    graph_.passes_[pass_].sideEffect = true;
    return *this;
}

PassBuilder& PassBuilder::queue(Queue queue) {
    graph_.passes_[pass_].queue = queue;
    return *this;
}

void Graph::addAccess(uint32_t pass, Resource resource, Use use, bool reads, bool writes) {
    for (Access& a : passes_[pass].accesses) {
        if (a.resource != resource) continue;
        if (resources_[resource].isImage && a.use.layout != use.layout) {
            throw std::runtime_error(passes_[pass].name + " needs an image in two layouts");
        }
        a.use.stages |= use.stages;
        a.use.access |= use.access;
        a.reads = a.reads || reads;
        a.writes = a.writes || writes;
        return;
    }
    passes_[pass].accesses.push_back({resource, use, reads, writes});
}

Resource Graph::importBuffer(std::string name, VkBuffer buffer, Use previous) {
    resources_.push_back({.name = std::move(name), .buffer = buffer, .previous = previous});
    return Resource(resources_.size() - 1);
}

Resource Graph::importImage(std::string name, VkImage image, VkImageView view,
                            VkImageSubresourceRange range, Use previous) {
    resources_.push_back({.name = std::move(name),
                          .isImage = true,
                          .image = image,
                          .view = view,
                          .range = range,
                          .previous = previous});
    return Resource(resources_.size() - 1);
}

Resource Graph::createBuffer(std::string name, VkDeviceSize size, VkBufferUsageFlags usage) {
    resources_.push_back(
        {.name = std::move(name), .transient = true, .size = size, .usage = usage});
    return Resource(resources_.size() - 1);
}

Resource Graph::createImage(std::string name, const vkf::ImageDesc& desc) {
    resources_.push_back({.name = std::move(name),
                          .isImage = true,
                          .transient = true,
                          .range = {desc.aspect, 0, desc.mipLevels, 0, desc.layers},
                          .desc = desc});
    return Resource(resources_.size() - 1);
}

PassBuilder Graph::addPass(std::string name, std::function<void(VkCommandBuffer)> record) {
    passes_.push_back({.name = std::move(name), .record = std::move(record)});
    return PassBuilder(*this, uint32_t(passes_.size() - 1));
}

Queue Graph::queueOf(uint32_t position) const {
    const bool async = passes_[order_[position]].queue == Queue::Compute;
    return async && ctx_.hasSeparateComputeQueue() ? Queue::Compute : Queue::Main;
}

void Graph::rebind(Resource resource, VkBuffer buffer, VkImage image, VkImageView view) {
    ResourceInfo& r = resources_.at(resource);
    if (r.transient) throw std::runtime_error("only imported resources can be rebound");
    r.buffer = buffer;
    r.image = image;
    r.view = view;
}

// snippet:begin cull
// A pass survives if it has a side effect or a surviving pass reads something it wrote.
void Graph::cull() {
    const auto writes = [&](const Pass& p, Resource r) {
        return std::any_of(p.accesses.begin(), p.accesses.end(),
                           [&](const Access& a) { return a.resource == r && a.writes; });
    };
    for (Pass& pass : passes_) pass.kept = pass.sideEffect;
    for (size_t i = passes_.size(); i-- > 0;) {
        if (!passes_[i].kept) continue;
        for (const Access& a : passes_[i].accesses) {
            if (!a.reads) continue;
            size_t j = i;
            while (j > 0 && !writes(passes_[j - 1], a.resource)) --j;
            if (j > 0) {
                passes_[j - 1].kept = true;
            } else if (resources_[a.resource].transient) {
                throw std::runtime_error("pass '" + passes_[i].name + "' reads '" +
                                         resources_[a.resource].name +
                                         "' before any pass writes it");
            }
        }
    }
    for (uint32_t i = 0; i < passes_.size(); ++i) {
        if (passes_[i].kept) order_.push_back(i);
    }
}
// snippet:end cull

void Graph::placeTransients(bool aliasMemory) {
    const VkDevice device = ctx_.device();
    const uint32_t families[2] = {ctx_.mainQueue().family, ctx_.computeQueue().family};
    std::vector<Resource> transients;
    uint32_t memoryTypes = ~0u;
    for (Resource r = 0; r < resources_.size(); ++r) {
        ResourceInfo& info = resources_[r];
        if (!info.transient || info.first < 0) continue;
        bool onQueue[2] = {};
        for (uint32_t k = 0; k < order_.size(); ++k) {
            for (const Access& a : passes_[order_[k]].accesses) {
                if (a.resource == r) onQueue[int(queueOf(k))] = true;
            }
        }
        // Shared between two queue families, CONCURRENT avoids ownership transfers.
        const bool shared = onQueue[0] && onQueue[1] && families[0] != families[1];
        const VkSharingMode sharing =
            shared ? VK_SHARING_MODE_CONCURRENT : VK_SHARING_MODE_EXCLUSIVE;
        if (info.isImage) {
            const vkf::ImageDesc& d = info.desc;
            const VkImageCreateInfo create{
                .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                .imageType = d.type,
                .format = d.format,
                .extent = {d.width, d.height, d.depth},
                .mipLevels = d.mipLevels,
                .arrayLayers = d.layers,
                .samples = d.samples,
                .tiling = VK_IMAGE_TILING_OPTIMAL,
                .usage = d.usage,
                .sharingMode = sharing,
                .queueFamilyIndexCount = shared ? 2u : 0u,
                .pQueueFamilyIndices = families,
            };
            VKF_CHECK(vkCreateImage(device, &create, nullptr, &info.image));
            ownedImages_.emplace_back(device, info.image);
            vkGetImageMemoryRequirements(device, info.image, &info.memory);
            ctx_.name(info.image, info.name.c_str());
        } else {
            const VkBufferCreateInfo create{
                .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = info.size,
                .usage = info.usage,
                .sharingMode = sharing,
                .queueFamilyIndexCount = shared ? 2u : 0u,
                .pQueueFamilyIndices = families,
            };
            VKF_CHECK(vkCreateBuffer(device, &create, nullptr, &info.buffer));
            ownedBuffers_.emplace_back(device, info.buffer);
            vkGetBufferMemoryRequirements(device, info.buffer, &info.memory);
            ctx_.name(info.buffer, info.name.c_str());
        }
        memoryTypes &= info.memory.memoryTypeBits;
        separateBytes_ += info.memory.size;
        transients.push_back(r);
    }
    if (transients.empty()) return;
    std::stable_sort(transients.begin(), transients.end(), [&](Resource a, Resource b) {
        return resources_[a].first < resources_[b].first;
    });

    // snippet:begin first-fit
    // A live buffer and image must not share a page of bufferImageGranularity bytes.
    const VkDeviceSize granularity = ctx_.properties().core.limits.bufferImageGranularity;
    for (size_t i = 0; i < transients.size(); ++i) {
        ResourceInfo& r = resources_[transients[i]];
        for (bool moved = true; moved;) {
            moved = false;
            for (size_t j = 0; j < i; ++j) {
                const ResourceInfo& other = resources_[transients[j]];
                if (aliasMemory && (other.last < r.first || r.last < other.first)) continue;
                const VkDeviceSize page = other.isImage != r.isImage ? granularity : 1;
                const VkDeviceSize start = other.offset / page * page;
                const VkDeviceSize end = vkf::alignUp(other.offset + other.memory.size, page);
                if (r.offset < end && start < vkf::alignUp(r.offset + r.memory.size, page)) {
                    r.offset = vkf::alignUp(end, r.memory.alignment);
                    moved = true;
                }
            }
        }
        aliasedBytes_ = std::max(aliasedBytes_, r.offset + r.memory.size);
    }
    // snippet:end first-fit

    const VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = aliasedBytes_,
        .memoryTypeIndex =
            vkf::findMemoryType(ctx_, memoryTypes, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateMemory(device, &allocate, nullptr, &memory));
    memory_ = vkf::Unique<VkDeviceMemory>(device, memory);
    for (Resource t : transients) {
        ResourceInfo& r = resources_[t];
        for (Resource o : transients) {
            const ResourceInfo& old = resources_[o];
            const bool overlap = old.offset < r.offset + r.memory.size &&
                                 r.offset < old.offset + old.memory.size;
            if (overlap && old.last < r.first) r.reuses.push_back(o);
        }
        if (!r.isImage) {
            VKF_CHECK(vkBindBufferMemory(device, r.buffer, memory, r.offset));
            continue;
        }
        VKF_CHECK(vkBindImageMemory(device, r.image, memory, r.offset));
        const VkImageViewCreateInfo view{
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = r.image,
            .viewType =
                r.desc.layers > 1 ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : VK_IMAGE_VIEW_TYPE_2D,
            .format = r.desc.format,
            .subresourceRange = r.range,
        };
        VKF_CHECK(vkCreateImageView(device, &view, nullptr, &r.view));
        ownedViews_.emplace_back(device, r.view);
    }
}

// Dependencies on another queue's batch become semaphore waits in `batches`.
std::vector<std::vector<Graph::Dependency>> Graph::derive(const std::vector<int>& batchOf,
                                                          std::vector<Batch>& batches) const {
    std::vector<Sim> sims(resources_.size());
    for (Resource r = 0; r < resources_.size(); ++r) {
        // An import's previous use is taken to have run on the queue of its first user.
        const ResourceInfo& info = resources_[r];
        Sim::OnQueue& before = sims[r].queue[info.first < 0 ? 0 : int(queueOf(info.first))];
        const VkAccessFlags2 writes = info.previous.access & WriteAccess;
        before.writeStages = writes ? info.previous.stages : 0;
        before.writeAccess = writes;
        before.readStages = writes ? 0 : info.previous.stages;
        sims[r].layout = info.previous.layout;
    }
    const auto wait = [&](int batch, int producer, VkPipelineStageFlags2 stages) {
        auto& waits = batches[batch].waits;
        auto same = std::find_if(waits.begin(), waits.end(),
                                 [&](const auto& w) { return w.first == producer; });
        if (same != waits.end()) {
            same->second |= stages;
        } else {
            waits.push_back({producer, stages});
        }
    };
    std::vector<std::vector<Dependency>> plan(order_.size());
    for (uint32_t k = 0; k < order_.size(); ++k) {
        const uint32_t q = uint32_t(queueOf(k));
        const int batch = batchOf[k];
        std::vector<Dependency> needs;
        for (const Access& a : passes_[order_[k]].accesses) {
            const ResourceInfo& info = resources_[a.resource];
            Sim& s = sims[a.resource];
            if (int(k) == info.first) {
                for (Resource old : info.reuses) s.absorb(sims[old]);
            }
            // snippet:begin derive
            const Use& use = a.use;
            const VkAccessFlags2 writes = use.access & WriteAccess;
            const bool transition = info.isImage && use.layout != s.layout;
            const bool modifies = writes != 0 || transition;
            Dependency d{.resources = {a.resource},
                         .dstStages = use.stages,
                         .dstAccess = use.access,
                         .oldLayout = s.layout,
                         .newLayout = use.layout,
                         .transition = transition};
            Sim::OnQueue& mine = s.queue[q];
            bool waited = false;
            for (uint32_t x = 0; x < 2; ++x) {
                const Sim::OnQueue& prior = s.queue[x];
                if (prior.writeStages != 0 && (modifies || !mine.sees(use))) {
                    if (x == q) {
                        d.srcStages |= prior.writeStages;
                        d.srcAccess |= prior.writeAccess;
                    } else if (mine.waitedStages != 0) {
                        d.srcStages |= mine.waitedStages;
                    } else if (prior.writeBatch >= 0) {
                        wait(batch, prior.writeBatch, use.stages);
                        waited = true;
                    }
                }
                if (modifies && prior.readStages != 0) {
                    if (x == q) {
                        d.srcStages |= prior.readStages;
                    } else if (prior.readBatch >= 0) {
                        wait(batch, prior.readBatch, use.stages);
                        waited = true;
                    }
                }
            }
            // A layout transition after a semaphore wait must chain from the waiting stages.
            if (waited && transition) d.srcStages |= use.stages;
            if (d.srcStages != 0 || transition) needs.push_back(d);
            // snippet:end derive

            // snippet:begin update
            if (modifies) {
                s.queue[0] = s.queue[1] = {};
                s.layout = use.layout;
                mine.writeStages = use.stages;
                mine.writeAccess = writes;
                mine.writeBatch = batch;
                if (writes == 0) {
                    // Only a layout transition: its writes are visible to this read already.
                    mine.seenBy.push_back(use);
                    mine.readStages = use.stages;
                    mine.readBatch = batch;
                }
                continue;
            }
            if (d.srcStages != 0 || waited) mine.seenBy.push_back(use);
            if (waited) mine.waitedStages |= use.stages;
            mine.readStages |= use.stages;
            mine.readBatch = batch;
            // snippet:end update
        }
        // snippet:begin group
        // One memory barrier per pair of stage masks; each layout transition its own.
        for (Dependency& d : needs) {
            auto same = std::find_if(plan[k].begin(), plan[k].end(), [&](const Dependency& g) {
                return !d.transition && !g.transition && g.srcStages == d.srcStages &&
                       g.dstStages == d.dstStages;
            });
            if (same == plan[k].end()) {
                plan[k].push_back(d);
                continue;
            }
            same->srcAccess |= d.srcAccess;
            same->dstAccess |= d.dstAccess;
            same->resources.push_back(d.resources[0]);
        }
        // snippet:end group
    }
    return plan;
}

// snippet:begin batches
// Cutting after waited-on passes and before waiting ones lets independent work overlap.
void Graph::formBatches() {
    std::vector<int> alone(order_.size());
    std::iota(alone.begin(), alone.end(), 0);
    std::vector<Batch> single(order_.size());
    derive(alone, single);
    std::vector<bool> starts(order_.size()), ends(order_.size());
    for (uint32_t k = 0; k < order_.size(); ++k) {
        for (const auto& wait : single[k].waits) {
            ends[wait.first] = true;
            starts[k] = true;
        }
    }
    std::vector<int> batchOf(order_.size());
    int open[2] = {-1, -1};
    for (uint32_t k = 0; k < order_.size(); ++k) {
        const int q = int(queueOf(k));
        if (open[q] < 0 || starts[k]) {
            batches_.push_back({.queue = Queue(q)});
            open[q] = int(batches_.size() - 1);
        }
        batchOf[k] = open[q];
        batches_[open[q]].passes.push_back(k);
        if (ends[k]) open[q] = -1;
    }
    plan_ = derive(batchOf, batches_);
    // The last batch signals the caller's semaphores, so it waits for the other queue too.
    Batch& last = batches_.back();
    for (int i = int(batches_.size()) - 2; i >= 0; --i) {
        if (batches_[i].queue == last.queue) continue;
        if (std::none_of(last.waits.begin(), last.waits.end(),
                         [&](const auto& w) { return w.first == i; })) {
            last.waits.push_back({i, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT});
        }
        break;
    }
}
// snippet:end batches

void Graph::compile(bool aliasMemory) {
    if (!order_.empty()) throw std::runtime_error("a graph compiles once");
    cull();
    for (uint32_t k = 0; k < order_.size(); ++k) {
        for (const Access& a : passes_[order_[k]].accesses) {
            ResourceInfo& r = resources_[a.resource];
            if (r.first < 0) r.first = int(k);
            r.last = int(k);
        }
    }
    placeTransients(aliasMemory);
    formBatches();
    const VkQueryPoolCreateInfo queries{
        .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
        .queryType = VK_QUERY_TYPE_TIMESTAMP,
        .queryCount = uint32_t(2 * order_.size()),
    };
    VkQueryPool pool = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateQueryPool(ctx_.device(), &queries, nullptr, &pool));
    timestamps_ = vkf::Unique<VkQueryPool>(ctx_.device(), pool);
    for (Batch& batch : batches_) {
        const int q = int(batch.queue);
        if (!pools_[q]) {
            pools_[q] = vkf::createCommandPool(
                ctx_, q == 0 ? ctx_.mainQueue().family : ctx_.computeQueue().family, 0);
            timelines_[q] = vkf::createTimelineSemaphore(ctx_);
        }
        batch.cmd = vkf::allocateCommandBuffer(ctx_, pools_[q]);
    }
}

Barriers Graph::vulkanBarriers(uint32_t position) const {
    Barriers out;
    for (const Dependency& d : plan_[position]) {
        if (!d.transition) {
            out.memory.push_back({.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                                  .srcStageMask = d.srcStages,
                                  .srcAccessMask = d.srcAccess,
                                  .dstStageMask = d.dstStages,
                                  .dstAccessMask = d.dstAccess});
            continue;
        }
        out.images.push_back({.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
                              .srcStageMask = d.srcStages,
                              .srcAccessMask = d.srcAccess,
                              .dstStageMask = d.dstStages,
                              .dstAccessMask = d.dstAccess,
                              .oldLayout = d.oldLayout,
                              .newLayout = d.newLayout,
                              .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                              .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                              .image = resources_[d.resources[0]].image,
                              .subresourceRange = resources_[d.resources[0]].range});
    }
    return out;
}

std::vector<Barriers> Graph::barriers() const {
    std::vector<Barriers> out;
    for (uint32_t k = 0; k < order_.size(); ++k) out.push_back(vulkanBarriers(k));
    return out;
}

// snippet:begin record-batch
void Graph::recordBatch(const Batch& batch, VkCommandBuffer cmd) {
    const uint32_t family =
        batch.queue == Queue::Main ? ctx_.mainQueue().family : ctx_.computeQueue().family;
    const bool timed = ctx_.properties().queueFamilies[family].timestampValidBits > 0;
    for (uint32_t k : batch.passes) {
        const Barriers barriers = vulkanBarriers(k);
        if (!barriers.memory.empty() || !barriers.images.empty()) {
            const VkDependencyInfo dependency{
                .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                .memoryBarrierCount = uint32_t(barriers.memory.size()),
                .pMemoryBarriers = barriers.memory.data(),
                .imageMemoryBarrierCount = uint32_t(barriers.images.size()),
                .pImageMemoryBarriers = barriers.images.data(),
            };
            vkCmdPipelineBarrier2(cmd, &dependency);
        }
        const Pass& pass = passes_[order_[k]];
        if (timed) {
            vkCmdResetQueryPool(cmd, timestamps_, 2 * k, 2);
            vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, timestamps_,
                                 2 * k);
        }
        ctx_.beginLabel(cmd, pass.name.c_str());
        if (pass.record) pass.record(cmd);
        ctx_.endLabel(cmd);
        if (timed) {
            vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, timestamps_,
                                 2 * k + 1);
        }
    }
}
// snippet:end record-batch

void Graph::record(VkCommandBuffer cmd) {
    if (batches_.size() != 1) throw std::runtime_error("record() needs exactly one batch");
    recordBatch(batches_[0], cmd);
}

// snippet:begin submit
void Graph::submit(std::span<const vkf::SemaphoreSubmit> waits,
                   std::span<const vkf::SemaphoreSubmit> signals, VkFence fence) {
    for (auto& pool : pools_) {
        if (pool) VKF_CHECK(vkResetCommandPool(ctx_.device(), pool, 0));
    }
    bool mainWaited = false;
    for (Batch& batch : batches_) {
        vkf::beginCommands(batch.cmd);
        recordBatch(batch, batch.cmd);
        vkf::endCommands(batch.cmd);
        const int q = int(batch.queue);
        batch.value = ++submitted_[q];
        std::vector<vkf::SemaphoreSubmit> waitFor, signal;
        for (const auto& [producer, stages] : batch.waits) {
            const Batch& from = batches_[producer];
            waitFor.push_back({timelines_[int(from.queue)], from.value, stages});
        }
        if (batch.queue == Queue::Main && !mainWaited) {
            waitFor.insert(waitFor.end(), waits.begin(), waits.end());
            mainWaited = true;
        }
        signal.push_back({timelines_[q], batch.value, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT});
        const bool last = &batch == &batches_.back();
        if (last) signal.insert(signal.end(), signals.begin(), signals.end());
        const VkQueue queue = q == 0 ? ctx_.mainQueue().queue : ctx_.computeQueue().queue;
        vkf::submit(queue, std::span(&batch.cmd, 1), waitFor, signal,
                    last ? fence : VK_NULL_HANDLE);
    }
}
// snippet:end submit

std::vector<std::pair<std::string, double>> Graph::passTimes() const {
    std::vector<std::pair<std::string, double>> times;
    for (uint32_t k = 0; k < order_.size(); ++k) {
        const uint32_t family =
            queueOf(k) == Queue::Main ? ctx_.mainQueue().family : ctx_.computeQueue().family;
        const uint32_t bits = ctx_.properties().queueFamilies[family].timestampValidBits;
        uint64_t ticks[2] = {};
        if (bits > 0) {
            VKF_CHECK(vkGetQueryPoolResults(
                ctx_.device(), timestamps_, 2 * k, 2, sizeof(ticks), ticks, sizeof(uint64_t),
                VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT));
        }
        const uint64_t mask = bits >= 64 ? ~0ull : (1ull << bits) - 1;
        const double ns = double((ticks[1] - ticks[0]) & mask) *
                          ctx_.properties().core.limits.timestampPeriod;
        times.push_back({passes_[order_[k]].name, ns / 1e6});
    }
    return times;
}

// snippet:begin print-plan
void Graph::printPlan() const {
    std::string culled;
    for (const Pass& pass : passes_) {
        if (!pass.kept) culled += (culled.empty() ? "" : ", ") + pass.name;
    }
    std::printf("compiled: %zu passes, %zu kept, culled: %s\n", passes_.size(), order_.size(),
                culled.empty() ? "none" : culled.c_str());
    std::printf("transient memory: %llu KiB with aliasing, %llu KiB without\n",
                (unsigned long long)(aliasedBytes_ / 1024),
                (unsigned long long)(separateBytes_ / 1024));
    for (const ResourceInfo& r : resources_) {
        if (!r.transient || r.first < 0) continue;
        std::string reuses;
        for (Resource p : r.reuses) {
            reuses += (reuses.empty() ? ", reuses " : ", ") + resources_[p].name;
        }
        std::printf("  %-8s %-6s %8llu bytes at %-8llu passes %d-%d%s\n", r.name.c_str(),
                    r.isImage ? "image" : "buffer", (unsigned long long)r.memory.size,
                    (unsigned long long)r.offset, r.first, r.last, reuses.c_str());
    }
    // snippet:end print-plan
    for (size_t b = 0; batches_.size() > 1 && b < batches_.size(); ++b) {
        std::string line = "batch " + std::to_string(b) + " on the ";
        line += batches_[b].queue == Queue::Main ? "main queue:" : "compute queue:";
        for (uint32_t k : batches_[b].passes) line += " " + passes_[order_[k]].name;
        for (const auto& [producer, stages] : batches_[b].waits) {
            line +=
                "; waits for batch " + std::to_string(producer) + " at " + stageNames(stages);
        }
        std::printf("%s\n", line.c_str());
    }
    // snippet:begin print-barriers
    for (uint32_t k = 0; k < order_.size(); ++k) {
        std::printf("pass %u %s\n", k, passes_[order_[k]].name.c_str());
        for (const Dependency& d : plan_[k]) {
            std::string what = d.transition ? "  image  " : "  memory ";
            for (size_t i = 0; i < d.resources.size(); ++i) {
                const ResourceInfo& r = resources_[d.resources[i]];
                what += (i == 0 ? "" : ", ") + r.name;
                for (size_t j = 0; int(k) == r.first && j < r.reuses.size(); ++j) {
                    what += (j == 0 ? " (memory of " : ", ") + resources_[r.reuses[j]].name;
                    if (j + 1 == r.reuses.size()) what += ")";
                }
            }
            if (d.transition) {
                what += " " + shorten(string_VkImageLayout(d.oldLayout), "VK_IMAGE_LAYOUT_") +
                        " -> " +
                        shorten(string_VkImageLayout(d.newLayout), "VK_IMAGE_LAYOUT_");
            }
            std::printf("%s\n    src %-16s %s\n    dst %-16s %s\n", what.c_str(),
                        stageNames(d.srcStages).c_str(), accessNames(d.srcAccess).c_str(),
                        stageNames(d.dstStages).c_str(), accessNames(d.dstAccess).c_str());
        }
    }
}
// snippet:end print-barriers

// Resources appear once per version, so the drawing has no cycles.
void Graph::writeDot(const std::string& path) const {
    std::ofstream out(path);
    out << "digraph rendergraph {\n  rankdir=LR;\n  node [fontname=\"Helvetica\"];\n";
    std::vector<int> version(resources_.size(), 0);
    const auto node = [&](Resource r) {
        return "r" + std::to_string(r) + "v" + std::to_string(version[r]);
    };
    const auto declare = [&](Resource r) {
        out << "  " << node(r) << " [shape=ellipse, label=\"" << resources_[r].name << "\""
            << (resources_[r].transient ? ", style=dashed" : "") << "];\n";
    };
    for (Resource r = 0; r < resources_.size(); ++r) {
        if (!resources_[r].transient) declare(r);
    }
    for (uint32_t i = 0; i < passes_.size(); ++i) {
        out << "  p" << i << " [shape=box, label=\"" << passes_[i].name << "\""
            << (passes_[i].kept ? "" : ", style=dotted, fontcolor=gray") << "];\n";
        for (const Access& a : passes_[i].accesses) {
            if (a.reads) out << "  " << node(a.resource) << " -> p" << i << ";\n";
        }
        for (const Access& a : passes_[i].accesses) {
            if (!a.writes) continue;
            ++version[a.resource];
            declare(a.resource);
            out << "  p" << i << " -> " << node(a.resource) << ";\n";
        }
    }
    out << "}\n";
}

}  // namespace rg
