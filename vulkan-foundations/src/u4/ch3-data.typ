#import "../lib/template.typ": *

= Drawing with data <ch-data>

#chapter-meta(
  time: [6 hours],
  builds: [A scene of textured cubes on a textured ground: meshes uploaded through a staging buffer, a uniform buffer for each frame in flight, four textures with full mipmap chains generated on the GPU and checked against the CPU, trilinear and anisotropic sampling, and a bindless table of textures chosen per draw by a push constant.],
  needs: [Chapters 4.1 and 4.2.],
)

#why[
  Chapter 4.1 drew from host-visible buffers and coloured faces by their normals. Real rendering draws meshes from device-local memory, reads per-frame data such as the camera from uniform buffers that must not be overwritten while the GPU reads them, and samples textures, which need mipmaps to avoid aliasing and the right colour space to look right. It also chooses among many textures per draw, which is where Vulkan's descriptor model is most constraining and where descriptor indexing, the "bindless" style, frees it. This chapter puts all of these together and verifies each, including the mipmaps, against the CPU.
]

#skip-test(
  rule: [If all five are easy, read the section on bindless textures and do Labs 4.3.2 and 4.3.4.],
  [Which barrier does a vertex buffer filled by `vkCmdCopyBuffer` need before a draw reads it?],
  [Why does each frame in flight have its own uniform buffer?],
  [How is a mipmap chain generated on the GPU, and which layouts does each level pass through?],
  [Why does averaging the bytes of an sRGB texture give the wrong colour for its smaller mip levels?],
  [What must a device support for a shader to index an array of textures with a value from a push constant?],
)

== Core ideas

=== Meshes in device-local memory

Vertex and index data are read every frame by every draw, so they belong in device-local memory, filled through a staging buffer as Chapter 1.2 described. One staging buffer holds both, and two copies move them into their buffers. The barrier after the copies has two destinations: the vertex attribute fetch at `VERTEX_ATTRIBUTE_INPUT` and the index fetch at `INDEX_INPUT`, each with its own access type:

#snippet("u4/textured/main.cpp", "staging", caption: [Uploading a mesh through one staging buffer])

The vertices now carry texture coordinates, `u` and `v`, as well as positions and normals; Chapter 4.1's cube already had them. The vertex shader reads the camera's matrix from a uniform buffer in set 0 and the model matrix from push constants, and passes the texture coordinate on:

#listing("u4/textured/textured.vert", caption: [The vertex shader: a per-frame uniform and a per-draw push constant])

=== Data for each frame in flight

The camera moves every frame, so its matrix is rewritten every frame. With two frames in flight, the CPU writes frame n + 1's matrix while the GPU may still be reading frame n's, so the two must be in different memory. The program keeps one small host-visible uniform buffer and one descriptor set per frame slot:

#snippet("u4/textured/main.cpp", "frame-uniforms", caption: [A uniform buffer and a descriptor set for each frame in flight])

#snippet("u4/textured/main.cpp", "frame-loop", caption: [Each frame writes its slot's buffer after the frame ring has waited for that slot])

The frame ring's wait in `begin` is what makes the write safe: it returns only when the frame that last used the slot has finished on the GPU. The program prints which slot each frame used, `0 1 0 1`, as a check.

#keyidea[
  Anything the CPU writes every frame and the GPU reads needs one copy per frame in flight, indexed by the frame's slot. Anything written once and read every frame, such as meshes and textures, needs one copy, protected by a barrier after it is written.
]

=== Textures and their mipmaps

A texture viewed from far away covers fewer pixels than it has texels, and sampling it directly skips most of its texels, which shows as shimmering moiré patterns. _Mipmaps_ solve this: a chain of copies of the texture, each half the size of the one before, down to a single texel. The sampler picks the level whose texels are about the size of a pixel, and with _trilinear_ filtering blends between the two nearest levels.

The program's textures are 256 × 256 with nine levels. It uploads level 0 from a staging buffer and generates the others on the GPU with `vkCmdBlitImage`, which scales a region of one image level into another with filtering. Each level is the blit of the one above, which must first move from `TRANSFER_DST_OPTIMAL`, where it was written, to `TRANSFER_SRC_OPTIMAL`, from which it is read (@fig-mips):

#fig("u4-mips", caption: [Generating a mipmap chain with blits. Each level is written as a blit destination, then read as the source of the next.]) <fig-mips>

#snippet("u4/textured/main.cpp", "mipmaps", caption: [One blit per level, with a barrier on the level above before each])

