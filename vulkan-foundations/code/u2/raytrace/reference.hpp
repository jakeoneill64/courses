#pragma once

#include <cmath>
#include <cstdint>
#include <limits>

#include "scene.hpp"

namespace rt {

constexpr uint32_t missId = 0xFFFFFFFFu;
constexpr uint32_t sphereKind = 1u << 28, quadKind = 2u << 28, triangleKind = 3u << 28;
constexpr double tMin = 1e-4;  // must equal T_MIN in trace.glsl
constexpr double never = std::numeric_limits<double>::infinity();

struct D3 {
    double x, y, z;
};
inline D3 d3(Vec3 v) {
    return {v.x, v.y, v.z};
}
inline D3 operator+(D3 a, D3 b) {
    return {a.x + b.x, a.y + b.y, a.z + b.z};
}
inline D3 operator-(D3 a, D3 b) {
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}
inline D3 operator*(double s, D3 a) {
    return {s * a.x, s * a.y, s * a.z};
}
inline double dot(D3 a, D3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline D3 cross(D3 a, D3 b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}

struct ReferenceRay {
    D3 origin;
    D3 direction;
};

struct ReferenceHit {
    double t = never;
    uint32_t id = missId;
};

inline ReferenceRay primaryRay(const Camera& c, uint32_t x, uint32_t y) {
    const double u = (x + 0.5) / c.width, v = (y + 0.5) / c.height;
    const D3 target = d3(c.corner) + u * d3(c.horizontal) - v * d3(c.vertical);
    const D3 d = target - d3(c.origin);
    return {d3(c.origin), (1 / std::sqrt(dot(d, d))) * d};
}

// A positive margin grows each primitive slightly and a negative one shrinks it.
inline double hitSphere(const Sphere& s, const ReferenceRay& ray, double margin) {
    const double radius = s.radius * (1 + margin);
    const D3 oc = ray.origin - d3(s.centre);
    const double b = dot(oc, ray.direction), c = dot(oc, oc) - radius * radius;
    const double discriminant = b * b - c;
    if (discriminant < 0) return never;
    const double root = std::sqrt(discriminant);
    if (-b - root >= tMin) return -b - root;
    return -b + root >= tMin ? -b + root : never;
}

inline double hitQuad(const Quad& q, const ReferenceRay& ray, double margin) {
    const D3 n = cross(d3(q.u), d3(q.v));
    const double denominator = dot(n, ray.direction);
    if (std::abs(denominator) < 1e-12) return never;
    const double t = dot(n, d3(q.corner) - ray.origin) / denominator;
    if (t < tMin) return never;
    const D3 p = ray.origin + t * ray.direction - d3(q.corner);
    const double alpha = dot(n, cross(p, d3(q.v))) / dot(n, n);
    const double beta = dot(n, cross(d3(q.u), p)) / dot(n, n);
    const bool inside =
        alpha >= -margin && alpha <= 1 + margin && beta >= -margin && beta <= 1 + margin;
    return inside ? t : never;
}

inline double hitTriangle(const Triangle& tri, const ReferenceRay& ray, double margin) {
    const D3 e1 = d3(tri.edge1), e2 = d3(tri.edge2);
    const D3 p = cross(ray.direction, e2);
    const double determinant = dot(e1, p);
    if (std::abs(determinant) < 1e-12) return never;
    const D3 s = ray.origin - d3(tri.v0);
    const double u = dot(s, p) / determinant;
    const D3 q = cross(s, e1);
    const double v = dot(ray.direction, q) / determinant;
    if (u < -margin || v < -margin || u + v > 1 + margin) return never;
    const double t = dot(e2, q) / determinant;
    return t >= tMin ? t : never;
}

inline double hitPrimitive(const Scene& scene, uint32_t id, const ReferenceRay& ray,
                           double margin) {
    const uint32_t index = id & ((1u << 28) - 1);
    switch (id & ~((1u << 28) - 1)) {
        case sphereKind: return hitSphere(scene.spheres[index], ray, margin);
        case quadKind: return hitQuad(scene.quads[index], ray, margin);
        case triangleKind: return hitTriangle(scene.triangles[index], ray, margin);
        default: return never;
    }
}

inline ReferenceHit closestHit(const Scene& scene, const ReferenceRay& ray, double margin) {
    ReferenceHit best;
    auto consider = [&](double t, uint32_t id) {
        if (t < best.t) best = {t, id};
    };
    for (uint32_t i = 0; i < scene.spheres.size(); ++i) {
        consider(hitSphere(scene.spheres[i], ray, margin), sphereKind | i);
    }
    for (uint32_t i = 0; i < scene.quads.size(); ++i) {
        consider(hitQuad(scene.quads[i], ray, margin), quadKind | i);
    }
    for (uint32_t i = 0; i < scene.triangles.size(); ++i) {
        consider(hitTriangle(scene.triangles[i], ray, margin), triangleKind | i);
    }
    return best;
}

}  // namespace rt
