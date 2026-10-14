#pragma once

#include <vulkan/vulkan.h>

#include <chrono>
#include <cstdint>
#include <vector>

#include "vkf/context.hpp"
#include "vkf/handles.hpp"

namespace vkf {

// Call reset() in the command buffer before its first stamp(), and read() after it finishes.
class GpuTimer {
public:
    explicit GpuTimer(const Context& ctx, uint32_t capacity = 64);

    void reset(VkCommandBuffer cmd);
    uint32_t stamp(VkCommandBuffer cmd,
                   VkPipelineStageFlags2 stage = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT);
    // Milliseconds from the first stamp to each later one; waits for the results.
    std::vector<double> read();
    double elapsedMs(uint32_t from, uint32_t to);

private:
    const Context* ctx_;
    Unique<VkQueryPool> pool_;
    uint32_t capacity_;
    uint32_t used_ = 0;
    double periodNs_;
    uint64_t validMask_;
    std::vector<double> lastRead_;
};

class CpuTimer {
public:
    CpuTimer() { restart(); }
    void restart() { start_ = std::chrono::steady_clock::now(); }
    double elapsedMs() const {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() -
                                                         start_)
            .count();
    }

private:
    std::chrono::steady_clock::time_point start_;
};

struct Stats {
    double min = 0;
    double median = 0;
    double mean = 0;
    double max = 0;
};

Stats summarize(std::vector<double> samples);

}  // namespace vkf
