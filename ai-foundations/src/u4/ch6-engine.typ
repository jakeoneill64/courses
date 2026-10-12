#import "../lib/template.typ": *

= An inference engine in C++ <ch-engine>

#chapter-meta(
  time: [8 hours],
  builds: [An inference engine of about 1,100 lines of dependency-free C++20 that memory-maps an exported model, encodes text with a byte-level BPE tokeniser of its own, and generates with a KV cache, a thread pool and NEON vector code; checked against PyTorch on tokens and on logits; and timed from one thread to eight, on the course's model and on SmolLM2.],
  needs: [Chapters 2.4, 2.7 and 4.1, and C++ at the level of the Handbook's prerequisites. CMake 3.25 and Ninja.],
)

#why[
  Running a trained model needs no framework. Generating a token is a sequence of matrix-vector products and a handful of small functions, and an engine that does only that can be small, fast and free of dependencies: this is how models run on laptops, phones and servers without Python. Writing one shows exactly where the time goes when a model talks, which is almost entirely in reading its weights from memory, and that fact shapes the remaining chapters of the course: quantisation shrinks the weights, and serving reads them once for many users.
]

#skip-test(
  rule: [If all four are easy, read the sections on matrix-vector products and on speed, and do Labs 4.6.3 and 4.6.4.],
  [Why is generating one token at a time limited by memory bandwidth rather than arithmetic?],
  [What does the KV cache hold for each layer and token, and why does generation need it?],
  [How would you divide a matrix-vector product among eight threads, and why that way?],
  [A model's weights take 540 MB. At most how many tokens per second can a machine with 100 GB/s of bandwidth generate from it, one sequence at a time?],
)

== Core ideas

=== The plan

The engine needs three things from Python: the weights, the tokeniser and a reference to check itself against. `u4/export.py` writes all of them into one file: a four-byte tag, a JSON header describing the configuration, every tensor's name, kind, shape and offset, the tokeniser's tokens and merges, and the reference logits for a test prompt, then the tensors themselves, each aligned to 64 bytes.

#snippet("u4/export.py", "export", caption: [Exporting a model, its tokeniser and a reference into one file])

The engine memory-maps the file, so loading costs nothing until the weights are used and the operating system shares and pages them as it likes. Every weight is a view into the mapping:

#snippet("engine/model.hpp", "weight", caption: [A weight: its kind, its shape, and pointers into the mapped file])

#snippet("engine/model.cpp", "load", caption: [Mapping the file and parsing its header])

The header is JSON, read by a parser of about 170 lines in `engine/json.hpp`, so that the engine depends on nothing beyond the C++ standard library and POSIX.

=== The tokeniser, again

Chapter 2.1's tokeniser in C++ needs two parts. The BPE merges are a direct translation, with the merge table in a hash map keyed by the pair of token ids:

#snippet("engine/tokenizer.cpp", "bpe", caption: [Applying merges in rank order, as in Python])

The pre-tokeniser is harder, because GPT-2's regular expression uses Unicode character classes, letters and numbers in any script, which the C++ standard library cannot match. The engine decodes UTF-8 to code points and classifies them itself, exactly for ASCII and approximately elsewhere: common spaces, punctuation, symbols and digits are recognised, and other characters count as letters. It then reproduces the expression's alternatives by hand, including the rule that a run of spaces leaves its last space for the following word:

#snippet("engine/tokenizer.cpp", "pretokenise", caption: [GPT-2's pre-tokenisation, written out by hand])

For English text this gives exactly Python's tokens; for scripts and symbols outside the recognised ranges it can differ, which Lab 4.6.1 asks you to find.

=== The forward pass

The forward pass for one token at one position mirrors Chapter 2.4's model line for line, with the keys and values of every earlier position kept in a cache:

#snippet("engine/engine.cpp", "forward", caption: [One token through every layer, writing its keys and values into the cache])

