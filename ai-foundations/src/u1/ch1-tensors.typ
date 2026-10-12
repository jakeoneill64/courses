#import "../lib/template.typ": *

= Tensors and what they cost <ch-tensors>

#chapter-meta(
  time: [5 hours],
  builds: [A tour of array memory through strides and views; the broadcasting rule written out and checked against NumPy; three ways to compute a table of distances, the fastest three thousand times quicker than the slowest; and a matrix multiplication taken from Python loops to BLAS and the GPU, timed against your machine's peak.],
  needs: [The companion code installed as in the Handbook's setup part. No machine learning yet.],
)

#why[
  Every model in this course, from a linear regression to a language model, is arithmetic on arrays of numbers. How fast it trains, how large it can grow and whether it fits in memory at all are decided less by the mathematics than by how that arithmetic meets the machine: how arrays are laid out, how many bytes each operation moves, and whether the processor spends its time computing or waiting. This chapter builds the vocabulary for those questions. Later chapters lean on it constantly, and Unit 4 returns to it in depth.
]

#skip-test(
  rule: [If all four are easy, skim the chapter and do Lab 1.1.4.],
  [A `float32` array has shape `(3, 4)` and strides `(16, 4)`. What are the shape and strides of its transpose, and does taking the transpose copy any data?],
  [What shape does broadcasting `(8, 1, 6, 1)` with `(7, 1, 5)` produce, and why does `(3, 4)` with `(3,)` fail?],
  [How many floating-point operations does multiplying two $n times n$ matrices take, and how many bytes must it move at the least?],
  [Why can copying an array through its transpose be forty times slower than copying it in memory order?],
)

== Core ideas

=== A tensor is a buffer and a recipe

In machine learning, _tensor_ means an array with any number of dimensions: a scalar has none, a vector one, a matrix two, a batch of colour images four. Whatever its dimensions, the numbers live in one flat block of memory. What makes the block a tensor is a small recipe kept beside it: a _shape_, the length of each dimension; a _data type_, such as `float32`; and _strides_, the number of bytes to step in memory to move one place along each dimension. Element $(i_0, i_1, dots, i_(k-1))$ lives at

$ "offset" = sum_(d=0)^(k-1) i_d s_d $

bytes from the start of the buffer, where $s_d$ is the stride of dimension $d$. A $3 times 4$ array of `float32` stored row by row has strides $(16, 4)$: the next column is four bytes on, the next row sixteen. That order, last index fastest, is _row-major_ or _C order_, NumPy's and PyTorch's default; such an array is _contiguous_.

Because the recipe and the buffer are separate, many operations change only the recipe. A transpose swaps the strides; a slice moves the start and multiplies a stride; a reshape of a contiguous array computes new strides. None copies a byte. The results are _views_: new tensors that share the original memory.

#snippet("u1/strides.py", "views", caption: [Six tensors described by their recipes])

#console-part("/src/console/u1-strides.txt", to: 7, caption: [Five views and one copy])

The last line is the exception. The transpose is not contiguous, so no choice of strides can read it as a flat run of twelve numbers in its new order, and `reshape` has to copy. NumPy copies silently; PyTorch's `view` refuses and its `reshape` copies. Knowing which operations copy matters for speed and, as the next lab shows, for correctness: writing through a view changes the original.

Strides can be stranger than any reshape produces. A stride may be zero, which repeats one element along a dimension, and two dimensions may overlap. `as_strided` builds such views directly, here eight overlapping windows of three over a signal of ten:

#snippet("u1/strides.py", "windows", caption: [Sliding windows without a copy: both dimensions step by one float])

Broadcasting, below, uses zero strides internally, and convolution libraries use overlapping windows like these to turn a convolution into a matrix multiplication.

=== Layout decides speed

Memory is fast to read in order and slow to read at random. A processor fetches memory in _cache lines_ of 64 or 128 bytes and keeps recently used lines in caches close to the arithmetic units; reading the rest of a line it has fetched costs almost nothing, while reading one float from each of many distant lines costs a full trip to memory for each. The same rule holds on a GPU, as Unit 4 shows. The program copies a $8192 times 8192$ array twice: once in memory order, and once through its transpose, so that the reads walk down columns.

#snippet("u1/strides.py", "cost", caption: [The same copy in two orders])

#console-part("/src/console/u1-strides.txt", from: -2, command: false, caption: [Copying in memory order and across it on the M2 Pro])

Both copies read 256 MiB and write 256 MiB; one does it nearly forty times faster. Nothing in the arithmetic differs. This is the first instance of a theme of the whole course: _the cost of an operation is usually the cost of moving its data_.

=== Broadcasting

Arithmetic on two tensors of different shapes is defined by _broadcasting_. Align the shapes at the right; along each dimension the sizes must be equal, or one of them must be 1, and a missing dimension counts as 1; a dimension of size 1 is stretched, with stride zero, to match the other. The result has the larger size in every dimension.

#snippet("u1/broadcast.py", "rule", caption: [The broadcasting rule, dimension by dimension from the right])

