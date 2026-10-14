#pragma once

#include <vkf/vkf.hpp>

#include <functional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace rg {

// snippet:begin use
// How a pass uses a resource: the stages and accesses, and for an image the layout it needs.
struct Use {
    VkPipelineStageFlags2 stages = VK_PIPELINE_STAGE_2_NONE;
    VkAccessFlags2 access = VK_ACCESS_2_NONE;
    VkImageLayout layout = VK_IMAGE_LAYOUT_UNDEFINED;
};
// snippet:end use

// snippet:begin presets
inline constexpr Use ComputeRead{VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                 VK_ACCESS_2_SHADER_STORAGE_READ_BIT, VK_IMAGE_LAYOUT_GENERAL};
inline constexpr Use ComputeWrite{VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                  VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
                                  VK_IMAGE_LAYOUT_GENERAL};
inline constexpr Use IndirectRead{VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
                                  VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT};
inline constexpr Use CopySource{VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT,
                                VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL};
inline constexpr Use CopyDestination{VK_PIPELINE_STAGE_2_COPY_BIT,
                                     VK_ACCESS_2_TRANSFER_WRITE_BIT,
                                     VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL};
inline constexpr Use ClearDestination{VK_PIPELINE_STAGE_2_CLEAR_BIT,
                                      VK_ACCESS_2_TRANSFER_WRITE_BIT,
                                      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL};
inline constexpr Use HostRead{VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT};
inline constexpr Use VertexInput{VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT,
                                 VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT};
inline constexpr Use IndexInput{VK_PIPELINE_STAGE_2_INDEX_INPUT_BIT,
                                VK_ACCESS_2_INDEX_READ_BIT};
