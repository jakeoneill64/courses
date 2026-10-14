#pragma once

#include <cstdint>
#include <vector>

#include "vecmath.hpp"

namespace u4 {

// snippet:begin mesh-vertex
struct MeshVertex {
    Vec3 position;
    Vec3 normal;
    float u = 0, v = 0;
};
// snippet:end mesh-vertex

struct Mesh {
    std::vector<MeshVertex> vertices;
    std::vector<uint16_t> indices;
};

// snippet:begin cube
// Four vertices per face, for per-face normals; front faces wind counter-clockwise.
inline Mesh cubeMesh() {
    struct Face {
        Vec3 normal, right, up;
    };
    const Face faces[] = {
        {{1, 0, 0}, {0, 0, -1}, {0, 1, 0}}, {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
        {{0, 1, 0}, {1, 0, 0}, {0, 0, -1}}, {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
        {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},  {{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
    };
    Mesh mesh;
    for (const Face& f : faces) {
        const auto first = static_cast<uint16_t>(mesh.vertices.size());
        mesh.vertices.push_back({f.normal - f.right - f.up, f.normal, 0, 1});
        mesh.vertices.push_back({f.normal + f.right - f.up, f.normal, 1, 1});
        mesh.vertices.push_back({f.normal + f.right + f.up, f.normal, 1, 0});
        mesh.vertices.push_back({f.normal - f.right + f.up, f.normal, 0, 0});
        for (int corner : {0, 1, 2, 0, 2, 3}) {
            mesh.indices.push_back(static_cast<uint16_t>(first + corner));
        }
    }
    return mesh;
}
// snippet:end cube

inline Mesh groundMesh(float tiles) {
    Mesh mesh;
    mesh.vertices = {
        {{-1, 0, 1}, {0, 1, 0}, 0, tiles},
        {{1, 0, 1}, {0, 1, 0}, tiles, tiles},
        {{1, 0, -1}, {0, 1, 0}, tiles, 0},
        {{-1, 0, -1}, {0, 1, 0}, 0, 0},
    };
    mesh.indices = {0, 1, 2, 0, 2, 3};
    return mesh;
}

}  // namespace u4
