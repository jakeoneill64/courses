#version 460
#extension GL_GOOGLE_include_directive : require

#include "frame.glsl"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(std430, set = 0, binding = 2) readonly buffer Instances {
    vec4 positionScale[];
};

layout(std430, set = 0, binding = 3) readonly buffer Visible {
    uint visible[];
};

layout(location = 0) out vec3 normal;
layout(location = 1) out vec3 albedo;

void main() {
    uint id = visible[gl_InstanceIndex];
    vec4 s = positionScale[id];
    gl_Position = frame.viewProjection * vec4(inPosition * s.w + s.xyz, 1.0);
    normal = inNormal;
    uint hash = id * 0x9E3779B9u;
    albedo = vec3(uvec3(hash >> 8, hash >> 16, hash >> 24) & 255u) / 255.0 * 0.3 + 0.1;
}