#console-part("/src/console/u1-broadcast.txt", to: 7, caption: [The rule against `np.broadcast_shapes`])

Broadcasting replaces loops with whole-array expressions, which run in compiled code. It can also hide a large cost. Consider the table of squared distances between 1,000 points and 1,000 others, in 64 dimensions, which nearest-neighbour search and several later chapters need. Three versions:

#snippet("u1/broadcast.py", "distances", caption: [Squared distances by loops, by broadcasting, and by expanding the square])

The broadcast version builds `x[:, None, :] - y[None, :, :]`, a tensor of shape $(1000, 1000, 64)$, before summing it away. The third uses the identity

$ norm(x - y)^2 = norm(x)^2 + norm(y)^2 - 2 x dot y, $

which turns the whole table into one matrix multiplication and two small sums.

#console-part("/src/console/u1-broadcast.txt", from: 7, command: false, caption: [The three versions on the M2 Pro])

The loops spend their time in the Python interpreter; the broadcast version spends it creating and reading a 244 MiB temporary; the matrix multiplication does the same arithmetic as the broadcast version with almost no traffic. Expanding the square has one cost of its own: when $x$ and $y$ are close and large, the subtraction cancels, and the result can come out slightly negative. Code that takes a square root of it clamps it at zero first.

#hazard(title: [Pitfall])[
  Broadcasting never fails silently in shape, but it can succeed with a shape you did not intend. Subtracting a vector of shape `(n,)` from a column of shape `(n, 1)` gives an $n times n$ matrix, not $n$ differences. When a loss or a metric comes out with an unexpected value, print the shapes of every intermediate first.
]

=== Counting the cost

Two numbers describe the cost of an operation: the floating-point operations it performs, its _FLOPs_, counting a multiplication and an addition as two; and the bytes it must move between memory and the processor. Their ratio is the operation's _arithmetic intensity_, in FLOPs per byte.

Multiplying an $n times k$ matrix by a $k times m$ matrix computes $n m$ dot products of length $k$: $2 n k m$ FLOPs. It must at least read both inputs and write the output, $4(n k + k m + n m)$ bytes in `float32`. For square matrices that is $2n^3$ FLOPs over $12 n^2$ bytes, an intensity of $n / 6$: it grows with the matrix. Adding two vectors of length $n$ performs $n$ FLOPs and moves $12 n$ bytes, an intensity of $1 / 12$, whatever $n$.

Every processor has a peak rate of arithmetic and a peak rate of memory traffic. An operation whose intensity is below the ratio of the two is limited by memory, and an operation above it by arithmetic. Large matrix multiplications are among the few operations in machine learning that can keep a processor's arithmetic busy, which is why models are built from them, and why so much engineering goes into making everything else look like one. Unit 4 makes this picture, the _roofline_, precise.

=== From loops to the machine's peak

The program multiplies square matrices four ways and checks every result against a float64 reference:

#snippet("u1/matmul.py", "loops", caption: [The definition, in Python])

#snippet("u1/matmul.py", "outer", caption: [The same product as a sum of $k$ outer products, each a whole-array NumPy operation])

The outer-product version runs its arithmetic in compiled code, but each of its $k$ steps reads and writes the whole $n times n$ output, so its intensity is about $1 / 4$, whatever $n$. The third is NumPy's `a @ b`, which calls a BLAS library: on macOS, Apple's Accelerate, which on Apple Silicon uses the CPU's matrix coprocessor. The fourth runs the product on the GPU through PyTorch.

#console(read("/src/console/u1-matmul.txt"), caption: [Four matrix multiplications on the M2 Pro])

#fig("u1-matmul", caption: [Speed of the four methods against matrix size, on a logarithmic scale.]) <fig-matmul>

The spread is enormous (@fig-matmul). Python loops manage about a tenth of a GFLOP/s, because each multiply-add costs dozens of interpreted instructions. The outer products reach a few GFLOP/s, held down by memory traffic exactly as their intensity predicts. BLAS passes a trillion FLOPs per second once $n$ is a few hundred, from the CPU's matrix units, by _blocking_: it splits the matrices into tiles small enough to stay in cache, so each number fetched from memory is used many times. The GPU is slower than the CPU for small matrices, because sending it work and waiting for the result costs about half a millisecond here, and fastest for large ones, at over 5 TFLOP/s. Every one of these lessons reappears with neural networks: small models are dominated by overheads, large ones by arithmetic, and between them by memory.

#keyidea[
  Before asking how to make an operation faster, count its FLOPs and its bytes. An operation that moves many bytes per FLOP can only be made faster by moving fewer bytes; one that performs many FLOPs per byte is limited by arithmetic, and the best available library is usually already close to the limit.
]

#inpytorch[
  A `torch.Tensor` is the same recipe over a buffer, with one addition, the device the buffer lives on. `x.stride()` reports strides in elements rather than bytes, `x.is_contiguous()` and `x.contiguous()` behave as in NumPy, and `x.view(shape)` reshapes only when no copy is needed, raising an error otherwise. `torch.from_numpy(a)` shares `a`'s memory; `x.to("mps")` copies to the GPU. Broadcasting follows the same rule.
]

