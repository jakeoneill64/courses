#version 460

// snippet:begin particle-inputs
layout(location = 0) in vec4 inPosition;
layout(location = 1) in vec4 inVelocity;

layout(push_constant) uniform Camera {
    mat4 viewProjection;
} camera;

layout(location = 0) out vec3 color;

void main() {
    gl_Position = camera.viewProjection * vec4(inPosition.xyz, 1.0);
    gl_PointSize = 1.0;
    float speed = clamp(length(inVelocity.xyz) / 1.5, 0.0, 1.0);
    color = mix(vec3(0.15, 0.3, 1.0), vec3(1.0, 0.55, 0.2), speed) * 0.12;
}
// snippet:end particle-inputs
