#version 460

layout(set = 1, binding = 0) uniform texture2D textureTable[4];
layout(set = 1, binding = 1) uniform sampler tableSampler;

layout(push_constant) uniform DrawConstants {
    mat4 model;
    uint textureIndex;
} draw;

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;

// snippet:begin constant-index
void main() {
    // Without descriptor indexing, only constant indices into an image array are valid.
    switch (draw.textureIndex) {
        case 0u: outColor = texture(sampler2D(textureTable[0], tableSampler), uv); break;
        case 1u: outColor = texture(sampler2D(textureTable[1], tableSampler), uv); break;
        case 2u: outColor = texture(sampler2D(textureTable[2], tableSampler), uv); break;
        default: outColor = texture(sampler2D(textureTable[3], tableSampler), uv); break;
    }
}
// snippet:end constant-index
