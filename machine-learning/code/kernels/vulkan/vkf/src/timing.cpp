#include "vkf/timing.hpp"

#include <algorithm>
#include <numeric>

#include "vkf/check.hpp"

namespace vkf {

// snippet:begin query-pool
GpuTimer::GpuTimer(const Context& ctx, uint32_t capacity) : ctx_(&ctx), capacity_(capacity) {
    const uint32_t bits =
        ctx.properties().queueFamilies[ctx.mainQueue().family].timestampValidBits;
    if (bits == 0) {
        throw Error(VK_ERROR_FEATURE_NOT_PRESENT,
                    "the main queue does not support timestamps");
    }
    validMask_ = bits >= 64 ? ~0ull : ((1ull << bits) - 1);
    periodNs_ = ctx.properties().core.limits.timestampPeriod;

    VkQueryPoolCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
        .queryType = VK_QUERY_TYPE_TIMESTAMP,
        .queryCount = capacity,
    };
    VkQueryPool pool = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateQueryPool(ctx.device(), &info, nullptr, &pool));
    pool_ = Unique<VkQueryPool>(ctx.device(), pool);
}
// snippet:end query-pool

// snippet:begin stamp
void GpuTimer::reset(VkCommandBuffer cmd) {
    vkCmdResetQueryPool(cmd, pool_, 0, capacity_);
    used_ = 0;
    lastRead_.clear();
}

uint32_t GpuTimer::stamp(VkCommandBuffer cmd, VkPipelineStageFlags2 stage) {
    if (used_ == capacity_) {
        throw Error(VK_ERROR_OUT_OF_POOL_MEMORY,
                    "GpuTimer is full; create it with a larger capacity");
    }
    vkCmdWriteTimestamp2(cmd, stage, pool_, used_);
    return used_++;
}
// snippet:end stamp

// snippet:begin read
std::vector<double> GpuTimer::read() {
    std::vector<uint64_t> ticks(used_);
    if (used_ > 0) {
        VKF_CHECK(vkGetQueryPoolResults(
            ctx_->device(), pool_, 0, used_, ticks.size() * sizeof(uint64_t), ticks.data(),
            sizeof(uint64_t), VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT));
    }
    lastRead_.assign(used_, 0.0);
    for (uint32_t i = 1; i < used_; ++i) {
        const uint64_t delta = (ticks[i] - ticks[0]) & validMask_;
        lastRead_[i] = static_cast<double>(delta) * periodNs_ / 1e6;
    }
    return lastRead_;
}
// snippet:end read

double GpuTimer::elapsedMs(uint32_t from, uint32_t to) {
    if (lastRead_.size() != used_) read();
    return lastRead_.at(to) - lastRead_.at(from);
}

Stats summarize(std::vector<double> samples) {
    if (samples.empty()) return {};
    std::sort(samples.begin(), samples.end());
    const size_t n = samples.size();
    const double median = n % 2 ? samples[n / 2] : (samples[n / 2 - 1] + samples[n / 2]) / 2;
    const double mean =
        std::accumulate(samples.begin(), samples.end(), 0.0) / static_cast<double>(n);
    return {samples.front(), median, mean, samples.back()};
}

}  // namespace vkf