#reading(
  [The NumPy documentation, "The N-dimensional array (ndarray)" and "Broadcasting".],
  [Ulrich Drepper, "What Every Programmer Should Know About Memory", 2007, sections 3 and 6: caches, and how to write code that uses them.],
  [Kazushige Goto and Robert van de Geijn, "Anatomy of High-Performance Matrix Multiplication", _ACM Transactions on Mathematical Software_ 34(3), 2008.],
)

== Labs

#lab([Strides by hand], goal: [Predict views before NumPy shows them, and see a view's writes reach the original.], time: [1 hour], code: "code/u1/strides.py")[
  + For a `float32` array of shape `(2, 3, 4)`, write down the strides of `a`, `a.transpose(2, 0, 1)`, `a[:, ::2, 1:]`, `a[..., None]` and `a.reshape(6, 4)`, then check them in Python.
  + Write `offset(index, strides)` and use it, with `np.frombuffer`, to read three elements of a transposed view straight from the original buffer.
  + Set every element of `a[:, ::2]` to zero and print `a`. Then do the same through `a.T.reshape(-1)` and explain the difference.
  #done-when(
    [All five predictions match NumPy, or you can explain each one that did not.],
    [Your `offset` reads the right elements, and you can say which of the two writes changed `a` and why.],
  )
  #evidence([The predictions, the code and the printed arrays.])
]

#lab([Broadcasting drills], goal: [Write common operations as single broadcast expressions.], time: [1 hour], code: "code/u1/broadcast.py")[
  + Without loops, compute: the outer product of two vectors; every row of a matrix minus its row mean; a batch of 32 vectors each multiplied by its own $8 times 8$ matrix; and a mask of shape $(n, n)$ that is true above the diagonal.
  + Check each against a loop version on random inputs.
  + Find one case in which broadcasting produces a result of the wrong shape without an error, and write the assertion that would have caught it.
  #done-when(
    [Each expression matches its loop version.],
    [Your silent-shape example and its assertion are in the notebook.],
  )
  #evidence([The four expressions with their checks, and the example.])
]

#lab([What a temporary costs], goal: [Measure the memory and time of the three distance computations as the problem grows.], time: [1 hour], code: "code/u1/broadcast.py")[
  + Time the broadcast and matrix-multiplication versions for 1,000, 2,000 and 4,000 points in 64 dimensions, watching memory use in Activity Monitor or `top`.
  + Find the size at which the broadcast version no longer fits comfortably in your machine's memory.
  + Construct two nearby points with large coordinates for which the expanded square comes out negative, and fix the function.
  #done-when(
    [You have both timings at three sizes and the size at which broadcasting runs out of memory.],
    [Your fixed function never returns a negative distance.],
  )
  #evidence([A table of times and peak memory, and the fix.])
]

#lab([Your machine's ladder], goal: [Measure the four multiplications on your own machine and explain each with FLOPs and bytes.], time: [1.5 hours], code: "code/u1/matmul.py")[
  + Run `uv run -m u1.matmul` with the default sizes, and once more with `--sizes 32 64 96`.
  + For each method at $n = 512$, compute its arithmetic intensity and say whether memory or arithmetic limits it.
  + Find your CPU's and GPU's published peaks and express the best measured speed of each as a fraction of them.
  #done-when(
    [Your table has every method at every size it runs at.],
    [For each method you can say what limits it, from its intensity and your measurements.],
  )
  #evidence([The table, a plot of it, and a paragraph per method.])
]

#problems(
  [A `float32` tensor of shape $(32, 3, 224, 224)$ is stored contiguously. What are its strides in bytes, and at what offset is element $(5, 2, 10, 20)$?],
  [Which of `a[1:, :]`, `a[:, 1:]` and `a[::-1]` of a contiguous $4 times 4$ array is contiguous? Can a stride be negative?],
  [Broadcasting `x` of shape $(n, 1)$ against `y` of shape $(m,)$ gives an $n times m$ result. Write the stride NumPy uses internally to read `y` along the first dimension.],
  [Count the FLOPs and minimum bytes for the product of a $4096 times 4096$ matrix with a vector. Is it limited by memory or by arithmetic on a processor with 200 GB/s and 6 TFLOP/s?],
  [The outer-product matmul reaches about 7 GFLOP/s. Using its intensity of $1 / 4$ FLOP per byte, what memory bandwidth does that imply, and how does it compare with the 88 GB/s copy measured in this chapter?],
)

#checklist(
  [I can explain shape, strides and contiguity, and say whether an operation returns a view or a copy.],
  [I can apply the broadcasting rule by hand and spot a broadcast that gives the wrong shape.],
  [I can count the FLOPs and bytes of an operation and say what limits it.],
  [I can explain why BLAS is fast and when a GPU is slower than a CPU.],
  [Lab 1.1.1–1.1.4 done-when criteria all hold, with evidence filed.],
)
