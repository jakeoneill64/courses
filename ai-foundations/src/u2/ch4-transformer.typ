#import "../lib/template.typ": *

= The transformer <ch-transformer>

#chapter-meta(
  time: [6 hours],
  builds: [A decoder-only transformer in about 200 lines, with pre-norm blocks, RMS normalisation, rotary position embeddings, grouped-query attention and a SwiGLU feed-forward network, written so that it can load the weights of the Llama family; its parameters counted by formula and checked; its FLOPs per token derived; and the three tests that every transformer should pass.],
  needs: [Chapters 1.7 and 2.3.],
)

#why[
  The transformer is the architecture of essentially every language model in use, from this course's 28 million parameters to models ten thousand times larger, and the differences between them are mostly a handful of well-understood design choices. This chapter assembles one from the pieces of earlier chapters, explains each choice, and checks the result. The details are not optional: Unit 3 loads SmolLM2's published weights into this exact code, and every choice here must match its designers' or the model will produce nonsense.
]

#skip-test(
  rule: [If all four are easy, read the sections on rotary embeddings and on counting, and do Labs 2.4.3 and 2.4.4.],
  [Draw a pre-norm transformer block, and say where the residual connections and the normalisations go.],
  [Rotary position embeddings rotate queries and keys by an angle that depends on position. Why does the dot product of a rotated query and key depend only on their distance?],
  [What does grouped-query attention save, and what does it cost?],
  [How many parameters does one block have with $d = 512$, a feed-forward width of 1,408, 8 query heads and 4 key-value heads of 64 dimensions?],
)

== Core ideas

=== The shape of a decoder-only transformer

A token sequence enters as embedding vectors, one row of a learned table per token. A stack of identical _blocks_ then transforms them, each adding to the vectors what it computes, so that the vector at each position, the _residual stream_, accumulates information as it rises through the stack. Each block does two things in turn: attention, which moves information between positions, and a feed-forward network, which transforms each position on its own. A final normalisation and a linear map to the vocabulary turn the top of the residual stream into logits for the next token (@fig-transformer).

#fig("u2-transformer", caption: [The decoder-only transformer of this course. Each of the eight blocks adds the output of attention and of the feed-forward network to the residual stream; the output layer shares its weights with the embedding.]) <fig-transformer>

All the dimensions live in one configuration:

#snippet("aif/gpt.py", "config", caption: [The configuration, with the defaults of Chapter 2.5's model])

=== Normalisation and blocks

Chapter 1.7 showed why deep networks need normalisation and residual connections, and why pre-norm trains more easily than post-norm. The transformer uses RMS normalisation before each half of each block, computed in float32 whatever the model's precision, since a sum of squares overflows half precision easily:

#snippet("aif/gpt.py", "rmsnorm", caption: [RMS normalisation])

#snippet("aif/gpt.py", "block", caption: [A pre-norm block: two residual additions, each of a normalised sublayer])

=== Rotary position embeddings

Attention is blind to order, so the model must be told where each token is. The original transformer added a vector depending on the position to each embedding. Modern models instead _rotate_ the queries and keys. Split each head's vector into pairs of dimensions; rotate pair $k$ by the angle $p theta_k$, where $p$ is the token's position and the frequencies $theta_k = 10000^(-2k \/ d)$ range from one radian per position down to a tiny fraction of one.

#derivation[
  Treat one pair of dimensions as a complex number, rotated with frequency $theta$. The query at position $m$ becomes $q e^(i m theta)$ and the key at position $n$ becomes $k e^(i n theta)$, with $i$ the imaginary unit. The pair's contribution to the dot product is the real part of the rotated query times the conjugate of the rotated key,
  $ "Re"(q e^(i m theta) dot overline(k e^(i n theta))) = "Re"(q overline(k) e^(i (m - n) theta)), $
  which depends on the positions only through $m - n$. Summing over the pairs, the score between a query and a key depends on their content and their relative position, never on their absolute positions.
]

Rotating by relative position is exactly what attention needs: "the previous token" or "the token after the last occurrence of this one" means the same thing anywhere in the sequence. The implementation follows the convention of the Llama family, which rotates the first half of a head's dimensions against the second half rather than adjacent pairs; the two are equivalent up to a fixed permutation of the dimensions, but loading another model's weights requires using the same one.

#snippet("aif/gpt.py", "rope", caption: [The rotation tables and their application])

