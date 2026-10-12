#import "../lib/template.typ": *

= Profiling and memory <ch-profiling>

#chapter-meta(
  time: [6 hours],
  builds: [A training step of Chapter 2.5's model split into its forward pass, backward pass and optimiser step, and its forward pass split by module; the memory equation for training, with the weights and optimiser state predicted exactly and the activations measured per token; activation checkpointing, measured; and an account of what `torch.compile` gains by fusion.],
  needs: [Chapters 2.5 and 4.1.],
)

#why[
  Optimising without measuring is guessing. Before changing a training run, find where its time goes, which is rarely where intuition puts it, and where its memory goes, which decides what fits at all. This chapter measures both for the model you trained, writes down the memory equation that every large training run is planned with, and examines the two standard trades of time for memory and of memory traffic for time: activation checkpointing and fusion.
]

#skip-test(
  rule: [If all four are easy, read the section on activations and do Labs 4.2.2 and 4.2.4.],
  [Why must GPU work be synchronised before stopping a timer, and what happens if it is not?],
  [How many bytes per parameter does training with AdamW in float32 need before activations, and what are they?],
  [What determines the memory of activations, and how does it grow with batch size and sequence length?],
  [What does activation checkpointing trade, and roughly how much time does it cost?],
)

== Core ideas

=== Timing a training step

A GPU runs work asynchronously: each PyTorch call queues a kernel and returns at once, and the CPU races ahead until it must wait for a result. A timer stopped without waiting measures the queueing, not the work. Synchronising after each phase of a step separates the forward pass, the backward pass and the optimiser step:

#console-part("/src/console/u4-profile.txt", to: 5, caption: [One training step of the Chapter 2.5 model in eager mode, by phase])

One step at 16 sequences takes 842 ms in eager mode. The backward pass takes 2.4 times as long as the forward pass, a little more than the factor of two that its FLOPs predict, since more of its work is in operations less efficient than the forward pass's matrix multiplications. The optimiser's step, which touches each parameter a few times, costs about 1%.

Splitting the forward pass by module needs a timer around each one. Hooks, functions that PyTorch calls before and after a module runs, provide that without changing the model; each synchronises, which adds overhead and stops the GPU overlapping work, so the shares are approximate.

#snippet("u4/profile.py", "hooks", caption: [Timing modules with forward hooks])

#console-part("/src/console/u4-profile.txt", from: 5, to: 12, command: false, caption: [The forward pass by module])

The feed-forward networks hold three-fifths of the parameters and more than half of the forward pass's FLOPs, but take 38% of its time; attention, with its scores and softmax, takes 35%; the output layer, a seventh of the FLOPs in one large, efficient product, takes 7%. The norms, with almost no FLOPs at all, take 18%.

Proper profilers go further: PyTorch's `torch.profiler` records every operation with its time and memory, and on Apple Silicon `torch.mps.profiler` emits signposts that Instruments shows on a timeline with the GPU's own counters.

=== Fusion

The norms take a share of the time far larger than their share of the FLOPs, because they are memory-bound: each reads and writes its tensor, and a chain of them, a norm, a rotation, a SiLU, a multiplication, a residual addition, reads and writes it again and again. `torch.compile` traces the model and generates kernels that perform such chains in one pass, keeping intermediate values in registers. Chapter 2.5 measured its effect on training: about 9,400 tokens per second in eager mode and 18,100 compiled, nearly double, with the matrix multiplications unchanged and everything else fused.

=== The memory equation

Training memory has four parts. The _weights_ and their _gradients_ take 4 bytes each per parameter in float32; AdamW's two _moments_ take 8; together 16 bytes per parameter, fixed for a given model.

#snippet("u4/profile.py", "equation", caption: [Weights, gradients and moments])

The fourth part, the _activations_, holds every intermediate tensor that the backward pass will need, and grows with the number of tokens in the batch. The program measures memory at rest and at the end of a forward pass for three batch sizes:

#console-part("/src/console/u4-profile.txt", from: 12, to: -1, command: false, caption: [Memory at rest, and the activations of a forward pass])

The state at rest is the predicted 424 MiB plus a little that grows with the batch, buffers the allocator keeps from earlier steps. The activations of a forward pass are 502 KiB per token at every batch size: they grow exactly in proportion to the tokens in the batch.

An estimate per token per layer counts what the backward pass needs: the block's input and its normalised version, the queries, keys and values, the attention output and its saved statistics, and in the feed-forward network the gate and up projections and their SiLU and product, each $d_"ff"$ wide. For this model that is about $10 d + 4 d_"ff"$ numbers, about 43 KB per token per layer in float32, plus attention's saved weights where the kernel keeps them, plus the logits, which at 8,192 values per token are large: the total lands near the measured 500 KiB per token. Activations grow linearly with batch and sequence length, and for long sequences any attention implementation that stores its scores adds a term quadratic in length.

=== Activation checkpointing

Activations can be traded for time. _Activation checkpointing_ keeps only each block's input during the forward pass and recomputes the block's internals during the backward pass, when they are needed. Memory falls to roughly one tensor per block; time rises by about one extra forward pass, a third of a training step counted in FLOPs.

