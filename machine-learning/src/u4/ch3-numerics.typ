#import "../lib/template.typ": *

= Numerics <ch-numerics>

#chapter-meta(
  time: [5 hours],
  builds: [A table of the floating-point formats of machine learning, from float32 to fp8; sums that stall, exponentials that overflow and gradients that underflow, each demonstrated and fixed; the error of a matrix product in each format, measured; and the speed of each on your GPU.],
  needs: [Chapters 1.3, 4.1 and 4.2.],
)

#why[
  Every number in a model is approximate, and the format it is stored in sets how approximate. Fewer bits per number mean less memory, less traffic and, on hardware built for them, faster arithmetic, which is why large models train in 16 bits and increasingly in 8. They also mean less range and less precision, and the failures are silent: a sum that stops growing, a norm that becomes infinity, a gradient that becomes zero. This chapter shows each failure on purpose, so that you can recognise it, and the standard remedies, so that you can use low precision safely.
]

#skip-test(
  rule: [If all four are easy, read the sections on accumulation and on fp8, and do Labs 4.3.3 and 4.3.4.],
  [How many bits of exponent and mantissa do float16 and bfloat16 have, and what does each trade for the other?],
  [Why does adding 0.0001 to a float16 running total eventually stop changing it?],
  [What is loss scaling, and why does float16 training need it while bfloat16 training does not?],
  [Why are fp8 numbers always used with a scale factor?],
)

== Core ideas

=== Floating-point formats

A floating-point number stores a sign, an _exponent_ that sets its magnitude as a power of two, and a _mantissa_ of significant bits. The exponent's width sets the _range_, the largest and smallest representable magnitudes; the mantissa's sets the _precision_, the spacing between neighbouring numbers relative to their size, measured by _machine epsilon_, the gap between 1 and the next larger number.

#snippet("u4/numerics.py", "formats", caption: [The formats, from PyTorch's description of each])

#console-part("/src/console/u4-numerics.txt", to: 7, caption: [Five formats of machine learning])

float32, with 23 mantissa bits, gives about seven significant decimal digits and a huge range. float16 keeps 10 mantissa bits, about three digits, but only five exponent bits: nothing above 65,504 and nothing normal below $6 times 10^(-5)$. bfloat16 ("brain float") makes the opposite trade: float32's eight exponent bits, so float32's range, and only seven mantissa bits, about two digits. The two fp8 formats go further still: e4m3 keeps three mantissa bits and a range up to 448, e5m2 two bits and a wider range. Halving the bits halves the memory and the memory traffic of every tensor stored that way, which for the memory-bound operations of Chapter 4.1 halves their time.

=== Accumulation

Addition loses whatever part of the smaller number falls below the larger number's last mantissa bit. A running sum grows, its spacing grows with it, and eventually each new term is smaller than half the spacing and is lost:

#snippet("u4/numerics.py", "summation", caption: [A running total in each format, and the same values summed into float32])

#console-part("/src/console/u4-numerics.txt", from: 7, to: 11, command: false, caption: [Low-precision totals stall; a float32 accumulator does not])

In float16 the total stops at 0.25, where the spacing between neighbouring numbers is $2^(-12) approx 0.00024$ and 0.0001 is less than half of it; in bfloat16, with three fewer mantissa bits, it stops at 0.03. Even float32 drifts by six thousandths over 100,000 additions. Summed into a float32 accumulator, as PyTorch does internally for `sum`, the 16-bit values give nearly the right answer. The general rule is to _store_ values in low precision and _accumulate_ them in high precision, and matrix multiplication hardware follows it, multiplying 16-bit inputs and accumulating in 32 bits.

=== Range: overflow and underflow

float16's small range causes two failures. Large values overflow to infinity:

#snippet("u4/numerics.py", "overflow", caption: [An exponential and a mean of squares, too large for float16])

#console-part("/src/console/u4-numerics.txt", from: 11, to: 13, command: false, caption: [Infinity from values that are not large])

