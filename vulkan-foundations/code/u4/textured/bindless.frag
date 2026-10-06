#version 460
#extension GL_EXT_nonuniform_qualifier : require

// snippet:begin table
layout(set = 1, binding = 0) uniform texture2D textureTable[];
layout(set = 1, binding = 1) uniform sampler tableSampler;

layout(push_constant) uniform DrawConstants {
    mat4 model;
    uint textureIndex;
} draw;

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = texture(
        sampler2D(textureTable[nonuniformEXT(draw.textureIndex)], tableSampler), uv);
}
// snippet:end table
