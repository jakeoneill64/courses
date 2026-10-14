#pragma once

#include <vkf/vkf.hpp>

#include <vector>

#include "compute.hpp"
#include "rendergraph.hpp"

namespace demo {

struct Stats {
    uint32_t selected;
    uint32_t blurredSum;
    uint32_t indexXor;
    uint32_t pad;
};

// The objects one run of the pipeline works on, whether made by hand or by the graph.
struct Targets {
    VkImage field = VK_NULL_HANDLE;
    VkImageView fieldView = VK_NULL_HANDLE;
    VkBuffer blurred = VK_NULL_HANDLE;
    VkBuffer edges = VK_NULL_HANDLE;
    VkImage mask = VK_NULL_HANDLE;
    VkImageView maskView = VK_NULL_HANDLE;
    VkBuffer stats = VK_NULL_HANDLE;
    VkBuffer list = VK_NULL_HANDLE;
    VkBuffer command = VK_NULL_HANDLE;
    VkBuffer results = VK_NULL_HANDLE;
};

struct Kernels {
    explicit Kernels(const vkf::Context& ctx);
    u3::Kernel generate, blur, edges, select, command, score;
};

// The commands of each pass, without any barriers.
class Pipeline {
public:
    Pipeline(const vkf::Context& ctx, const Kernels& kernels, const Targets& targets,
             uint32_t side);
    void clearStats(VkCommandBuffer cmd) const;
    void generate(VkCommandBuffer cmd) const;
    void blur(VkCommandBuffer cmd) const;
    void edges(VkCommandBuffer cmd) const;
    void select(VkCommandBuffer cmd) const;
    void command(VkCommandBuffer cmd) const;
    void score(VkCommandBuffer cmd) const;
    void readback(VkCommandBuffer cmd) const;

private:
    const Kernels& kernels_;
    Targets targets_;
    uint32_t side_;
    vkf::DescriptorPool pool_;
    VkDescriptorSet generateSet_, blurSet_, edgesSet_, selectSet_, commandSet_, scoreSet_;
};

// The results buffer holds the Stats and then the mask, one uint per cell.
VkDeviceSize resultsSize(uint32_t side);
bool verify(const vkf::Buffer& results, uint32_t side, Stats& got);

// Records with hand-written barriers and returns them, one entry per pass, for comparison.
std::vector<rg::Barriers> recordByHand(VkCommandBuffer cmd, const Pipeline& pipeline,
                                       const Targets& targets);

}  // namespace demo