Activations of a few hundred are common in a large model, but their squares exceed 65,504, so a norm computed in float16 divides by infinity. This is why Chapter 2.4's RMSNorm, and softmax and loss computations generally, run in float32 whatever the model's precision. Small values underflow to zero. The gradient of a loss averaged over a large batch, flowing back through many layers, is often below float16's smallest normal number.

#snippet("u4/numerics.py", "underflow", caption: [Small gradients in float16, with and without a scale])

#console-part("/src/console/u4-numerics.txt", from: 13, to: 15, command: false, caption: [Scaling by 1,024 rescues the gradients that float16 would lose])

_Loss scaling_ multiplies the loss by a large factor before the backward pass, so that every gradient is multiplied by it too and stays within float16's range, and divides the gradients by the same factor, in float32, before the optimiser step. PyTorch's `GradScaler` chooses the factor dynamically: it doubles it after every 2,000 steps without an overflow, and halves it and skips the step whenever a gradient overflows to infinity. bfloat16, with float32's range, needs none of this, which is why it has become the default for training.

=== Precision of a matrix product

#console-part("/src/console/u4-numerics.txt", from: 15, to: 20, command: false, caption: [Relative error of a 512 × 512 product in each format, against float64])

Rounding the inputs to fewer bits makes each product slightly wrong, and the errors of a sum of 512 products partly cancel. float16's product is wrong by a few parts in ten thousand, bfloat16's by a few parts in a thousand, eight times more, matching its three fewer mantissa bits. For training either is enough, because the noise of stochastic gradients is far larger. For fp8, with three mantissa bits, the error reaches a few per cent, and fp8 is usable only with care.

=== fp8 and scaling

fp8 e4m3's largest number is 448 and its smallest normal number $1.6 times 10^(-2)$, a range of about $2^(15)$. Most tensors' values span more than that, or sit outside it, so fp8 is always used with a _scale_: each tensor, or each block of one, is divided by a factor that maps its largest value to the format's largest, stored with the factor, and multiplied back after the arithmetic.

#snippet("u4/numerics.py", "fp8", caption: [An fp8 matrix product with per-tensor scales, accumulated in float32])

Hardware with fp8 arithmetic, NVIDIA's from the Hopper generation on, doubles its throughput again over 16-bit formats. The largest recent training runs use fp8 for most of their matrix multiplications, with per-block scales and a careful choice of which operations stay in higher precision. Chapter 4.7 applies the same idea of a scaled low-precision format to model weights, where it is called quantisation.

=== Speed of each format

#console-part("/src/console/u4-numerics.txt", from: 20, command: false, caption: [A 4096 × 4096 product in each format on the M2 Pro's GPU])

On GPUs with tensor cores, 16-bit products run several times faster than float32. The M2 Pro's GPU has no separate matrix units for 16-bit formats, and its float16 products run at about float32's speed. bfloat16 runs at half that speed because on the M2 generation of Apple's GPUs each bfloat16 operation is computed in float32, with conversions on the way in and out. That is why Chapter 2.5 measured float16 autocast as only 5% faster than float32 for the whole training step, and bfloat16 as a third slower. It is also why this course trains in float32 on the M2 Pro, where 5% does not repay loss scaling and the risk of overflow. On a recent NVIDIA GPU the same code would run several times faster in bfloat16, so formats must be compared on the machine at hand.

#keyidea[
  Choose formats by range and precision: bfloat16 for training, since it has float32's range and its imprecision averages out; float16 only with loss scaling; float32 for norms, softmax, losses and every accumulator; fp8 only with scales. Then measure, because whether fewer bits are faster depends on the hardware.
]

#inpytorch[
  `torch.autocast(device_type, dtype=torch.bfloat16)` runs matrix multiplications and convolutions in the lower precision and keeps norms, softmax and losses in float32, without changing the model's float32 master weights. `torch.amp.GradScaler` implements dynamic loss scaling for float16. `torch.finfo(dtype)` describes any format, and `torch.float8_e4m3fn` and `torch.float8_e5m2` exist as storage types, with fused fp8 matrix multiplication on supported GPUs through `torch._scaled_mm`.
]

