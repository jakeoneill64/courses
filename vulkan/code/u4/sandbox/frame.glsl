// snippet:begin frame-params
layout(std430, set = 0, binding = 0) readonly buffer FrameParams {
    mat4 viewProjection;
    vec4 planes[6];
    uint instanceCount;
} frame;
// snippet:end frame-params