#snippet("engine/ops.cpp", "rope", caption: [Rotary embeddings, in the Llama convention])

#snippet("engine/engine.cpp", "attention", caption: [Attention over the cache, one head per task])

Generation is then a loop: run the prompt through `forward`, sample a token from the last logits, feed it back, and repeat until a stop token or the context is full.

#snippet("engine/engine.cpp", "sample", caption: [Greedy decoding, or top-p sampling at a temperature])

=== Matrix-vector products

During generation each projection multiplies a matrix by a single vector, and nearly all the time goes there. Each output element is the dot product of one weight row with the input, so the rows divide naturally among threads, with no two threads writing the same output:

#snippet("engine/ops.cpp", "matvec", caption: [A matrix-vector product, rows shared among threads, for each kind of weight])

The thread pool keeps its workers alive between calls and hands out chunks of rows through an atomic counter. A generated token makes about sixty such calls for the course's model, so the cost of waking threads matters: the workers spin, checking a counter, instead of sleeping on a condition variable, which would add tens of microseconds per call.

#snippet("engine/ops.hpp", "pool", caption: [The thread pool])

#snippet("engine/ops.cpp", "parallel-for", caption: [Publishing a job, working on it too, and waiting for the workers])

The dot product itself uses the CPU's vector unit, NEON on ARM, four lanes of float32 per instruction. Four independent accumulators let four multiply-adds be in flight at once; with one, each would wait for the previous to finish, and the loop would run at a quarter of the speed.

#snippet("engine/ops.cpp", "dot", caption: [A NEON dot product with four accumulators, and a scalar fallback])

=== Checking against PyTorch

#snippet("engine/main.cpp", "check", caption: [Encoding the reference prompt and comparing the logits])

#console(read("/src/console/u4-engine-check.txt"), caption: [The engine against PyTorch, on the course's model])

The tokens are identical and the logits agree to about $10^(-5)$, the rounding of float32 arithmetic done in a different order. A story generated by the engine:

#console(read("/src/console/u4-engine-story.txt"), caption: [Chapter 2.5's model, running in C++])

=== Where the time goes

Generating one token reads every weight once, multiplies it once and adds once: two FLOPs per four bytes, an arithmetic intensity of 0.5, far left of the ridge of any processor's roofline. Decoding one sequence is therefore limited by memory bandwidth, and the best possible speed is the bandwidth divided by the bytes of weights read per token.

#console(read("/src/console/u4-engine-bench.txt"), caption: [Tokens per second by threads, three models, float32 weights, on the M2 Pro's CPU])

One thread cannot keep the memory system busy: a core issues only so many requests at a time. More threads raise the speed up to four, and beyond that it barely moves. At their best the three models read their weights at similar rates, between 78 and 91 GB/s, which suggests that all three meet the same limit, the bandwidth that the CPU's cores can draw from memory; Lab 4.6.3 measures that limit directly. Twelve threads, one for every core, are slower than eight for every model, most likely because with every core busy, anything else the machine runs preempts one of the engine's threads, and each operation waits for its slowest. Every route to faster generation from here either reads fewer bytes per token, the subject of Chapter 4.7, or reads them once for many sequences, Chapter 4.8's.

#keyidea[
  Generating a token reads every weight once, so single-sequence decoding is bound by memory bandwidth: its speed is at most the bandwidth divided by the model's size in bytes. Threads and vector instructions exist to approach that bound, not to exceed it.
]

#inpytorch(title: [In practice])[
  `llama.cpp`, built on the `ggml` library, is the best-known engine of this kind: C and C++, memory-mapped weights in its GGUF format, hand-written kernels for every CPU and GPU it supports, and quantised weights of 2 to 8 bits. Andrej Karpathy's `llama2.c` is a single-file engine much like this chapter's. PyTorch's own route to devices without Python is ExecuTorch, which compiles a model ahead of time.
]