#reading(
  [David Goldberg, "What Every Computer Scientist Should Know About Floating-Point Arithmetic", _ACM Computing Surveys_ 23(1), 1991.],
  [Paulius Micikevicius and others, "Mixed Precision Training", ICLR 2018: loss scaling and float32 master weights.],
  [Dhiraj Kalamkar and others, "A Study of BFLOAT16 for Deep Learning Training", 2019.],
  [Paulius Micikevicius and others, "FP8 Formats for Deep Learning", 2022.],
)

== Labs

#lab([Where a sum stalls], goal: [Predict and measure the stall of a running sum.], time: [1 hour], code: "code/u4/numerics.py")[
  + From each format's mantissa width, predict the total at which adding 0.0001 stops changing it, and the totals for 0.001 and 0.01.
  + Measure all nine and compare. Then implement Kahan's compensated summation in float16 and measure its result.
  #done-when(
    [Your nine predictions agree with the measurements to within a factor of two.],
    [Your Kahan sum in float16 reaches 10 to within 1%.],
  )
  #evidence([The predictions, the measurements and the code.])
]

#lab([Training in float16], goal: [See loss scaling at work.], time: [1.5 hours], code: "code/u2/pretrain.py")[
  + Train the `tiny` preset for 20 million tokens three ways: float32; float16 autocast with `GradScaler`; and float16 autocast with the scaler disabled.
  + Log the scaler's scale factor and count the skipped steps.
  #done-when(
    [You have three loss curves and the scale factor's history.],
    [You can explain the difference between the scaled and unscaled float16 runs from the gradients' magnitudes.],
  )
  #evidence([The curves and the explanation.])
]

#lab([Norms in low precision], goal: [Find where float16 breaks a transformer.], time: [1.5 hours], code: "code/aif/gpt.py")[
  + Change `RMSNorm` to compute in the input's precision instead of float32, and run Chapter 2.5's model in float16 on validation text.
  + Find the first layer whose activations produce infinities, and the activation size that caused them.
  #done-when(
    [You can name the layer and the value that overflowed.],
    [Restoring the float32 computation removes the infinities.],
  )
  #evidence([The trace and the fix.])
]

#lab([fp8 with finer scales], goal: [Measure how scale granularity affects fp8's error.], time: [1 hour], code: "code/u4/numerics.py")[
  + Repeat the fp8 product with one scale per tensor, per row, and per block of 32 values along the inner dimension.
  + Repeat with inputs drawn from a heavy-tailed distribution, such as a Student t with three degrees of freedom.
  #done-when(
    [Your table has six relative errors.],
    [You can explain why finer scales matter more for heavy-tailed values.],
  )
  #evidence([The table and the explanation.])
]

#problems(
  [How many decimal digits does a mantissa of 10 bits give? Of 7? Of 3?],
  [A float16 running sum adds terms of size 1. At what total does it stop growing? A bfloat16 one?],
  [Loss scaling multiplies the loss by $2^(16)$. A gradient's true value is $10^(-9)$. Is it representable after scaling in float16? What happens to a gradient of $10$?],
  [Why does mixed-precision training keep a float32 copy of the weights, when it computes in 16 bits? What would go wrong updating 16-bit weights directly with a learning rate of $10^(-5)$?],
  [An fp8 e4m3 tensor's values range from $10^(-3)$ to $10^3$. Can one scale represent both ends? What would you do?],
)

#checklist(
  [I can describe float32, float16, bfloat16 and fp8 by range and precision.],
  [I can explain why accumulators stay in float32, and why norms and softmax do too.],
  [I can explain loss scaling and when it is needed.],
  [I can measure whether a format is faster on my hardware, and explain the result.],
  [Lab 4.3.1–4.3.4 done-when criteria all hold, with evidence filed.],
)
