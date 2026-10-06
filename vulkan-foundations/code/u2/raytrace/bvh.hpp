#pragma once

#include <algorithm>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <vector>

#include "scene.hpp"

namespace rt {

struct Bounds {
    Vec3 lo{std::numeric_limits<float>::max(), std::numeric_limits<float>::max(),
            std::numeric_limits<float>::max()};
    Vec3 hi{-std::numeric_limits<float>::max(), -std::numeric_limits<float>::max(),
            -std::numeric_limits<float>::max()};

    void grow(Vec3 p) {
        lo = {std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z)};
        hi = {std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z)};
    }
    void grow(const Bounds& b) {
        if (b.lo.x > b.hi.x) return;
        grow(b.lo);
        grow(b.hi);
    }
    float area() const {
        const Vec3 d = hi - lo;
        return d.x < 0 ? 0 : 2 * (d.x * d.y + d.y * d.z + d.z * d.x);
    }
};

// The stack in trace.glsl holds one entry per level, so the depth must stay below its size.
constexpr uint32_t maxBvhDepth = 32;

class BvhBuilder {
public:
    explicit BvhBuilder(std::vector<Triangle>& triangles);
    std::vector<Node> nodes;
    uint32_t depth = 0;

private:
    static constexpr int bins = 16;
    struct Split {
        int axis = -1;
        int bin = 0;
        float cost = std::numeric_limits<float>::max();
    };
    Split bestSplit(uint32_t first, uint32_t count, const Bounds& centres) const;
    void subdivide(uint32_t index, uint32_t first, uint32_t count, uint32_t level);
    int binOf(Vec3 centroid, int axis, const Bounds& centres) const;

    std::vector<uint32_t> order_;
    std::vector<Bounds> bounds_;
    std::vector<Vec3> centroids_;
};

inline BvhBuilder::BvhBuilder(std::vector<Triangle>& triangles) {
    const auto n = uint32_t(triangles.size());
    order_.resize(n);
    std::iota(order_.begin(), order_.end(), 0u);
    for (const Triangle& t : triangles) {
        Bounds b;
        b.grow(t.v0);
        b.grow(t.v0 + t.edge1);
        b.grow(t.v0 + t.edge2);
        bounds_.push_back(b);
        centroids_.push_back(t.v0 + (1.0f / 3) * (t.edge1 + t.edge2));
    }
    nodes.reserve(2 * size_t(n));
    nodes.push_back({});
    if (n > 0) subdivide(0, 0, n, 1);
    std::vector<Triangle> sorted;
    for (uint32_t i : order_) sorted.push_back(triangles[i]);
    triangles = std::move(sorted);
}

inline int BvhBuilder::binOf(Vec3 centroid, int axis, const Bounds& centres) const {
    const float extent = centres.hi[axis] - centres.lo[axis];
    const int bin = int((centroid[axis] - centres.lo[axis]) / extent * bins);
    return std::clamp(bin, 0, bins - 1);
}

// snippet:begin sah
inline BvhBuilder::Split BvhBuilder::bestSplit(uint32_t first, uint32_t count,
                                               const Bounds& centres) const {
    Split best;
    for (int axis = 0; axis < 3; ++axis) {
        if (centres.hi[axis] <= centres.lo[axis]) continue;
        Bounds binBounds[bins];
        uint32_t binCounts[bins] = {};
        for (uint32_t i = first; i < first + count; ++i) {
            const int bin = binOf(centroids_[order_[i]], axis, centres);
            binBounds[bin].grow(bounds_[order_[i]]);
            ++binCounts[bin];
        }
        float leftCost[bins] = {};
        Bounds left;
        uint32_t leftCount = 0;
        for (int b = 0; b < bins - 1; ++b) {
            left.grow(binBounds[b]);
            leftCount += binCounts[b];
            leftCost[b] = leftCount * left.area();
        }
        Bounds right;
        uint32_t rightCount = 0;
        for (int b = bins - 1; b > 0; --b) {
            right.grow(binBounds[b]);
            rightCount += binCounts[b];
            const float cost = leftCost[b - 1] + rightCount * right.area();
            if (cost < best.cost) best = {axis, b, cost};
        }
    }
    return best;
}
// snippet:end sah

// snippet:begin subdivide
inline void BvhBuilder::subdivide(uint32_t index, uint32_t first, uint32_t count,
                                  uint32_t level) {
    depth = std::max(depth, level);
    Bounds box, centres;
    for (uint32_t i = first; i < first + count; ++i) {
        box.grow(bounds_[order_[i]]);
        centres.grow(centroids_[order_[i]]);
    }
    nodes[index] = {
        .boundsMin = box.lo, .leftOrFirst = first, .boundsMax = box.hi, .count = count};
    const Split split = bestSplit(first, count, centres);
    if (count <= 2 || split.axis < 0 || split.cost >= count * box.area()) return;
    if (level + 1 >= maxBvhDepth) throw std::runtime_error("the BVH is too deep");

    const auto middle = std::partition(
        order_.begin() + first, order_.begin() + first + count,
        [&](uint32_t t) { return binOf(centroids_[t], split.axis, centres) < split.bin; });
    const auto leftCount = uint32_t(middle - (order_.begin() + first));
    if (leftCount == 0 || leftCount == count) return;
    const auto left = uint32_t(nodes.size());
    nodes.push_back({});
    nodes.push_back({});
    nodes[index].leftOrFirst = left;
    nodes[index].count = 0;
    subdivide(left, first, leftCount, level + 1);
    subdivide(left + 1, first + leftCount, count - leftCount, level + 1);
}
// snippet:end subdivide

inline void buildBvh(Scene& scene) {
    BvhBuilder builder(scene.triangles);
    scene.nodes = std::move(builder.nodes);
    scene.bvhDepth = builder.depth;
}

}  // namespace rt