#reading(
  [Reiner Pope and others, "Efficiently Scaling Transformer Inference", MLSys 2023: the arithmetic of inference.],
  [Andrej Karpathy, `llama2.c`, 2023, a minimal inference engine in C.],
  [Georgi Gerganov and contributors, `llama.cpp` and `ggml`, in particular the CPU matrix-vector kernels.],
  [Arm, _Neon Intrinsics Reference_, for the vector instructions used here.],
)

== Labs

#lab([Your model, in C++], goal: [Run your own models through the engine and find the tokeniser's limits.], time: [1.5 hours], code: "code/engine")[
  + Build the engine with CMake, export your Chapter 2.5 model and SmolLM2-135M-Instruct, and run `--check` on both.
  + Generate a story from your model and an answer from SmolLM2 with its chat template written into the prompt.
  + Find three strings, in other scripts or with unusual symbols, on which the engine's tokens differ from Python's, and explain each.
  #done-when(
    [Both checks pass.],
    [Your three strings come with the classification error that causes each.],
  )
  #evidence([The outputs and the three explanations.])
]

#lab([Batched prefill], goal: [Process the prompt with matrix-matrix products.], time: [2 hours], code: "code/engine/engine.cpp")[
  + Add `prefill(tokens)` that runs all the prompt's tokens through each layer together, so that each projection becomes a matrix-matrix product, with causal attention among the prompt's positions.
  + Check that the logits after prefill equal those after feeding the prompt one token at a time.
  + Measure prefill time for prompts of 16, 64 and 256 tokens both ways.
  #done-when(
    [The logits agree to within $10^(-4)$.],
    [Your table shows the speed-up growing with prompt length, and you can explain why from arithmetic intensity.],
  )
  #evidence([The code, the check and the table.])
]

#lab([Against the bound], goal: [Measure how close the engine comes to the memory bound.], time: [1.5 hours], code: "code/engine/ops.cpp")[
  + Measure your CPU's read bandwidth with a simple program that sums a 1 GiB array with 1 to 12 threads.
  + Compute each model's bound in tokens per second and compare with the engine's best.
  + Find the share of each token's time spent outside matrix-vector products, by timing them separately.
  #done-when(
    [You have the bandwidth curve, the bounds and the measured speeds.],
    [You can account for any gap between each model and its bound.],
  )
  #evidence([The measurements and the accounting.])
]

#lab([Long contexts], goal: [Make attention scale with the context.], time: [2 hours], code: "code/engine/engine.cpp")[
  + Measure milliseconds per token at positions 100, 500 and 2,000 of a long generation with SmolLM2-135M.
  + Replace the attention's scalar loops with the NEON dot product and a vectorised weighted sum.
  #done-when(
    [Your measurements show attention's growing share of time before the change.],
    [After the change the logits still match PyTorch, and the time per token at position 2,000 has fallen.],
  )
  #evidence([Both sets of timings and the check.])
]

#problems(
  [How many bytes does the course's model read per generated token in float32, counting the weights and the KV cache at position 500?],
  [Why is the output layer of SmolLM2-135M a large share of its decoding time? What fraction of its weights is it?],
  [The thread pool's workers spin while waiting. What does that cost when the engine is idle, and how could it sleep without slowing generation?],
  [Why must the engine's rotary embeddings use the same pairing of dimensions as the PyTorch model, and what would happen if they did not?],
  [With a memory-mapped file of weights larger than the machine's free memory, what does the operating system do during generation, and how fast would it be?],
)

#checklist(
  [I can describe each step of generating a token and implement it without a framework.],
  [I can implement and test a tokeniser and a forward pass against a reference.],
  [I can parallelise and vectorise a matrix-vector product, and explain the role of independent accumulators.],
  [I can compute the memory bound on decoding speed and compare an engine against it.],
  [Lab 4.6.1–4.6.4 done-when criteria all hold, with evidence filed.],
)
