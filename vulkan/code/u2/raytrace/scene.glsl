// snippet:begin glsl-structs
struct Material {
    vec3 albedo;
    uint type;
    vec3 emission;
    float parameter;
};

struct Sphere {
    vec3 centre;
    float radius;
    uint material;
};

struct Quad {
    vec3 corner;
    uint material;
    vec3 u;
    vec3 v;
};

struct Triangle {
    vec3 v0;
    uint material;
    vec3 edge1;
    vec3 edge2;
};

struct Node {
    vec3 boundsMin;
    uint leftOrFirst;
    vec3 boundsMax;
    uint count;
};
// snippet:end glsl-structs

struct DebugHit {
    float t;
    uint id;
};

// snippet:begin scene-block
layout(std140, set = 0, binding = 0) uniform Scene {
    vec3 origin;
    float lensRadius;
    vec3 corner;
    uint width;
    vec3 horizontal;
    uint height;
    vec3 vertical;
    uint sphereCount;
    vec3 right;
    uint quadCount;
    vec3 up;
    uint triangleCount;
} scene;
// snippet:end scene-block

// snippet:begin buffers
layout(std430, set = 0, binding = 1) restrict readonly buffer Materials {
    Material materials[];
};
layout(std430, set = 0, binding = 2) restrict readonly buffer Spheres {
    Sphere spheres[];
};
layout(std430, set = 0, binding = 3) restrict readonly buffer Quads {
    Quad quads[];
};
layout(std430, set = 0, binding = 4) restrict readonly buffer Triangles {
    Triangle triangles[];
};
layout(std430, set = 0, binding = 5) restrict readonly buffer Nodes {
    Node nodes[];
};
layout(set = 0, binding = 6, rgba32f) uniform restrict image2D accumulation;
layout(std430, set = 0, binding = 7) restrict buffer RayCounts {
    uint rayCounts[];
};
layout(std430, set = 0, binding = 8) restrict writeonly buffer DebugHits {
    DebugHit hits[];
};
layout(set = 0, binding = 9, rgba8) uniform restrict writeonly image2D picture;

layout(push_constant) uniform Push {
    uint pass;
    uint maxDepth;
    uint useBvh;
} push;
// snippet:end buffers
