#import "../lib/template.typ": *

= Dispatch at scale <ch-scale>

#chapter-meta(
  time: [6 hours],
  builds: [A gravitational N-body simulation of 16,384 particles, tiled in shared memory, that reaches its buffers through device addresses instead of descriptors, sizes its dispatches on the GPU with indirect dispatch, survives a dispatch-size limit forced to sixteen workgroups, and conserves energy to a few parts in ten million over two hundred steps.],
  needs: [Chapters 2.1 to 2.5.],
)

#why[
  The kernels so far have been dispatched with sizes the CPU computed, through descriptors the CPU wrote, on problems that fit comfortably in one dispatch. Larger GPU programs lose all three comforts: the amount of work is decided by earlier GPU work, data structures point at each other, and problems exceed what one dispatch can cover. This chapter meets each with the feature Vulkan provides: indirect dispatch, buffer device addresses, and grids that wrap a problem across dimensions. It does so in a simulation whose arithmetic finally outweighs its memory traffic, and whose physics provides an exact check.
]

#skip-test(
  rule: [If all four are easy, read the section on device addresses and do Labs 2.6.2 and 2.6.4.],
  [How does a dispatch take its workgroup counts from a buffer, and which barrier does the buffer need if a shader wrote it?],
  [What does a buffer device address give a shader that a descriptor does not, and what must a buffer be created with to have one?],
  [`maxComputeWorkGroupCount[0]` is 65,535 and a problem needs 100,000 workgroups of 256. How do you dispatch it?],
  [Why is an N-body force calculation compute-bound when SAXPY is memory-bound?],
)

== Core ideas

=== The simulation

Each of n particles attracts every other with a force that falls with the square of the distance. Computing every pair is n#super[2] interactions per step, 268 million for 16,384 particles, and each interaction is about twenty floating-point operations on data that, with tiling, is read from memory only once per workgroup. That puts the kernel far to the right of the roofline's ridge: like the Mandelbrot renderer of Chapter 2.4, it is limited by arithmetic.

The particles start in a _Plummer sphere_, a standard model of a star cluster whose density and velocities are in equilibrium, generated on the CPU. The force is _softened_: a small constant is added to each squared distance, so that close encounters do not produce enormous accelerations. The integrator is _leapfrog_, also called velocity Verlet: a half-step kick of the velocities, a full-step drift of the positions, the forces at the new positions, and another half-step kick. Leapfrog is _symplectic_: it conserves energy very well over long runs, which is what lets the program check itself, by computing the total energy at the start and the end and requiring them to agree.

#snippet("u2/nbody/main.cpp", "plummer", caption: [The initial conditions: a Plummer sphere, centred on the origin])

The energy check needs each particle's potential energy, another all-pairs sum, which a fourth kernel, `potential.comp`, computes in the same tiled way as the forces. The CPU adds the kinetic and potential energies in double precision:

#snippet("u2/nbody/main.cpp", "energy", caption: [Total energy, summed in double precision on the CPU])

The GPU computes in single precision, because double precision is slow on most GPUs and unavailable through MoltenVK; only the sums for the energy check use doubles, on the CPU.

=== Tiling the force calculation

A naive kernel would have each invocation read all n positions from memory. The tiled kernel has the invocations of a workgroup load one tile of 256 positions into shared memory together, each loading one, and then accumulate the pull of all 256 on their own particles, before moving to the next tile (@fig-nbody-tiles). Each position is then read from memory once per workgroup instead of once per invocation, a saving of a factor of 256.

#fig("u2-nbody-tiles", caption: [The tiled force calculation. Shared memory turns 256 reads of each position into one.]) <fig-nbody-tiles>

#snippet("u2/nbody/forces.comp", "forces", caption: [Accumulating the forces from shared memory, then the second half kick])

The kernel needs no test to skip a particle's pull on itself: the separation is zero, so the softened term contributes nothing. Slots of the last tile beyond the particle count are filled with zero mass for the same reason. The first force dispatch of a run is made with a half step of zero, to compute the initial accelerations without changing the velocities.

#snippet("u2/nbody/drift.comp", "drift", caption: [The first half kick and the drift])

=== Buffer device addresses

The shaders reach their five buffers without a single descriptor. Since Vulkan 1.2, a buffer created with `VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT`, from memory allocated with the matching flag, has a 64-bit _device address_ that `vkGetBufferDeviceAddress` returns. Shaders that enable `GL_EXT_buffer_reference` declare _buffer reference_ types and use such addresses like pointers. The feature `bufferDeviceAddress` must be enabled; `vkf` enables it whenever the device supports it, and `vkf::createBuffer` allocates the memory of a buffer with that usage with `VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT` and stores its address in `vkf::Buffer::address`.

