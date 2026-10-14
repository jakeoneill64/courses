// Include after the local size, with GL_KHR_shader_subgroup_arithmetic enabled.

// snippet:begin position
uint scanPosition() {
    return gl_SubgroupID * gl_SubgroupSize + gl_SubgroupInvocationID;
}

shared uint subgroupPrefixes[gl_WorkGroupSize.x];
shared uint workgroupTotal;
// snippet:end position

// snippet:begin workgroup-scan
uint workgroupExclusiveAdd(uint value, out uint total) {
    uint inclusive = subgroupInclusiveAdd(value);
    if (gl_SubgroupInvocationID == gl_SubgroupSize - 1) {
        subgroupPrefixes[gl_SubgroupID] = inclusive;
    }
    barrier();
    if (gl_SubgroupID == 0) {
        uint carry = 0;
        for (uint first = 0; first < gl_NumSubgroups; first += gl_SubgroupSize) {
            uint s = first + gl_SubgroupInvocationID;
            uint subgroupTotal = s < gl_NumSubgroups ? subgroupPrefixes[s] : 0;
            uint prefix = carry + subgroupExclusiveAdd(subgroupTotal);
            if (s < gl_NumSubgroups) subgroupPrefixes[s] = prefix;
            carry += subgroupAdd(subgroupTotal);
        }
        if (subgroupElect()) workgroupTotal = carry;
    }
    barrier();
    total = workgroupTotal;
    uint result = subgroupPrefixes[gl_SubgroupID] + inclusive - value;
    barrier();  // the next call overwrites subgroupPrefixes
    return result;
}
// snippet:end workgroup-scan
