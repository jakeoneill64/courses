#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>
#include <vector>

namespace rt {

struct Vec3 {
    float x = 0;
    float y = 0;
    float z = 0;
    float operator[](int axis) const { return axis == 0 ? x : axis == 1 ? y : z; }
};

inline Vec3 operator+(Vec3 a, Vec3 b) {
    return {a.x + b.x, a.y + b.y, a.z + b.z};
}
inline Vec3 operator-(Vec3 a, Vec3 b) {
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}
inline Vec3 operator*(Vec3 a, float s) {
    return {a.x * s, a.y * s, a.z * s};
}
inline Vec3 operator*(float s, Vec3 a) {
    return a * s;
}
inline float dot(Vec3 a, Vec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline Vec3 cross(Vec3 a, Vec3 b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline Vec3 normalize(Vec3 a) {
    return a * (1.0f / std::sqrt(dot(a, a)));
}

enum MaterialType : uint32_t { Diffuse = 0, Metal = 1, Dielectric = 2 };

// snippet:begin cpp-structs
struct Material {
    Vec3 albedo;
    uint32_t type;
    Vec3 emission;
    float parameter;
};

struct Sphere {
    Vec3 centre;
    float radius;
    uint32_t material;
    uint32_t pad[3];
};

struct Quad {
    Vec3 corner;
    uint32_t material;
    Vec3 u;
    float pad0;
    Vec3 v;
    float pad1;
};

struct Triangle {
    Vec3 v0;
    uint32_t material;
    Vec3 edge1;
    float pad0;
    Vec3 edge2;
    float pad1;
};

struct Node {
    Vec3 boundsMin;
    uint32_t leftOrFirst;
    Vec3 boundsMax;
    uint32_t count;
};
// snippet:end cpp-structs

// snippet:begin layout-checks
static_assert(sizeof(Material) == 32 && offsetof(Material, emission) == 16);
static_assert(sizeof(Sphere) == 32 && offsetof(Sphere, material) == 16);
static_assert(sizeof(Quad) == 48 && offsetof(Quad, u) == 16 && offsetof(Quad, v) == 32);
static_assert(sizeof(Triangle) == 48 && offsetof(Triangle, edge1) == 16 &&
              offsetof(Triangle, edge2) == 32);
static_assert(sizeof(Node) == 32 && offsetof(Node, boundsMax) == 16);
// snippet:end layout-checks

// snippet:begin camera
struct Camera {
    Vec3 origin;
    float lensRadius;
    Vec3 corner;
    uint32_t width;
    Vec3 horizontal;
    uint32_t height;
    Vec3 vertical;
    uint32_t sphereCount;
    Vec3 right;
    uint32_t quadCount;
    Vec3 up;
    uint32_t triangleCount;
};
static_assert(sizeof(Camera) == 96 && offsetof(Camera, corner) == 16 &&
              offsetof(Camera, up) == 80);
// snippet:end camera

struct Scene {
    std::vector<Material> materials;
    std::vector<Sphere> spheres;
    std::vector<Quad> quads;
    std::vector<Triangle> triangles;
    std::vector<Node> nodes;
    uint32_t bvhDepth = 0;
    Vec3 eye;
    Vec3 target;
    float verticalFov = 40;
    float aperture = 0;
};

// snippet:begin make-camera
inline Camera makeCamera(const Scene& scene, uint32_t width, uint32_t height) {
    const float halfHeight = std::tan(scene.verticalFov * std::numbers::pi_v<float> / 360);
    const float halfWidth = halfHeight * float(width) / float(height);
    const float focus = std::sqrt(dot(scene.eye - scene.target, scene.eye - scene.target));
    const Vec3 back = normalize(scene.eye - scene.target);
    const Vec3 right = normalize(cross(Vec3{0, 1, 0}, back));
    const Vec3 up = cross(back, right);
    return {
        .origin = scene.eye,
        .lensRadius = scene.aperture / 2,
        .corner =
            scene.eye - focus * back - halfWidth * focus * right + halfHeight * focus * up,
        .width = width,
        .horizontal = 2 * halfWidth * focus * right,
        .height = height,
        .vertical = 2 * halfHeight * focus * up,
        .sphereCount = uint32_t(scene.spheres.size()),
        .right = right,
        .quadCount = uint32_t(scene.quads.size()),
        .up = up,
        .triangleCount = uint32_t(scene.triangles.size()),
    };
}
// snippet:end make-camera

inline uint32_t addMaterial(Scene& scene, Material material) {
    scene.materials.push_back(material);
    return uint32_t(scene.materials.size() - 1);
}

inline void addQuad(Scene& scene, Vec3 corner, Vec3 u, Vec3 v, uint32_t material) {
    scene.quads.push_back({.corner = corner, .material = material, .u = u, .v = v});
}

inline void addTriangle(Scene& scene, Vec3 a, Vec3 b, Vec3 c, uint32_t material) {
    scene.triangles.push_back({.v0 = a, .material = material, .edge1 = b - a, .edge2 = c - a});
}

// snippet:begin icosphere
inline void addIcosphere(Scene& scene, Vec3 centre, float radius, int levels,
                         uint32_t material) {
    const float g = (1 + std::sqrt(5.0f)) / 2;
    const Vec3 corners[12] = {{-1, g, 0}, {1, g, 0}, {-1, -g, 0}, {1, -g, 0},
                              {0, -1, g}, {0, 1, g}, {0, -1, -g}, {0, 1, -g},
                              {g, 0, -1}, {g, 0, 1}, {-g, 0, -1}, {-g, 0, 1}};
    const int faces[20][3] = {{0, 11, 5}, {0, 5, 1},  {0, 1, 7},   {0, 7, 10}, {0, 10, 11},
                              {1, 5, 9},  {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
                              {3, 9, 4},  {3, 4, 2},  {3, 2, 6},   {3, 6, 8},  {3, 8, 9},
                              {4, 9, 5},  {2, 4, 11}, {6, 2, 10},  {8, 6, 7},  {9, 8, 1}};
    std::vector<std::array<Vec3, 3>> mesh;
    for (const auto& f : faces) {
        mesh.push_back(
            {normalize(corners[f[0]]), normalize(corners[f[1]]), normalize(corners[f[2]])});
    }
    for (int level = 0; level < levels; ++level) {
        std::vector<std::array<Vec3, 3>> finer;
        for (const auto& [a, b, c] : mesh) {
            const Vec3 ab = normalize(a + b), bc = normalize(b + c), ca = normalize(c + a);
            finer.insert(finer.end(), {{a, ab, ca}, {b, bc, ab}, {c, ca, bc}, {ab, bc, ca}});
        }
        mesh = std::move(finer);
    }
    for (const auto& [a, b, c] : mesh) {
        const bool outward = dot(cross(b - a, c - a), a + b + c) > 0;
        addTriangle(scene, centre + radius * a, centre + radius * (outward ? b : c),
                    centre + radius * (outward ? c : b), material);
    }
}
// snippet:end icosphere

// snippet:begin showcase
inline Scene cornellBox(bool furnace, float albedo, float emission) {
    Scene scene;
    auto diffuse = [&](Vec3 colour, Vec3 light = {}) {
        return addMaterial(scene, {colour, Diffuse, light, 0});
    };
    const uint32_t uniform = diffuse({albedo, albedo, albedo}, {emission, emission, emission});
    auto pick = [&](uint32_t material) { return furnace ? uniform : material; };
    const uint32_t white = pick(diffuse({0.73f, 0.73f, 0.73f}));
    const uint32_t red = pick(diffuse({0.65f, 0.05f, 0.05f}));
    const uint32_t green = pick(diffuse({0.12f, 0.45f, 0.15f}));
    const uint32_t light = pick(diffuse({0, 0, 0}, {10, 10, 10}));
    const uint32_t glass = pick(addMaterial(scene, {{1, 1, 1}, Dielectric, {}, 1.5f}));
    const uint32_t steel = pick(addMaterial(scene, {{0.8f, 0.8f, 0.85f}, Metal, {}, 0.05f}));
    const uint32_t blue = pick(diffuse({0.25f, 0.45f, 0.85f}));

    addQuad(scene, {-1, 0, -1}, {2, 0, 0}, {0, 0, 2}, white);
    addQuad(scene, {-1, 2, -1}, {2, 0, 0}, {0, 0, 2}, white);
    addQuad(scene, {-1, 0, -1}, {2, 0, 0}, {0, 2, 0}, white);
    addQuad(scene, {-1, 0, -1}, {0, 2, 0}, {0, 0, 2}, red);
    addQuad(scene, {1, 0, -1}, {0, 2, 0}, {0, 0, 2}, green);
    addQuad(scene, {-0.4f, 1.999f, -0.4f}, {0.8f, 0, 0}, {0, 0, 0.8f}, light);
    scene.spheres.push_back(
        {.centre = {-0.55f, 0.35f, 0.2f}, .radius = 0.35f, .material = glass});
    scene.spheres.push_back(
        {.centre = {0.05f, 0.4f, -0.45f}, .radius = 0.4f, .material = steel});
    addIcosphere(scene, {0.55f, 0.38f, 0.3f}, 0.38f, 4, blue);
    if (furnace) {
        scene.spheres.push_back({.centre = {0, 1, 0}, .radius = 10, .material = uniform});
    }
    scene.eye = {0, 1, 3.6f};
    scene.target = {0, 0.95f, 0};
    scene.verticalFov = 38;
    return scene;
}
// snippet:end showcase

}  // namespace rt
