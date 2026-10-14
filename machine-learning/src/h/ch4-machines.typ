#import "../lib/template.typ": *

= Machines for machine learning <h-machines>

The course runs on one computer. This part says what matters about a machine for machine learning, what the reference machine is, what other machines can do, and how long each chapter's programs take, so that you can plan the long runs.

== What matters

Three properties of a machine decide what it can train and how fast, and Chapter 4.1 measures them.

- *Memory capacity* decides what fits. Training with AdamW in float32 needs 16 bytes per parameter before activations, Chapter 4.2's memory equation: about 0.5 GB for the course's 28-million-parameter model and 5.8 GB for full fine-tuning of SmolLM2-360M, with activations on top. Apple Silicon shares one pool of _unified memory_ between the CPU and the GPU, so a Mac with 32 GB can give most of it to the GPU. An NVIDIA GPU has its own memory, typically 8 to 24 GB on a desktop card.
- *Memory bandwidth* decides the speed of everything that does little arithmetic per byte: normalisations, element-wise operations and, most of all, generating text one token at a time, which reads every weight once per token.
- *Arithmetic throughput* decides the speed of large matrix multiplications, and so of training. NVIDIA GPUs have _tensor cores_ that run 16-bit products many times faster than float32. Apple's GPUs before the M5 generation have no such units, which is one reason the course trains in float32 on the M2 Pro.

The software also affects what runs and how fast. PyTorch's CUDA backend, for NVIDIA GPUs, is the most mature. Its Metal backend, MPS, runs everything in this course, but some operations are slower than their CUDA equivalents. An operation that MPS lacks stops the program with an error naming it, and setting `PYTORCH_ENABLE_MPS_FALLBACK=1` runs such operations on the CPU instead.

== The reference machine

Every console listing and measurement in the course comes from a 16-inch MacBook Pro of 2023 with an Apple M2 Pro: 12 CPU cores, 8 for performance and 4 for efficiency, a 19-core GPU and 32 GB of unified memory. Its memory's published bandwidth is 200 GB/s, and its GPU's float32 peak about 6.8 TFLOP/s. Chapter 4.1 measures what programs achieve. PyTorch reaches the GPU through MPS.

The M2 Pro runs everything in this course, although it is small by the standards of the field. A data-centre GPU such as NVIDIA's H100 has about seventeen times its bandwidth and well over a hundred times its 16-bit matrix arithmetic. The course's techniques are the same at both scales, and Unit 4 says where the balance between them differs.

== Other machines

#tbl(columns: (auto, 1fr), header: ([Machine], [What to expect]), align: (left, left),
  [Apple Silicon Pro or Max, 32 GB or more], [Everything, at about the times below. A Max chip, with twice the GPU cores and bandwidth, can take about half as long.],
  [Apple Silicon with 16 GB], [Units 1, 2 and 4 in full, with Chapter 2.5's run two or more times as long on a base chip. In Unit 3, fine-tune SmolLM2-135M where the text uses 360M, or use LoRA.],
  [NVIDIA GPU with 16 to 24 GB], [Everything, usually faster than the M2 Pro. On a GPU of the Ampere generation or later, Chapter 2.5's `--dtype bf16` trains several times faster than float32. The Metal track of Chapter 4.4 needs a Mac, so follow the Vulkan track.],
  [NVIDIA GPU with 8 to 12 GB], [Units 1, 2 and 4, with smaller batches and gradient accumulation where memory runs out. In Unit 3, use LoRA and the 135M models.],
  [CPU only], [Unit 1 to Chapter 1.7, the n-gram models, and the C++ chapters run normally. Use the `small` preset and fewer tokens for Chapters 2.5 and 2.6, and expect Unit 3's runs to take a day or more.],
)

Renting a single GPU by the hour from a cloud provider is a sensible alternative for the long runs of Units 2 and 3, because the code runs unchanged on CUDA and `uv sync` installs the same environment. Check the rate, and remember to stop the machine.

The C++ engine of Chapter 4.6 uses ARM's NEON instructions on Apple Silicon and other ARM processors. Elsewhere it falls back to plain loops, which are correct but several times slower. Writing AVX2 versions is a worthwhile extension of Lab 4.6.3.

== Machine time

The study hours in each chapter's header leave out time a program spends running unattended. This table lists every program that runs for more than a minute on the M2 Pro with 32 GB. The times were measured one program at a time while the course was written, and are rounded.

#tbl(columns: (auto, 1fr, auto), header: ([Chapter], [Command, after `uv run -m`], [Time]), align: (left, left, right),
  [1.7], [`u1.deep`], [1 min],
  [1.8], [`u1.cifar`], [22 min],
  [1.8], [`u1.contrastive`], [22 min],
  [2.2], [`u2.ngram`], [3 min],
  [2.2], [`u2.mlp_lm`], [10 min],
  [2.5], [`u2.pretrain`], [4 h 45 min],
  [2.5], [`u2.throughput`], [3 min],
  [2.6], [`u2.scaling`], [3 h],
  [2.8], [`u2.probe`], [2 min],
  [3.2], [`u3.sft`], [1 h 20 min],
  [3.3], [`u3.lora`], [1 h 15 min],
  [3.3], [`u3.lora --full --examples 5000`], [40 min],
  [3.3], [`u3.lora --model HuggingFaceTB/SmolLM2-360M --int4 --examples 5000`], [2 h 5 min],
  [3.4], [`u3.reward`], [30 min],
  [3.4], [`u3.dpo`], [1 h 10 min],
  [3.5], [`u3.grpo`], [1 h 5 min],
  [3.6], [`u3.evaluate`], [50 min],
  [3.7], [`u3.retrieval`], [1 h 50 min],
  [3.8], [`u3.agent`], [4 min],
  [4.7], [`u4.quantise --model HuggingFaceTB/SmolLM2-135M`], [6 min],
  [4.8], [`u4.serve`], [6 min],
)

Chapter 2.5's run, the longest, can be stopped and later restarted with `--resume`, which continues from the last checkpoint.

== Keeping a long run alive

- *Stop the machine sleeping.* On macOS, prefix the command with `caffeinate -i`, which keeps the Mac awake until the program ends. Keep a laptop on mains power with its lid open, which lets it cool best. On Linux, run long jobs inside `tmux` so that closing the terminal does not end them.
- *Run one GPU job at a time.* Two programs sharing the GPU each run at less than half speed, and every timing in the course assumes an idle machine.
- *Watch the run.* Training programs print their progress, and Chapter 2.5's also writes a log. The GPU's load is visible in Activity Monitor's GPU History window on a Mac, and with `nvidia-smi` on NVIDIA machines.
- *Make it smaller first.* Before a long run, run the same command with a tenth of the tokens or steps and check that the loss falls, so that a mistake costs minutes instead of hours.
