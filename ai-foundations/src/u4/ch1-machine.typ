#import "../lib/template.typ": *

= The machine <ch-machine>

#chapter-meta(
  time: [5 hours],
  builds: [Your GPU's memory bandwidth and arithmetic peak, measured; its roofline; every operation of a layer of Chapter 2.5's model timed, its FLOPs and bytes counted, and placed against the roofline; and an account of each operation's distance from its bound.],
  needs: [Chapters 1.1 and 2.4.],
)

#why[
  Unit 1 measured matrix multiplications and found them limited sometimes by arithmetic and sometimes by memory; Unit 2 trained a transformer at about half of the GPU's arithmetic peak. This unit is about closing such gaps, and every attempt starts with the same question: what limits this operation? The _roofline model_ answers it from four numbers, the machine's peak arithmetic and memory bandwidth and the operation's FLOPs and bytes, and this chapter measures all of them for the machine on your desk and the model you trained.
]

#skip-test(
  rule: [If all four are easy, read the section on the transformer's operations and do Labs 4.1.2 and 4.1.4.],
  [State the roofline: the attainable FLOP/s of an operation with arithmetic intensity $I$ on a machine with peak $P$ and bandwidth $B$.],
  [What is the arithmetic intensity of multiplying an $N times d$ matrix by a $d times d$ one in float32, and of an element-wise addition?],
  [Why can a GPU with ten times a CPU's arithmetic peak run an RMS normalisation only slightly faster?],
  [What is the ridge point of a machine, and how do you compute it?],
)

== Core ideas

=== Two numbers for a machine

A GPU is thousands of simple arithmetic units fed by a memory system. Its _peak_ is how many FLOPs per second the units can perform; its _bandwidth_ is how many bytes per second memory can deliver to them. Between the units and main memory sit faster, smaller stores: registers private to each thread, a small _shared_ or _threadgroup_ memory per group of threads, and caches. Chapter 4.4 programs them directly; for now they explain why measured numbers fall short of datasheets.

The M2 Pro's CPU and GPU share one pool of memory, Apple's _unified memory_, with a published bandwidth of 200 GB/s, and its GPU's 19 cores have a peak of about 6.8 TFLOP/s in float32. A data-centre GPU such as NVIDIA's H100 has 3.35 TB/s of bandwidth and nearly 1,000 TFLOP/s for bfloat16 matrix multiplications on its tensor cores: about seventeen times the bandwidth and well over a hundred times the matrix arithmetic. The ratio between the two numbers is what matters for what follows, and it is larger on the H100.

#snippet("u4/roofline.py", "peaks", caption: [Measuring bandwidth with a copy, and the arithmetic peak with a large product])

#console-part("/src/console/u4-roofline.txt", to: 3, caption: [The M2 Pro's GPU, measured])

=== The roofline

An operation that performs $F$ FLOPs and moves $M$ bytes has an _arithmetic intensity_ $I = F \/ M$. It cannot run faster than the arithmetic allows, $P$, nor faster than memory can feed it, $I B$:
$ "attainable FLOP/s" = min(P, I B). $
Plotted against intensity on logarithmic axes, the bound is a sloping line that meets a flat roof at the _ridge point_ $I = P \/ B$. An operation left of the ridge is _memory-bound_: making its arithmetic faster changes nothing, and only moving fewer bytes helps. An operation right of it is _compute-bound_, and only less or faster arithmetic helps.

=== A transformer layer on the roofline

The program builds tensors with the shapes of one layer of Chapter 2.5's model at its training batch, 32 sequences of 512 tokens, and times each operation of a layer's forward pass, with its FLOPs and the minimum bytes it must move:

#snippet("u4/roofline.py", "ops", caption: [Each operation with its FLOPs and minimum bytes])

#console-part("/src/console/u4-roofline.txt", from: 3, command: false, caption: [One layer's operations against the roofline])

#fig("u4-roofline", caption: [The M2 Pro's measured roofline, with the operations of a transformer layer at their measured speeds.]) <fig-roofline>

The measured machine falls short of its datasheet, as measured machines do: copies run at 175 GB/s of the published 200, and a large product at 5.5 of the nominal 6.8 TFLOP/s, which puts the ridge at 32 FLOP per byte. The matrix multiplications run at 88% to 100% of that peak: they are compute-bound, and PyTorch's kernels leave little to gain. Attention reaches about half the peak, and Chapter 4.4 writes such a kernel to see why. The element-wise operations sit far left of the ridge, where only bandwidth matters. The residual addition streams at 94% of the copy's bandwidth, but SiLU-gating and RMS normalisation reach 59% and 37% of their bounds, and together, counting each layer's two norms and two additions, they take about a fifth of the layer's time for well under 1% of its FLOPs. The worst is the cross-entropy, at a quarter of its bound: PyTorch computes a log-softmax over all 537 MB of logits and writes it out before picking each target's entry, moving several times the bytes a fused kernel would need.

=== What the roofline says about everything that follows

The roofline sorts this unit's techniques by the bound they attack. Fusing element-wise operations, so that a normalisation, a SiLU and a multiplication read and write memory once instead of three times, raises their effective intensity; Chapter 4.2 measures what `torch.compile` gains that way. FlashAttention, in Chapter 4.4, avoids writing the attention scores to memory at all. Generating text one token at a time turns every matrix multiplication into a matrix-vector product with intensity near 0.5, far left of the ridge; quantisation, in Chapter 4.7, raises it by moving fewer bytes per weight, and batching, in Chapter 4.8, by reusing each weight for many sequences. Data-centre GPUs, whose ridge points lie further right than the M2 Pro's, make all of these matter more.

#keyidea[
  Every operation has a bound: arithmetic or memory, whichever its intensity selects. Measure the machine's two peaks, count each operation's FLOPs and bytes, and the roofline tells you how fast it could be and what would make it faster.
]

