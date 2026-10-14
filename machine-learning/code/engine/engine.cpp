#include "engine.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <numeric>
#include <stdexcept>

namespace aif {

Engine::Engine(const Model& model, int threads)
    : m_(model),
      c_(model.config),
      pool_(threads),
      x_(c_.d_model),
      xb_(c_.d_model),
      xb2_(c_.d_model),
      q_(c_.heads * c_.headDim()),
      k_(c_.kv_heads * c_.headDim()),
      v_(c_.kv_heads * c_.headDim()),
      att_(static_cast<size_t>(c_.heads) * c_.max_seq),
      attOut_(c_.heads * c_.headDim()),
      hb_(c_.d_ff),
      hb2_(c_.d_ff),
      logits_(c_.vocab),
      kcache_(static_cast<size_t>(c_.layers) * c_.max_seq * c_.kv_heads * c_.headDim()),
      vcache_(kcache_.size()) {}

// snippet:begin attention
void Engine::attention(int layer, int pos) {
    const int hd = c_.headDim(), group = c_.heads / c_.kv_heads;
    const float scale = 1.0f / std::sqrt(static_cast<float>(hd));
    pool_.parallelFor(c_.heads, [&](int begin, int end) {
        for (int h = begin; h < end; ++h) {
            const float* q = q_.data() + h * hd;
            float* scores = att_.data() + static_cast<size_t>(h) * c_.max_seq;
            int kv = h / group;
            for (int t = 0; t <= pos; ++t) {
                const float* k = kAt(layer, t) + kv * hd;
                float dot = 0.0f;
                for (int i = 0; i < hd; ++i) dot += q[i] * k[i];
                scores[t] = dot * scale;
            }
            softmax(scores, pos + 1);
            float* out = attOut_.data() + h * hd;
            std::fill(out, out + hd, 0.0f);
            for (int t = 0; t <= pos; ++t) {
                const float* v = vAt(layer, t) + kv * hd;
                for (int i = 0; i < hd; ++i) out[i] += scores[t] * v[i];
            }
        }
    });
}
// snippet:end attention

// snippet:begin forward
const float* Engine::forward(int token, int pos) {
    if (pos >= c_.max_seq)
        throw std::runtime_error("sequence longer than the model's context");
    const int d = c_.d_model, kvDim = c_.kv_heads * c_.headDim();
    std::memcpy(x_.data(), m_.embed.f32() + static_cast<size_t>(token) * d, d * sizeof(float));
    for (int l = 0; l < c_.layers; ++l) {
        const Layer& L = m_.layers[l];
        rmsnorm(xb_.data(), x_.data(), L.attn_norm.f32(), d, c_.norm_eps);
        matvec(L.q, xb_.data(), q_.data(), pool_);
        matvec(L.k, xb_.data(), k_.data(), pool_);
        matvec(L.v, xb_.data(), v_.data(), pool_);
        rope(q_.data(), c_.heads, c_.headDim(), pos, c_.rope_theta);
        rope(k_.data(), c_.kv_heads, c_.headDim(), pos, c_.rope_theta);
        std::memcpy(kAt(l, pos), k_.data(), kvDim * sizeof(float));
        std::memcpy(vAt(l, pos), v_.data(), kvDim * sizeof(float));
        attention(l, pos);
        matvec(L.o, attOut_.data(), xb2_.data(), pool_);
        for (int i = 0; i < d; ++i) x_[i] += xb2_[i];
        rmsnorm(xb_.data(), x_.data(), L.mlp_norm.f32(), d, c_.norm_eps);
        matvec(L.gate, xb_.data(), hb_.data(), pool_);
        matvec(L.up, xb_.data(), hb2_.data(), pool_);
        for (int i = 0; i < c_.d_ff; ++i)
            hb_[i] = hb_[i] / (1.0f + std::exp(-hb_[i])) * hb2_[i];
        matvec(L.down, hb_.data(), xb2_.data(), pool_);
        for (int i = 0; i < d; ++i) x_[i] += xb2_[i];
    }
    rmsnorm(x_.data(), x_.data(), m_.norm.f32(), d, c_.norm_eps);
    matvec(m_.head, x_.data(), logits_.data(), pool_);
    return logits_.data();
}
// snippet:end forward

// snippet:begin sample
int Engine::sample(const float* logits, const Sampling& s) {
    if (s.temperature <= 0.0f)
        return static_cast<int>(std::max_element(logits, logits + c_.vocab) - logits);
    std::vector<float> p(logits, logits + c_.vocab);
    for (float& v : p) v /= s.temperature;
    softmax(p.data(), c_.vocab);
    std::vector<int> order(c_.vocab);
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) { return p[a] > p[b]; });
    float kept = 0.0f;
    size_t n = 0;
    while (n < order.size() && kept < s.top_p) kept += p[order[n++]];
    std::uniform_real_distribution<float> uniform(0.0f, kept);
    float r = uniform(rng_);
    for (size_t i = 0; i < n; ++i) {
        r -= p[order[i]];
        if (r <= 0.0f) return order[i];
    }
    return order[n - 1];
}
// snippet:end sample

std::vector<int> Engine::generate(const std::vector<int>& prompt, int max_new, int stop,
                                  const Sampling& s,
                                  const std::function<void(int)>& on_token) {
    rng_.seed(s.seed);
    const float* logits = nullptr;
    int pos = 0;
    for (int t : prompt) logits = forward(t, pos++);
    std::vector<int> out;
    while (static_cast<int>(out.size()) < max_new && pos < c_.max_seq) {
        int next = sample(logits, s);
        out.push_back(next);
        if (on_token) on_token(next);
        if (next == stop) break;
        logits = forward(next, pos++);
    }
    return out;
}

}  // namespace aif
