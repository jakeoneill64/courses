#version 460

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

// snippet:begin instance-fetch
layout(std430, set = 0, binding = 0) readonly buffer Instances {
    vec4 positionScale[];
};

layout(std430, set = 0, binding = 1) readonly buffer Visible {
    uint visible[];
};

layout(push_constant) uniform Camera {
    mat4 viewProjection;
} camera;

layout(location = 0) out vec3 normal;
layout(location = 1) out vec3 albedo;

void main() {
    uint id = visible[gl_InstanceIndex];
    vec4 s = positionScale[id];
    gl_Position = camera.viewProjection * vec4(inPosition * s.w + s.xyz, 1.0);
    normal = inNormal;
    uint hash = id * 0x9E3779B9u;
    albedo = vec3(uvec3(hash >> 8, hash >> 16, hash >> 24) & 255u) / 255.0 * 0.3 + 0.1;
}
// snippet:end instance-fetch