#snippet("u4/profile.py", "checkpointing", caption: [Wrapping each block so its internals are recomputed in the backward pass])

#console-part("/src/console/u4-profile.txt", from: -1, command: false, caption: [The same batch with checkpointing])

Checkpointing cuts the activations from 4,017 MiB to 432 MiB, by nine-tenths, and lengthens the step from 845 ms to 1,050 ms, by a quarter: one more forward pass, which on this machine is a quarter of a step rather than a third.

Large training runs choose what to checkpoint selectively, recomputing cheap element-wise operations and keeping the outputs of expensive matrix multiplications, to save most of the memory for a fraction of the time.

#keyidea[
  Measure before optimising: synchronise to time GPU work, and account for memory as fixed state, 16 bytes per parameter with AdamW, plus activations that grow with tokens per batch. Checkpointing trades a quarter to a third more time for most of the activations; fusion trades nothing for less memory traffic.
]

#inpytorch[
  `torch.profiler.profile` records operations, shapes, times and memory, and exports traces for the browser's trace viewer; `torch.mps.profiler.profile` adds Instruments signposts on Apple Silicon. `torch.cuda.max_memory_allocated` reports peak memory on NVIDIA GPUs; on MPS, `torch.mps.current_allocated_memory` and `driver_allocated_memory` report what is held now. `torch.utils.checkpoint.checkpoint` implements checkpointing, and `torch.compile(mode="max-autotune")` searches for faster kernels at the cost of a longer compilation.
]

#reading(
  [Tianqi Chen, Bing Xu, Chiyuan Zhang and Carlos Guestrin, "Training Deep Nets with Sublinear Memory Cost", 2016: activation checkpointing.],
  [Vijay Korthikanti and others, "Reducing Activation Recomputation in Large Transformer Models", MLSys 2023: activation memory per layer, counted, and selective recomputation.],
  [Jason Ansel and others, "PyTorch 2: Faster Machine Learning Through Dynamic Python Bytecode Transformation and Graph Compilation", ASPLOS 2024.],
)

== Labs

#lab([A profile of your own], goal: [Use a real profiler on a training step.], time: [1.5 hours], code: "code/u4/profile.py")[
  + Record three training steps with `torch.profiler` and list the ten operations with the most device or CPU time.
  + On Apple Silicon, also record them with `torch.mps.profiler` and view the timeline in Instruments; elsewhere use your vendor's tool.
  #done-when(
    [Your top-ten list accounts for most of the step's time.],
    [You can find one gap on the timeline where the GPU is idle, and say why.],
  )
  #evidence([The list and an annotated screenshot of the timeline.])
]

#lab([Predict, then measure], goal: [Plan a fine-tuning run's memory before running it.], time: [1.5 hours], code: "code/u4/profile.py")[
  + Predict the peak memory of fine-tuning every weight of SmolLM2-360M with AdamW at batches of about 2,048 tokens, from the memory equation and an activation estimate scaled from this chapter's per-token figure by width and depth.
  + Measure it with `uv run -m u3.lora --full --model HuggingFaceTB/SmolLM2-360M --batch-tokens 2048 --examples 1000`, which prints the largest memory in use that it sampled.
  #done-when(
    [Your prediction is within 20% of the measurement.],
  )
  #evidence([The prediction with its working, and the measurement.])
]

#lab([Selective checkpointing], goal: [Find a better trade than checkpointing everything.], time: [1.5 hours], code: "code/u4/profile.py")[
  + Checkpoint every second block, then only the feed-forward networks, and measure memory and step time for each.
  + Plot step time against activation memory for these and the two extremes.
  #done-when(
    [Your plot has four points.],
    [You can recommend a policy for a run that needs to halve its activation memory.],
  )
  #evidence([The plot and the recommendation.])
]

#lab([The biggest batch], goal: [Find what fits.], time: [1 hour], code: "code/u2/pretrain.py")[
  + Find the largest batch of 512-token sequences with which Chapter 2.5's model trains on your machine, with and without checkpointing.
  + Compare tokens per second at the largest batch and at the default 32.
  #done-when(
    [You have both maximum batches and the throughput at each.],
    [You can explain why the largest batch is or is not the fastest.],
  )
  #evidence([The batches and throughputs.])
]

#problems(
  [Training a 7-billion-parameter model with AdamW in float32 needs how much memory before activations? With bfloat16 weights and gradients but float32 moments and master weights?],
  [Activations are 500 KiB per token for an 8-layer model of width 512. Estimate them for a 32-layer model of width 4,096 with the same structure, and for a batch of one million tokens.],
  [Why does checkpointing cost about a third of a training step rather than half or all of it?],
  [A hook that synchronises the device after every module makes the measured total larger than the unhooked forward pass. Why?],
  [Why does fusing element-wise operations save time on the M2 Pro but not FLOPs?],
)

#checklist(
  [I can time GPU work correctly and break a step down by phase and by module.],
  [I can write the memory equation for training and account for activations.],
  [I can apply activation checkpointing and measure its trade.],
  [I can explain fusion and what `torch.compile` gains.],
  [Lab 4.2.1–4.2.4 done-when criteria all hold, with evidence filed.],
)
