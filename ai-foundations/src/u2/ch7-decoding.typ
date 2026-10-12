#import "../lib/template.typ": *

= Decoding <ch-decoding>

#chapter-meta(
  time: [6 hours],
  builds: [A generation loop with greedy choice, beam search, temperature, and top-k, top-p and min-p truncation; eight strategies compared on the same model by probability, repetition and diversity; and a KV cache that makes each new token cost one token's work, timed against generation without it.],
  needs: [Chapters 2.4 and 2.5.],
)

#why[
  A language model gives a probability for every possible next token; text appears only when something chooses among them, one token at a time. That choice, the _decoding strategy_, changes the output as much as the model does: the same weights write loops, gibberish or good stories depending on it. And choosing token by token is slow unless the work already done for earlier tokens is kept, which is what the KV cache does. Every chat model's style, and much of its speed, comes from these two pieces.
]

#skip-test(
  rule: [If all four are easy, read the sections on truncation and on measuring decoding, and do Labs 2.7.2 and 2.7.4.],
  [Why does greedy decoding of open-ended text tend to repeat itself?],
  [What does sampling at temperature $T$ do to the distribution, as $T$ approaches 0 and as it grows above 1?],
  [How do top-k, top-p and min-p differ in which tokens they remove?],
  [What does a KV cache store, how large is it, and what work does it save?],
)

== Core ideas

=== The generation loop

Generation runs the model on the prompt, chooses a token from the distribution at the last position, appends it, and repeats until an end-of-text token or a length limit. Processing the prompt in one parallel pass is called _prefill_; producing the tokens that follow, one per step, _decode_.

#snippet("aif/sample.py", "generate", caption: [The generation loop, with a KV cache])

=== Greedy choice and beam search

The simplest rule takes the most probable token every time. _Greedy_ decoding is deterministic and often good for short answers with one right reply, but it does not find the most probable sequence, since a likely token now can lead to unlikely ones later. _Beam search_ searches further: it keeps the $w$ partial sequences with the highest total log-probability, extends each by every token, keeps the best $w$ of the results, and stops when $w$ sequences have ended.

#snippet("aif/sample.py", "beam", caption: [Beam search over a batch of $w$ sequences, sharing one KV cache])

For open-ended text, finding more probable sequences is not the goal. Human writing is not the most probable continuation of itself: it surprises at a steady rate, while the highest-probability paths through a model are bland and, given enough length, drift into loops, because once a phrase has repeated, repeating it again becomes the likeliest thing to do. Beam search is the right tool where a single correct output exists, as in translation, and a poor one for stories, which should differ every time they are told.

=== Sampling and temperature

Sampling draws the next token at random from the model's distribution, so every run differs and the text has the variety of the training data. _Temperature_ $T$ reshapes the distribution before drawing:
$ p_i = exp(z_i \/ T) / (sum_j exp(z_j \/ T)). $
At $T = 1$ it is the model's own distribution; below 1 it sharpens towards the most likely tokens, and as $T -> 0$ sampling becomes greedy; above 1 it flattens towards uniform.

#snippet("aif/sample.py", "next-token", caption: [Choosing one token: greedy at zero temperature, otherwise filter and sample])

Pure sampling has a different weakness. A model spreads a little probability over thousands of unlikely tokens; each is rare, but together they are drawn often enough that a long story will pick a few, and one bad token can derail everything after it.

=== Truncation

Truncation removes the tail before sampling. _Top-k_ keeps the $k$ most likely tokens, a fixed number whatever the distribution's shape: too many when the model is sure, too few when many continuations are reasonable. _Top-p_, or nucleus sampling, keeps the smallest set of most likely tokens whose probabilities sum to at least $p$, which adapts to the shape. _Min-p_ keeps every token whose probability is at least a fraction of the most likely token's, so it cuts hard when the model is confident and loosely when it is not, and stays coherent at higher temperatures.

#snippet("aif/sample.py", "filters", caption: [Top-k, top-p and min-p, as masks on the logits])

=== Measuring decoding

Three measures summarise a strategy, none of them quality itself: the average log-probability per generated token under the model, how likely the text is; the fraction of each sample's four-token sequences that repeat earlier ones within it, how loopy it is; and the fraction of distinct three-token sequences across ten samples, how varied the samples are from each other.

