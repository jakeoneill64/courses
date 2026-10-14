#import "../lib/template.typ": *

= Serving <ch-serving>

#chapter-meta(
  time: [6 hours],
  builds: [A paged KV cache that allocates memory in blocks; batched decoding of sequences of different lengths in one forward pass; a scheduler that admits requests as others finish; one load of chat requests served one at a time, in static batches and with continuous batching, measured for throughput and latency; speculative decoding, a small model drafting for a large one, checked to give exactly the large model's output; and a streaming HTTP endpoint.],
  needs: [Chapters 2.7, 4.1 and 4.6.],
)

#why[
  A deployed model serves many people at once. Its users experience its latency, the time until the first word and the speed at which the rest arrive, while its running cost depends on its throughput in tokens per second per machine. Decoding one sequence at a time leaves the GPU almost idle, waiting on memory, as Chapter 2.7 showed. This capstone builds the three techniques that make serving efficient: batching many sequences through each pass over the weights, a cache layout that lets sequences of any length share memory, and speculative decoding, which spends cheap computation to save expensive memory traffic.
]

#skip-test(
  rule: [If all four are easy, read the sections on the scheduler and on speculative decoding, and do Labs 4.8.2 and 4.8.4.],
  [Why does batching decode steps raise throughput almost in proportion to the batch, until it does not?],
  [What problem does a paged KV cache solve, and what does it cost?],
  [What is the difference between static and continuous batching, and which latency does each hurt?],
  [How does speculative decoding produce exactly the large model's greedy output while running the large model fewer times?],
)

== Core ideas

=== What to measure

A request's _time to first token_ is spent waiting for a slot and processing its prompt; its _inter-token latency_ is the time per generated token after that. The server's _throughput_ is generated tokens per second over all requests. These measures conflict. A server that runs one request at a time gives that request the fastest tokens and everyone else a long wait, while large batches raise throughput and slow each step. Designing a server means choosing a point on that trade-off, measured under a realistic load of requests arriving at random, with prompts and replies of varied lengths.

=== Batching decode steps

Generating one token reads every weight once, an intensity near 1 FLOP per byte with 16-bit weights. Generating one token for each of $N$ sequences in the same pass reads the weights once for all of them, so the intensity grows with $N$ and the step's time barely changes until the arithmetic catches up with the memory. Throughput rises almost $N$-fold. Two things complicate batching: the sequences have different lengths, so their attention covers different numbers of keys, and they start and finish at different times.

=== A paged KV cache

Chapter 2.7's cache gave each sequence one contiguous tensor. A server holding many sequences of different lengths, which start and finish at different times, would have to find a contiguous region for every new one, and the gaps that finished sequences leave behind fragment memory, as in any heap allocator. A _paged_ cache, like an operating system's virtual memory, divides the cache into fixed-size blocks of 16 positions. Each sequence holds a list of blocks, its _block table_, which need not be adjacent, and the scheduler takes blocks from a free list and returns them when the sequence finishes, so any free block can serve any sequence.

This chapter's scheduler reserves a sequence's blocks for its prompt and its longest permitted reply when it admits it. Production servers allocate each block only when the sequence reaches it, so that the only memory wasted is the unfilled part of each sequence's last block. Lab 4.8.2 makes that change and measures what it saves.

#snippet("aif/serving.py", "paged", caption: [The block pool])

Decoding a batch then computes each sequence's query, key and value for its new token together, writes each new key and value into its sequence's current block, gathers each sequence's keys and values through its block table, and runs attention with a mask that hides each sequence's unused positions:

#snippet("aif/serving.py", "decode", caption: [One decode step for a batch of sequences of different lengths])

Production kernels read the blocks in place inside the attention kernel instead of gathering them into a padded tensor. The gather here costs memory traffic but keeps the code to a page.

=== Scheduling

_Static batching_ collects a batch of requests, runs them until all have finished, and only then admits more, so a batch's short requests wait for its longest and new arrivals wait for the whole batch. _Continuous batching_ admits a waiting request into the running batch as soon as a slot and enough blocks are free, so the batch stays full and nobody waits for anyone else's reply to finish.

#snippet("aif/serving.py", "scheduler", caption: [The scheduler: admit, prefill, decode, retire])

