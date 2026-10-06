#import "../lib/template.typ": *

= Parallel patterns <ch-patterns>

#chapter-meta(
  time: [7 hours],
  builds: [A reduction of 16 million floats in five variants, measured against memory bandwidth; three prefix sums, from a single workgroup to a multi-level scan of four million values; stream compaction built on the scan; and a stable radix sort of four million key-value pairs, checked against `std::stable_sort`.],
  needs: [Chapters 2.1 and 2.2.],
)

#why[
  A small number of patterns account for most of what GPUs compute beyond simple element-wise work: reduction, which combines many values into one; scan, which gives every element the combination of those before it; compaction, which keeps the elements that pass a test; and sorting. Each looks sequential at first sight, and each has a parallel form whose structure, a tree of partial results computed level by level, recurs throughout GPU programming. This chapter builds all four, verifies each against the CPU, and measures them against the bandwidth limits of Chapter 2.1.
]

#skip-test(
  rule: [If all five are easy, read the radix sort section and do Labs 2.3.1 and 2.3.4.],
  [Why is a reduction in shared memory with `if (t < stride)` faster than one with `if (t % (2 * stride) == 0)`?],
  [What are the work and the span of the Hillis–Steele scan and of the Blelloch scan for n values?],
  [How does a scan of four million values that each workgroup can only scan 2048 of at a time produce a correct result?],
  [How does an exclusive scan turn a list of keep-or-drop flags into the output positions of stream compaction?],
  [Why must each pass of an LSD radix sort be stable?],
)

== Core ideas

=== Work and span

Two numbers describe a parallel algorithm. Its _work_ is the total number of operations it performs, and its _span_, or depth, is the length of its longest chain of operations that must happen one after another. Adding n numbers in a loop has work n and span n. Adding them in a tree, pairs first, then pairs of pairs, has the same work but a span of only log₂ n, which is what lets thousands of invocations share it. An algorithm is _work-efficient_ if its work is no larger, asymptotically, than the best sequential algorithm's; a parallel algorithm that does more work can still win with enough hardware, but it spends energy and bandwidth to do so.

=== Reduction

A reduction combines n values with an associative operation, here addition. Each workgroup loads its share of the input into shared memory and sums it in a tree, halving the number of active invocations at each step, with a barrier between steps; invocation 0 then writes the workgroup's sum. Which invocations stay active matters (@fig-reduction-trees).

#fig("u2-reduction-trees", caption: [Two ways to address a tree reduction, shown for eight values. Both perform the same additions; they differ in which invocations do them.]) <fig-reduction-trees>

With _interleaved addressing_, the invocations whose index is a multiple of twice the stride add their neighbours. The active invocations become sparser at every step but remain spread across every subgroup, so every subgroup keeps executing until the last step, mostly with idle lanes:

#snippet("u2/reduce/interleaved.comp", "interleaved", caption: [A tree with interleaved addressing])

With _sequential addressing_, the first half adds the second half, then the first quarter adds the second quarter, and so on. The active invocations stay contiguous, so whole subgroups fall idle and stop at once:

#snippet("u2/reduce/sequential.comp", "sequential", caption: [A tree with sequential addressing])

Each workgroup produces one partial sum, so the program reduces the partial sums again in a second pass, and a third if needed, alternating between two buffers until one value remains:

#snippet("u2/shared/reduction.hpp", "passes", caption: [Planning the passes down to a single value])

Subgroups offer a shortcut. `subgroupAdd`, from `GL_KHR_shader_subgroup_arithmetic`, sums a value across a subgroup without shared memory or barriers, often in a few hardware instructions. A workgroup then needs only one tree step per subgroup: each subgroup's sum goes to shared memory, written by the single invocation that `subgroupElect` chooses, and the first subgroup sums those.

#snippet("u2/reduce/subgroup.comp", "subgroup", caption: [A workgroup sum built from two subgroup reductions])

The last variant changes something else: each invocation first adds several elements on its own, eight here, before the workgroup's tree starts. This _coarsening_ divides the number of workgroups, the tree steps and the barriers by eight, and gives each invocation several independent loads to have in flight at once:

#snippet("u2/reduce/coarse.comp", "coarse", caption: [Each invocation sums `ITEMS` elements before the tree])

The program sums 16,777,216 random floats in each variant, and compares each result with a sum computed in double precision on the CPU:

#snippet("u2/reduce/main.cpp", "reference", caption: [The CPU's reference sum])

#console(read("/src/console/u2-reduce.txt"), caption: [Five reductions of 64 MiB on the M2 Pro, with validation off])