#snippet("u2/nbody/main.cpp", "buffers", caption: [Buffers with device addresses])

The addresses travel in push constants, which hold 64-bit values as easily as 32-bit ones. On the GPU side, each buffer reference type describes the layout of what an address points at:

#snippet("u2/nbody/nbody.glsl", "references", caption: [Buffer reference types, and push constants that carry five addresses])

#snippet("u2/nbody/main.cpp", "push", caption: [The same push constants on the host])

#hazard(title: [Pitfall])[
  A buffer reference's `buffer_reference_align` declares the alignment of every address of that type; an address that is not so aligned is undefined behaviour. Device addresses of buffers are aligned to the buffer's memory requirements, but an address computed by adding an offset may not be. Declare the alignment your offsets actually guarantee.
]

Device addresses make GPU data structures natural: a buffer can hold addresses of other buffers, so that a tree, a list or a scene can link its parts as it would on the CPU, without a descriptor for each. They also remove the bookkeeping of descriptor sets for buffers. The cost is safety. The validation layer cannot check what a shader does with an address, a wrong address can corrupt any memory the device can reach, and synchronisation validation, which tracks accesses through descriptors, cannot see accesses through addresses at all, so the barriers between these kernels rest on reasoning alone.

#hazard(title: [Pitfall])[
  Remove the barriers between the drift and force dispatches and, on the M2 Pro, the simulation still conserves energy and validation still says nothing. Neither proves the barriers unnecessary: the layer cannot see these accesses, and another GPU, or the same one under a different load, may overlap the dispatches.
]

=== Indirect dispatch

The number of workgroups a step needs depends on the number of particles, which here is fixed, but in many programs is decided by earlier GPU work: the survivors of a cull, the elements of a compaction, the cells a simulation refined. Reading the count back to the CPU to dispatch would stall the GPU. `vkCmdDispatchIndirect` instead reads the three workgroup counts from a `VkDispatchIndirectCommand` in a buffer, created with `VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT`, when the command executes.

A one-invocation kernel writes the command from the particle count stored on the GPU:

#snippet("u2/nbody/prepare.comp", "prepare", caption: [Computing the dispatch on the GPU])

The indirect command is read at `VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT`, before any shader of the dispatch runs, so the barrier between the kernel that writes it and the dispatch that reads it must name that stage and `VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT`:

#snippet("u2/nbody/main.cpp", "indirect", caption: [Preparing the dispatch, then dispatching from it])

#snippet("u2/nbody/main.cpp", "steps", caption: [Two hundred steps, each two indirect dispatches with barriers between them])

=== Problems larger than a dispatch

`maxComputeWorkGroupCount` limits each dimension of a dispatch, to as little as 65,535. A one-dimensional problem that needs more workgroups can be dispatched as a two-dimensional grid, with each workgroup computing its linear index from both coordinates (@fig-grid2d). Grid-stride loops, as in Chapter 2.1, are another answer: dispatch fewer workgroups and let each invocation handle several elements. A third is to split the problem across several dispatches, passing each the index of its first element in a push constant.

#fig("u2-grid2d", caption: [Sixty-four workgroups' worth of work on a device that allows only sixteen per dimension, as a grid of sixteen by four.]) <fig-grid2d>

#hazard(title: [Pitfall])[
  `vkCmdDispatchBase` dispatches a range of workgroups whose `gl_WorkGroupID` starts at a given base, which looks like a way past the limit. It is not: the base plus the count must still be within `maxComputeWorkGroupCount`.
]

#snippet("u2/nbody/nbody.glsl", "particle-index", caption: [Every kernel computes its particle's index from a two-dimensional grid])

The program can pretend that the device's limit is smaller than it is, to test this path on hardware that would never need it. With `--max-groups 16`, the preparation kernel spreads the 64 workgroups over a 16 × 4 grid, and the simulation must give bit-identical positions:

#snippet("u2/nbody/main.cpp", "forced", caption: [Running again with the limit forced down, and comparing every position])

#console(read("/src/console/u2-nbody.txt"), caption: [Two hundred steps on the M2 Pro, with validation off])

#console(read("/src/console/u2-nbody-maxgroups.txt"), caption: [The same with the dispatch limit forced to sixteen, with validation on])

Each step takes 2 ms, 134 billion interactions per second. At the customary count of twenty operations per interaction, that is 2.7 trillion operations per second, 43% of the arithmetic peak that Chapter 2.5 measured. Part of the difference is accounting: the peak assumes that every instruction is a fused multiply-add, worth two operations, and few of the loop's instructions are. The rest goes mainly to the reciprocal square root, which is slower than a multiply-add, and to the reads from shared memory. The energy drifts by 2.5 parts in ten million over the run, well within the limit of one part in ten thousand.

