#include <vkf/vkf.hpp>

#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"
#include "messages.hpp"

namespace {

constexpr uint32_t Count = 1 << 16;
constexpr uint32_t Side = 256;
constexpr uint32_t Batches = 4;

struct FillPush {
    uint32_t count;
    uint32_t seed;
};

struct CountPush {
    uint32_t count;
};

struct SeedPush {
    uint32_t seed;
};

constexpr uint32_t filled(uint32_t i, uint32_t seed) {
    return u3::scramble(i ^ seed);
}
constexpr uint32_t transformed(uint32_t value) {
    return value * 3u + 1u;
}

constexpr VkBufferUsageFlags StorageCopy = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                           VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                           VK_BUFFER_USAGE_TRANSFER_DST_BIT;

struct Env {
    explicit Env(const vkf::Context& c)
        : ctx(c),
          pool(c),
          fill(u3::makeKernel(c, "fill.comp", {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
                              sizeof(FillPush))),
          transform(u3::makeKernel(
              c, "transform.comp",
              {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
              sizeof(CountPush))),
          pattern(u3::makeKernel(c, "pattern.comp", {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE},
                                 sizeof(SeedPush))),
          a(vkf::createBuffer(c, Count * 4, StorageCopy, vkf::MemoryUse::DeviceLocal, "a")),
          b(vkf::createBuffer(c, Count * 4, StorageCopy, vkf::MemoryUse::DeviceLocal, "b")),
          readback(vkf::createBuffer(c, Count * 4, StorageCopy, vkf::MemoryUse::Readback,
                                     "readback")) {}

    const vkf::Context& ctx;
    vkf::DescriptorPool pool;
    u3::Kernel fill, transform, pattern;
    vkf::Buffer a, b, readback;

    void fillBuffer(VkCommandBuffer cmd, VkBuffer target, uint32_t seed) {
        const VkDescriptorSet set = u3::bufferSet(ctx, pool, fill, {target});
        u3::dispatch(cmd, fill, set, FillPush{Count, seed}, Count / 256);
    }

    void transformBuffer(VkCommandBuffer cmd, VkBuffer src, VkBuffer dst) {
        const VkDescriptorSet set = u3::bufferSet(ctx, pool, transform, {src, dst});
        u3::dispatch(cmd, transform, set, CountPush{Count}, Count / 256);
    }

    std::vector<uint32_t> readBack() const {
        readback.invalidate();
        const uint32_t* values = readback.data<uint32_t>();
        return {values, values + Count};
    }
};

void barrier(VkCommandBuffer cmd, const VkMemoryBarrier2& memory) {
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &memory,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}

void toHost(VkCommandBuffer cmd, VkPipelineStageFlags2 stage, VkAccessFlags2 access) {
    const VkMemoryBarrier2 toHostBarrier{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = stage,
        .srcAccessMask = access,
        .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
        .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT,
    };
    barrier(cmd, toHostBarrier);
}

template <class Expected>
bool matches(const std::vector<uint32_t>& values, Expected expected) {
    for (uint32_t i = 0; i < values.size(); ++i) {
        if (values[i] != expected(i)) return false;
    }
    return true;
}

bool missingVisibility(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.fillBuffer(cmd, e.a, 1);
        // snippet:begin missing-visibility
        const VkMemoryBarrier2 visibility{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = bug ? 0 : VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = bug ? 0 : VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
        };
        barrier(cmd, visibility);
        // snippet:end missing-visibility
        e.transformBuffer(cmd, e.a, e.b);
    });
    return matches(vkf::download<uint32_t>(e.ctx, e.b, Count),
                   [](uint32_t i) { return transformed(filled(i, 1)); });
}

bool wrongStage(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        // snippet:begin wrong-stage
        vkCmdFillBuffer(cmd, e.a, 0, VK_WHOLE_SIZE, 7);
        const VkMemoryBarrier2 fillDone{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = bug ? VK_PIPELINE_STAGE_2_COPY_BIT : VK_PIPELINE_STAGE_2_CLEAR_BIT,
            .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
        };
        barrier(cmd, fillDone);
        // snippet:end wrong-stage
        e.transformBuffer(cmd, e.a, e.b);
    });
    return matches(vkf::download<uint32_t>(e.ctx, e.b, Count),
                   [](uint32_t) { return transformed(7); });
}

bool layoutMismatch(Env& e, bool bug) {
    const vkf::Image image = vkf::createImage(
        e.ctx,
        {.format = VK_FORMAT_R32_UINT,
         .width = Side,
         .height = Side,
         .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
        "image");
    const VkDescriptorSet set = e.pool.allocate(e.pattern.setLayout);
    vkf::DescriptorWriter()
        .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, image.view, VK_IMAGE_LAYOUT_GENERAL)
        .update(e.ctx, set);
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                          VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                          VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                          VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
        u3::dispatch(cmd, e.pattern, set, SeedPush{3}, Side / 16, Side / 16);
        // snippet:begin layout-mismatch
        const VkImageMemoryBarrier2 toCopy{
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
            .dstAccessMask = VK_ACCESS_2_TRANSFER_READ_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_GENERAL,
            .newLayout = bug ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = vkf::colorRange(),
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &toCopy,
        };
        vkCmdPipelineBarrier2(cmd, &dependency);
        const VkBufferImageCopy region{
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {Side, Side, 1},
        };
        vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, e.readback, 1,
                               &region);
        // snippet:end layout-mismatch
        toHost(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
    });
    return matches(e.readBack(), [](uint32_t i) { return filled(i, 3); });
}