#fig("u2-reduce", caption: [The reductions' bandwidth on the M2 Pro. Coarsening doubles the speed of either kind of tree; the choice of tree matters little once it does.]) <fig-reduce>

The three variants that load one element per invocation reach 70 to 90 GB/s. Interleaved addressing is the slowest, by a margin that changes from run to run on this GPU, and the other two are within a few per cent of each other. Coarsening doubles their speed, to about 177 GB/s, close to the SAXPY bandwidth of Chapter 2.1: the work per element left in the tree is now too small to matter, and the kernel is limited by memory, as a reduction should be. On GPUs whose shared memory is slower relative to their memory bandwidth, the addressing and the subgroup operations matter more; Lab 2.3.1 asks how much on yours.

The relative errors also deserve a look. Adding floats in a different order gives a different result, so a GPU sum never matches a sequential CPU sum exactly. A tree is, if anything, the more accurate order: its rounding error grows with the logarithm of n, where a sequential loop's grows with n. The program accepts a relative error of 10#super[−5] against the double-precision sum, which every variant meets with a wide margin.

=== Scan

A _scan_, or prefix sum, replaces each element with the sum of the elements before it. An _inclusive_ scan includes the element itself; an _exclusive_ scan does not and starts with zero, so that the exclusive scan of [3, 1, 7, 0, 4, 1, 6, 3] is [0, 3, 4, 11, 11, 15, 16, 22]. Scans allocate space in parallel: if each element needs some number of output slots, the exclusive scan of those numbers gives each element the position of its first slot. Compaction and the radix sort below are both built on that.

The simplest parallel scan, due to Hillis and Steele, adds to each element the element `offset` places before it, for offsets of 1, 2, 4 and so on. After log₂ n steps every element holds its inclusive prefix sum. It reads and writes the whole array at every step, so it double-buffers in shared memory:

#snippet("u2/scan/hillis_steele.comp", "hillis-steele", caption: [The Hillis–Steele scan within one workgroup])

Its span is log₂ n, but its work is n log₂ n, which makes it a poor choice for large arrays. Blelloch's scan is work-efficient. Its _up-sweep_ is a reduction tree that leaves partial sums at the tree's nodes; its _down-sweep_ clears the root and walks back down the tree, giving each left child its parent's value and each right child the parent's value plus the old left child (@fig-blelloch). It performs about 2n additions in 2 log₂ n steps.

#fig("u2-blelloch", caption: [The Blelloch scan of eight values, in place in shared memory. Each row is one step, separated from the next by a barrier.]) <fig-blelloch>

#snippet("u2/scan/blelloch.comp", "up-sweep", caption: [The up-sweep: a reduction that keeps its partial sums])

#snippet("u2/scan/blelloch.comp", "down-sweep", caption: [The down-sweep: pushing prefixes back down the tree])

The fastest block scan uses subgroups. `subgroupInclusiveAdd` scans a value across a subgroup in hardware; the last invocation of each subgroup writes the subgroup's total to shared memory; the first subgroup scans those totals; and each invocation adds its subgroup's prefix to its own result.

#snippet("u2/shared/scan.glsl", "workgroup-scan", caption: [An exclusive scan across a workgroup, built from subgroup scans])

This scan numbers invocations by subgroup, through `gl_SubgroupID` and `gl_SubgroupInvocationID`, so it needs each subgroup to be full and in order. The program asks for that with `VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT` when the device supports it, which Chapter 2.5 explains. Each invocation also scans four consecutive values of its own sequentially, which coarsens the scan as the reduction was coarsened:

#snippet("u2/shared/scan_blocks.comp", "scan-blocks", caption: [Each invocation scans four values, and the workgroup scans the invocations' sums])

=== Scanning more than one block

A workgroup scans one block of the input, 1024 to 4096 values here. A larger input needs a _multi-level scan_ (@fig-multilevel). The first dispatch scans every block independently and writes each block's total. A second scans the totals, which gives each block the sum of all the blocks before it. A third adds that offset to every element of its block. When the totals themselves span several blocks, the second step is the same procedure one level up, recursively.

#fig("u2-multilevel", caption: [A multi-level scan. Blocks are scanned independently; the scan of their totals gives each block its offset; adding the offsets completes the scan.]) <fig-multilevel>

#snippet("u2/shared/scan.hpp", "build-levels", caption: [Building the levels: each level's totals are the next level's input])

#snippet("u2/shared/scan.hpp", "record-levels", caption: [Recording the scans up the levels and the additions back down, with a barrier after each dispatch])