At the end every level but the last is in `TRANSFER_SRC_OPTIMAL` and the last in `TRANSFER_DST_OPTIMAL`, so two barriers, one per range, move them all to `SHADER_READ_ONLY_OPTIMAL` for the fragment shader. Only the last level's barrier needs a source access: the others were last written before an earlier barrier already made their writes available.

#snippet("u4/textured/main.cpp", "to-sampled", caption: [Every level to `SHADER_READ_ONLY_OPTIMAL`])

Blitting with linear filtering is an optional feature of each format, so the program checks for it and falls back to generating the levels on the CPU:

#snippet("u4/textured/main.cpp", "blit-support", caption: [Linear blits are a format feature])

=== Mipmaps in the right colour space

The textures are stored as `VK_FORMAT_R8G8B8A8_SRGB`: their bytes are sRGB-encoded, as image files are, and the hardware decodes them to linear values when a shader samples them and encodes when a blit or a render writes them. Averaging must happen in linear light: the average of black and white is a linear 0.5, which sRGB encodes as 188, not 128. A blit between sRGB images does this correctly, and the program's CPU reference does the same, so that it can check every level of every texture to within one step of 8 bits:

#snippet("u4/textured/main.cpp", "cpu-mips", caption: [The CPU's mipmap chain, averaged in linear light])

The checker texture's single-texel level is (188, 188, 188), and the program prints what naive byte averaging would have given, 128: a visibly darker grey at a distance.

=== Samplers for textures

The sampler enables trilinear filtering by setting `mipmapMode` to `LINEAR` and `maxLod` to `VK_LOD_CLAMP_NONE`, and _anisotropic filtering_, which takes several samples along the direction in which a texture is compressed on screen. Surfaces seen at a grazing angle, like the ground here, are compressed far more in one direction than the other, and anisotropic filtering keeps them sharp where plain trilinear filtering would blur them. It is an optional feature, `samplerAnisotropy`, with a device limit on the number of samples.

#snippet("u4/textured/main.cpp", "sampler", caption: [Trilinear, anisotropic, repeating])

=== Many textures: the bindless table

Each cube shows a different texture. One way to draw them is a descriptor set per texture, bound before each draw. Another is to bind one array of textures once and let each draw choose an element. That is what the program does, with a push constant holding the index. The table lives in set 1 as an array of sampled images, separate from a single sampler, which the shader combines with `sampler2D(image, sampler)`:

#snippet("u4/textured/bindless.frag", "table", caption: [Indexing a table of textures with a push constant])

Indexing an array of images with a value that is not a compile-time constant needs _descriptor indexing_, core in Vulkan 1.2 but with optional features. `runtimeDescriptorArray` allows the array's size to be unspecified in the shader; `descriptorBindingPartiallyBound` allows the table to have more slots than the program has filled; and `shaderSampledImageArrayNonUniformIndexing` allows an index that differs between invocations, which the shader marks with `nonuniformEXT`. The index here comes from a push constant and so is the same for every invocation of a draw, but marking it costs nothing and keeps the shader correct if the index ever varies. The program checks for the features:

#snippet("u4/textured/main.cpp", "features", caption: [Using the table only where the device supports it])

#snippet("u4/textured/main.cpp", "set-layouts", caption: [A uniform buffer in set 0; a table of up to 64 textures and a sampler in set 1])

Only four of the sixty-four slots are written; partial binding makes the rest legal as long as no shader reads them.

#snippet("u4/textured/main.cpp", "table-writes", caption: [Writing the textures into the table's first slots, and the sampler])

#snippet("u4/textured/main.cpp", "draw-scene", caption: [Binding both sets once, then one push constant and one draw per object])

Without descriptor indexing, a shader may index an array of textures only with constant expressions. The fallback shader, chosen by `--no-bindless` or on devices without the features, uses a `switch` with a constant index in each branch:

#snippet("u4/textured/fixed.frag", "constant-index", caption: [Without descriptor indexing: constant indices only])

#console(read("/src/console/u4-textured.txt"), caption: [The textured scene on the M2 Pro, with the bindless table])

The program checks the rendered scene as well as the textures. The cube faces must show the textures their draws chose, and the far ground, where many texels fall in each pixel, must be a uniform grey with mipmaps: its brightness varies by 12 levels with them and by 126 without, the moiré of @fig-textured.

#fig("/src/figures/u4-textured-images.jpg", caption: [The scene with mipmaps and with level 0 only. Without mipmaps, the distant checkerboard breaks into moiré.]) <fig-textured>