bool warReuse(Env& e, bool bug) {
    const vkf::Buffer staging =
        vkf::createBuffer(e.ctx, Batches * Count * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                          vkf::MemoryUse::Upload, "staging");
    const vkf::Buffer output = vkf::createBuffer(e.ctx, Batches * Count * 4, StorageCopy,
                                                 vkf::MemoryUse::DeviceLocal, "output");
    std::vector<VkDescriptorSet> sets;
    for (uint32_t k = 0; k < Batches; ++k) {
        for (uint32_t i = 0; i < Count; ++i) {
            staging.data<uint32_t>()[k * Count + i] = filled(i, 100 + k);
        }
        sets.push_back(e.pool.allocate(e.transform.setLayout));
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, e.a)
            .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, output, k * Count * 4, Count * 4)
            .update(e.ctx, sets.back());
    }
    staging.flush();
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        for (uint32_t k = 0; k < Batches; ++k) {
            // snippet:begin war-reuse
            if (k > 0 && !bug) {
                // Waits for the last dispatch's reads, and covers the last copy's write.
                const VkMemoryBarrier2 reuse{
                    .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                    .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    .srcAccessMask = VK_ACCESS_2_NONE,
                    .dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
                    .dstAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
                };
                barrier(cmd, reuse);
            }
            const VkBufferCopy region{.srcOffset = k * Count * 4, .size = Count * 4};
            vkCmdCopyBuffer(cmd, staging, e.a, 1, &region);
            const VkMemoryBarrier2 copied{
                .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
                .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
                .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
            };
            barrier(cmd, copied);
            u3::dispatch(cmd, e.transform, sets[k], CountPush{Count}, Count / 256);
            // snippet:end war-reuse
        }
    });
    const auto results = vkf::download<uint32_t>(e.ctx, output, Batches * Count);
    return matches(results,
                   [](uint32_t i) { return transformed(filled(i % Count, 100 + i / Count)); });
}

// Mapped memory from the host-visible type that most needs flushing: non-coherent if any.
struct Mapped {
    vkf::Unique<VkBuffer> buffer;
    vkf::Unique<VkDeviceMemory> memory;
    uint32_t* values = nullptr;
    bool coherent = true;
};

Mapped createMapped(const vkf::Context& ctx, const char* name) {
    const VkBufferCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = Count * 4,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
    };
    VkBuffer buffer = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateBuffer(ctx.device(), &info, nullptr, &buffer));
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(ctx.device(), buffer, &requirements);
    const VkPhysicalDeviceMemoryProperties& memory = ctx.properties().memory;
    int type = -1;
    for (uint32_t i = 0; i < memory.memoryTypeCount; ++i) {
        const VkMemoryPropertyFlags flags = memory.memoryTypes[i].propertyFlags;
        if (!(requirements.memoryTypeBits & (1u << i))) continue;
        if (!(flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) continue;
        if (type < 0 || !(flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) type = int(i);
    }
    if (type < 0) throw std::runtime_error("no host-visible memory type for a storage buffer");
    const VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = uint32_t(type),
    };
    Mapped out;
    VkDeviceMemory allocation = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateMemory(ctx.device(), &allocate, nullptr, &allocation));
    out.buffer = {ctx.device(), buffer};
    out.memory = {ctx.device(), allocation};
    VKF_CHECK(vkBindBufferMemory(ctx.device(), buffer, allocation, 0));
    void* data = nullptr;
    VKF_CHECK(vkMapMemory(ctx.device(), allocation, 0, VK_WHOLE_SIZE, 0, &data));
    out.values = static_cast<uint32_t*>(data);
    out.coherent =
        memory.memoryTypes[type].propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    ctx.name(buffer, name);
    return out;
}