#snippet("u2/shared/scan_add.comp", "add", caption: [Adding each block's offset])

#console(read("/src/console/u2-scan.txt"), caption: [Scans on the M2 Pro: the single-workgroup Hillis–Steele scan, and two multi-level scans of four million values])

The table's bandwidth counts one read and one write of each element, the least that any scan must do. The multi-level scan reads and writes every element twice, once in the block scan and again when the offsets are added, so it moves about twice the bytes the table counts. Counted that way, the Blelloch version runs at about 200 GB/s, the limit of the M2 Pro's memory, and the subgroup version at nearly 250 GB/s, which is possible only because part of the data is still in the GPU's caches when the second pass reads it. Faster scans exist: the single-pass _decoupled look-back_ scan of Merrill and Garland reads and writes each element once, by having each workgroup wait for the totals of the workgroups before it. Chapter 2.1 explained why Vulkan does not guarantee that such waiting finishes, which is why this course uses the multi-level form.

=== Stream compaction

_Stream compaction_ keeps the elements that satisfy a predicate, in their original order. With a scan it takes three passes: write a flag of 1 or 0 for every element, scan the flags exclusively, and write each kept element to the position its scanned flag gives. The scan's total is the number kept.

#snippet("u2/scan/compact_flags.comp", "flags", caption: [The predicate and the flags])

#snippet("u2/scan/compact_scatter.comp", "scatter", caption: [Each kept element goes to the position the scan gave it])

#snippet("u2/scan/main.cpp", "compact", caption: [Flags, scan and scatter, with the count read from the scan's total])

#console(read("/src/console/u2-scan-compact.txt"), caption: [Compaction of four million values on the M2 Pro])

=== Radix sort

A _least-significant-digit radix sort_ sorts integer keys by one digit at a time, starting with the least significant, with a _stable_ sort for each digit: one that keeps keys with equal digits in their existing order. Stability is what makes the method work: after the pass for digit k, keys are ordered by their lowest k + 1 digits, because ties in digit k were left in the order the earlier passes produced. Thirty-two-bit keys with four-bit digits take eight passes. The sort carries a value with each key, and the values test stability, because equal keys must keep their values in the input's order.

Each pass has three steps (@fig-radix). The _count_ step has each workgroup count how many keys of its block have each digit. The counts are stored digit by digit, every block's count of digit 0 first, so that an exclusive scan of the whole array, the multi-level scan above, gives each block the first output position for each of its digits. The _scatter_ step then writes every key to its digit's position for its block, plus the key's rank among the block's keys with the same digit.

#fig("u2-radix", caption: [One pass of the radix sort. Counting and scanning give each block a starting position for each digit; the scatter writes each block's keys there in a stable order.]) <fig-radix>

#snippet("u2/sort/sort_count.comp", "count", caption: [Counting each block's digits in shared memory])

The scatter must rank keys stably within the block. It sorts the block in shared memory one bit of the digit at a time with a _split_: an exclusive scan of the bits tells each key how many ones precede it, so a key whose bit is 1 goes after all the zeros in that order, and a key whose bit is 0 goes to its position minus the ones before it. Each split is stable, so four of them sort the block stably by the four-bit digit.

#snippet("u2/sort/sort_scatter.comp", "split", caption: [Four stable splits sort the block by the current digit])

#snippet("u2/sort/sort_scatter.comp", "scatter", caption: [Writing each key to its global position])

The passes alternate between two pairs of buffers, and each pass's three steps are separated by barriers:

#snippet("u2/sort/main.cpp", "passes", caption: [Eight passes of count, scan and scatter])

#snippet("u2/sort/main.cpp", "verify", caption: [The result must match `std::stable_sort` exactly, keys and values])

#console(read("/src/console/u2-sort.txt"), caption: [Sorting four million pairs on the M2 Pro, with validation off])

The GPU sorts a billion pairs per second, fifty times faster than `std::stable_sort` on one CPU core. A parallel sort on all the CPU's cores would narrow the gap, but not close it: each pass of the radix sort reads and writes every pair a few times, at memory bandwidth, and does almost nothing else.

#keyidea[
  Reduction, scan and the scatter that follows a scan are the building blocks of most parallel algorithms on the GPU. When a problem seems to need a sequential loop, ask whether a scan can compute what each element needs to know about the elements before it.
]

#opengl[
  These algorithms are the same in OpenGL 4.3 compute shaders, with `glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)` between passes where Vulkan records a pipeline barrier. Subgroup operations require the `GL_KHR_shader_subgroup` extension, which most desktop drivers offer and macOS does not. In CUDA, the CUB and Thrust libraries provide all four, and the CUDA literature in the reading list explains them with the same diagrams.
]

