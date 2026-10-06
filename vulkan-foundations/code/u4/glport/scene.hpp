#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include "vecmath.hpp"

namespace glport {

// snippet:begin draw-data
struct DrawData {
    u4::Mat4 mvp;
    float color[4];
};
// snippet:end draw-data

struct FrameTiming {
    double issueMs = 0;
    double submitMs = 0;
    double totalMs = 0;
};

// snippet:begin projections
inline u4::Mat4 perspectiveOpenGl(float fovY, float aspect, float zNear, float zFar) {
    const float f = 1.0f / std::tan(fovY / 2);
    u4::Mat4 r;
    r.m[0][0] = f / aspect;
    r.m[1][1] = f;
    r.m[2][2] = (zFar + zNear) / (zNear - zFar);
    r.m[2][3] = -1;
    r.m[3][2] = 2 * zFar * zNear / (zNear - zFar);
    r.m[3][3] = 0;
    return r;
}

// Maps OpenGL clip space (+y up, depth -1 to 1) to Vulkan's (+y down, depth 0 to 1).
inline u4::Mat4 vulkanFromOpenGlClip() {
    u4::Mat4 r;
    r.m[1][1] = -1;
    r.m[2][2] = 0.5f;
    r.m[3][2] = 0.5f;
    return r;
}
// snippet:end projections

inline std::vector<DrawData> buildDraws(uint32_t objects, uint32_t frame,
                                        const u4::Mat4& projection) {
    const u4::Mat4 viewProjection = projection * u4::lookAt({0, 6, 34}, {0, 0, 0}, {0, 1, 0});
    std::vector<DrawData> draws(objects);
    for (uint32_t i = 0; i < objects; ++i) {
        const float x = float(i % 25) - 12.0f;
        const float y = float((i / 25) % 20) - 9.5f;
        const float z = -float(i / 500);
        const float angle = 0.03f * float(frame) * (1.0f + float(i % 7) * 0.25f) + float(i);
        const u4::Mat4 model = u4::translate({x, y, z}) * u4::rotateY(angle) *
                               u4::rotateX(angle * 0.7f) * u4::scale({0.3f, 0.3f, 0.3f});
        const uint32_t hash = i * 0x9E3779B9u;
        draws[i] = {viewProjection * model,
                    {0.35f + float((hash >> 8) & 255) / 400.0f,
                     0.35f + float((hash >> 16) & 255) / 400.0f,
                     0.35f + float((hash >> 24) & 255) / 400.0f, 1.0f}};
    }
    return draws;
}

}  // namespace glport
