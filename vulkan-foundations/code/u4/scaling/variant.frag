#version 460

layout(constant_id = 0) const int octaves = 4;
layout(constant_id = 1) const float seed = 0.0;

layout(location = 0) out vec4 outColor;

float valueHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float valueNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 offset = p - cell;
    vec2 blend = offset * offset * (3.0 - 2.0 * offset);
    float bottom = mix(valueHash(cell), valueHash(cell + vec2(1, 0)), blend.x);
    float top = mix(valueHash(cell + vec2(0, 1)), valueHash(cell + vec2(1, 1)), blend.x);
    return mix(bottom, top, blend.y);
}

void main() {
    vec2 p = gl_FragCoord.xy / 64.0;
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; ++i) {
        value += amplitude * valueNoise(p);
        p = p * 2.0 + vec2(seed);
        amplitude *= 0.5;
    }
    outColor = vec4(vec3(value), 1.0);
}
