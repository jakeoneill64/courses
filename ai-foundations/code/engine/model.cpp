#include "model.hpp"

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstring>
#include <stdexcept>

namespace aif {

namespace {

Weight weightFrom(const json::Value& entry, const char* base) {
    Weight w;
    const std::string& kind = entry["kind"].str();
    w.kind = kind == "i8" ? Kind::I8 : kind == "q4" ? Kind::Q4 : Kind::F32;
    const auto& shape = entry["shape"];
    w.rows = static_cast<int>(shape[0].num());
    w.cols = shape.size() > 1 ? static_cast<int>(shape[1].num()) : 1;
    const auto& offsets = entry["offsets"];
    w.data = base + static_cast<size_t>(offsets[0].num());
    if (offsets.size() > 1)
        w.scale = reinterpret_cast<const float*>(base + static_cast<size_t>(offsets[1].num()));
    return w;
}

size_t weightBytes(const Weight& w) {
    size_t n = static_cast<size_t>(w.rows) * w.cols;
    if (w.kind == Kind::I8) return n + w.rows * sizeof(float);
    if (w.kind == Kind::Q4) return n / 2 + n / 32 * sizeof(float);
    return n * sizeof(float);
}

}  // namespace

// snippet:begin load
Model::Model(const std::string& path) {
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) throw std::runtime_error("cannot open " + path);
    struct stat st{};
    fstat(fd, &st);
    mapped_ = static_cast<size_t>(st.st_size);
    map_ = mmap(nullptr, mapped_, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map_ == MAP_FAILED) throw std::runtime_error("cannot map " + path);
    const char* file = static_cast<const char*>(map_);
    if (std::memcmp(file, "AIF1", 4) != 0)
        throw std::runtime_error(path + " is not an AIF1 file");
    uint32_t length;
    std::memcpy(&length, file + 4, 4);
    header = json::parse(std::string_view(file + 8, length));
    const char* base = file + (8 + length + 63) / 64 * 64;
    // snippet:end load

    const auto& c = header["config"];
    config = {
        static_cast<int>(c["vocab"].num()),      static_cast<int>(c["d_model"].num()),
        static_cast<int>(c["layers"].num()),     static_cast<int>(c["heads"].num()),
        static_cast<int>(c["kv_heads"].num()),   static_cast<int>(c["d_ff"].num()),
        static_cast<int>(c["max_seq"].num()),    static_cast<float>(c["rope_theta"].num()),
        static_cast<float>(c["norm_eps"].num()), c["tied"].boolean()};
    layers.resize(config.layers);
    for (const auto& entry : header["tensors"].array()) {
        const std::string& name = entry["name"].str();
        Weight w = weightFrom(entry, base);
        bytes += weightBytes(w);
        if (name == "embed")
            embed = w;
        else if (name == "norm")
            norm = w;
        else if (name == "head")
            head = w;
        else {
            size_t dot = name.find('.');
            Layer& L = layers.at(std::stoul(name.substr(0, dot)));
            std::string part = name.substr(dot + 1);
            Weight* slot = part == "attn_norm"  ? &L.attn_norm
                           : part == "mlp_norm" ? &L.mlp_norm
                           : part == "q"        ? &L.q
                           : part == "k"        ? &L.k
                           : part == "v"        ? &L.v
                           : part == "o"        ? &L.o
                           : part == "gate"     ? &L.gate
                           : part == "up"       ? &L.up
                           : part == "down"     ? &L.down
                                                : nullptr;
            if (!slot) throw std::runtime_error("unknown tensor " + name);
            *slot = w;
        }
    }
    if (!head.data) head = embed;
}

Model::~Model() {
    if (map_ && map_ != MAP_FAILED) munmap(map_, mapped_);
}

}  // namespace aif