inline constexpr Use FragmentSampled{VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                                     VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
                                     VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
inline constexpr Use ColorAttachment{
    VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
inline constexpr Use DepthAttachment{
    VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
        VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
// Nothing in the queue waits for presentation; vkQueuePresentKHR waits on a semaphore instead.
inline constexpr Use Present{VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                             VK_IMAGE_LAYOUT_PRESENT_SRC_KHR};
// snippet:end presets

enum class Queue { Main, Compute };

using Resource = uint32_t;

class Graph;

// snippet:begin builder
class PassBuilder {
public:
    // The pass needs the resource's current contents.
    PassBuilder& read(Resource resource, Use use);
    // The pass produces new contents; also call read() when it reads the old ones.
    PassBuilder& write(Resource resource, Use use);
    // Keeps the pass even when no kept pass reads what it writes: readbacks, presentation.
    PassBuilder& sideEffect();
    // Runs on the async compute queue when the context has one, otherwise on the main queue.
    PassBuilder& queue(Queue queue);

private:
    friend class Graph;
    PassBuilder(Graph& graph, uint32_t pass) : graph_(graph), pass_(pass) {}
    Graph& graph_;
    uint32_t pass_;
};
// snippet:end builder

// The barriers recorded in one vkCmdPipelineBarrier2 call before a pass.
struct Barriers {
    std::vector<VkMemoryBarrier2> memory;
    std::vector<VkImageMemoryBarrier2> images;
};

class Graph {
public:
    explicit Graph(const vkf::Context& ctx) : ctx_(ctx) {}
    Graph(const Graph&) = delete;
    Graph& operator=(const Graph&) = delete;

    // snippet:begin resources
    // A resource made outside the graph; `previous` is its last use before the graph runs.
    Resource importBuffer(std::string name, VkBuffer buffer, Use previous = {});
    Resource importImage(std::string name, VkImage image, VkImageView view,
                         VkImageSubresourceRange range, Use previous = {});
    // Made by compile(); transients whose lifetimes do not overlap may share memory.
    Resource createBuffer(std::string name, VkDeviceSize size, VkBufferUsageFlags usage);
    Resource createImage(std::string name, const vkf::ImageDesc& desc);
    // snippet:end resources

    PassBuilder addPass(std::string name, std::function<void(VkCommandBuffer)> record = {});

    // Throws if a kept pass reads a transient before any pass writes it.
    void compile(bool aliasMemory = true);

    VkBuffer buffer(Resource resource) const { return resources_.at(resource).buffer; }
    VkImage image(Resource resource) const { return resources_.at(resource).image; }
    VkImageView view(Resource resource) const { return resources_.at(resource).view; }
    // Points an import at another object, such as this frame's swapchain image.
    void rebind(Resource resource, VkBuffer buffer, VkImage image = VK_NULL_HANDLE,
                VkImageView view = VK_NULL_HANDLE);

    // Records every kept pass with its barriers; only when all of them run on one queue.
    void record(VkCommandBuffer cmd);
    // The first main-queue batch waits on `waits`; the last runs last and signals the rest.
    void submit(std::span<const vkf::SemaphoreSubmit> waits = {},
                std::span<const vkf::SemaphoreSubmit> signals = {},
                VkFence fence = VK_NULL_HANDLE);

    void printPlan() const;
    void writeDot(const std::string& path) const;
    // GPU ms per kept pass, from the end of the work before it on its queue to its own end.
    std::vector<std::pair<std::string, double>> passTimes() const;
    std::vector<Barriers> barriers() const;

private:
    friend class PassBuilder;
    struct Access {
        Resource resource;
        Use use;
        bool reads, writes;
    };
    struct Pass {
        std::string name;
        std::function<void(VkCommandBuffer)> record;
        std::vector<Access> accesses;
        Queue queue = Queue::Main;
        bool sideEffect = false, kept = false;
    };
    struct ResourceInfo {
        std::string name;
        bool isImage = false, transient = false;
        VkBuffer buffer = VK_NULL_HANDLE;
        VkImage image = VK_NULL_HANDLE;
        VkImageView view = VK_NULL_HANDLE;
        VkImageSubresourceRange range{};
        VkDeviceSize size = 0;
        VkBufferUsageFlags usage = 0;
        vkf::ImageDesc desc;
        Use previous;
        int first = -1, last = -1;
        VkMemoryRequirements memory{};
        VkDeviceSize offset = 0;
        std::vector<Resource> reuses;
    };
    // One dependency before a pass, for one resource or for several merged into one barrier.
    struct Dependency {
        std::vector<Resource> resources;
        VkPipelineStageFlags2 srcStages = 0, dstStages = 0;
        VkAccessFlags2 srcAccess = 0, dstAccess = 0;
        VkImageLayout oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, newLayout = oldLayout;
        bool transition = false;
    };
    struct Batch {
        Queue queue = Queue::Main;
        std::vector<uint32_t> passes;
        std::vector<std::pair<int, VkPipelineStageFlags2>> waits;
        VkCommandBuffer cmd = VK_NULL_HANDLE;
        uint64_t value = 0;
    };
    struct Sim;

    void addAccess(uint32_t pass, Resource resource, Use use, bool reads, bool writes);
    Queue queueOf(uint32_t position) const;
    void cull();
    void placeTransients(bool aliasMemory);
    std::vector<std::vector<Dependency>> derive(const std::vector<int>& batchOf,
                                                std::vector<Batch>& batches) const;
    void formBatches();
    Barriers vulkanBarriers(uint32_t position) const;
    void recordBatch(const Batch& batch, VkCommandBuffer cmd);

    const vkf::Context& ctx_;
    std::vector<Pass> passes_;
    std::vector<ResourceInfo> resources_;
    std::vector<uint32_t> order_;
    std::vector<std::vector<Dependency>> plan_;
    std::vector<Batch> batches_;
    VkDeviceSize aliasedBytes_ = 0, separateBytes_ = 0;
    vkf::Unique<VkDeviceMemory> memory_;
    std::vector<vkf::Unique<VkBuffer>> ownedBuffers_;
    std::vector<vkf::Unique<VkImage>> ownedImages_;
    std::vector<vkf::Unique<VkImageView>> ownedViews_;
    vkf::Unique<VkQueryPool> timestamps_;
    vkf::Unique<VkCommandPool> pools_[2];
    vkf::Unique<VkSemaphore> timelines_[2];
    uint64_t submitted_[2] = {};
};

}  // namespace rg
