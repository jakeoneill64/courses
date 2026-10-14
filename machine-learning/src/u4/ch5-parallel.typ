#import "../lib/template.typ": *

= Parallel training <ch-parallel>

#chapter-meta(
  time: [7 hours],
  builds: [A ring all-reduce written with point-to-point messages and checked against the library's; data-parallel training across four processes that matches one-process training; ZeRO's sharded optimiser state; a tensor-parallel feed-forward layer split by columns and rows; a two-stage pipeline with micro-batches; and the communication cost of each, worked out for a model of seven billion parameters.],
  needs: [Chapters 2.4, 4.1 and 4.2.],
)

#why[
  One accelerator cannot train a large model in a useful time: a 7-billion-parameter model's weights, gradients and optimiser state alone need over 100 GB, more than most GPUs hold, and its training run needs more arithmetic than one GPU could do in a year. Every large model is therefore trained across many devices, by combining a few strategies, each a different way of dividing the work and each paid for in communication. This chapter implements all of them across processes on one machine, where the logic is identical to a cluster's and only the speeds differ, so that you can reason about the choices large training runs make.
]

#skip-test(
  rule: [If all four are easy, read the sections on ZeRO and on costs at scale, and do Labs 4.5.3 and 4.5.4.],
  [What does an all-reduce compute, and how many bytes does each of $N$ processes send in a ring all-reduce of $S$ bytes?],
  [How much memory does training a 7-billion-parameter model with Adam need before activations, and what do ZeRO's three stages shard?],
  [How does tensor parallelism split a feed-forward network so that its forward pass needs only one all-reduce?],
  [What fraction of the time are the stages of a pipeline idle with $p$ stages and $m$ micro-batches?],
)

== Core ideas

=== Why and how to divide the work

Chapter 4.2's memory equation gives the minimum. With AdamW in float32, every parameter costs 16 bytes for its weight, gradient and two moments, so 7 billion parameters need 112 GB before a single activation, more than an 80 GB H100 holds. Time is the other limit. Chapter 2.4's rule of 6 FLOPs per parameter per token puts a 7-billion-parameter model trained on two trillion tokens at $8.4 times 10^22$ FLOPs, nearly nine years of one GPU running at 300 TFLOP/s.

There are three basic ways to divide training among devices. _Data parallelism_ gives every device the whole model and a different slice of each batch. _Tensor parallelism_ splits each layer's matrices among devices, which then cooperate on every token. _Pipeline parallelism_ gives each device a contiguous range of layers, and passes activations along. A fourth technique, _sharding_, makes data parallelism store each piece of state on only one device. Large runs combine them, and each needs a different pattern of communication.

=== Collectives

Devices communicate through _collective_ operations in which every process of a group takes part. A _broadcast_ copies one process's tensor to all. A _reduce_ sums all processes' tensors onto one, and an _all-reduce_ leaves the sum on every process. A _reduce-scatter_ leaves each process with the sum of one slice, and an _all-gather_ leaves every process with every process's slice. PyTorch's `torch.distributed` provides them over several backends: NCCL between NVIDIA GPUs, and gloo, used here, between CPU processes. This chapter's programs start four processes on one machine, each with its own copy of PyTorch, connected through the loopback network.

=== The ring all-reduce

The simplest all-reduce sends every tensor to one process, which sums them and sends the result back, so that process sends and receives $N$ times the data while the others idle. A _ring_ does better. Arrange the processes in a ring and split each tensor into $N$ chunks. In $N - 1$ steps of a _reduce-scatter_, each process sends one chunk to its right-hand neighbour and adds the chunk arriving from its left into its own; afterwards each process holds the complete sum of one chunk. In $N - 1$ steps of an _all-gather_, the completed chunks travel round the ring until every process has all of them.

#snippet("u4/parallel.py", "ring", caption: [A ring all-reduce from sends and receives])

Each process sends $2(N - 1) \/ N$ times the tensor's size, which tends to twice the size however many processes there are, and all links are busy all the time. No algorithm can send less, so the ring is optimal in bandwidth. Its weakness is latency: it takes $2(N - 1)$ sequential steps, which tree-shaped algorithms reduce for small tensors.

#console-part("/src/console/u4-parallel.txt", to: 3, caption: [The ring against gloo's all-reduce, four processes])

The ring's sums agree with the library's to within rounding, since the two add the same numbers in different orders, and it runs within a small factor of the library's speed. Gloo's implementation is a carefully tuned version of the same algorithm, with chunks pipelined so that sending one overlaps adding another.

=== Data parallelism

In data-parallel training, each process holds the whole model, computes gradients on its own slice of the batch, and all-reduces them, so every process steps its optimiser with the same averaged gradient. Because the gradient of a mean over a batch is the mean of the gradients over its slices, this is exactly one-process training on the whole batch, as long as the processes start from the same weights.

#snippet("u4/parallel.py", "data-parallel", caption: [Data parallelism: local gradients, one all-reduce, identical steps])

#console-part("/src/console/u4-parallel.txt", from: 3, to: 4, command: false, caption: [Four processes match one])

