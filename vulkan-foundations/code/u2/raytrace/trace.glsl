const float T_MIN = 1e-4;
const float FAR = 1e30;
const uint MISS = 0xFFFFFFFFu;
const uint SPHERE = 1u << 28;
const uint QUAD = 2u << 28;
const uint TRIANGLE = 3u << 28;
const uint INDEX_MASK = (1u << 28) - 1;
const uint DIFFUSE = 0;
const uint METAL = 1;
const uint DIELECTRIC = 2;
const uint STACK_SIZE = 32;

// snippet:begin rng
uint rngState;

// The hash and the generator follow Jarzynski and Olano, "Hash Functions for GPU Rendering".
uint pcgHash(uint value) {
    uint state = value * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

void seedRandom(uint pixel, uint pass) {
    rngState = pcgHash(pixel ^ pcgHash(pass));
}

float random() {
    rngState = rngState * 747796405u + 2891336453u;
    uint word = ((rngState >> ((rngState >> 28u) + 4u)) ^ rngState) * 277803737u;
    return float(((word >> 22u) ^ word) >> 8) * (1.0 / 16777216.0);
}
// snippet:end rng

vec3 randomUnitVector() {
    float z = 2.0 * random() - 1.0;
    float phi = 6.2831853 * random();
    float r = sqrt(max(0.0, 1.0 - z * z));
    return vec3(r * cos(phi), r * sin(phi), z);
}

vec2 randomInDisk() {
    float r = sqrt(random());
    float phi = 6.2831853 * random();
    return r * vec2(cos(phi), sin(phi));
}

struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Hit {
    float t;
    uint id;
};

// snippet:begin camera-ray
Ray cameraRay(vec2 pixel, vec2 lens) {
    vec2 uv = pixel / vec2(scene.width, scene.height);
    vec3 offset = scene.lensRadius * (lens.x * scene.right + lens.y * scene.up);
    vec3 target = scene.corner + uv.x * scene.horizontal - uv.y * scene.vertical;
    return Ray(scene.origin + offset, normalize(target - scene.origin - offset));
}
// snippet:end camera-ray

// snippet:begin sphere
bool hitSphere(Sphere s, Ray ray, float tMax, out float t) {
    vec3 oc = ray.origin - s.centre;
    float b = dot(oc, ray.direction);
    float c = dot(oc, oc) - s.radius * s.radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) return false;
    float root = sqrt(discriminant);
    t = -b - root;
    if (t < T_MIN) t = -b + root;
    return t >= T_MIN && t < tMax;
}
// snippet:end sphere

// snippet:begin quad
bool hitQuad(Quad q, Ray ray, float tMax, out float t) {
    vec3 n = cross(q.u, q.v);
    float denominator = dot(n, ray.direction);
    if (abs(denominator) < 1e-12) return false;
    t = dot(n, q.corner - ray.origin) / denominator;
    if (t < T_MIN || t >= tMax) return false;
    vec3 p = ray.origin + t * ray.direction - q.corner;
    float alpha = dot(n, cross(p, q.v)) / dot(n, n);
    float beta = dot(n, cross(q.u, p)) / dot(n, n);
    return alpha >= 0.0 && alpha <= 1.0 && beta >= 0.0 && beta <= 1.0;
}
// snippet:end quad

// snippet:begin triangle
bool hitTriangle(Triangle tri, Ray ray, float tMax, out float t) {
    vec3 p = cross(ray.direction, tri.edge2);
    float determinant = dot(tri.edge1, p);
    if (abs(determinant) < 1e-12) return false;
    vec3 s = ray.origin - tri.v0;
    float u = dot(s, p) / determinant;
    vec3 q = cross(s, tri.edge1);
    float v = dot(ray.direction, q) / determinant;
    if (u < 0.0 || v < 0.0 || u + v > 1.0) return false;
    t = dot(tri.edge2, q) / determinant;
    return t >= T_MIN && t < tMax;
}
// snippet:end triangle

float boxDistance(Node node, Ray ray, vec3 inverseDirection, float tMax) {
    vec3 t0 = (node.boundsMin - ray.origin) * inverseDirection;
    vec3 t1 = (node.boundsMax - ray.origin) * inverseDirection;
    vec3 tNear = min(t0, t1);
    vec3 tFar = max(t0, t1);
    float tEnter = max(max(tNear.x, tNear.y), max(tNear.z, T_MIN));
    float tExit = min(min(tFar.x, tFar.y), min(tFar.z, tMax));
    return tEnter <= tExit ? tEnter : FAR;
}

void testTriangle(uint i, Ray ray, inout Hit hit) {
    float t;
    if (hitTriangle(triangles[i], ray, hit.t, t)) hit = Hit(t, TRIANGLE | i);
}

