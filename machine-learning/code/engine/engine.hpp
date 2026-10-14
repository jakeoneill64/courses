#pragma once

#include <functional>
#include <random>
#include <vector>

#include "model.hpp"
#include "ops.hpp"

namespace aif {

struct Sampling {
    float temperature = 0.0f;
    float top_p = 1.0f;
    unsigned seed = 0;
};

class Engine {
public:
    Engine(const Model& model, int threads);
    const float* forward(int token, int pos);
    std::vector<int> generate(const std::vector<int>& prompt, int max_new, int stop,
                              const Sampling& sampling,
                              const std::function<void(int)>& on_token = {});
    int sample(const float* logits, const Sampling& sampling);

private:
    const Model& m_;
    const Config& c_;
    ThreadPool pool_;
    std::vector<float> x_, xb_, xb2_, q_, k_, v_, att_, attOut_, hb_, hb2_, logits_, kcache_,
        vcache_;
    std::mt19937 rng_;
    float* kAt(int layer, int pos) {
        return kcache_.data() +
               ((static_cast<size_t>(layer) * c_.max_seq + pos) * c_.kv_heads) * c_.headDim();
    }
    float* vAt(int layer, int pos) {
        return vcache_.data() +
               ((static_cast<size_t>(layer) * c_.max_seq + pos) * c_.kv_heads) * c_.headDim();
    }
    void attention(int layer, int pos);
};

}  // namespace aif
