#import "lib/template.typ": *
#show: course-doc.with(unit: "4", title: "Making It Fast", short: "Making It Fast",
  subtitle: "The machine, profiling, numerics, kernels, parallel training, an inference engine, quantisation and serving",
  chapters: ("The machine", "Profiling and memory", "Numerics", "Kernels", "Parallel training", "An inference engine in C++", "Quantisation", "Serving"))
#contents()

#about-unit(unit: "4",
  intro: [Unit 4 is about speed and size: what limits a model's training and inference, and how the field pushes those limits back. It measures the machine's roofline and places every operation of your transformer on it, profiles a training step and writes down its memory equation, and studies the number formats that make large models possible. It then writes the kernels behind the operations, in Metal or Vulkan, parallelises training across processes, builds an inference engine in C++, quantises models to 8 and 4 bits, and ends with a server that batches requests continuously, pages its KV cache and decodes speculatively.],
  rows: (
    ([4.1], [Your machine's roofline, measured, with every transformer operation placed on it], [5]),
    ([4.2], [A training step profiled, its memory predicted and measured, and checkpointing], [6]),
    ([4.3], [Floating-point formats, overflow and underflow, loss scaling and fp8], [5]),
    ([4.4], [Matrix multiplication, softmax and FlashAttention as GPU kernels, in Metal or Vulkan], [9]),
    ([4.5], [A ring all-reduce, data parallelism, ZeRO, tensor and pipeline parallelism], [7]),
    ([4.6], [An inference engine in C++ with a tokeniser, threads, SIMD and a KV cache], [8]),
    ([4.7], [Int8 and int4 weights, GPTQ, a quantised KV cache, and the engine's quantised paths], [6]),
    ([4.8], [Continuous batching, a paged KV cache, speculative decoding and a streaming server], [6]),
  ),
  before: [Finish Unit 2; Unit 3 helps but is not required. For Chapters 4.6 and 4.7, install a C++20 compiler, CMake and Ninja; for the Vulkan track of Chapter 4.4, the Vulkan SDK.],
  needs: [The machine you have: this unit measures it. Chapter 4.4's Metal track needs an Apple Silicon Mac; its Vulkan track runs on any GPU with a Vulkan 1.3 driver, including Macs through MoltenVK.],
)

#include "u4/ch1-machine.typ"
#include "u4/ch2-profiling.typ"
#include "u4/ch3-numerics.typ"
#include "u4/ch4-kernels.typ"
#include "u4/ch5-parallel.typ"
#include "u4/ch6-engine.typ"
#include "u4/ch7-quantisation.typ"
#include "u4/ch8-serving.typ"

#signoff(unit: "4",
  chapters: ("The machine", "Profiling and memory", "Numerics", "Kernels", "Parallel training", "An inference engine in C++", "Quantisation", "Serving"),
  review: (
    [Place matrix multiplication, attention, a norm and the cross-entropy on your machine's roofline, from your measurements, and say what limits each.],
    [Write down the memory needed to train a 7-billion-parameter model with AdamW in mixed precision, before activations, and say which parallelism you would use to fit it on eight 80 GB GPUs.],
    [Explain FlashAttention's online softmax, and why it reads and writes less memory than materialised attention.],
    [Explain why decoding one token at a time is memory-bound, and how quantisation, batching and speculative decoding each attack that bound.],
    [Describe how continuous batching and a paged KV cache raise a server's throughput, with your Chapter 4.8 measurements.],
  ),
)
