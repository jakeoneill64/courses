#version 460

layout(push_constant) uniform Rect {
    vec4 bounds;
    vec4 color;
    vec2 targetSize;
} rect;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = rect.color;
}
