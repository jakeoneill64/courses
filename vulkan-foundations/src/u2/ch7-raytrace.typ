#import "../lib/template.typ": *

= A ray tracer in a compute shader <ch-raytrace>

#chapter-meta(
  time: [8 hours],
  builds: [A path tracer written entirely in compute shaders: a Cornell box with spheres, quads and a mesh of 5,120 triangles in a bounding volume hierarchy built on the CPU, rendered progressively over many passes and tone-mapped for display. It checks every primary ray against a double-precision CPU reference, the hierarchy against brute force, and its light transport against the exact answer of a white furnace, and it measures how coherence and workgroup size decide its speed.],
  needs: [Chapters 2.1 to 2.6.],
)

#why[
  Ray tracing looks made for a GPU and resists it. Every pixel is independent, yet the rays scatter through the scene in different directions, take different numbers of bounces and visit different parts of the acceleration structure. A path tracer therefore exercises the whole of this unit at once: divergence, memory access, data structures in buffers, work accumulated over many dispatches, and measurement. It also needs an unusual kind of testing, because its output is random by design. Vulkan can drive dedicated ray-tracing hardware, and building a tracer in plain compute first shows what that hardware accelerates.
]

#skip-test(
  rule: [If all four are easy, read the sections on testing and on performance, and do Labs 2.7.2 and 2.7.3.],
  [How do you test a renderer whose every pixel is a random estimate?],
  [What does a bounding volume hierarchy save, and what decides how good a hierarchy is?],
  [Two dispatches read and write the same storage image. Which barrier goes between them, and does the image change layout?],
  [Why can a path tracer run several times slower per ray than a tracer of primary rays alone, on the same scene?],
)

== Core ideas

=== Rays and paths

A _ray_ is a starting point and a direction, and a ray tracer finds the closest surface each ray meets. A _path tracer_ uses that to estimate how much light reaches the camera through each pixel. It follows a path from the camera into the scene; at each surface it adds the light the surface emits, then picks a new direction at random, as the material scatters light, and continues. The average over many random paths converges to the light the pixel receives: a Monte Carlo estimate of the integral that Kajiya's rendering equation describes.

The scene is a _Cornell box_, a standard test scene: five walls and a light, a glass sphere, a steel sphere, and a third sphere made of 5,120 triangles, which gives the acceleration structure something to do.

#snippet("u2/raytrace/scene.hpp", "showcase", caption: [The Cornell box, and its white-furnace variant for testing])

=== The scene in buffers

Each kind of primitive lives in a storage buffer of its own, with the materials in another and the camera in a uniform buffer. In a `std430` array, GLSL aligns a `vec3` like a `vec4`, so a structure that mixes `vec3` and scalars has holes that the C++ side must reproduce exactly. The program writes its padding out explicitly and lets the compiler check every offset:

#snippet("u2/raytrace/scene.hpp", "cpp-structs", caption: [The scene's structures on the CPU, padded as `std430` lays them out])

#snippet("u2/raytrace/scene.hpp", "layout-checks", caption: [Layout mistakes become build errors])

A layout mistake that compiles is a renderer that draws nonsense, or crashes the GPU; a `static_assert` turns it into a build error. The shaders see ten bindings in one set, and a push-constant block that names the pass:

#snippet("u2/raytrace/scene.glsl", "buffers", caption: [The tracer's interface])

=== Intersections

Each pixel's ray starts at the camera and passes through a point on the image plane, jittered within the pixel so that the passes together smooth the edges:

#snippet("u2/raytrace/trace.glsl", "camera-ray", caption: [A camera ray through a point of the image])

Each kind of primitive has a test that returns the distance along the ray to the hit. A sphere needs a quadratic equation, and a triangle the Möller–Trumbore test, which finds the hit's barycentric coordinates without computing the triangle's plane first. The constant `T_MIN`, 10#super[−4], discards hits closer than that: a ray leaving a surface would otherwise hit the same surface again through rounding. A hit records its distance and an identifier whose top four bits give the kind of primitive and whose remaining bits give its index.

#snippet("u2/raytrace/trace.glsl", "sphere", caption: [Ray and sphere])

#snippet("u2/raytrace/trace.glsl", "triangle", caption: [Ray and triangle, after Möller and Trumbore])

=== A bounding volume hierarchy

Testing every triangle for every ray costs 5,120 tests per ray. A _bounding volume hierarchy_ (BVH) is a binary tree of axis-aligned boxes in which each node's box encloses everything below it, and each leaf holds a few triangles (@fig-bvh). A ray that misses a box skips everything inside it, and a ray that has already hit something skips every box that starts beyond the hit.

