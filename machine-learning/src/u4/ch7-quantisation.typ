#import "../lib/template.typ": *

= Quantisation <ch-quantisation>

#chapter-meta(
  time: [6 hours],
  builds: [Weights rounded to 8, 4 and 3 bits in groups of several sizes, with the cost in validation loss measured on the course's model and on SmolLM2; GPTQ, written from its definition, which corrects each column's rounding error using the next columns; a KV cache in 8 bits; and the engine's 8- and 4-bit kernels, checked against PyTorch and timed.],
  needs: [Chapters 4.3 and 4.6.],
)

#why[
  Chapter 4.6 showed that generating text is limited by the bytes of weights read per token. Storing each weight in 8 bits instead of 32 reads a quarter of the bytes, and in 4 bits an eighth. If the model's predictions barely change, that is a large speed-up at almost no cost, and it also lets a model fit in a phone's memory. This chapter measures how far the bits can be cut before the predictions suffer, and how a better rounding method, GPTQ, pushes that limit further.
]

#skip-test(
  rule: [If all four are easy, read the sections on GPTQ and on speed, and do Labs 4.7.2 and 4.7.4.],
  [What is symmetric absmax quantisation to $b$ bits, and what does the scale store?],
  [Why do quantised weights use a scale per group of 32 or 128 values rather than one per tensor?],
  [What does GPTQ do differently from rounding each weight to the nearest level?],
  [Why can 4-bit weights be slower than 8-bit weights on a CPU, despite moving half the bytes?],
)

== Core ideas

=== Rounding weights

_Symmetric absmax_ quantisation maps a group of weights to integers: divide by a scale chosen so that the largest magnitude maps to the largest level, $2^(b - 1) - 1$, round to the nearest integer, and store the integers with the scale. Dequantisation multiplies the integers by the scale. The rounding error of each weight is at most half a step, and the step is the group's largest magnitude divided by $2^(b - 1) - 1$, so a single large weight coarsens the whole group. Scales are therefore kept per group: one per row of a matrix for 8 bits, and one per 32 to 128 consecutive weights for 4 bits. Each scale costs 32 bits, a quarter of a bit per weight with groups of 128.

#snippet("u4/quantise.py", "rtn", caption: [Round-to-nearest quantisation to any width, with a scale per group])

The program quantises every matrix of every block of a model, leaves the embedding and norms alone, and measures the validation loss:

#snippet("u4/quantise.py", "variants", caption: [Five quantisations of the same model])

#console(read("/src/console/u4-quantise.txt"), caption: [The cost of fewer bits on the course's model])

#console(read("/src/console/u4-quantise-smollm2.txt"), caption: [The same on SmolLM2-135M, on TinyStories' validation text])

On the course's model, eight bits with a scale per row cost nothing measurable. Four bits cost one to two hundredths of a nat, less with smaller groups at the price of more scales, and three bits nearly seven hundredths. SmolLM2-135M is far more sensitive. Eight bits cost two thousandths of a nat, four bits from a quarter to over a third of a nat, and three bits more than one and a half, which makes the model unusable. SmolLM2 was trained on over a thousand times as many tokens per parameter, and studies of quantisation across many training runs find that the more data a model has absorbed, the more rounding its weights costs it. The general pattern holds on both models: 8-bit weights are effectively free, 4-bit weights are the usual compromise and need care with well-trained models, and below 4 bits quality falls quickly without better methods.

=== GPTQ

Rounding each weight to its nearest level ignores how weights combine. A layer computes $y = W x$, and what matters is the error in $y$ over the inputs the layer actually sees. GPTQ quantises the columns of $W$ one at a time, and after rounding a column, adjusts the columns not yet quantised to cancel the error it introduced, as far as the inputs allow.

