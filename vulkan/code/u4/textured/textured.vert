#version 460

layout(location = 0) in vec3 inPosition;
layout(location = 2) in vec2 inUv;

layout(set = 0, binding = 0) uniform FrameUniforms {
    mat4 viewProjection;
} frame;

layout(push_constant) uniform DrawConstants {
    mat4 model;
    uint textureIndex;
} draw;

layout(location = 0) out vec2 uv;

void main() {
    gl_Position = frame.viewProjection * draw.model * vec4(inPosition, 1.0);
    uv = inUv;
}