#snippet("u4/serve.py", "load-test", caption: [A load of requests arriving at random, and the measurements])

#console-part("/src/console/u4-serve.txt", to: 7, caption: [48 chat requests at two per second, served three ways, and a check of batched decoding])

Serving one request at a time, the server generates 46 tokens per second, and each request's tokens come quickly, 21.4 ms apart. Requests arrive faster than it can serve them, however, so they queue: the mean wait for a first token is 40 seconds, and the last request finishes nearly two minutes after the first arrived. Static batches of 16 serve 3.4 times as many tokens per second and cut the mean wait to 2.1 seconds, at the cost of slower steps, 32.2 ms per token, since each step now processes up to sixteen sequences. Continuous batching raises throughput further, to 176 tokens per second, and cuts the mean wait to 0.06 seconds, the time of one prefill, because a request no longer waits for anyone else's reply to finish. Its tokens come 33.9 ms apart, about 60% slower than alone, because each step is shared. For almost every request the shorter wait repays that many times over.

The last line checks batching itself: eight prompts decoded together, and each decoded alone. A sequence decoded in a batch can choose a different greedy token from the same sequence decoded alone, because the batched kernels add the same numbers in a different order and two candidate tokens can be within rounding of each other. Here all eight prompts agree in both precisions, but nothing guarantees it, and near-ties are more frequent in float16, whose rounding is coarser. Users of a batched server should expect greedy outputs to be reproducible only up to such near-ties.

=== Speculative decoding

A large model's decode step costs the same whether it processes one token or several, as long as the memory traffic dominates, and _speculative decoding_ uses this. A small _draft_ model, cheap to run, proposes the next $k$ tokens one at a time, and the large _target_ model then processes all $k$ in one pass and checks them. Each proposed token that matches what the target would have chosen is accepted. At the first mismatch, the target's own choice replaces the draft's and the rest are discarded. Every round therefore produces between one and $k + 1$ tokens, all of them exactly the target's greedy choices, for the price of one target pass and $k$ draft passes.

#snippet("aif/serving.py", "speculative", caption: [Greedy speculative decoding, with both caches rolled back to the accepted tokens])

#console-part("/src/console/u4-serve.txt", from: 7, command: false, caption: [SmolLM2-1.7B-Instruct drafted by SmolLM2-135M-Instruct, on eight prompts])

The target alone generates 19.3 tokens per second. Drafting two tokens at a time raises that to 26.5, 1.37 times as fast, with 80% of the drafted tokens accepted. Drafting four or six gains less, 1.31 and 1.26 times, because acceptance falls to 67% and 59% and every rejected token wasted a draft pass. The output is identical to the target's in every case, as the algorithm guarantees. The gain is modest because drafting has a cost. SmolLM2-135M has a thirteenth of the target's parameters, but a decode step of a small model on a GPU costs more than its share of the arithmetic, as Chapter 2.7 found for the course's model. Speculative decoding pays most when the draft is much cheaper per step than the target, and when the two agree often.

With sampling instead of greedy choice, a rejection-sampling rule accepts each draft token with probability $min(1, p_"target" \/ p_"draft")$ and resamples from the leftover probability on rejection, which provably gives exactly the target's sampling distribution. Lab 4.8.4 implements it.

=== A streaming endpoint

The scheduler runs as an asynchronous task; each HTTP request adds a sequence with a queue, and the handler streams tokens from the queue to the client as server-sent events as the scheduler produces them:

#snippet("u4/serve.py", "http", caption: [The scheduler as an asyncio task, feeding each request's queue])

```bash
uv run -m u4.serve --http 8000
curl -N -d '{"prompt": "Write a haiku about the sea."}' http://127.0.0.1:8000/generate
```

#keyidea[
  Decoding is memory-bound, so a server's efficiency comes from reading the weights once for many tokens: continuous batching fills each step with many sequences, a paged cache lets them share memory without fragmenting it, and speculative decoding lets one pass of a large model accept several cheaply drafted tokens.
]

#inpytorch(title: [In practice])[
  vLLM introduced the paged KV cache, as PagedAttention, and combines it with continuous batching, speculative decoding, prefix caching and quantised kernels; SGLang and TensorRT-LLM are its main alternatives, and `llama.cpp` has a server of its own. All expose an HTTP interface compatible with OpenAI's API, which streams tokens much as this chapter's endpoint does.
]