#fig("u2-bvh", caption: [A hierarchy over eight triangles. Traversal visits the nearer of two children first, and the closest hit found there lets it skip the boxes of the farther one.]) <fig-bvh>

The CPU builds the tree once, with the _surface area heuristic_ (SAH). The chance that a ray through a box also passes through a smaller box inside it is roughly the ratio of their surface areas, so the expected cost of a split is the area of each side times the number of triangles it holds. Instead of trying every possible split, the builder sorts the triangles' centres into 16 bins along each axis and evaluates the 15 boundaries between the bins:

#snippet("u2/raytrace/bvh.hpp", "sah", caption: [Choosing a split by binned SAH])

A node becomes a leaf when it holds two triangles or fewer, or when no split is cheaper than testing its triangles directly. Otherwise its triangles are partitioned at the chosen boundary, and its two children are written next to each other, so that one index finds both. The triangles are reordered to match, so that each leaf's triangles are contiguous:

#snippet("u2/raytrace/bvh.hpp", "subdivide", caption: [Building the tree, depth first])

GLSL has no recursion, so the traversal keeps its own stack of node indices in a local array of 32 entries. Each level of the tree adds at most one entry, and the builder refuses to go deeper than the stack. At each inner node, the traversal measures the distance to both children's boxes, drops any box that the ray misses or that starts beyond the closest hit so far, and pushes the farther child first so that the nearer is visited next:

#snippet("u2/raytrace/trace.glsl", "bvh", caption: [Traversing the hierarchy with an explicit stack])

For this scene the builder makes 6,109 nodes, 14 levels deep. Without the hierarchy the tracer is 96 times slower.

=== Random numbers and materials

Each invocation needs its own stream of random numbers, different for every pixel and every pass. The tracer runs a PCG generator, whose state is a single 32-bit integer, seeded from a hash of the pixel's index and the pass number:

#snippet("u2/raytrace/trace.glsl", "rng", caption: [A random-number generator per invocation])

The materials scatter light in three ways. A diffuse surface sends it in a random direction with the cosine-weighted distribution of an ideal matte surface, which adding a random unit vector to the normal produces exactly. Metal reflects about the normal, blurred by a random offset. Glass refracts by Snell's law, or reflects with the probability that Schlick's approximation gives, and always reflects beyond the critical angle.

#snippet("u2/raytrace/trace.glsl", "scatter", caption: [Three materials])

The path loop adds each surface's emission, weighted by the product of the albedos of the surfaces before it, the path's _throughput_. A path ends when it leaves the scene, when a material absorbs it, or at the depth limit. After three bounces the loop plays _Russian roulette_: it continues with a probability equal to the throughput's largest component, at most 0.95, and divides the throughput by that probability when it does. Paths that could contribute little end early, and the division keeps the estimate's expected value unchanged.

#snippet("u2/raytrace/trace.glsl", "path", caption: [Following a path])

=== Accumulating over passes

Each pass traces one path per pixel and adds its radiance to an `rgba32f` storage image whose alpha channel counts the samples. A shared counter totals the rays its workgroup traced, and one atomic addition per workgroup adds them to a buffer, which gives the measurements below their ray counts.

#snippet("u2/raytrace/render.comp", "accumulate", caption: [One path per pixel per pass])

Each pass is a dispatch of its own. The next pass reads and writes the pixels this one wrote, so a barrier orders them, from storage writes to storage reads and writes in the compute stage. The image stays in `VK_IMAGE_LAYOUT_GENERAL`, the layout storage images use, and the barrier names it on both sides: an image barrier without a layout transition, used for its memory dependency alone.

#snippet("u2/raytrace/main.cpp", "passes", caption: [Passes, with a barrier between each and the next])

Short passes, 1.5 ms each here, keep the GPU responsive. A dispatch that runs for seconds can trip the operating system's GPU timeout, which on Windows resets the device after two seconds, and short passes let an interactive viewer show the image as it converges. A last pass divides each pixel's sum by its count, compresses the range with Narkowicz's fit to the ACES filmic curve, and applies the sRGB curve itself before writing an 8-bit image, since sRGB storage images are not portable (Chapter 1.2).

#snippet("u2/raytrace/resolve.comp", "resolve", caption: [Resolving the accumulated sums for display])

#fig("/src/figures/u2-raytrace.jpg", caption: [The Cornell box at 1280 × 720 with 512 paths per pixel, which took 3 seconds on the M2 Pro.]) <fig-raytrace>

=== Testing a random renderer

A renderer can be wrong and still draw a plausible picture: a triangle slightly out of place, a material that loses energy, a hierarchy that drops a node. The program checks three things, from exact to statistical.

