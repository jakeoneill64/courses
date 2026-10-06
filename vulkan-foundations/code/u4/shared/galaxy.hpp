#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include "vecmath.hpp"

namespace u4 {

// snippet:begin particle
struct Particle {
    float position[4];
    float velocity[4];
};
// snippet:end particle

struct Gravity {
    float dt = 0.004f;
    float strength = 1.0f;
    float softening = 0.1f;
};

// A small deterministic generator, so that every platform builds the same scene.
class Random {
public:
    explicit Random(uint32_t seed) : state_(seed) {}
    uint32_t bits() {
        state_ ^= state_ << 13;
        state_ ^= state_ >> 17;
        state_ ^= state_ << 5;
        return state_;
    }
    float next(float low, float high) {
        return low + (high - low) * float(bits() >> 8) / float(1u << 24);
    }

private:
    uint32_t state_;
};

inline std::vector<Particle> makeGalaxy(uint32_t count, const Gravity& gravity) {
    Random random(7);
    std::vector<Particle> particles(count);
    for (Particle& p : particles) {
        const float radius = random.next(0.4f, 4.0f);
        const float angle = random.next(0.0f, 2 * Pi);
        const float height = random.next(-0.08f, 0.08f) * radius;
        const float d2 = radius * radius + gravity.softening * gravity.softening;
        const float speed =
            std::sqrt(gravity.strength * radius * radius / std::pow(d2, 1.5f)) *
            random.next(0.85f, 1.05f);
        p = {{radius * std::cos(angle), height, radius * std::sin(angle), 1.0f},
             {-speed * std::sin(angle), 0.0f, speed * std::cos(angle), 0.0f}};
    }
    return particles;
}

// Each Vec4 holds a cube's centre in xyz and its half-size in w.
inline std::vector<Vec4> makeCubeField(uint32_t count) {
    Random random(11);
    std::vector<Vec4> instances(count);
    for (Vec4& s : instances) {
        s = {random.next(-40.0f, 40.0f), random.next(-4.5f, -3.0f), random.next(-40.0f, 40.0f),
             random.next(0.04f, 0.12f)};
    }
    return instances;
}

// Must match the simulation shaders step for step: the CPU checks depend on it.
inline void stepOnCpu(Particle& p, const Gravity& gravity) {
    Vec3 r{p.position[0], p.position[1], p.position[2]};
    Vec3 v{p.velocity[0], p.velocity[1], p.velocity[2]};
    const float d2 = dot(r, r) + gravity.softening * gravity.softening;
    const Vec3 a = r * (-gravity.strength / std::sqrt(d2 * d2 * d2));
    v = v + a * gravity.dt;
    r = r + v * gravity.dt;
    p = {{r.x, r.y, r.z, p.position[3]}, {v.x, v.y, v.z, p.velocity[3]}};
}

inline Vec3 angularMomentum(const Particle& p) {
    return cross({p.position[0], p.position[1], p.position[2]},
                 {p.velocity[0], p.velocity[1], p.velocity[2]});
}

}  // namespace u4