#snippet("u2/decode.py", "metrics", caption: [Repetition within a sample, and diversity across samples])

#snippet("u2/decode.py", "strategies", caption: [Eight strategies, each applied to the same prompt])

#console(read("/src/console/u2-decode.txt"), caption: [Eight ways to continue one prompt with the Chapter 2.5 model])

The two deterministic methods find the most probable text, beam search more so, at −0.30 nats per token against greedy's −0.48, and both give one story per prompt however often they are asked. Greedy decoding already repeats 6% of its four-token sequences within 120 tokens; beam search's story does not repeat here, and is fluent and generic. Sampling at temperature 1.0 keeps the model's own distribution and is far more varied, nine in ten three-token sequences distinct across ten samples, at a cost of three-quarters of a nat per token in probability. At 1.5 the tail takes over and the text dissolves into fragments of words, at −7.2 nats per token. Truncation buys back probability at little cost in variety: top-k 40 keeps all of pure sampling's variety at a fifth of a nat better probability, top-p 0.9 trades a little variety for more, and min-p 0.1 lands next to temperature 0.7 on both measures, with stories that read as well as greedy's.

Judging quality needs more than these numbers: a reader, or a model acting as one, as in Chapter 3.6.

#hazard(title: [Pitfall])[
  Sampled text varies widely between runs. Judging a strategy by one or two samples, and especially by a sample chosen because it looked good, says little. Compare strategies on many samples with fixed seeds, and measure.
]

=== The KV cache

Without a cache, generating each new token runs the model over the whole sequence so far: the work for the $t$-th token grows with $t$, and the work for a sequence of $n$ tokens with $n^2$. Most of it is repeated. With causal attention, the keys and values of earlier positions never change once computed, so they can be kept. Each step then computes the query, key and value of one new token per layer, appends the key and value to the cache, and attends over everything stored.

#snippet("aif/gpt.py", "cache", caption: [The KV cache: a pair of tensors per model, filled one step at a time])

Chapter 2.4's attention uses the cache when one is passed, with a mask that lets the new tokens see every cached position. The program generates the longest sequence the model allows, with and without the cache, checks that the outputs are identical, and times each token:

#snippet("u2/kvcache.py", "compare", caption: [The same generation, with and without the cache])

#console(read("/src/console/u2-kvcache.txt"), caption: [Greedy generation of 508 tokens, timed on the GPU and on the CPU])

#fig("u2-kvcache", caption: [Time per generated token against its position, on each device. Without the cache, the cost of a token grows with the length of the sequence wherever arithmetic dominates; with it, the cost barely grows.]) <fig-kvcache>

Both ways produce the same 508 tokens. Without the cache, the cost of a token grows with its position: on the CPU from 9.4 ms for each of the first 50 tokens to 39.5 ms for each of the last 50, and on the GPU from 5.2 to 14.0 ms. With the cache the cost stays flat apart from noise: from 4.2 to 4.7 ms on the CPU, and between about 5 and 10 ms on the GPU, where the first and last 50 tokens average 5.6 and 6.4 ms (@fig-kvcache). The cache makes the whole sequence 5.5 times faster on the CPU and only 1.3 times faster on the GPU, where a step of this 28M-parameter model costs mostly the fixed price of launching its kernels: for the first two hundred tokens, the GPU recomputes the whole sequence as quickly as it extends the cache by one token. Once the cache removes the arithmetic, the CPU generates faster than the GPU. Decoding one sequence a token at a time leaves a GPU nearly idle, which is why Chapter 4.8 batches many sequences together.

The cache costs memory. Each layer stores a key and a value vector per key-value head for every token:

#snippet("u2/kvcache.py", "bytes", caption: [The cache's size])

For the course's model at 512 tokens that is a few megabytes, but for large models at long contexts it rivals or exceeds the weights, and it grows with every sequence served at once. That is why Chapter 2.4's grouped-query attention shares key-value heads, why Chapter 4.7 quantises the cache, and why Chapter 4.8 manages it in blocks.

#keyidea[
  The decoding rule is part of the model as used. Greedy choice and beam search find likely text and loop; pure sampling wanders into the tail; sampling with truncation, min-p or top-p at a moderate temperature, keeps the variety and drops the tail. The KV cache makes each new token cost one token's work, at the price of memory that grows with the context.
]

