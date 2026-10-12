#pragma once

#include <atomic>
#include <functional>
#include <thread>
#include <vector>

#include "model.hpp"

namespace aif {

// snippet:begin pool
class ThreadPool {
public:
    explicit ThreadPool(int threads);
    ~ThreadPool();
    void parallelFor(int n, const std::function<void(int, int)>& fn);
    int size() const { return static_cast<int>(workers_.size()) + 1; }

private:
    std::vector<std::thread> workers_;
    const std::function<void(int, int)>* job_ = nullptr;
    int n_ = 0, chunk_ = 1;
    std::atomic<int> next_{0}, pending_{0};
    std::atomic<uint64_t> epoch_{0};
    std::atomic<bool> stop_{false};
    void work();
};
// snippet:end pool

void matvec(const Weight& w, const float* x, float* y, ThreadPool& pool);
void rmsnorm(float* out, const float* x, const float* weight, int n, float eps);
void rope(float* v, int heads, int headDim, int pos, float theta);
void softmax(float* x, int n);

}  // namespace aif