#reading(
  [Woosuk Kwon and others, "Efficient Memory Management for Large Language Model Serving with PagedAttention", SOSP 2023.],
  [Gyeong-In Yu and others, "Orca: A Distributed Serving System for Transformer-Based Generative Models", OSDI 2022: iteration-level scheduling.],
  [Yaniv Leviathan, Matan Kalman and Yossi Matias, "Fast Inference from Transformers via Speculative Decoding", ICML 2023.],
  [Charlie Chen and others, "Accelerating Large Language Model Decoding with Speculative Sampling", 2023.],
)

== Labs

#lab([Load and latency], goal: [Plot latency and throughput against the arrival rate.], time: [1.5 hours], code: "code/u4/serve.py")[
  + Run the continuous-batching benchmark at arrival rates of 0.5, 1, 2, 4 and 8 requests per second.
  + Plot median and 90th-percentile time to first token, and throughput, against the rate.
  #done-when(
    [Your plot has five rates.],
    [You can name the rate at which latency starts to climb steeply, and relate it to the throughput at that point.],
  )
  #evidence([The plot and the analysis.])
]

#lab([Blocks on demand], goal: [Allocate cache memory as sequences grow.], time: [1.5 hours], code: "code/aif/serving.py")[
  + Change the scheduler to give a sequence blocks for its prompt when it is admitted, and one more block whenever its length reaches the end of its last block.
  + Record, at every step of a benchmark, the blocks allocated and the positions actually filled, with reservation and on demand, for block sizes of 4, 16 and 64.
  #done-when(
    [Your table gives the average fraction of allocated cache in use for each block size under both policies.],
    [You can say what an on-demand scheduler must do when a sequence needs a block and none is free, and what each option costs.],
  )
  #evidence([The code and the table.])
]

#lab([Prefix caching], goal: [Share the cache of a common system prompt.], time: [2 hours], code: "code/aif/serving.py")[
  + Give every request the same long system prompt. Compute its blocks once and let every sequence's block table start with them, with blocks counted so that shared ones are not freed while in use.
  + Measure time to first token with and without sharing.
  #done-when(
    [Outputs are unchanged by sharing.],
    [Your measurements show the saving, and you can relate it to the prompt's length.],
  )
  #evidence([The code and the measurements.])
]

#lab([Speculative sampling], goal: [Apply speculative decoding to sampling and keep the target's distribution.], time: [2 hours], code: "code/aif/serving.py")[
  + Implement the rejection rule: accept each draft token with probability $min(1, p_"target" \/ p_"draft")$, and on rejection sample from the normalised positive part of $p_"target" - p_"draft"$.
  + Check the output distribution on a toy vocabulary by comparing token frequencies from 10,000 runs with the target's own sampling, then measure the speed-up on SmolLM2 at temperature 1.
  #done-when(
    [Your frequencies agree with the target's within sampling error.],
    [You have the speed-up and acceptance rate at temperature 1.],
  )
  #evidence([The test, the speed-up and the acceptance rate.])
]

#problems(
  [A decode step of SmolLM2-360M in float16 reads 720 MB of weights. On a machine with 150 GB/s, what is the step's time for a batch of 1, and up to what batch size does it stay about the same on a GPU with 6 TFLOP/s?],
  [Static batching runs batches of 16; requests' replies are 20 to 128 tokens long. What fraction of the batch's slots is idle on average, if lengths are uniform?],
  [With a draft that agrees with the target 70% of the time per token and $k = 4$, what is the expected number of tokens per round? If a draft pass costs a tenth of a target pass, what is the speed-up?],
  [Why must both caches be rolled back after a rejection, and what would go wrong if the draft's were not?],
  [Continuous batching admits long prompts whose prefill stalls everyone's decoding. How could a scheduler limit that, and what does it cost?],
)

#checklist(
  [I can explain why batching raises decode throughput and measure throughput and latency under load.],
  [I can implement a paged KV cache and batched decoding of sequences of different lengths.],
  [I can implement continuous batching and compare it with static batching.],
  [I can implement speculative decoding and show that it preserves the target's output.],
  [Lab 4.8.1–4.8.4 done-when criteria all hold, with evidence filed.],
)
