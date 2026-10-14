const uint ITEMS = 4;
const uint DIGIT_BITS = 4;
const uint BUCKETS = 1 << DIGIT_BITS;

layout(push_constant) uniform Push {
    uint count;
    uint shift;
    uint blocks;
} push;

uint digitOf(uint key) {
    return bitfieldExtract(key, int(push.shift), int(DIGIT_BITS));
}
