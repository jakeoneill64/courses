#version 460

// snippet:begin rect
layout(push_constant) uniform Rect {
    vec4 bounds;
    vec4 color;
    vec2 targetSize;
} rect;

void main() {
    const vec2 corners[6] = vec2[](vec2(0, 0), vec2(0, 1), vec2(1, 1),
                                   vec2(0, 0), vec2(1, 1), vec2(1, 0));
    vec2 pixel = mix(rect.bounds.xy, rect.bounds.zw, corners[gl_VertexIndex]);
    gl_Position = vec4(pixel / rect.targetSize * 2.0 - 1.0, 0.0, 1.0);
}
// snippet:end rect