#hazard(title: [Pitfall])[
  Descriptor sets cannot be updated while a pending command buffer uses them, unless the binding was created with `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` and its pool and layout with the matching flags. A bindless table that grows while frames are in flight needs that flag, or one table per frame in flight.
]

#opengl[
  OpenGL binds textures to numbered texture units and uniform blocks to binding points, and changes them freely between draws. `glGenerateMipmap` builds the chain in one call, choosing the filter and the colour space handling itself. Bindless textures exist in OpenGL as `ARB_bindless_texture`, with 64-bit texture handles stored in buffers, which neither macOS nor every desktop driver supports. Vulkan's descriptor indexing is the portable form of the same idea.
]

#reading(
  [The Vulkan specification, "Copy Commands" (`vkCmdBlitImage`), "Samplers", and "Descriptor Indexing" in "Resource Descriptors".],
  [The Vulkan Guide, "Descriptor Arrays", "VK_EXT_descriptor_indexing" and "Image Copies".],
  [The sRGB transfer function, as defined in IEC 61966-2-1, or in the Vulkan specification's "Formats" chapter.],
)

== Labs

#lab([The scene with and without its features], goal: [Run every path through the program.], time: [1 hour], code: "code/u4/textured")[
  + Run `build/bin/u4_textured`, then with `--no-bindless`, then with `--cpu-mips`.
  + Compare `textured.png` and `textured-no-mips.png` on screen.
  #done-when(
    [All three runs pass with validation silent.],
    [You can explain each of the program's checks on the ground's brightness.],
  )
  #evidence([The three outputs.])
]

#lab([Mipmaps in the wrong colour space], goal: [See the error the linear-light average prevents.], time: [1.5 hours], code: "code/u4/textured")[
  + Change the CPU path to average sRGB bytes directly, and run with `--cpu-mips`.
  + Create the textures as `VK_FORMAT_R8G8B8A8_UNORM` while uploading the same bytes, and run with blits.
  + Compare the far ground's brightness and the cube faces in each case with the correct version.
  #done-when(
    [You have the three images and the far ground's mean in each.],
    [You can explain each difference with the sRGB transfer function.],
  )
  #evidence([The images, the means and the explanation.])
]

#lab([Anisotropy and level of detail], goal: [Measure what the sampler's settings do to the image.], time: [1.5 hours], code: "code/u4/textured")[
  + Render with anisotropy off, and with `maxAnisotropy` of 2, 4, 8 and 16.
  + Measure the sharpness of the ground's middle distance, for example the deviation of a band of rows, for each.
  + Add a `mipLodBias` of +1 and −1 and describe the effect.
  #done-when(
    [You have the deviation for each setting.],
    [You can explain what anisotropic filtering does that trilinear filtering cannot.],
  )
  #evidence([The table and two representative crops.])
]

#lab([A larger table], goal: [Use the bindless table as it is meant to be used.], time: [2 hours], code: "code/u4/textured")[
  + Generate sixty-four textures, each a different colour, and draw a grid of sixty-four cubes, each using its own texture through the push constant.
  + Check on the CPU that each cube shows its texture's colour.
  + Time recording and submission against a version that binds a separate descriptor set per cube.
  #done-when(
    [Both versions render the same image, checked on the CPU.],
    [You have the CPU time of each.],
  )
  #evidence([The image and the timings.])
]

#problems(
  [A mesh's vertex buffer is written by a compute shader instead of a copy. Change the staging barrier's source and destination accordingly.],
  [With three frames in flight, how many uniform buffers does the program need, and what goes wrong if it has two?],
  [A 1000 × 600 texture is mipmapped down to one texel. How many levels are there, and what are their sizes? How does `vkCmdBlitImage` handle the odd sizes?],
  [The checker texture is half black and half white. Show that its 1 × 1 level is 188 in sRGB, and compute what a UNORM texture of the same bytes would give.],
  [Why does `finishMipmaps` use two image barriers, with different source accesses, instead of one?],
)

#checklist(
  [I can upload meshes through staging and synchronise them with draws.],
  [I can keep per-frame data per frame in flight and per-object data in push constants.],
  [I can generate and check mipmaps on the GPU, in the right colour space.],
  [I can create samplers with trilinear and anisotropic filtering, and use a bindless table of textures.],
  [Lab 4.3.1–4.3.4 done-when criteria all hold, with evidence filed.],
)