#inpytorch(title: [In the libraries])[
  Hugging Face's `generate` takes `do_sample`, `temperature`, `top_k`, `top_p`, `min_p` and `num_beams`, and keeps its cache in a `DynamicCache` object; `llama.cpp` chains samplers in a configurable order. `torch.multinomial` draws from a distribution, and a `torch.Generator` with a fixed seed makes the draws repeatable.
]

#reading(
  [Ari Holtzman and others, "The Curious Case of Neural Text Degeneration", ICLR 2020: nucleus sampling, and why likely text is dull.],
  [Minh Nhat Nguyen and others, "Turning Up the Heat: Min-p Sampling for Creative and Coherent LLM Outputs", ICLR 2025.],
  [Clara Meister, Ryan Cotterell and Tim Vieira, "If Beam Search is the Answer, What was the Question?", EMNLP 2020.],
  [Reiner Pope and others, "Efficiently Scaling Transformer Inference", MLSys 2023: the KV cache's memory and the cost of decoding.],
)

== Labs

#lab([A repetition penalty], goal: [Implement and measure the commonest fix for loops.], time: [1.5 hours], code: "code/aif/sample.py")[
  + Add a penalty that divides the positive logits, and multiplies the negative ones, of every token already in the output by a factor $r$.
  + Measure greedy decoding's repetition and log-probability for $r$ = 1, 1.1, 1.3 and 1.5, and read the outputs.
  #done-when(
    [Your table has four rows.],
    [You can describe what goes wrong at the largest penalty, with an example.],
  )
  #evidence([The code, the table and the example.])
]

#lab([Temperature and truncation], goal: [See what truncation buys at each temperature.], time: [1.5 hours], code: "code/u2/decode.py")[
  + Measure log-probability and distinct 3-grams at temperatures from 0.3 to 2.0, for pure sampling and for min-p 0.1.
  + Plot both measures against temperature for both strategies.
  #done-when(
    [Your plot has both strategies over the whole range.],
    [You can state the highest temperature at which each still writes readable stories, with samples to show it.],
  )
  #evidence([The plot and the samples.])
]

#lab([The width of the beam], goal: [Find where wider search stops helping.], time: [1 hour], code: "code/aif/sample.py")[
  + Run beam search with widths 1, 2, 4, 8 and 16 on five prompts, and record log-probability per token, repetition and length.
  + Repeat with length penalties of 0 and 2.
  #done-when(
    [Your table covers every width and both penalties.],
    [You can explain how the penalty changes the outputs' lengths.],
  )
  #evidence([The table.])
]

#lab([Many samples at once], goal: [Measure what batching does for generation.], time: [1.5 hours], code: "code/aif/sample.py")[
  + Generate 16 continuations of one prompt with `generate_group`, which decodes them as one batch, and then with 16 calls of `generate`.
  + Time both, and repeat for 1, 4, 16 and 64 continuations.
  #done-when(
    [Your table has both times at four sizes.],
    [You can explain why the batch costs little more than one sequence, using Chapter 1.1's measurements of matrix products.],
  )
  #evidence([The table and the explanation.])
]

#problems(
  [Show that sampling at temperature $T$ approaches greedy choice as $T -> 0$, assuming one most likely token. What does it approach as $T -> infinity$?],
  [A distribution has probabilities 0.5, 0.2, 0.12, 0.08, 0.06 and 0.04. Which tokens survive top-k with $k = 3$, top-p with $p = 0.75$, and min-p with 0.3?],
  [SmolLM2-360M has 32 layers, 5 key-value heads and heads of 64 dimensions. How large is its KV cache for one sequence of 8,192 tokens in bfloat16? For 32 such sequences?],
  [Generating $n$ tokens without a cache, how do the total work of the feed-forward layers and of attention grow with $n$? With a cache?],
  [Why does beam search with a wide beam tend to prefer short outputs, and how does dividing the score by length raised to a power correct it?],
)

#checklist(
  [I can implement greedy choice, beam search, temperature and top-k, top-p and min-p sampling.],
  [I can explain why likely text loops and sampled text wanders, and choose a strategy for a task.],
  [I can measure decoding strategies and avoid judging them by a few samples.],
  [I can implement a KV cache, compute its size, and explain what it saves.],
  [Lab 2.7.1–2.7.4 done-when criteria all hold, with evidence filed.],
)