=== Grouped-query attention

During generation, every layer keeps the keys and values of all previous tokens, Chapter 2.7's KV cache, and for long contexts that cache dominates memory. _Grouped-query attention_ lets several query heads share one key-value head: with 8 query heads and 4 key-value heads, each pair of query heads reads the same keys and values. The cache and the key and value projections halve, and the quality cost is small. SmolLM2-135M shares each of 3 key-value heads among 3 query heads.

#snippet("aif/gpt.py", "attention", caption: [Attention with rotary embeddings, grouped key-value heads and an optional KV cache])

=== The feed-forward network

Each position then passes through the same two-layer network. Modern models use a gated variant, _SwiGLU_: one projection, passed through the smooth SiLU nonlinearity $x sigma(x)$, multiplies another element-wise before the down projection. Gating lets the network switch features on and off depending on the input, and consistently trains slightly better than a plain MLP with the same number of parameters. Since it has three matrices instead of two, its width is conventionally about $8 \/ 3$ of the model dimension, rounded to a multiple of 64.

#snippet("aif/gpt.py", "mlp", caption: [The SwiGLU feed-forward network])

=== The whole model

#snippet("aif/gpt.py", "gpt", caption: [Embedding, blocks, final norm and a tied output layer, with the loss when targets are given])

The output layer _ties_ its weights to the embedding: the same matrix maps tokens to vectors on the way in and vectors to logits on the way out. That saves $V times d$ parameters, a seventh of this model, and works as well as separate matrices at this scale. Initialisation follows GPT-2: weights drawn with standard deviation 0.02, and the two projections that write into the residual stream scaled down by $sqrt(2 L)$, so that the sum of $2 L$ contributions keeps a steady size.

=== Counting parameters and FLOPs

Per block, attention has $d dot h_d (2 H + 2 H_"kv")$ parameters, with $h_d$ the head size: queries and output projections for $H$ heads, keys and values for $H_"kv"$. The feed-forward network has $3 d dot d_"ff"$, and the two norms $2 d$. A forward pass multiplies each parameter by one input once per token, two FLOPs per parameter, and the backward pass costs twice the forward pass, as Chapter 1.2 derived, so training costs about six FLOPs per parameter per token. Attention's scores and weighted sums add $6 L T d$ per token for a context of $T$, and the output layer, which multiplies by the embedding matrix, counts with the parameters even though it is tied.

#snippet("aif/gpt.py", "count", caption: [Parameters, and training FLOPs per token])

#snippet("u2/gpt_check.py", "breakdown", caption: [Where the parameters are])

#console-part("/src/console/u2-gpt-check.txt", to: 17, caption: [This course's model and SmolLM2-135M, part by part])

Six-tenths of each model is its feed-forward networks. The embedding is a seventh of the course's model and a fifth of SmolLM2's, whose vocabulary is six times larger. Training the course's model costs 179 MFLOPs per token, so Chapter 2.5's 300 million tokens need $5.4 times 10^16$ FLOPs, just under five hours at the 3.2 TFLOP/s that the M2 Pro sustains on it.

=== Three tests every transformer should pass

A transformer can contain bugs that still let it train, to a worse result. Three cheap tests catch most of them.

#snippet("u2/gpt_check.py", "causal", caption: [Causality: changing later tokens must not change earlier outputs])

#snippet("u2/gpt_check.py", "rope", caption: [Relative positions: the same offset must give the same score anywhere])

#snippet("u2/gpt_check.py", "overfit", caption: [Capacity: a small model must memorise a single batch])

#console-part("/src/console/u2-gpt-check.txt", from: 17, command: false, caption: [All three pass])

A model that leaks the future scores impossibly well and generates nonsense; a wrong rotation convention trains, but loads no one else's weights; a model that cannot memorise four sequences of random tokens has a bug in its plumbing, whatever its loss on real text.

#keyidea[
  A modern transformer is a stack of pre-norm blocks, each adding attention and a gated feed-forward network to a residual stream, with positions supplied by rotating queries and keys. Training costs about six FLOPs per parameter per token, and most of the parameters are in the feed-forward networks.
]

