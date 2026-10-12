#include "ops.hpp"

#include <algorithm>
#include <cmath>

#if defined(__ARM_NEON)
#include <arm_neon.h>
#endif

namespace aif {

ThreadPool::ThreadPool(int threads) {
    for (int i = 1; i < threads; ++i) {
        workers_.emplace_back([this] {
            uint64_t seen = 0;
            while (!stop_.load(std::memory_order_acquire)) {
                uint64_t e = epoch_.load(std::memory_order_acquire);
                if (e == seen) {
                    std::this_thread::yield();
                    continue;
                }
                seen = e;
                work();
                pending_.fetch_sub(1, std::memory_order_acq_rel);
            }
        });
    }
}

ThreadPool::~ThreadPool() {
    stop_.store(true, std::memory_order_release);
    for (auto& t : workers_) t.join();
}

void ThreadPool::work() {
    for (;;) {
        int begin = next_.fetch_add(chunk_, std::memory_order_relaxed);
        if (begin >= n_) return;
        (*job_)(begin, std::min(n_, begin + chunk_));
    }
}

// snippet:begin parallel-for
void ThreadPool::parallelFor(int n, const std::function<void(int, int)>& fn) {
    if (workers_.empty()) {
        fn(0, n);
        return;
    }
    job_ = &fn;
    n_ = n;
    chunk_ = std::max(1, n / (size() * 8));
    next_.store(0, std::memory_order_relaxed);
    pending_.store(static_cast<int>(workers_.size()), std::memory_order_relaxed);
    epoch_.fetch_add(1, std::memory_order_release);
    work();
    while (pending_.load(std::memory_order_acquire) > 0) std::this_thread::yield();
}
// snippet:end parallel-for

namespace {

// snippet:begin dot
float dotF32(const float* w, const float* x, int n) {
    int i = 0;
    float sum = 0.0f;
#if defined(__ARM_NEON)
    float32x4_t a0 = vdupq_n_f32(0), a1 = a0, a2 = a0, a3 = a0;
    for (; i + 16 <= n; i += 16) {
        a0 = vfmaq_f32(a0, vld1q_f32(w + i), vld1q_f32(x + i));
        a1 = vfmaq_f32(a1, vld1q_f32(w + i + 4), vld1q_f32(x + i + 4));
        a2 = vfmaq_f32(a2, vld1q_f32(w + i + 8), vld1q_f32(x + i + 8));
        a3 = vfmaq_f32(a3, vld1q_f32(w + i + 12), vld1q_f32(x + i + 12));
    }
    sum = vaddvq_f32(vaddq_f32(vaddq_f32(a0, a1), vaddq_f32(a2, a3)));
#endif
    for (; i < n; ++i) sum += w[i] * x[i];
    return sum;
}
// snippet:end dot

// snippet:begin dot-quantised
float dotI8(const int8_t* w, const float* x, int n) {
    int i = 0;
    float sum = 0.0f;
#if defined(__ARM_NEON)
    float32x4_t a0 = vdupq_n_f32(0), a1 = a0, a2 = a0, a3 = a0;
    for (; i + 16 <= n; i += 16) {
        int8x16_t bytes = vld1q_s8(w + i);
        int16x8_t low = vmovl_s8(vget_low_s8(bytes)), high = vmovl_s8(vget_high_s8(bytes));
        a0 = vfmaq_f32(a0, vcvtq_f32_s32(vmovl_s16(vget_low_s16(low))), vld1q_f32(x + i));
        a1 = vfmaq_f32(a1, vcvtq_f32_s32(vmovl_s16(vget_high_s16(low))), vld1q_f32(x + i + 4));
        a2 = vfmaq_f32(a2, vcvtq_f32_s32(vmovl_s16(vget_low_s16(high))), vld1q_f32(x + i + 8));
        a3 = vfmaq_f32(a3, vcvtq_f32_s32(vmovl_s16(vget_high_s16(high))),
                       vld1q_f32(x + i + 12));
    }
    sum = vaddvq_f32(vaddq_f32(vaddq_f32(a0, a1), vaddq_f32(a2, a3)));
#endif
    for (; i < n; ++i) sum += static_cast<float>(w[i]) * x[i];
    return sum;
}

float dotQ4(const uint8_t* w, const float* scale, const float* x, int n) {
    float sum = 0.0f;
    for (int g = 0; g < n / 32; ++g) {
        const uint8_t* p = w + g * 16;
        const float* xg = x + g * 32;
        float part = 0.0f;
#if defined(__ARM_NEON)
        uint8x16_t bytes = vld1q_u8(p);
        int8x16_t eight = vdupq_n_s8(8);
        int8x16_t lo = vsubq_s8(
            veorq_s8(vreinterpretq_s8_u8(vandq_u8(bytes, vdupq_n_u8(0xF))), eight), eight);
        int8x16_t hi =
            vsubq_s8(veorq_s8(vreinterpretq_s8_u8(vshrq_n_u8(bytes, 4)), eight), eight);
        int8x16x2_t values = vzipq_s8(lo, hi);
        float32x4_t acc = vdupq_n_f32(0);
        for (int half = 0; half < 2; ++half) {
            int16x8_t a = vmovl_s8(vget_low_s8(values.val[half]));
            int16x8_t b = vmovl_s8(vget_high_s8(values.val[half]));
            const float* xs = xg + half * 16;
            acc = vfmaq_f32(acc, vcvtq_f32_s32(vmovl_s16(vget_low_s16(a))), vld1q_f32(xs));
            acc =
                vfmaq_f32(acc, vcvtq_f32_s32(vmovl_s16(vget_high_s16(a))), vld1q_f32(xs + 4));
            acc = vfmaq_f32(acc, vcvtq_f32_s32(vmovl_s16(vget_low_s16(b))), vld1q_f32(xs + 8));
            acc =
                vfmaq_f32(acc, vcvtq_f32_s32(vmovl_s16(vget_high_s16(b))), vld1q_f32(xs + 12));
        }
        sum += vaddvq_f32(acc) * scale[g];
        continue;
#endif
        for (int j = 0; j < 16; ++j) {
            int lo = (p[j] & 0xF) ^ 8, hi = (p[j] >> 4) ^ 8;
            part += static_cast<float>(lo - 8) * xg[2 * j] +
                    static_cast<float>(hi - 8) * xg[2 * j + 1];
        }
        sum += part * scale[g];
    }
    return sum;
}
// snippet:end dot-quantised

}  // namespace

// snippet:begin matvec
void matvec(const Weight& w, const float* x, float* y, ThreadPool& pool) {
    pool.parallelFor(w.rows, [&](int begin, int end) {
        for (int r = begin; r < end; ++r) {
            size_t row = static_cast<size_t>(r) * w.cols;
            if (w.kind == Kind::F32) {
                y[r] = dotF32(w.f32() + row, x, w.cols);
            } else if (w.kind == Kind::I8) {
                y[r] = dotI8(static_cast<const int8_t*>(w.data) + row, x, w.cols) * w.scale[r];
            } else {
                y[r] = dotQ4(static_cast<const uint8_t*>(w.data) + row / 2, w.scale + row / 32,
                             x, w.cols);
            }
        }
    });
}
// snippet:end matvec

void rmsnorm(float* out, const float* x, const float* weight, int n, float eps) {
    float ss = 0.0f;
    for (int i = 0; i < n; ++i) ss += x[i] * x[i];
    float inv = 1.0f / std::sqrt(ss / n + eps);
    for (int i = 0; i < n; ++i) out[i] = weight[i] * (x[i] * inv);
}

// snippet:begin rope
void rope(float* v, int heads, int headDim, int pos, float theta) {
    int half = headDim / 2;
    for (int i = 0; i < half; ++i) {
        float freq = 1.0f / std::pow(theta, static_cast<float>(2 * i) / headDim);
        float angle = static_cast<float>(pos) * freq;
        float c = std::cos(angle), s = std::sin(angle);
        for (int h = 0; h < heads; ++h) {
            float* p = v + h * headDim;
            float x1 = p[i], x2 = p[i + half];
            p[i] = x1 * c - x2 * s;
            p[i + half] = x2 * c + x1 * s;
        }
    }
}
// snippet:end rope

void softmax(float* x, int n) {
    float peak = *std::max_element(x, x + n), sum = 0.0f;
    for (int i = 0; i < n; ++i) sum += (x[i] = std::exp(x[i] - peak));
    for (int i = 0; i < n; ++i) x[i] /= sum;
}

}  // namespace aif