The parameters after 20 steps differ from one-process training by $3 times 10^(-5)$. The difference is rounding: the processes add the same numbers in a different order, and Adam's division by small second moments enlarges the differences a little. Production systems overlap the all-reduce with the backward pass, sending each layer's gradients as soon as they exist, in _buckets_ of a few megabytes, so that communication hides behind computation.

=== ZeRO: sharding the state

Data parallelism keeps a full copy of the optimiser's state on every process, which wastes memory, since each process needs to update only the parameters it is responsible for. _ZeRO_, the Zero Redundancy Optimizer, removes the redundancy in stages. Stage 1 shards the optimiser's state: after the gradients are summed, each process updates only its slice of the parameters, then all-gathers the updated slices. Stage 2 also shards the gradients, using a reduce-scatter instead of an all-reduce, and stage 3 shards the parameters themselves, gathering each layer's weights just before they are needed and discarding them afterwards.

#snippet("u4/parallel.py", "zero", caption: [ZeRO stage 1: Adam's state for one slice per process])

#console-part("/src/console/u4-parallel.txt", from: 4, to: 5, command: false, caption: [A quarter of the optimiser state per process, the same parameters])

Stage 1 cuts Adam's 8 bytes per parameter by the number of processes at the cost of one all-gather per step. Stage 3 cuts all 16 bytes and moves the parameters across the network on every forward and backward pass. PyTorch's _Fully Sharded Data Parallel_ is stage 3.

=== Tensor parallelism

Data parallelism cannot help when one layer's matrices, or its activations, are too large for a device. _Tensor parallelism_ splits the matrices themselves. In a feed-forward network, split the first layer's weights by output columns: each process computes a slice of the hidden features from the full input, with no communication. Split the second layer's weights by input rows, the same slices: each process multiplies its hidden slice by its rows and produces a partial sum of the full output. One all-reduce adds the partial sums. The SwiGLU network splits the same way, since the gate and the up projection are split identically and their product is element-wise.

#snippet("u4/parallel.py", "tensor-parallel", caption: [A SwiGLU network split by columns and rows across processes])

#console-part("/src/console/u4-parallel.txt", from: 5, to: 6, command: false, caption: [The split layer equals the whole one])

Attention splits the same way, by heads. The cost is an all-reduce of a layer's output in every forward pass and another in every backward pass, for every layer, which only fast links within one machine can sustain. Tensor parallelism is therefore used across the eight GPUs of a server, and rarely beyond.

=== Pipeline parallelism

_Pipeline parallelism_ gives each device a contiguous group of layers. A batch flows through the stages in order, each sending its output activations to the next, so communication is only one activation tensor per stage boundary. The stages are often idle, because while the first stage works on a batch the second waits for it, and vice versa. Splitting each batch into $m$ _micro-batches_ lets the stages work on different micro-batches at the same time. With $p$ stages, the pipeline needs $m + p - 1$ steps to process $m$ micro-batches, of which each stage is busy for $m$, so the idle fraction, the _bubble_, is $(p - 1) \/ (m + p - 1)$.

#snippet("u4/parallel.py", "pipeline", caption: [A two-stage pipeline, forward only, with the batch split into micro-batches])

#console-part("/src/console/u4-parallel.txt", from: 6, command: false, caption: [Two stages on two processes, 64 sequences])

#fig("u4-pipeline", caption: [Time per batch against the number of micro-batches, with the theoretical bubble. Micro-batches fill the pipeline until the overhead of each message and the smaller matrices take over.]) <fig-pipeline>

With one micro-batch the stages take turns, and the pipeline is no faster than one process. Splitting the batch lets them overlap, and the time falls towards half (@fig-pipeline). Beyond a few micro-batches the gains stop, because each micro-batch costs a message and smaller matrix multiplications run less efficiently, the trade-off measured in Chapter 1.1. Real schedules, such as 1F1B, interleave forward and backward passes of different micro-batches to limit the activations held at once, and interleaved variants that give each device several stages also shrink the bubble.

#keyidea[
  Data parallelism divides the batch and communicates gradients once per step, and ZeRO divides the stored state. Tensor parallelism divides the layers' matrices and communicates in every layer. Pipeline parallelism divides the depth and communicates activations, at the cost of a bubble. Large runs combine them, with the most communication-hungry strategy on the fastest links.
]

=== Costs at scale

For a model of $P$ parameters in bf16 on $N$ devices, data parallelism sends about $2 times 2P$ bytes per device per step in its all-reduce. For 7 billion parameters that is 28 GB, about 0.3 seconds on a 100 GB/s link, every step, which is why the all-reduce is overlapped with the backward pass and starts on each layer's gradients as soon as they are ready. Tensor parallelism across $t$ devices sends two all-reduces of each layer's activations per pass, each of $2 B T d$ bytes in bf16, so with the ring's factor of two about $8 B T d$ bytes per device per layer, every layer, every micro-batch. Pipeline parallelism sends one activation tensor per stage boundary per micro-batch. A typical recipe for a model of tens of billions of parameters is tensor parallelism of 8 within each server, pipeline parallelism across a few servers, and data parallelism with ZeRO across the rest, which is called _3D parallelism_.