// snippet:begin bvh
void traverseBvh(Ray ray, inout Hit hit) {
    vec3 inverseDirection = 1.0 / ray.direction;
    uint stack[STACK_SIZE];
    uint top = 0;
    stack[top++] = 0;
    while (top > 0) {
        Node node = nodes[stack[--top]];
        if (node.count > 0) {
            for (uint i = node.leftOrFirst; i < node.leftOrFirst + node.count; ++i) {
                testTriangle(i, ray, hit);
            }
            continue;
        }
        uint nearChild = node.leftOrFirst, farChild = node.leftOrFirst + 1;
        float tNear = boxDistance(nodes[nearChild], ray, inverseDirection, hit.t);
        float tFar = boxDistance(nodes[farChild], ray, inverseDirection, hit.t);
        if (tFar < tNear) {
            uint child = nearChild;
            nearChild = farChild;
            farChild = child;
            float t = tNear;
            tNear = tFar;
            tFar = t;
        }
        if (tFar < FAR) stack[top++] = farChild;
        if (tNear < FAR) stack[top++] = nearChild;
    }
}
// snippet:end bvh

Hit closestHit(Ray ray) {
    Hit hit = Hit(FAR, MISS);
    float t;
    for (uint i = 0; i < scene.sphereCount; ++i) {
        if (hitSphere(spheres[i], ray, hit.t, t)) hit = Hit(t, SPHERE | i);
    }
    for (uint i = 0; i < scene.quadCount; ++i) {
        if (hitQuad(quads[i], ray, hit.t, t)) hit = Hit(t, QUAD | i);
    }
    if (scene.triangleCount == 0) return hit;
    if (push.useBvh != 0) {
        traverseBvh(ray, hit);
    } else {
        for (uint i = 0; i < scene.triangleCount; ++i) testTriangle(i, ray, hit);
    }
    return hit;
}

struct Surface {
    vec3 position;
    vec3 normal;
    bool frontFace;
    uint material;
};

Surface surfaceAt(Hit hit, Ray ray) {
    uint index = hit.id & INDEX_MASK;
    vec3 position = ray.origin + hit.t * ray.direction;
    vec3 normal;
    uint material;
    if ((hit.id & ~INDEX_MASK) == SPHERE) {
        normal = (position - spheres[index].centre) / spheres[index].radius;
        material = spheres[index].material;
    } else if ((hit.id & ~INDEX_MASK) == QUAD) {
        normal = normalize(cross(quads[index].u, quads[index].v));
        material = quads[index].material;
    } else {
        normal = normalize(cross(triangles[index].edge1, triangles[index].edge2));
        material = triangles[index].material;
    }
    bool frontFace = dot(ray.direction, normal) < 0.0;
    return Surface(position, frontFace ? normal : -normal, frontFace, material);
}

float schlick(float cosine, float ior) {
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 *= r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
}

// snippet:begin scatter
bool scatter(Material m, vec3 incoming, Surface s, out vec3 direction) {
    if (m.type == DIFFUSE) {
        direction = s.normal + randomUnitVector();
        direction = dot(direction, direction) > 1e-8 ? normalize(direction) : s.normal;
        return true;
    }
    if (m.type == METAL) {
        direction = normalize(reflect(incoming, s.normal) + m.parameter * randomUnitVector());
        return dot(direction, s.normal) > 0.0;
    }
    float eta = s.frontFace ? 1.0 / m.parameter : m.parameter;
    float cosine = min(dot(-incoming, s.normal), 1.0);
    bool mustReflect = eta * sqrt(1.0 - cosine * cosine) > 1.0;
    if (mustReflect || schlick(cosine, m.parameter) > random()) {
        direction = reflect(incoming, s.normal);
    } else {
        direction = refract(incoming, s.normal, eta);
    }
    return true;
}
// snippet:end scatter

// snippet:begin path
vec3 tracePath(Ray ray, inout uint rays) {
    vec3 radiance = vec3(0.0);
    vec3 throughput = vec3(1.0);
    for (uint depth = 0; depth < push.maxDepth; ++depth) {
        Hit hit = closestHit(ray);
        ++rays;
        if (hit.id == MISS) break;
        Surface s = surfaceAt(hit, ray);
        Material m = materials[s.material];
        radiance += throughput * m.emission;
        vec3 direction;
        if (!scatter(m, ray.direction, s, direction)) break;
        throughput *= m.albedo;
        if (depth >= 3) {
            float survival = min(max(throughput.r, max(throughput.g, throughput.b)), 0.95);
            if (random() >= survival) break;
            throughput /= survival;
        }
        ray = Ray(s.position, direction);
    }
    return radiance;
}
// snippet:end path