#inpytorch[
  PyTorch's operations each read their inputs from memory and write their outputs back, so a chain of element-wise operations is a chain of memory-bound kernels. `torch.compile` fuses such chains, and `torch.utils.flop_counter.FlopCounterMode` counts an operation's FLOPs for you. Vendor tools, Nsight Compute for NVIDIA and Xcode's Metal profiler for Apple, report measured bytes and FLOPs per kernel and draw rooflines of their own.
]

#reading(
  [Samuel Williams, Andrew Waterman and David Patterson, "Roofline: An Insightful Visual Performance Model for Multicore Architectures", _Communications of the ACM_ 52(4), 2009.],
  [Horace He, "Making Deep Learning Go Brrrr From First Principles", 2022: compute, memory and overhead bounds in PyTorch.],
  [NVIDIA, _H100 Tensor Core GPU Architecture_ white paper, 2022, and Apple's documentation of the M2 family's GPU.],
)

== Labs

#lab([Bandwidth and the caches], goal: [See the memory hierarchy in a bandwidth curve.], time: [1 hour], code: "code/u4/roofline.py")[
  + Measure copy bandwidth on your GPU for sizes from 64 KiB to 1 GiB, doubling each time, with enough repetitions for each to take at least 10 ms.
  + Plot bandwidth against size and mark where the curve changes.
  #done-when(
    [Your plot covers at least 15 sizes.],
    [You can relate each step in the curve to a level of the memory hierarchy, or explain why there is none.],
  )
  #evidence([The plot and its interpretation.])
]

#lab([The shape of a product], goal: [Map a matrix multiplication's speed against its shape.], time: [1.5 hours], code: "code/u4/roofline.py")[
  + Time products of an $N times 512$ matrix by a $512 times 512$ one for $N$ from 1 to 16,384, and compute each one's intensity.
  + Place them on your roofline, and find the $N$ at which the product becomes compute-bound.
  #done-when(
    [Your points follow the roofline's shape, and you can name the crossover $N$.],
    [You can relate $N = 1$ to generating one token and the largest $N$ to training.],
  )
  #evidence([The table and the plot.])
]

#lab([Fusion by hand], goal: [Measure what fusing element-wise operations gains.], time: [1 hour], code: "code/u4/roofline.py")[
  + Time RMSNorm followed by SiLU-gating as separate PyTorch operations, and the same function compiled with `torch.compile`.
  + Count the bytes each version must move at least, and compare the measured speed-up with the ratio of bytes.
  #done-when(
    [Your two byte counts and two times are recorded.],
    [The speed-up is within a factor of two of the byte ratio, or you can explain why not.],
  )
  #evidence([The counts, the times and the comparison.])
]

#lab([Another machine on paper], goal: [Predict the same layer on a data-centre GPU.], time: [1.5 hours], code: "code/u4/roofline.py")[
  + Using an H100's published bandwidth and bfloat16 peak, predict the time of each operation in the table, halving the bytes for bfloat16.
  + Find the operations whose share of the layer's time would grow most compared with the M2 Pro.
  #done-when(
    [Your predictions cover every operation.],
    [You can say which operations would dominate on the H100 and what that implies for optimising them.],
  )
  #evidence([The predictions and the conclusion.])
]

#problems(
  [Compute the ridge points of the M2 Pro from your measurements and of an H100 for bfloat16. What do they imply about the operations each machine runs well?],
  [Show that multiplying an $N times d$ matrix by a $d times d$ matrix in float32 has intensity $N d \/ (2(2 N + d))$, counting the bytes of both inputs and the output. What is it for $N = 1$ and $N = d$?],
  [RMS normalisation of $N d$ values reads them, computes a mean square per row and writes the result. What is its intensity, and its best time on the M2 Pro for $N = 8192$, $d = 512$?],
  [Why does the measured cross-entropy run far below its memory bound, and what would a fused implementation have to do?],
  [The attention row of the table counts bytes as if the scores never touched memory. When is that true, and what would the bytes be otherwise?],
)

#checklist(
  [I can measure a machine's bandwidth and arithmetic peak, and draw its roofline.],
  [I can count an operation's FLOPs and minimum bytes and compute its intensity.],
  [I can place a transformer's operations on the roofline and say what limits each.],
  [I can predict which optimisations will help an operation from its position on the roofline.],
  [Lab 4.1.1–4.1.4 done-when criteria all hold, with evidence filed.],
)
