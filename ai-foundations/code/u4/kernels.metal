#include <metal_stdlib>
using namespace metal;

// snippet:begin naive
kernel void matmul_naive(device const float* a [[buffer(0)]],
                         device const float* b [[buffer(1)]],
                         device float* c [[buffer(2)]], constant uint& n [[buffer(3)]],
                         constant uint& k [[buffer(4)]], constant uint& m [[buffer(5)]],
                         uint2 id [[thread_position_in_grid]]) {
    uint row = id.y, col = id.x;
    if (row >= n || col >= m) return;
    float sum = 0.0f;
    for (uint p = 0; p < k; ++p) sum += a[row * k + p] * b[p * m + col];
    c[row * m + col] = sum;
}
// snippet:end naive

// snippet:begin tiled
constant uint TILE = 16;

kernel void matmul_tiled(device const float* a [[buffer(0)]],
                         device const float* b [[buffer(1)]],
                         device float* c [[buffer(2)]], constant uint& n [[buffer(3)]],
                         constant uint& k [[buffer(4)]], constant uint& m [[buffer(5)]],
                         uint2 id [[thread_position_in_grid]],
                         uint2 local [[thread_position_in_threadgroup]]) {
    threadgroup float ta[TILE][TILE];
    threadgroup float tb[TILE][TILE];
    uint row = id.y, col = id.x;
    float sum = 0.0f;
    for (uint start = 0; start < k; start += TILE) {
        bool inA = row < n && start + local.x < k, inB = col < m && start + local.y < k;
        ta[local.y][local.x] = inA ? a[row * k + start + local.x] : 0.0f;
        tb[local.y][local.x] = inB ? b[(start + local.y) * m + col] : 0.0f;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint p = 0; p < TILE; ++p) sum += ta[local.y][p] * tb[p][local.x];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (row < n && col < m) c[row * m + col] = sum;
}
// snippet:end tiled

// snippet:begin blocked
constant uint BLOCK = 64;
constant uint WORK = 4;

kernel void matmul_blocked(device const float* a [[buffer(0)]],
                           device const float* b [[buffer(1)]],
                           device float* c [[buffer(2)]], constant uint& n [[buffer(3)]],
                           constant uint& k [[buffer(4)]], constant uint& m [[buffer(5)]],
                           uint2 group [[threadgroup_position_in_grid]],
                           uint2 local [[thread_position_in_threadgroup]]) {
    threadgroup float ta[BLOCK][TILE];
    threadgroup float tb[TILE][BLOCK];
    float acc[WORK][WORK] = {};
    uint row0 = group.y * BLOCK + local.y * WORK, col0 = group.x * BLOCK + local.x * WORK;
    uint linear = local.y * (BLOCK / WORK) + local.x;
    for (uint start = 0; start < k; start += TILE) {
        for (uint i = linear; i < BLOCK * TILE; i += (BLOCK / WORK) * (BLOCK / WORK)) {
            uint r = i / TILE, p = i % TILE;
            uint gr = group.y * BLOCK + r;
            ta[r][p] = gr < n && start + p < k ? a[gr * k + start + p] : 0.0f;
            uint q = i / BLOCK, col = i % BLOCK;
            uint gc = group.x * BLOCK + col;
            tb[q][col] = gc < m && start + q < k ? b[(start + q) * m + gc] : 0.0f;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint p = 0; p < TILE; ++p) {
            float av[WORK], bv[WORK];
            for (uint i = 0; i < WORK; ++i) av[i] = ta[local.y * WORK + i][p];
            for (uint j = 0; j < WORK; ++j) bv[j] = tb[p][local.x * WORK + j];
            for (uint i = 0; i < WORK; ++i)
                for (uint j = 0; j < WORK; ++j) acc[i][j] = fma(av[i], bv[j], acc[i][j]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    for (uint i = 0; i < WORK; ++i)
        for (uint j = 0; j < WORK; ++j)
            if (row0 + i < n && col0 + j < m) c[(row0 + i) * m + col0 + j] = acc[i][j];
}
// snippet:end blocked

// snippet:begin softmax
kernel void softmax_rows(device const float* x [[buffer(0)]], device float* y [[buffer(1)]],
                         constant uint& cols [[buffer(2)]],
                         uint row [[threadgroup_position_in_grid]],
                         uint t [[thread_position_in_threadgroup]],
                         uint width [[threads_per_threadgroup]],
                         uint lane [[thread_index_in_simdgroup]],
                         uint sg [[simdgroup_index_in_threadgroup]]) {
    threadgroup float partial[32];
    device const float* in = x + row * cols;
    device float* out = y + row * cols;
    float peak = -INFINITY;
    for (uint i = t; i < cols; i += width) peak = max(peak, in[i]);
    peak = simd_max(peak);
    if (lane == 0) partial[sg] = peak;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    peak = simd_max(lane < (width + 31) / 32 ? partial[lane] : -INFINITY);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float total = 0.0f;
    for (uint i = t; i < cols; i += width) total += exp(in[i] - peak);
    total = simd_sum(total);
    if (lane == 0) partial[sg] = total;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    total = simd_sum(lane < (width + 31) / 32 ? partial[lane] : 0.0f);
    for (uint i = t; i < cols; i += width) out[i] = exp(in[i] - peak) / total;
}
// snippet:end softmax

// snippet:begin flash
constant uint KEYS = 32;
constant uint HEAD = 64;

kernel void flash_attention(device const float* q [[buffer(0)]],
                            device const float* k [[buffer(1)]],
                            device const float* v [[buffer(2)]], device float* o [[buffer(3)]],
                            constant uint& length [[buffer(4)]],
                            constant float& scale [[buffer(5)]],
                            uint2 group [[threadgroup_position_in_grid]],
                            uint2 local [[thread_position_in_threadgroup]],
                            uint2 size [[threads_per_threadgroup]]) {
    threadgroup float kb[KEYS][HEAD];
    threadgroup float vb[KEYS][HEAD];
    uint t = local.x, width = size.x;
    uint head = group.y, row = group.x * width + t;
    device const float* qh = q + head * length * HEAD;
    float qr[HEAD], acc[HEAD];
    for (uint d = 0; d < HEAD; ++d) {
        qr[d] = row < length ? qh[row * HEAD + d] * scale : 0.0f;
        acc[d] = 0.0f;
    }
    float best = -INFINITY, total = 0.0f;
    uint last = min(length, (group.x + 1) * width);
    for (uint start = 0; start < last; start += KEYS) {
        for (uint i = t; i < KEYS * HEAD; i += width) {
            uint key = start + i / HEAD;
            uint at = (head * length + key) * HEAD + i % HEAD;
            kb[i / HEAD][i % HEAD] = key < length ? k[at] : 0.0f;
            vb[i / HEAD][i % HEAD] = key < length ? v[at] : 0.0f;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint j = 0; j < KEYS && start + j <= row && row < length; ++j) {
            float s = 0.0f;
            for (uint d = 0; d < HEAD; ++d) s += qr[d] * kb[j][d];
            float next = max(best, s);
            float shrink = exp(best - next), weight = exp(s - next);
            total = total * shrink + weight;
            for (uint d = 0; d < HEAD; ++d) acc[d] = acc[d] * shrink + weight * vb[j][d];
            best = next;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (row < length)
        for (uint d = 0; d < HEAD; ++d) o[(head * length + row) * HEAD + d] = acc[d] / total;
}
// snippet:end flash
