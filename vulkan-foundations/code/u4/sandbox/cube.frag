#version 460

layout(location = 0) in vec3 normal;
layout(location = 1) in vec3 albedo;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 towardsLight = normalize(vec3(0.4, 1.0, 0.3));
    float light = 0.25 + 0.75 * max(dot(normalize(normal), towardsLight), 0.0);
    outColor = vec4(albedo * light, 1.0);
}