The first check is exact. A debugging kernel traces one ray through the centre of each pixel of a small image, with no randomness, and records what it hit and how far away:

#snippet("u2/raytrace/debug.comp", "debug", caption: [Primary rays, recorded for checking])

The CPU traces the same rays in double precision through every primitive, and the two must agree. Rounding can legitimately change the answer for a ray that grazes an edge or meets two surfaces at the same distance, so where they disagree, the CPU traces the ray again with every primitive shrunk and grown by 10#super[−4]. It accepts the GPU's answer only if the GPU's primitive, grown, is hit at the GPU's distance, and nothing in the shrunk scene is hit noticeably closer.

#snippet("u2/raytrace/main.cpp", "check-primary", caption: [Every primary ray against a double-precision reference])

The second check compares the hierarchy with brute force. The same rays, traced through the BVH and through every triangle, must give bit-identical distances, and the same primitive except at exact ties. Both use the same intersection code on the same triangles, so any other difference is a node the traversal lost.

#snippet("u2/raytrace/main.cpp", "checks", caption: [The hierarchy against brute force])

The third check tests the light transport, which has no exact answer for any one pixel. In a _white furnace_, every surface has the same albedo _a_ and emits the same radiance _E_, and the scene is closed, here by a large sphere around everything. Every path then meets a surface at every bounce, whatever the geometry, and a path of at most _D_ bounces collects _E_ (1 + _a_ + _a_#super[2] + … + _a_#super[_D_−1]) = _E_ (1 − _a_#super[_D_]) / (1 − _a_) on average. The mean over all pixels must lie within five standard errors of that value. This check reaches what the first two cannot: the scattering, the random numbers and the roulette.

#snippet("u2/raytrace/main.cpp", "furnace", caption: [The furnace's statistics])

Each check was tested by breaking the code it guards. A traversal that skips a child fails the first two checks, a sign error in the triangle test fails the first, and roulette without the division by the survival probability fails the furnace.

#console(read("/src/console/u2-raytrace.txt"), caption: [The checks and a render on the M2 Pro, with validation off])

=== Coherence and workgroups

#console(read("/src/console/u2-raytrace-benchmark.txt"), caption: [Five configurations of the tracer, with validation off])

Primary rays alone run at 1.26 billion rays per second, and full paths at 404 million, three times fewer. The difference is coherence. Rays from neighbouring pixels start together, hit the same surfaces and visit the same nodes, so the invocations of a subgroup run the same instructions on nearby data. After a bounce, each ray leaves in a random direction of its own. The invocations of a subgroup then visit different nodes, test different triangles, meet different materials and end after different numbers of bounces, and a subgroup runs at the speed of its slowest invocation (Chapter 2.4).

The size of a workgroup matters more here than its shape. With 64 invocations, square tiles of 8 × 8 are 6% faster than strips of 64 × 1, because their subgroups start with rays from a compact patch of the image. Workgroups of 16 × 16 are 29% slower than 8 × 8. A sweep of shapes on the M2 Pro finds 32 × 8 as slow as 16 × 16, while every shape from 32 to 128 invocations runs within 7% of 8 × 8. Each invocation keeps a 32-entry stack as well as its path's state, and the more state each invocation keeps, the fewer invocations a core can hold. A core holds only whole workgroups, so the larger the workgroup, the more of that capacity is left unused. On the M2 Pro, a stack of 16 entries, enough for this tree's depth of 14, makes workgroups of 8 × 8 about 14% faster and workgroups of 16 × 16 about 35% faster.

=== Hardware ray tracing

Many GPUs now have hardware for the work this chapter does in software: traversing a hierarchy of boxes and intersecting triangles. Vulkan exposes it through extensions. `VK_KHR_acceleration_structure` builds hierarchies on the device, in a format only the driver knows; `VK_KHR_ray_query` lets any shader, a compute shader included, trace a ray through one; and `VK_KHR_ray_tracing_pipeline` adds a pipeline with shaders for ray generation, hits and misses. A tracer that uses ray queries keeps the camera, the materials, the paths, the accumulation and the tests of this chapter, and replaces only the hierarchy and the intersection code.

#keyidea[
  A path tracer is a Monte Carlo estimate computed in parallel, with every pixel independent and every path different. Keep the data structures in buffers whose layouts are checked at compile time, accumulate over short passes with a barrier between each, and test what is exact exactly and the rest statistically.
]

#opengl[
  OpenGL 4.3 can run this tracer almost line for line: the scene in shader storage buffers, the accumulation in an image bound with `glBindImageTexture`, and `glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)` between passes. Its compute shaders use the same `std430` layouts, so the layout checks carry over unchanged.
]