#derivation[
  For a row $w$ of $W$ and inputs $x$ collected from calibration text, the expected squared output error of a change $delta$ is half of $delta^T H delta$, with $H = 2 E[x x^T]$. Quantising coordinate $q$ changes it by $delta_q = "quant"(w_q) - w_q$. The change to the remaining coordinates that minimises the error given that one is $delta_q H^(-1)_(: , q) \/ H^(-1)_(q q)$, the optimal-brain-surgeon update. GPTQ applies it to all rows at once, column by column, using the Cholesky factor of $H^(-1)$ so that the whole update costs about as much as one matrix multiplication per layer.
]

#snippet("u4/quantise.py", "gptq", caption: [GPTQ for one layer: quantise a column, push its error onto the columns that remain])

Each layer's inputs come from running 32 windows of training text through the model, with the layers before it already quantised, so that each layer's correction also compensates for the errors of the layers before it. The GPTQ row of each model's console shows the result. With the same groups of 128 and the same number of bits as plain rounding, GPTQ's loss is closer to float32's: it removes nearly half of the damage of 4 bits on the course's model, and two-thirds on SmolLM2, where there was more to remove.

=== Quantising the KV cache

At long contexts and large batches, Chapter 2.7's KV cache rivals the weights in size. It also quantises well. Storing each key and value vector in 8 bits with its own scale changes the loss by at most a ten-thousandth of a nat on either model.

#snippet("u4/quantise.py", "kv", caption: [Every key and value rounded to 8 bits as it enters the cache])

=== The engine's quantised kernels

Chapter 4.6's engine reads three kinds of weight. 8-bit rows store one byte per weight and a float32 scale per row, and 4-bit groups pack two weights per byte with a float32 scale per 32 weights. The dot products convert the integers to floats in vector registers and multiply as before:

#snippet("engine/ops.cpp", "dot-quantised", caption: [Dot products with 8-bit and 4-bit weights])

The export for each format computes its reference logits with the same rounding, so the engine's check tests its arithmetic exactly:

#console(read("/src/console/u4-engine-quantised.txt"), caption: [The quantised engines against PyTorch running the same rounded weights, and their speed on the M2 Pro's CPU])

With eight threads, 8-bit weights roughly double SmolLM2's speed, in line with the bytes they save. 4-bit weights cut the bytes by a further fifth to a quarter, but their dot product does more work per weight, unpacking two values from each byte and correcting their signs, and on the CPU that work can cost as much as the bytes it saves. Whether 4 bits are faster than 8 depends on whether the kernel is bound by memory or by arithmetic, which depends on the machine and the threads, the trade-off of Chapter 4.1. Production engines use integer dot-product instructions on quantised activations as well, which removes the per-weight conversions.

#keyidea[
  Quantisation reduces the bits per weight at the cost of error in the model's outputs. 8 bits with a scale per row are effectively free. 4 bits with group scales cost a little or a lot, depending on how much the model has learned, and GPTQ recovers much of that cost by correcting each rounding error with the weights that follow. Whether fewer bits run faster depends on whether the kernel was limited by memory or by arithmetic.
]

#inpytorch[
  `torch.ao.quantization` and the `torchao` library provide int8 and int4 weight quantisation for PyTorch models, with fused kernels on supported hardware. In the wider ecosystem, GPTQ and AWQ checkpoints load through Hugging Face's integrations, and `llama.cpp`'s formats, such as Q4_K and Q8_0, are block quantisations of this chapter's kind with refinements.
]

#reading(
  [Elias Frantar, Saleh Ashkboos, Torsten Hoefler and Dan Alistarh, "GPTQ: Accurate Post-Training Quantization for Generative Pre-trained Transformers", ICLR 2023.],
  [Tim Dettmers, Mike Lewis, Younes Belkada and Luke Zettlemoyer, "LLM.int8()", NeurIPS 2022: outliers and mixed-precision decomposition.],
  [Ji Lin and others, "AWQ: Activation-aware Weight Quantization for LLM Compression and Acceleration", MLSys 2024.],
  [Babak Hassibi and David Stork, "Second Order Derivatives for Network Pruning: Optimal Brain Surgeon", NeurIPS 1992: the update GPTQ builds on.],
  [Tanishq Kumar and others, "Scaling Laws for Precision", ICLR 2025: why models trained on more data lose more to quantisation.],
)

