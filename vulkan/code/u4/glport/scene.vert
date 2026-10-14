#version 460

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(push_constant) uniform DrawData {
    mat4 mvp;
    vec4 tint;
} draw;

layout(location = 0) out vec3 faceColor;

void main() {
    gl_Position = draw.mvp * vec4(inPosition, 1.0);
    faceColor = (inNormal * 0.5 + 0.5) * draw.tint.rgb;
}
