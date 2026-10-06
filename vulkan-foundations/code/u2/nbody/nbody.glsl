#extension GL_EXT_buffer_reference : require

// snippet:begin references
layout(buffer_reference, std430, buffer_reference_align = 16) buffer Vec4s {
    vec4 v[];
};
layout(buffer_reference, std430, buffer_reference_align = 4) buffer Floats {
    float f[];
};
layout(buffer_reference, std430, buffer_reference_align = 4) buffer Params {
    uint count;
};

layout(push_constant) uniform Push {
    Vec4s positions;
    Vec4s velocities;
    Vec4s accelerations;
    Floats potentials;
    Params params;
    float dt;
    float halfDt;
    float softening2;
} push;
// snippet:end references

// snippet:begin particle-index
uint particleIndex() {
    uint group = gl_WorkGroupID.y * gl_NumWorkGroups.x + gl_WorkGroupID.x;
    return group * gl_WorkGroupSize.x + gl_LocalInvocationIndex;
}
// snippet:end particle-index