#inpytorch[
  Hugging Face's `LlamaForCausalLM` is this chapter's model with different names: `q_proj` for `attn.q`, `input_layernorm` for `attn_norm`, `gate_proj` for `mlp.gate`, and so on, a mapping Chapter 3.1 uses to load weights. `torch.nn.RMSNorm` and `F.silu` are built in. `torch.compile(model)` fuses the small element-wise operations, the norms, the rotation, SiLU and the residual additions, into fewer kernels, which Chapter 2.5 measures and Chapter 4.2 explains.
]

#reading(
  [Ashish Vaswani and others, "Attention Is All You Need", NeurIPS 2017, section 3.],
  [Jianlin Su and others, "RoFormer: Enhanced Transformer with Rotary Position Embedding", 2021.],
  [Noam Shazeer, "GLU Variants Improve Transformer", 2020.],
  [Joshua Ainslie and others, "GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints", EMNLP 2023.],
  [Hugo Touvron and others, "LLaMA: Open and Efficient Foundation Language Models", 2023, section 2.2: the architecture this chapter follows.],
)

== Labs

#lab([Shapes everywhere], goal: [Know the shape of every tensor in the forward pass.], time: [1 hour], code: "code/aif/gpt.py")[
  + For a batch of 2 sequences of 16 tokens, write down the shape of every tensor in one block's forward pass, including inside attention.
  + Check your list with forward hooks that print the shapes of each module's inputs and outputs.
  #done-when(
    [Every shape in your list matches the hooks' output.],
  )
  #evidence([The annotated list.])
]

#lab([Ablations at small scale], goal: [Measure what the modern choices buy.], time: [2 hours], code: "code/u2/pretrain.py")[
  + Make three variants of the model: LayerNorm instead of RMSNorm; learned absolute position embeddings instead of rotary; a GELU MLP with the same parameter count instead of SwiGLU.
  + Train each, and the unchanged model, with `--preset small --tokens 20e6`, and compare validation losses.
  #done-when(
    [You have four validation losses from runs with the same data and seed.],
    [You can say which choice mattered most at this scale, and whether the differences exceed the run-to-run variation, measured with a second seed.],
  )
  #evidence([The table of losses with both seeds.])
]

#lab([Fewer key-value heads], goal: [Trade memory against quality with grouped-query attention.], time: [1.5 hours], code: "code/u2/pretrain.py")[
  + Compute the KV-cache size per token and the attention parameters for 4, 2 and 1 key-value heads with the `small` preset's 4 query heads.
  + Train the `small` preset with each, `--kv-heads 4` and so on, for 20 million tokens, and compare validation losses.
  #done-when(
    [Your table has the cache size, parameters and loss for all three settings.],
    [You can recommend a setting for a model whose cache must fit in a quarter of the memory.],
  )
  #evidence([The table and the recommendation.])
]

#lab([Count SmolLM2 by hand], goal: [Derive a real model's size and cost from its configuration.], time: [1 hour], code: "code/u2/gpt_check.py")[
  + From SmolLM2-360M's `config.json`, compute its parameters by part and its training FLOPs per token at 2,048 tokens of context.
  + Check your parameter count by loading the model with `gpt.from_huggingface`.
  + Estimate how long the M2 Pro would take to train it on two trillion tokens, its published budget.
  #done-when(
    [Your parameter count is exact.],
    [Your time estimate is stated with the throughput it assumes.],
  )
  #evidence([The calculation and the check.])
]

#problems(
  [Show that applying the same rotation to a query and a key leaves their dot product unchanged. Why does that make rotary embeddings relative?],
  [With 8 query heads, how many key-value heads does multi-query attention use, and how many standard multi-head attention? What is grouped-query attention between them?],
  [Why is the output layer's matrix multiplication counted in the training FLOPs even though its weights are tied to the embedding, whose lookup costs nothing?],
  [Derive the $6 N$ rule for training FLOPs per token from Chapter 1.2's result that the backward pass of a matrix multiplication costs twice the forward pass.],
  [The model is initialised with standard deviation 0.02 and residual projections scaled by $1 \/ sqrt(2 L)$. Estimate the standard deviation of the residual stream after all eight blocks at initialisation.],
)

#checklist(
  [I can draw the transformer and explain the purpose of each component.],
  [I can explain rotary embeddings, grouped-query attention and SwiGLU.],
  [I can count a transformer's parameters and training FLOPs from its configuration.],
  [I can test a transformer for causality, relative positions and capacity.],
  [Lab 2.4.1–2.4.4 done-when criteria all hold, with evidence filed.],
)