#keyidea[
  With indirect dispatch the GPU decides how much work to do, and with device addresses it finds its data the way a CPU program would. Together with grids that wrap their work, they make the GPU-driven rendering of Unit 4 possible.
]

#opengl[
  OpenGL 4.3 has indirect dispatch, `glDispatchComputeIndirect`, reading from the buffer bound to `GL_DISPATCH_INDIRECT_BUFFER` after a `glMemoryBarrier(GL_COMMAND_BARRIER_BIT)`. Pointers to buffers exist only as NVIDIA's `NV_shader_buffer_load` extension, which has no portable equivalent; Vulkan's buffer device addresses have been core since Vulkan 1.2 and are widely supported.
]

#reading(
  [Lars Nyland, Mark Harris and Jan Prins, "Fast N-Body Simulation with CUDA", _GPU Gems 3_, chapter 31: the tiled algorithm this chapter uses.],
  [The Vulkan Guide, "Buffer Device Address".],
  [The `GL_EXT_buffer_reference` extension specification, in the KhronosGroup/GLSL repository.],
  [S. J. Aarseth, M. Hénon and R. Wielen, "A comparison of numerical methods for the study of star cluster dynamics", _Astronomy and Astrophysics_ 37, 1974, for the Plummer sphere's construction.],
)

== Labs

#lab([Run, scale and check], goal: [Measure how the simulation scales with n.], time: [1.5 hours], code: "code/u2/nbody")[
  + Run `VKF_VALIDATION=0 build/bin/u2_nbody` with `--n` set to 4096, 16,384 and 65,536.
  + Record the interactions per second and the energy drift at each size.
  + Place the force kernel on your GPU's roofline from Chapter 2.5.
  #done-when(
    [Every run passes its energy check.],
    [You can explain how the interactions per second change with n, from the roofline and the number of workgroups.],
  )
  #evidence([The table and the placement on the roofline.])
]

#lab([Without tiling], goal: [Measure what shared memory saves here.], time: [1 hour], code: "code/u2/nbody")[
  + Write a force kernel that reads every source position directly from the buffer, and time it against the tiled one.
  + Try tiles of 64 and 512 invocations in the tiled kernel.
  #done-when(
    [Every version conserves energy within the limit.],
    [You can explain the difference in speed in terms of memory traffic, using your GPU's caches.],
  )
  #evidence([The timings and the explanation.])
]

#lab([Grow and shrink on the GPU], goal: [Make the indirect dispatch earn its place.], time: [2 hours], code: "code/u2/nbody")[
  + Add a pass that removes particles that move beyond a radius of 50, with stream compaction from Chapter 2.3, and writes the new count to the parameter buffer.
  + Prepare each step's dispatch from the new count with the existing kernel, so that the CPU never reads the count during the run.
  + Check at the end that the remaining particles are exactly those a CPU filter would keep, and that their energy is conserved.
  #done-when(
    [The CPU reads nothing during the run, and the final check passes.],
    [Validation is silent, including for the new barriers.],
  )
  #evidence([The new pass, its barriers, and the result.])
]

#lab([Addresses in data], goal: [Build a structure that links buffers by address.], time: [1.5 hours], code: "code/u2/nbody")[
  + Put the five addresses in a small buffer of their own, and pass only that buffer's address in the push constants.
  + Read the addresses in the shaders through a buffer reference to that structure.
  #done-when(
    [The simulation's results are bit-identical to the original's.],
    [You can explain why the alignment declared for each buffer reference type is safe.],
  )
  #evidence([The changed shaders and the comparison.])
]

#problems(
  [How many interactions does a step perform for n = 16,384, and how many bytes does the tiled kernel read from memory per step? Compute its arithmetic intensity.],
  [Write the barrier between a compute shader that writes a `VkDispatchIndirectCommand` and the `vkCmdDispatchIndirect` that reads it, and explain why a destination of `COMPUTE_SHADER` would be wrong.],
  [Why can synchronisation validation not check the barriers between these kernels? What could you do to gain some confidence that they are correct?],
  [A device's limit is 65,535 workgroups per dimension. Give the grid that `prepare.comp` writes for 100 million particles in workgroups of 256, and the number of invocations that do nothing. Find a grid that wastes fewer.],
  [Leapfrog conserves energy over long runs where a simple Euler integrator does not. Without the mathematics, what property of leapfrog makes the difference, and how would the energy check behave with Euler?],
)

#checklist(
  [I can tile an all-pairs computation in shared memory and know when it is compute-bound.],
  [I can use buffer device addresses from push constants and from data, with their alignment and their risks.],
  [I can size dispatches on the GPU with indirect dispatch and the right barrier.],
  [I can dispatch problems larger than the device's limits.],
  [Lab 2.6.1–2.6.4 done-when criteria all hold, with evidence filed.],
)