#reading(
  [Peter Shirley, Trevor David Black and Steve Hollasch, _Ray Tracing in One Weekend_ and its sequels: the camera and materials this tracer follows.],
  [Matt Pharr, Wenzel Jakob and Greg Humphreys, _Physically Based Rendering_, fourth edition, MIT Press, 2023: chapter 2 for Monte Carlo integration and chapter 7 for hierarchies built with the surface area heuristic.],
  [Jacco Bikker, "How to build a BVH", a series of articles from 2022, for binned construction and traversal on the CPU and the GPU.],
  [Mark Jarzynski and Marc Olano, "Hash Functions for GPU Rendering", _Journal of Computer Graphics Techniques_ 9(3), 2020.],
  [The Khronos Group, "Ray Tracing In Vulkan", 2020, on the ray-tracing extensions.],
)

== Labs

#lab([Watch it converge], goal: [Measure how noise falls with the number of samples.], time: [1.5 hours], code: "code/u2/raytrace")[
  + Render with `--spp` set to 16, 64, 256 and 1024, renaming each image.
  + Taking the 1024-sample image as the reference, compute the root-mean-square difference of each other image from it over a region of the back wall.
  + Plot the differences against the number of samples on logarithmic axes.
  #done-when(
    [The slope of your plot is within 0.1 of −½.],
    [You can explain why four times as many samples halve the noise, and why the reference's own noise flattens the slope a little.],
  )
  #evidence([The plot and the four images.])
]

#lab([Break it on purpose], goal: [Learn what each check can see.], time: [1.5 hours], code: "code/u2/raytrace")[
  + Make three changes, one at a time: push only the nearer child in the traversal; reverse the test `u < 0.0` in the triangle intersection; remove the division by the survival probability in the path loop.
  + Run the program after each change and record which checks fail.
  #done-when(
    [Every change fails at least one check.],
    [For each change, you can explain why the checks that passed could not see it.],
  )
  #evidence([The three outputs and the explanations.])
]

#lab([Size the stack], goal: [Find what large workgroups pay for.], time: [1.5 hours], code: "code/u2/raytrace")[
  + Run `VKF_VALIDATION=0 build/bin/u2_raytrace` with `--local` set to `8x4`, `8x8`, `64x1`, `16x8`, `16x16` and `32x8`, and record the rays per second.
  + Reduce `STACK_SIZE` in `trace.glsl` to 16, and `maxBvhDepth` in `bvh.hpp` to match, then repeat.
  #done-when(
    [You have both tables.],
    [You can explain from them why workgroup size matters more than shape here, and why the stack can be no smaller than the tree's depth.],
  )
  #evidence([The tables and the explanation.])
]

#lab([Measure the divergence], goal: [Put a number on incoherence.], time: [2 hours], code: "code/u2/raytrace")[
  + Record, for each pixel, the number of bounces its path took and the subgroup that traced it.
  + On the CPU, compute the lane use of each subgroup as in Chapter 2.4: the bounces traced, over the subgroup's largest number of bounces times its number of lanes.
  + Compare the mean lane use of workgroups of 8 × 8 and 64 × 1.
  #done-when(
    [You have the mean lane use for both shapes.],
    [You can relate the lane use to the speeds you measured in Lab 2.7.3.],
  )
  #evidence([The changes and the numbers.])
]

#problems(
  [The default render traces 624,205 rays per pass for 640 × 360 pixels. What is the mean number of rays per path? Would it rise or fall without Russian roulette, and why?],
  [A hierarchy of 6,109 nodes holds 5,120 triangles. How many leaves does it have, and how many triangles does a leaf hold on average? Why do some leaves hold more than two?],
  [Derive the furnace's expected radiance, and explain why it does not depend on the scene's geometry. What else must be true of the scene for the test to be valid?],
  [The primary-ray check accepts some disagreements. What bug could hide behind that allowance, and how does the second check limit the damage?],
  [What would be gained and lost by tracing all of a pixel's samples in one dispatch, with a loop in the shader?],
)

#checklist(
  [I can trace rays through spheres, quads and triangles in a compute shader, with the scene's layouts checked at compile time.],
  [I can build a bounding volume hierarchy with the surface area heuristic and traverse it with an explicit stack.],
  [I can accumulate a Monte Carlo estimate over many dispatches with the barrier it needs.],
  [I can test a random renderer exactly where answers are exact, and statistically elsewhere.],
  [I can explain a tracer's speed from coherence, workgroup size and the state each invocation keeps.],
  [Lab 2.7.1–2.7.4 done-when criteria all hold, with evidence filed.],
)
