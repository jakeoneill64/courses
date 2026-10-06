#import "../lib/template.typ": *

= Images and image processing <ch-images>

#chapter-meta(
  time: [6 hours],
  builds: [A separable Gaussian blur on storage images, tiled in shared memory with its aprons and compared with a naive two-dimensional kernel; a bilinear downscale through a sampler; and a Mandelbrot renderer that measures how much of the hardware its divergent loops waste. All write PNG files you can look at.],
  needs: [Chapters 2.1 to 2.3, and Chapter 1.2's section on images.],
)

#why[
  Buffers are arrays; images are something more. The GPU stores them in layouts suited to two-dimensional access, converts their formats as it reads and writes them, and can filter them in hardware through samplers, which is why so much of graphics and of image processing in compute works on images. This chapter uses images from compute shaders in both ways, as storage images read and written texel by texel and as sampled images filtered by the texture units, and meets their layouts, the subject of Unit 3, for the first time in practice. It also uses an image to make the cost of divergence, introduced in the Handbook, visible and measurable.
]

#skip-test(
  rule: [If all four are easy, read the section on divergence and do Labs 2.4.1 and 2.4.4.],
  [What is the difference between a storage image and a sampled image, as a shader sees them and as the descriptor set describes them?],
  [Why is a two-pass separable blur of radius 8 so much faster than a direct two-dimensional one?],
  [A workgroup loads a 16 × 16 tile of an image into shared memory to blur it horizontally with radius 8. How many texels must it load, and why?],
  [Pixels in one subgroup need 10, 20 and 1000 iterations of the same loop. What does the subgroup cost, and how would you measure the waste?],
)

== Core ideas

=== Storage images

A _storage image_ is an image that a shader reads and writes texel by texel, much as it would a buffer. GLSL declares it as `image2D` with a _format qualifier_ that names the image's format, such as `rgba32f`, `rgba8` or `r32ui`, and accesses it with `imageLoad`, `imageStore` and `imageSize`, using integer coordinates. The descriptor type is `VK_DESCRIPTOR_TYPE_STORAGE_IMAGE`, the image must have been created with `VK_IMAGE_USAGE_STORAGE_BIT`, and while a shader accesses it as storage it is in the `VK_IMAGE_LAYOUT_GENERAL` layout.

#snippet("u2/blur/blur_rows.comp", "images", caption: [Two storage images and a buffer of weights])

Not every format supports storage on every device, as Chapter 1.2's survey showed. The blur stores its intermediate images as `VK_FORMAT_R32G32B32A32_SFLOAT`, which every Vulkan device must support as a storage image, and checks the formats it uses before creating anything:

#snippet("u2/blur/main.cpp", "format-check", caption: [Refusing to run on a device that lacks a format feature])

An image created in device memory starts in `VK_IMAGE_LAYOUT_UNDEFINED`, and a barrier must move it to `GENERAL` before a shader writes it, exactly as in Chapter 3.1's catalogue. The program records one such transition for each image it will write:

#snippet("u2/blur/main.cpp", "create-images", caption: [Creating the images and moving them to `GENERAL`])

=== A separable Gaussian blur

A Gaussian blur replaces each pixel with a weighted average of its neighbours, the weights falling off with distance as a Gaussian. Computed directly, a blur of radius r reads (2r + 1)#super[2] pixels for each output pixel: 289 for r = 8. The two-dimensional Gaussian, however, is the product of a horizontal and a vertical one, so the same result comes from two passes of 2r + 1 taps each: blur every row, then blur every column of the result. That is 34 reads per pixel instead of 289.

The test input is a pattern of rings, checks and thin lines, generated on the CPU so that the reference blur can use exactly the same values:

#snippet("u2/blur/main.cpp", "pattern", caption: [A test pattern with edges in every direction])

Each pass is tiled in shared memory. A workgroup of 16 × 16 invocations produces a 16 × 16 tile of output, but to blur the tile's rows it needs eight more pixels on each side: the _apron_ (@fig-apron). The workgroup loads the tile with its aprons into shared memory, cooperatively, waits at a barrier, and then each invocation reads its 17 taps from shared memory instead of from the image.

#fig("u2-apron", caption: [The data each pass loads into shared memory: the tile it writes, plus aprons wide enough for the blur's radius in the direction of the pass.]) <fig-apron>

#snippet("u2/blur/blur_rows.comp", "rows", caption: [The rows pass: load the tile and its aprons, then blur from shared memory])

#snippet("u2/blur/blur_columns.comp", "columns", caption: [The columns pass, the same along the other axis])

Pixels beyond the image's edges are clamped to the edge, in the shader and in the CPU's reference alike. Between the passes, the intermediate image is written by one dispatch and read by the next, so a barrier separates them. It is an image barrier whose old and new layouts are both `GENERAL`: it changes no layout, and serves only as a memory dependency on that image.

