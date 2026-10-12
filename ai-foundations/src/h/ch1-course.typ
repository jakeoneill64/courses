#import "../lib/template.typ": *

= The course <h-course>

AI Foundations teaches modern machine learning from first principles, to programmers who know Python well and have never trained a model. It starts with arrays of numbers and the cost of arithmetic on them, builds an automatic differentiation engine, and uses it to derive and train the networks that the rest of the field is built from. It then builds a language model from an empty file, pretrains it, studies how its loss scales and what it learns inside, turns an open-weight model into an assistant by the methods the large laboratories use, and finally makes all of it fast, down to GPU kernels and an inference engine in C++.

The course is practical, and it is honest about what it shows. Every chapter has labs with measurable done-when criteria. Every listing in these volumes is taken from companion code that runs and checks its own results, usually against PyTorch or against a calculation done another way, and every console listing and plot is real output from those programs. All of it was run on an Apple M2 Pro with 32 GB of memory, and the text says wherever other hardware behaves differently. Nothing is trained on a rented cluster; the largest run takes just under five hours on that laptop.

== What you will have built

- *A deep-learning library of your own.* `tiny`, an automatic differentiation engine and tensor library of about 650 lines, checked operation by operation against central differences and against PyTorch to the last bit, with the optimisers in common use and networks trained on MNIST.
- *The classic results, reproduced.* Initialisation measured through thirty layers, overfitting cured four ways, double descent, a 30-layer network made trainable by normalisation and residual connections, a convolutional network on CIFAR-10, and an encoder trained by contrastive learning.
- *A language model from an empty file.* A byte-level tokeniser that encodes text exactly as SmolLM2's does; a transformer with rotary embeddings, grouped-query attention and SwiGLU; a 28-million-parameter model pretrained on 300 million tokens of children's stories; scaling laws that predict a run's loss before it is trained; every decoding strategy in use; and the induction heads inside your model, found and switched off.
- *An assistant.* SmolLM2's open weights loaded into your own model and matched to the reference implementation; supervised fine-tuning, LoRA, preference optimisation with DPO, and reinforcement learning with GRPO; an evaluation harness with honest confidence intervals; retrieval over a document collection with an HNSW index you wrote; and an agent that calls tools.
- *A fast stack.* Your machine's roofline, a profiled and budgeted training step, the numerics of low precision, matrix multiplication, softmax and FlashAttention written as GPU kernels in Metal or Vulkan, data, tensor and pipeline parallelism, an inference engine in C++, 8- and 4-bit quantisation, and a server with continuous batching, a paged KV cache and speculative decoding.

== Four units

#tbl(columns: (auto, 1fr, auto), header: ([Unit], [Chapters], [Hours]), align: (left, left, right),
  [*1* Learning Machines], [Tensors and what they cost; gradients by machine; models as probability; optimisers; neural networks; generalisation; training deep networks; representations], [46],
  [*2* Language Models], [Tokenisation; next-token prediction; attention; the transformer; pretraining; scaling laws; decoding; inside the model], [50],
  [*3* From Base Model to Assistant], [Open weights; supervised fine-tuning; LoRA; preferences; reinforcement learning with verifiable rewards; evaluation; retrieval; tools and agents], [52],
  [*4* Making It Fast], [The machine; profiling and memory; numerics; kernels; parallel training; an inference engine in C++; quantisation; serving], [52],
)

The hours are study time: reading, labs, problem sets and the checklist. The whole course is about 200 hours; at ten hours a week it takes about five months. Training runs add machine time on top, most of it unattended; Part 4 lists it chapter by chapter. Hours are a guide; done-when criteria are the contract.

#fig("h-map", caption: [The course map. Each unit builds on the units before it, and the transformer and sampler of Unit 2 run through Units 3 and 4. Arrows mark other code that a later chapter reuses: `tiny`, the tokeniser and the transformer, and the 4-bit weights and evaluation of Unit 3.]) <fig-map>

== Four threads

Four threads run through the units, and most chapters advance more than one.

- *Build it, then use the library.* Each idea is implemented from scratch before its library version is used: `tiny` before PyTorch's autograd (Chapter 1.2), optimisers before `torch.optim` (1.4), attention in NumPy before PyTorch's kernel (2.3), a tokeniser before Hugging Face's (2.1), LoRA, DPO and GRPO before any training library (Unit 3), FlashAttention before the vendor's (4.4). Each is checked against the library it replaces.
- *Probability.* Losses as likelihoods (1.3), language modelling as compression (2.2), sampling as a design choice (2.7), preferences as a probabilistic model (3.4), and evaluation as statistics (3.6).
- *Scale.* The cost of arithmetic (1.1), what the GPU is good at (1.5), throughput in tokens per second (2.5), scaling laws (2.6), the KV cache's memory (2.7), and all of Unit 4.
- *Measurement.* Every claim has a number behind it, and every number has a run behind it that you can repeat: gradient checks, learning curves, validation losses, win rates with confidence intervals, roofline placements and latency distributions.

== Who the course is for

The course assumes that you program fluently in Python: functions, classes, comprehensions, the standard library, a virtual environment and a terminal. It uses NumPy from the first chapter and introduces PyTorch as it goes. Chapters 4.6 and 4.7 and the Vulkan track of Chapter 4.4 are in C++, at the level of a programmer who has written a few thousand lines of it; the rest of the course needs none.

It assumes school mathematics: algebra, functions and graphs, logarithms and exponentials, and derivatives of simple functions. Part 3 of this Handbook summarises the linear algebra, calculus and probability the course uses, and says where each first appears. It assumes no knowledge of machine learning at all. Readers who have trained networks before will move faster through Unit 1, and should use the skip tests at the start of each chapter to decide what to skim.

== The volumes and the code

The course is five volumes: this Handbook and four units. The companion code is a single Python project, managed with `uv`, with one package per unit, `u1` to `u4`, and a helper package, `aif`, that the units build up and share: the data downloads, `tiny`, the tokeniser, the transformer, the training loop and the evaluation harness. The C++ inference engine and the Vulkan kernels live beside it in `engine` and `kernels`. It arrives as an archive beside the volumes; Part 5 explains how to set it up.

== Conventions

- *Versions.* The code uses Python 3.12 and PyTorch 2.14. Every model and dataset is pinned to an exact revision on the Hugging Face Hub, so that every number in these volumes can be reproduced from the same bytes.
- *Spelling.* British spelling in prose, library names verbatim: normalisation in the text, `LayerNorm` in code.
- *Numbering.* Chapters are numbered unit.chapter, so Chapter 3.2 is the second chapter of Unit 3. Labs are numbered unit.chapter.lab, and figures and tables unit.chapter.number.
- *Listings.* Each listing names the file it comes from, relative to the code folder, and shows a region marked in that file. Console listings begin with the command that produced them, run from the code folder. Long lines are wrapped to fit the page.
- *Units of measurement.* Losses are in nats unless stated otherwise; Chapter 1.3 explains nats, bits and perplexity. FLOPs count a multiplication and an addition as two. Time is in hours for study and in seconds for runs.
- *Platform.* "The M2 Pro" is the Apple M2 Pro, with 32 GB of memory, on which this course's code was run, using PyTorch's Metal backend, MPS. Commands assume a POSIX shell; on Windows, use WSL or the equivalent in PowerShell.