#reading(
  [Mark Harris, "Optimizing Parallel Reduction in CUDA", NVIDIA, 2007: seven versions of the reduction, from interleaved addressing to unrolled, coarsened kernels.],
  [Mark Harris, Shubhabrata Sengupta and John D. Owens, "Parallel Prefix Sum (Scan) with CUDA", _GPU Gems 3_, chapter 39.],
  [Duane Merrill and Michael Garland, "Single-pass Parallel Prefix Scan with Decoupled Look-back", NVIDIA, 2016, with this chapter's caveat about forward progress in mind.],
  [Hwu, Kirk and El Hajj, _Programming Massively Parallel Processors_, chapters 10 (reduction), 11 (scan) and 13 (sorting).],
  [The Vulkan Guide, "Subgroups".],
)

== Labs

#lab([Reduce at the bandwidth limit], goal: [Find the reduction's best configuration on your GPU.], time: [2 hours], code: "code/u2/reduce")[
  + Run `VKF_VALIDATION=0 build/bin/u2_reduce` and record the table.
  + Add variants with 2, 4, 16 and 32 elements per invocation, and run each with local sizes of 128, 256 and 512.
  + Compare the best result with your GPU's SAXPY and copy bandwidths from Chapters 2.1 and 2.2.
  #done-when(
    [Every variant's sum is within the tolerance.],
    [Your best variant reaches at least 90% of your GPU's copy bandwidth, or you can explain what prevents it.],
  )
  #evidence([The table of variants and the comparison.])
]

#lab([A scan by hand, then in code], goal: [Understand the Blelloch scan's index arithmetic exactly.], time: [1.5 hours], code: "code/u2/scan")[
  + Run the Blelloch scan on paper for the sixteen values 1 to 16, writing the tree after every step.
  + Add an inclusive variant of the block scan, as a specialisation constant, and check it against `std::inclusive_scan`.
  + Run the scans with `--n 1` and `--n 4194305` and confirm they are still exact.
  #done-when(
    [Your paper scan matches the program's output for those sixteen values.],
    [The inclusive variant is exact at every size you tried.],
  )
  #evidence([The paper scan and the new variant.])
]

#lab([Compaction that returns indices], goal: [Adapt the compaction to a new output.], time: [1.5 hours], code: "code/u2/scan")[
  + Change the compaction to keep the indices of elements whose highest bit is set, instead of the values that are multiples of three.
  + Check the result against the CPU, and time it at four million and sixteen million elements.
  #done-when(
    [The kept indices match a CPU implementation exactly at both sizes.],
    [You can say what fraction of the compaction's time each of its three steps takes, from timestamps around each.],
  )
  #evidence([The changes, the check and the breakdown of time.])
]

#lab([Sort with eight-bit digits], goal: [Trade passes for work per pass.], time: [2 hours], code: "code/u2/sort")[
  + Change the sort to eight-bit digits: 256 buckets in the count step and eight splits in the scatter step, in four passes.
  + Check the result against `std::stable_sort`, and compare its time with the four-bit version at four million and sixteen million pairs.
  #done-when(
    [The eight-bit sort matches `std::stable_sort` exactly.],
    [You can explain which version is faster on your GPU, in terms of memory traffic and shared-memory work per pass.],
  )
  #evidence([The changes and the timings, with your explanation.])
]

#problems(
  [Give the work and span of the Hillis–Steele and Blelloch scans for n = 2#super[20]. For what n does the Blelloch scan's extra steps outweigh Hillis–Steele's extra work on a GPU with 100,000 lanes?],
  [In a workgroup of 512 invocations with subgroups of 32, how many subgroups execute each step of the interleaved tree, and of the sequential tree?],
  [How many passes does the coarsened reduction need for 2#super[24] values with 512 invocations of 8 elements each? Check your answer against the program's output.],
  [Explain, with a small example, why the radix sort's output would be wrong if the split within a block were not stable.],
  [Why does compaction use an exclusive scan of the flags? What would go wrong with an inclusive scan, and how would you correct it?],
)

#checklist(
  [I can explain work and span, and why work efficiency matters.],
  [I can write a reduction with shared memory, subgroup operations and coarsening, and measure it against bandwidth.],
  [I can write the Hillis–Steele and Blelloch scans and a multi-level scan.],
  [I can build compaction and a stable radix sort from a scan.],
  [Lab 2.3.1–2.3.4 done-when criteria all hold, with evidence filed.],
)