#inpytorch[
  `torch.nn.parallel.DistributedDataParallel` implements data parallelism with bucketed, overlapped all-reduces, and `torch.distributed.fsdp.FullyShardedDataParallel` implements ZeRO stage 3. Tensor parallelism is expressed with `torch.distributed.tensor`, which describes how each tensor is split across a device mesh, and `torch.distributed.pipelining` provides pipeline schedules. Processes are started with `torchrun`, which sets the environment variables that `init_process_group` reads, as this chapter's program does by hand.
]

#reading(
  [Mohammad Shoeybi and others, "Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism", 2019: tensor parallelism.],
  [Samyam Rajbhandari, Jeff Rasley, Olatunji Ruwase and Yuxiong He, "ZeRO: Memory Optimizations Toward Training Trillion Parameter Models", SC 2020.],
  [Yanping Huang and others, "GPipe: Efficient Training of Giant Neural Networks using Pipeline Parallelism", NeurIPS 2019.],
  [Deepak Narayanan and others, "Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM", SC 2021: combining the strategies.],
  [Pitch Patarasuk and Xin Yuan, "Bandwidth Optimal All-reduce Algorithms for Clusters of Workstations", _Journal of Parallel and Distributed Computing_ 69(2), 2009.],
)

== Labs

#lab([The cost of an all-reduce], goal: [Fit the latency and bandwidth of your all-reduce.], time: [1.5 hours], code: "code/u4/parallel.py")[
  + Time your ring and gloo's all-reduce for tensors from 4 KiB to 64 MiB, with 2, 4 and 8 processes.
  + Fit each to $alpha + beta S$, with $S$ the bytes per process, and compare the fitted $beta$ with the ring's $2(N - 1) \/ N$ factor.
  #done-when(
    [Your plots cover at least six sizes for each process count.],
    [You can say at what size each all-reduce becomes bandwidth-bound, from your fit.],
  )
  #evidence([The plots and the fitted constants.])
]

#lab([Overlapping communication], goal: [Hide the all-reduce behind the backward pass.], time: [2 hours], code: "code/u4/parallel.py")[
  + Register a hook on each parameter that starts an asynchronous all-reduce, `dist.all_reduce(grad, async_op=True)`, as soon as its gradient is ready, and wait for them all before the optimiser step.
  + Measure the step time against the version that all-reduces once at the end, on a model large enough for the difference to show.
  #done-when(
    [The overlapped version gives identical parameters.],
    [You have both step times and can explain the difference, or its absence, on your machine.],
  )
  #evidence([The code and the timings.])
]

#lab([ZeRO stage 2], goal: [Shard the gradients as well.], time: [1.5 hours], code: "code/u4/parallel.py")[
  + Replace the all-reduce in `experiment_zero` with a reduce-scatter, so that each process receives only its slice of the summed gradients.
  + Measure the gradient and optimiser memory per process for 1, 2 and 4 processes.
  #done-when(
    [Parameters still match one-process training to within $10^(-4)$.],
    [Your table shows memory falling in proportion to the number of processes.],
  )
  #evidence([The code and the table.])
]

#lab([Tensor-parallel attention], goal: [Split attention by heads.], time: [2 hours], code: "code/u4/parallel.py")[
  + Split one of Chapter 2.4's attention layers across 2 and 4 processes, each taking whole query heads and the key-value heads they share.
  + Check the output against the whole layer, and count the bytes each process sends per forward pass.
  #done-when(
    [The split layer matches the whole one to within $10^(-5)$.],
    [Your byte count matches the formula for one all-reduce of the layer's output.],
  )
  #evidence([The code, the check and the count.])
]

#problems(
  [Show that a ring all-reduce over $N$ processes sends $2(N - 1) S \/ N$ bytes per process, and that no algorithm can send fewer than $(N - 1) S \/ N$ in each direction.],
  [A 70-billion-parameter model trains with AdamW in mixed precision, keeping float32 master weights. How many bytes of state per parameter? Spread with ZeRO stage 3 over 64 GPUs, how many GB per GPU?],
  [Why can the second layer of a tensor-parallel feed-forward network not be split by columns as well? What would it cost?],
  [With 4 pipeline stages, how many micro-batches keep the bubble below 10%? What does that do to each micro-batch's size for a batch of 512 sequences?],
  [Data parallelism over 1,024 GPUs needs a global batch of at least 1,024 sequences. Why might that harm training, and how do large runs choose the batch size?],
)

#checklist(
  [I can explain the collectives and implement a ring all-reduce.],
  [I can explain data parallelism and show that it matches one-process training.],
  [I can explain ZeRO's three stages and what each saves and costs.],
  [I can split a feed-forward network or attention for tensor parallelism, and compute a pipeline's bubble.],
  [Lab 4.5.1–4.5.4 done-when criteria all hold, with evidence filed.],
)