bool hostCoherency(Env& e, bool bug) {
    const Mapped input = createMapped(e.ctx, "mapped input");
    const Mapped output = createMapped(e.ctx, "mapped output");
    for (uint32_t i = 0; i < Count; ++i) input.values[i] = filled(i, 5);
    // snippet:begin flush
    // Host writes to non-coherent memory reach the device only after a flush.
    if (!bug) {
        const VkMappedMemoryRange written{
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = input.memory,
            .offset = 0,
            .size = VK_WHOLE_SIZE,
        };
        VKF_CHECK(vkFlushMappedMemoryRanges(e.ctx.device(), 1, &written));
    }
    // snippet:end flush
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.transformBuffer(cmd, input.buffer, output.buffer);
        toHost(cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
               VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
    });
    // snippet:begin invalidate
    // Without an invalidate, the host may read stale lines from its own caches.
    if (!bug) {
        const VkMappedMemoryRange result{
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = output.memory,
            .offset = 0,
            .size = VK_WHOLE_SIZE,
        };
        VKF_CHECK(vkInvalidateMappedMemoryRanges(e.ctx.device(), 1, &result));
    }
    // snippet:end invalidate
    if (input.coherent && output.coherent) {
        vkf::print(
            "  note: every host-visible memory type here is HOST_COHERENT, so flushes and\n"
            "  invalidates change nothing on this device, and no validation checks them\n");
    }
    const std::vector<uint32_t> values(output.values, output.values + Count);
    return matches(values, [](uint32_t i) { return transformed(filled(i, 5)); });
}

bool semaphoreStage(Env& e, bool bug) {
    const auto pool = vkf::createCommandPool(e.ctx, e.ctx.mainQueue().family);
    VkCommandBuffer produce = vkf::allocateCommandBuffer(e.ctx, pool);
    vkf::beginCommands(produce);
    e.fillBuffer(produce, e.a, 9);
    vkf::endCommands(produce);
    VkCommandBuffer consume = vkf::allocateCommandBuffer(e.ctx, pool);
    vkf::beginCommands(consume);
    const VkBufferCopy region{.size = Count * 4};
    vkCmdCopyBuffer(consume, e.a, e.readback, 1, &region);
    toHost(consume, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT);
    vkf::endCommands(consume);
    // snippet:begin semaphore-stage
    const auto written = vkf::createSemaphore(e.ctx);
    const auto fence = vkf::createFence(e.ctx);
    const vkf::SemaphoreSubmit signal{written, 0, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
    const vkf::SemaphoreSubmit wait{
        written, 0,
        bug ? VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT : VK_PIPELINE_STAGE_2_COPY_BIT};
    vkf::submit(e.ctx.mainQueue(), std::span(&produce, 1), {}, std::span(&signal, 1));
    vkf::submit(e.ctx.mainQueue(), std::span(&consume, 1), std::span(&wait, 1), {}, fence);
    vkf::waitFence(e.ctx, fence);
    // snippet:end semaphore-stage
    return matches(e.readBack(), [](uint32_t i) { return filled(i, 9); });
}

struct Bug {
    const char* name;
    const char* mistake;
    bool (*run)(Env&, bool);
};

constexpr Bug Bugs[] = {
    {"missing-visibility", "an execution dependency with no memory dependency",
     missingVisibility},
    {"wrong-stage", "the copy stage named for vkCmdFillBuffer, which runs in CLEAR",
     wrongStage},
    {"layout-mismatch", "a copy from an image left in GENERAL", layoutMismatch},
    {"war-reuse", "a buffer overwritten while the last dispatch may read it", warReuse},
    {"host-coherency", "mapped memory used without flush or invalidate", hostCoherency},
    {"semaphore-stage", "a semaphore wait at COMPUTE_SHADER before a copy reads",
     semaphoreStage},
};

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const std::string chosen = args.text("--bug", "");
        vkf::Context ctx({.appName = "u3_bugs"});
        u3::MessageLog log(ctx);
        Env env(ctx);

        if (chosen.empty()) {
            bool ok = true;
            for (const Bug& bug : Bugs) {
                env.pool.reset();
                const bool correct = bug.run(env, false);
                const bool clean = log.take().empty();
                ok = ok && correct && clean;
                vkf::print("{:<20}fixed: {}{}\n", bug.name, correct ? "correct" : "WRONG",
                           clean ? "" : ", with validation messages");
            }
            if (!ok) throw std::runtime_error("a fixed version failed");
            vkf::print("PASS {} fixed versions\n", std::size(Bugs));
            return;
        }
        const Bug* bug = nullptr;
        for (const Bug& b : Bugs) {
            if (chosen == b.name) bug = &b;
        }
        if (bug == nullptr) throw std::runtime_error("unknown --bug " + chosen);
        vkf::print("bug {}: {}\n", bug->name, bug->mistake);
        const bool correct = bug->run(env, true);
        std::string sync, core;
        for (const std::string& id : log.take()) {
            std::string& list = id.rfind("SYNC-", 0) == 0 ? sync : core;
            list += (list.empty() ? "" : ", ") + id;
        }
        if (!sync.empty()) vkf::print("  synchronisation validation: {}\n", sync);
        if (!core.empty()) vkf::print("  core validation: {}\n", core);
        if (sync.empty() && core.empty()) vkf::print("  validation: nothing reported\n");
        vkf::print("  results: {}\n", correct ? "correct on this device" : "wrong");
        const std::string by = !sync.empty()   ? "synchronisation validation"
                               : !core.empty() ? "core validation"
                               : !correct      ? "wrong results"
                                               : "nothing on this device";
        throw std::runtime_error("--bug " + chosen + " detected by " + by);
    });
}
