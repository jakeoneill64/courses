#pragma once

#include <array>
#include <cmath>
#include <numbers>

namespace u4 {

constexpr float Pi = std::numbers::pi_v<float>;

struct Vec3 {
    float x = 0, y = 0, z = 0;
};

constexpr Vec3 operator+(Vec3 a, Vec3 b) {
    return {a.x + b.x, a.y + b.y, a.z + b.z};
}
constexpr Vec3 operator-(Vec3 a, Vec3 b) {
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}
constexpr Vec3 operator-(Vec3 a) {
    return {-a.x, -a.y, -a.z};
}
constexpr Vec3 operator*(Vec3 a, float s) {
    return {a.x * s, a.y * s, a.z * s};
}
constexpr float dot(Vec3 a, Vec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
constexpr Vec3 cross(Vec3 a, Vec3 b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline float length(Vec3 a) {
    return std::sqrt(dot(a, a));
}
inline Vec3 normalize(Vec3 a) {
    return a * (1.0f / length(a));
}

struct Vec4 {
    float x = 0, y = 0, z = 0, w = 0;
};

// m[column][row]: column-major, the layout GLSL gives a mat4 in a buffer or push constant.
struct Mat4 {
    float m[4][4] = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
};

inline Mat4 operator*(const Mat4& a, const Mat4& b) {
    Mat4 r;
    for (int c = 0; c < 4; ++c) {
        for (int row = 0; row < 4; ++row) {
            float sum = 0;
            for (int k = 0; k < 4; ++k) sum += a.m[k][row] * b.m[c][k];
            r.m[c][row] = sum;
        }
    }
    return r;
}

inline Vec4 operator*(const Mat4& a, Vec4 v) {
    const float in[4] = {v.x, v.y, v.z, v.w};
    float out[4] = {};
    for (int row = 0; row < 4; ++row) {
        for (int k = 0; k < 4; ++k) out[row] += a.m[k][row] * in[k];
    }
    return {out[0], out[1], out[2], out[3]};
}

inline Vec3 transformPoint(const Mat4& a, Vec3 p) {
    const Vec4 r = a * Vec4{p.x, p.y, p.z, 1.0f};
    return {r.x, r.y, r.z};
}

inline Vec3 transformDirection(const Mat4& a, Vec3 d) {
    const Vec4 r = a * Vec4{d.x, d.y, d.z, 0.0f};
    return {r.x, r.y, r.z};
}

inline Mat4 translate(Vec3 t) {
    Mat4 r;
    r.m[3][0] = t.x;
    r.m[3][1] = t.y;
    r.m[3][2] = t.z;
    return r;
}

inline Mat4 scale(Vec3 s) {
    Mat4 r;
    r.m[0][0] = s.x;
    r.m[1][1] = s.y;
    r.m[2][2] = s.z;
    return r;
}

inline Mat4 rotateX(float radians) {
    const float c = std::cos(radians), s = std::sin(radians);
    Mat4 r;
    r.m[1][1] = c;
    r.m[1][2] = s;
    r.m[2][1] = -s;
    r.m[2][2] = c;
    return r;
}

inline Mat4 rotateY(float radians) {
    const float c = std::cos(radians), s = std::sin(radians);
    Mat4 r;
    r.m[0][0] = c;
    r.m[0][2] = -s;
    r.m[2][0] = s;
    r.m[2][2] = c;
    return r;
}

inline Mat4 rotateZ(float radians) {
    const float c = std::cos(radians), s = std::sin(radians);
    Mat4 r;
    r.m[0][0] = c;
    r.m[0][1] = s;
    r.m[1][0] = -s;
    r.m[1][1] = c;
    return r;
}

// Only for matrices whose last row is (0, 0, 0, 1).
inline Mat4 inverseAffine(const Mat4& a) {
    const auto& m = a.m;
    const float c00 = m[1][1] * m[2][2] - m[2][1] * m[1][2];
    const float c01 = m[2][1] * m[0][2] - m[0][1] * m[2][2];
    const float c02 = m[0][1] * m[1][2] - m[1][1] * m[0][2];
    const float c10 = m[2][0] * m[1][2] - m[1][0] * m[2][2];
    const float c11 = m[0][0] * m[2][2] - m[2][0] * m[0][2];
    const float c12 = m[1][0] * m[0][2] - m[0][0] * m[1][2];
    const float c20 = m[1][0] * m[2][1] - m[2][0] * m[1][1];
    const float c21 = m[2][0] * m[0][1] - m[0][0] * m[2][1];
    const float c22 = m[0][0] * m[1][1] - m[1][0] * m[0][1];
    const float invDet = 1.0f / (m[0][0] * c00 + m[1][0] * c01 + m[2][0] * c02);
    Mat4 r;
    r.m[0][0] = c00 * invDet;
    r.m[0][1] = c01 * invDet;
    r.m[0][2] = c02 * invDet;
    r.m[1][0] = c10 * invDet;
    r.m[1][1] = c11 * invDet;
    r.m[1][2] = c12 * invDet;
    r.m[2][0] = c20 * invDet;
    r.m[2][1] = c21 * invDet;
    r.m[2][2] = c22 * invDet;
    for (int row = 0; row < 3; ++row) {
        r.m[3][row] = -(r.m[0][row] * m[3][0] + r.m[1][row] * m[3][1] + r.m[2][row] * m[3][2]);
    }
    return r;
}

// snippet:begin look-at
// A right-handed camera at eye looking at target: it looks down its own -z axis with +y up.
inline Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    const Vec3 f = normalize(target - eye);
    const Vec3 s = normalize(cross(f, up));
    const Vec3 u = cross(s, f);
    Mat4 r;
    r.m[0][0] = s.x;
    r.m[1][0] = s.y;
    r.m[2][0] = s.z;
    r.m[0][1] = u.x;
    r.m[1][1] = u.y;
    r.m[2][1] = u.z;
    r.m[0][2] = -f.x;
    r.m[1][2] = -f.y;
    r.m[2][2] = -f.z;
    r.m[3][0] = -dot(s, eye);
    r.m[3][1] = -dot(u, eye);
    r.m[3][2] = dot(f, eye);
    return r;
}
// snippet:end look-at

// snippet:begin perspective
// Vulkan's clip space: +y points down the image and depth runs from 0 (near) to 1 (far).
inline Mat4 perspective(float fovY, float aspect, float zNear, float zFar) {
    const float f = 1.0f / std::tan(fovY / 2);
    Mat4 r;
    r.m[0][0] = f / aspect;
    r.m[1][1] = -f;
    r.m[2][2] = zFar / (zNear - zFar);
    r.m[2][3] = -1;
    r.m[3][2] = zNear * zFar / (zNear - zFar);
    r.m[3][3] = 0;
    return r;
}
// snippet:end perspective

// snippet:begin frustum
// Normalised: a*x + b*y + c*z + d is a point's signed distance, positive inside.
inline std::array<Vec4, 6> frustumPlanes(const Mat4& viewProj) {
    auto row = [&](int i) {
        return Vec4{viewProj.m[0][i], viewProj.m[1][i], viewProj.m[2][i], viewProj.m[3][i]};
    };
    auto add = [](Vec4 a, Vec4 b) { return Vec4{a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w}; };
    auto sub = [](Vec4 a, Vec4 b) { return Vec4{a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w}; };
    const Vec4 x = row(0), y = row(1), z = row(2), w = row(3);
    std::array<Vec4, 6> planes = {add(w, x), sub(w, x), add(w, y), sub(w, y), z, sub(w, z)};
    for (Vec4& p : planes) {
        const float n = std::sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
        p = {p.x / n, p.y / n, p.z / n, p.w / n};
    }
    return planes;
}
// snippet:end frustum

inline bool sphereVisible(const std::array<Vec4, 6>& planes, Vec3 centre, float radius) {
    for (const Vec4& p : planes) {
        if (p.x * centre.x + p.y * centre.y + p.z * centre.z + p.w < -radius) return false;
    }
    return true;
}

}  // namespace u4
