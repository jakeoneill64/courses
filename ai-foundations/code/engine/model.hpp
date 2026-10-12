#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "json.hpp"

namespace aif {

struct Config {
    int vocab, d_model, layers, heads, kv_heads, d_ff, max_seq;
    float rope_theta, norm_eps;
    bool tied;
    int headDim() const { return d_model / heads; }
};

// snippet:begin weight
enum class Kind { F32, I8, Q4 };

struct Weight {
    Kind kind = Kind::F32;
    int rows = 0, cols = 0;
    const void* data = nullptr;
    const float* scale = nullptr;
    const float* f32() const { return static_cast<const float*>(data); }
};
// snippet:end weight

struct Layer {
    Weight attn_norm, mlp_norm, q, k, v, o, gate, up, down;
};

class Model {
public:
    explicit Model(const std::string& path);
    ~Model();
    Model(const Model&) = delete;
    Model& operator=(const Model&) = delete;

    Config config{};
    Weight embed, norm, head;
    std::vector<Layer> layers;
    json::Value header;
    size_t bytes = 0;

private:
    void* map_ = nullptr;
    size_t mapped_ = 0;
};

}  // namespace aif