== Labs

#lab([The bits curve], goal: [Map loss against bits per weight.], time: [1 hour], code: "code/u4/quantise.py")[
  + Quantise your Chapter 2.5 model with round-to-nearest at 8, 6, 5, 4, 3 and 2 bits, with groups of 32 and of 128.
  + Plot the change in validation loss against bits per weight, including the scales.
  #done-when(
    [Your plot has twelve points.],
    [You can name the cheapest setting whose loss is within 0.01 nats of float32.],
  )
  #evidence([The plot and the choice.])
]

#lab([Outliers], goal: [Find the weights that make quantisation hard.], time: [1.5 hours], code: "code/u4/quantise.py")[
  + For each matrix of SmolLM2-135M, compute the ratio of its largest magnitude to its standard deviation, per row and per group of 128.
  + Quantise the ten matrices with the largest ratios to 4 bits and the rest to 8, and the reverse, and compare the losses.
  #done-when(
    [You have the ratios for every matrix and the two losses.],
    [You can say which layers are most sensitive and give a reason based on the ratios.],
  )
  #evidence([The table of ratios and the comparison.])
]

#lab([GPTQ, examined], goal: [See what GPTQ's corrections do.], time: [1.5 hours], code: "code/u4/quantise.py")[
  + For one layer, compute the output error on calibration inputs after round-to-nearest and after GPTQ, both at 4 bits with groups of 128.
  + Vary the number of calibration windows from 4 to 64 and the damping from 0.001 to 0.1, and record the validation loss.
  #done-when(
    [GPTQ's output error is smaller than rounding's on the calibration inputs, and you have the ratio.],
    [Your table shows how much calibration data GPTQ needs on this model.],
  )
  #evidence([The errors and the table.])
]

#lab([Faster 4-bit kernels], goal: [Make the engine's 4-bit path beat its 8-bit path.], time: [2 hours], code: "code/engine/ops.cpp")[
  + Profile the engine's 4-bit dot product and find its most expensive instructions.
  + Quantise the input vector to 8 bits per group as well, and compute the dot products with integer multiply-accumulate instructions, such as NEON's `vdotq_s32`, converting to float once per group.
  #done-when(
    [Your kernel's logits match the reference within $10^(-2)$; raise the tolerance of `--check` from $10^(-3)$ for this, since the input vector is now rounded too.],
    [Your 4-bit engine generates faster than the 8-bit one on SmolLM2-135M at your best thread count.],
  )
  #evidence([The code, the check and the timings.])
]

#problems(
  [A group of 128 weights has one weight of 2.0 and the rest below 0.1. At 4 bits with absmax scaling, what is the step size, and how many of the small weights round to zero?],
  [Count the bits per weight of 4-bit groups of 32 with a float16 scale per group, and with a float32 scale.],
  [Why does GPTQ quantise layers in order and collect each layer's inputs from the partly quantised model?],
  [The KV cache of a 70B model at 128K tokens is 40 GiB in bfloat16. What is it in 8 bits with a float16 scale per vector of 128?],
  [Explain why quantising weights to 4 bits speeds up decoding one sequence, but barely speeds up training or prefilling a long prompt.],
)

#checklist(
  [I can quantise weights with absmax scaling and explain the role of group size.],
  [I can measure the cost of quantisation in validation loss and choose a format.],
  [I can explain GPTQ's column-by-column error correction.],
  [I can explain when fewer bits per weight make a kernel faster, and when they do not.],
  [Lab 4.7.1–4.7.4 done-when criteria all hold, with evidence filed.],
)