#snippet("u2/blur/main.cpp", "separable", caption: [The two passes and the barrier between them])

For comparison, the naive kernel computes the full two-dimensional sum directly from the image:

#snippet("u2/blur/blur_2d.comp", "naive", caption: [A direct two-dimensional blur: 289 taps per pixel])

=== Sampled images

The texture units of a GPU read images through _samplers_, which add what storage images cannot: filtering between texels, normalised coordinates from 0 to 1, rules for coordinates outside the image, and mipmaps. A sampler is an object of its own, created with `vkCreateSampler`, and a shader reaches an image and a sampler together through a `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`, declared in GLSL as `sampler2D`. The image must have `VK_IMAGE_USAGE_SAMPLED_BIT` and is read in `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`, and linear filtering requires the format to support it, which the program checks.

#snippet("u2/blur/main.cpp", "sampler", caption: [A sampler with bilinear filtering that clamps at the edges])

The third kernel uses a sampler to shrink the input to three-eighths of its size. Each output pixel samples the input at the matching normalised position, and the texture unit blends the four nearest texels:

#snippet("u2/blur/downscale.comp", "downscale", caption: [A bilinear downscale through `textureLod`])

#console(read("/src/console/u2-blur.txt"), caption: [The blurs and the downscale on the M2 Pro, with validation off])

#fig("/src/figures/u2-blur-images.png", caption: [A 256 × 256 region of the input, the same region blurred, and the whole downscaled image, as the program wrote them.]) <fig-blur-images>

The separable blur takes 0.4 ms for a 1024 × 1024 image of four floats per pixel, thirteen times faster than the naive kernel, which performs eight and a half times as many reads. Each pass alone runs at more than 5 gigapixels per second. Both blurs agree with the CPU to better than 10#super[−6]. The downscale's error, 0.004, is about one step of an 8-bit value: the texture unit resolves positions between texels with limited precision and rounds the 8-bit result, both of which the Vulkan specification allows, and the program's tolerance accounts for them.

#hazard(title: [Pitfall])[
  Filtering with a sampler is fast but not exact. An implementation may resolve positions between texels with as few as four bits of precision, the limit `subTexelPrecisionBits` reports, and may round 8-bit formats differently, so results differ slightly between GPUs and from a CPU reference. Never compare sampled results for equality; derive a tolerance from the format and the precision the specification guarantees.
]

=== Divergence, made visible

The Mandelbrot set is the set of points c of the complex plane for which the iteration z ← z#super[2] + c, starting from z = 0, stays bounded. A renderer runs the iteration for each pixel until z escapes or a limit is reached, and colours the pixel by how quickly it escaped:

#snippet("u2/mandelbrot/mandelbrot.comp", "iterate", caption: [One invocation per pixel, iterating until escape or the limit])

#snippet("u2/mandelbrot/mandelbrot.comp", "colour", caption: [Smooth colouring from the escape count and the final magnitude])

The program checks itself in two ways. Points known to be inside the set, such as 0 and −1, must reach the iteration limit, and points known to be outside must escape after the number of iterations the CPU computes. Beyond the known points, the CPU's iteration counts must equal the GPU's for at least 99% of a 256 × 256 grid. They cannot be required to match everywhere: the GPU may fuse a multiplication and an addition into one operation with a single rounding where the CPU rounds twice, and near the boundary of the set the iteration is chaotic, so a difference in the last bit of z can change when it escapes.

#snippet("u2/mandelbrot/main.cpp", "reference", caption: [The CPU's iteration, the reference for every pixel])

Every invocation of a subgroup runs the loop until the slowest of them finishes, so a subgroup whose pixels need very different numbers of iterations wastes most of its lanes. The program records each pixel's iteration count and subgroup, and computes the fraction of executed lane-iterations that did useful work: the sum of every pixel's iterations, divided by the iterations each subgroup's slowest pixel forced on all its lanes.

#snippet("u2/mandelbrot/main.cpp", "efficiency", caption: [Lane use: useful iterations over iterations executed])

#console(read("/src/console/u2-mandelbrot.txt"), caption: [The Mandelbrot checks and three views on the M2 Pro, with validation off])

#fig("/src/figures/u2-mandelbrot-images.jpg", caption: [The whole set, and Seahorse Valley at the edge of the main cardioid, as the program rendered them.]) <fig-mandelbrot-images>

The view inside the main cardioid has every pixel run to the limit: perfectly uniform work, every lane in use, and 212 billion iterations per second. The Seahorse Valley view mixes pixels that escape early with pixels that never escape, its lane use falls to 80%, and its throughput falls by almost the same fraction, to 163 billion iterations per second. Divergence costs exactly what the lane use says, and lane use is something you can measure.

#keyidea[
  A subgroup runs as fast as its slowest lane. When work per invocation varies, arrange it so that neighbouring invocations, which share subgroups, do similar amounts: by the order of work, by sorting it, or by splitting it into passes.
]

#opengl[
  OpenGL 4.2 added image load and store: `image2D` variables bound with `glBindImageTexture` to numbered image units, which match Vulkan's storage images. Sampled textures in compute shaders work as in other OpenGL shaders, through texture units bound with `glBindTexture` and `glBindSampler`. OpenGL tracks the image layouts and inserts the transitions; Vulkan makes each one part of a barrier you record.
]

#reading(
  [The Vulkan specification, chapters "Samplers" and "Image Operations", in particular "Texel Filtering", and the format tables in "Formats".],
  [The Vulkan Guide, "Storage Image and Texel Buffers".],
  [Hwu, Kirk and El Hajj, _Programming Massively Parallel Processors_, chapters 7 and 8 on convolution and stencils.],
)

== Labs

#lab([Blur at several radii], goal: [Find where separability and tiling pay off.], time: [1.5 hours], code: "code/u2/blur")[
  + Run `VKF_VALIDATION=0 build/bin/u2_blur` with `--radius` set to 1, 2, 4, 8 and 16.
  + Plot the time of the separable and naive blurs against the radius.
  + Work out the largest radius whose tile and aprons fit in your device's shared memory, and try it.
  #done-when(
    [Every run matches the CPU reference.],
    [Your plot shows the two curves, and you can explain their shapes from the number of reads per pixel.],
  )
  #evidence([The plot and the shared-memory calculation.])
]

#lab([Two taps per fetch], goal: [Let the texture unit do half the blur's arithmetic.], time: [2 hours], code: "code/u2/blur")[
  + Write a rows pass that reads the input through a sampler with linear filtering. Sampling between two texels, at the position their weights determine, returns their weighted sum, so each fetch can replace two taps.
  + Work out the positions and weights for radius 8 on paper, then check the pass against the CPU reference with a tolerance justified by the filtering precision.
  + Time it against the tiled rows pass.
  #done-when(
    [The new pass matches the reference within your stated tolerance.],
    [You can say which rows pass is faster on your GPU, and why.],
  )
  #evidence([The derivation of the positions and weights, the tolerance, and the timings.])
]

#lab([Blur into 8-bit storage], goal: [Trade precision for bandwidth.], time: [1 hour], code: "code/u2/blur")[
  + Change the output image of the columns pass to `VK_FORMAT_R8G8B8A8_UNORM`, with the `rgba8` format qualifier, and adapt the check.
  + Time both versions.
  #done-when(
    [The 8-bit output matches the reference within half a level of 8-bit quantisation.],
    [You have both timings and can explain the difference in terms of bytes written.],
  )
  #evidence([The changes, the tolerance and the timings.])
]

#lab([Divergence and the shape of the workgroup], goal: [See how workgroup shape changes lane use.], time: [1.5 hours], code: "code/u2/mandelbrot")[
  + Change the Mandelbrot kernel's local size to 8 × 8, 32 × 8 and 64 × 4, adjusting `tile` and the dispatch, and run the boundary view with each.
  + Record the lane use and the time.
  + Explain why the shape of a subgroup's pixels on the screen affects its lane use.
  #done-when(
    [The checks pass for every shape.],
    [Your explanation predicts which shape uses its lanes best, and the measurements agree or you can say why not.],
  )
  #evidence([The table of shapes, lane use and times, and your explanation.])
]

#problems(
  [How many texels does a 16 × 16 workgroup load into shared memory for the rows pass at radius 8? How many reads of shared memory does it perform? Compare with the naive kernel's reads of the image.],
  [Why does the barrier between the blur's passes use an image barrier from `GENERAL` to `GENERAL`, and could it be a global memory barrier instead?],
  [A sampler with linear filtering reads a 1024-texel-wide image at normalised coordinate 0.5. Which texels does it blend, and with what weights?],
  [A subgroup of 32 pixels has 31 that escape after 10 iterations and one that never escapes, with a limit of 1024. What is its lane use?],
  [Why can the Mandelbrot program not demand that every iteration count equals the CPU's? What could it demand instead, and would that be stronger or weaker than its check?],
)

#checklist(
  [I can use storage images and sampled images from compute shaders, with the right descriptors, formats and layouts.],
  [I can write a tiled, separable filter with aprons in shared memory and verify it.],
  [I can create and use samplers, and choose a tolerance for filtered results.],
  [I can measure divergence as lane use, and reduce it.],
  [Lab 2.4.1–2.4.4 done-when criteria all hold, with evidence filed.],
)
