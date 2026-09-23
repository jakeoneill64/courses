# Module 9: Sequence models and transformers

**Part III · 2 weeks · Needs: Module 5. Data: Tiny Shakespeare, TinyStories (subset).**

## Why this module

You have read about transformers and you can draw the diagram. That is the level at which
the Oxford Generative AI course will pitch its architecture material, and it is not enough
to explain to an examiner why the √d_k is there, why generation gets slower as the answer
gets longer, or why a model that writes fluent prose cannot reverse a word. The way past
surface reading is to write the thing from an empty file, train it, and then add the two
pieces that turn a toy into a system: a tokeniser and a KV cache. After that the papers
read as engineering notes.

The module also pays a debt to the practical-training gap. Language models are where the
craft from Module 5 earns most: warmup matters, initialisation scale matters, the batch is
measured in tokens, and a loss curve is the only thing you can watch. The scaling
mini-study in Lab 9.5 is a small version of the experiment that decided how every large
model since 2022 was sized, and doing it on a laptop gives you a feel for the numbers that
the compute estimate in Problem 5 turns into a formula.

Structurally, this is the third generative family. Module 7 gave you latent variable
models and diffusion; Module 8 gave you masked prediction as a pretext task. Autoregressive
models factorise the joint exactly, p(x) = Π_t p(x_t | x_{<t}), which is why they report an
honest likelihood and why they sample one token at a time. Module 10 assumes you know what
is inside the model it fine-tunes, and Module 13 assumes you can cost its memory.

## Skip test

Answer cold, in writing.

1. Write the language-modelling loss for a sequence of T tokens. Show how perplexity is
   derived from it and what a perplexity of 1 and of |V| mean.
2. Why is the dot product in attention divided by √d_k? What happens to the gradient
   through the softmax if you leave it out at d_k = 512?
3. A decoder-only transformer generates one token at a time. Without a KV cache, what is
   the cost of generating the n-th token, and what does the cache store to make it O(n)?
4. State the Chinchilla rule of thumb and derive the training FLOPs for a 1B-parameter
   model trained at that ratio.
5. RoPE rotates queries and keys. Show in two lines why the resulting dot product depends
   only on the difference in positions.
6. Why does a model with a byte-pair tokeniser struggle to add two five-digit numbers or
   spell a word backwards? Name two things the tokeniser does to the input that cause it.

If all six are easy, do Labs 9.3 and 9.4 only, and the write-up.

## Core ideas

**A language model is a next-token classifier, and its loss is cross-entropy per token.**
The model assigns p_θ(x_t | x_{<t}) over a vocabulary V and is trained to minimise
L = −(1/T) Σ_t log p_θ(x_t | x_{<t}) in nats per token, which Problem 1 shows is
minimising KL from the data distribution to the model. Perplexity is exp(L): the effective
number of equally likely choices at each step, so a perplexity of 1 is certainty and |V| is
uniform guessing. The baseline is an n-gram model: count (n − 1)-token contexts, estimate
the next-token distribution from counts, and smooth, because most contexts of length four
have never been seen. Kneser-Ney smoothing is the good version; add-k is the one you can
write in ten lines. An n-gram model with n = 5 on a million characters of Shakespeare is
surprisingly hard to beat with a small network, and you should know its number before
training anything.

**Tokenisation decides what the model can see, and byte-pair encoding is a compression
algorithm doing a linguist's job.** Characters give a tiny vocabulary and long sequences;
words give short sequences and an unbounded vocabulary with no way to spell a new one.
Subwords split the difference. BPE starts from bytes or characters, counts every adjacent
pair in the corpus, merges the most frequent pair into a new symbol, and repeats until the
vocabulary is the size you asked for; encoding applies the same merges in the same order.
Byte-level BPE starts from the 256 bytes so nothing is ever out of vocabulary. Larger
vocabularies shorten sequences and enlarge the embedding matrix and softmax; 32,000 to
128,000 is where current models sit. The failures follow from the design: numbers are
split into chunks that vary with digit count, so arithmetic is learned per chunking; a
word is one or two opaque tokens, so the model has never seen its letters and cannot
reverse or count them; and whitespace and code indentation tokenise in ways that make
formatting fragile.

**Recurrent networks solved sequences by compressing the past into a state, and the
gradient through time was the problem.** An RNN computes h_t = f(W h_{t−1} + U x_t), so the
gradient at step t reaches step t − k through k multiplications by Wᵀ f′, which shrinks to
nothing or explodes depending on W's largest singular value. Clipping handles the
explosion; nothing handles the vanishing in a plain RNN. The LSTM adds a cell state
updated additively, c_t = f_t ⊙ c_{t−1} + i_t ⊙ g_t, with learned forget, input and output
gates, so the gradient has a path through time that is a product of gate values near one
rather than of weight matrices (Problem 8); the GRU is the same idea with two gates.
Truncated backpropagation through time trains on windows and carries the state across
them. What recurrence never solved is that all history lives in one fixed-size vector and
that each step depends on the last, so nothing parallelises across the sequence. Attention
removed both constraints at once.

**Attention is soft retrieval: every position asks a question and reads a weighted
average of the answers.** Each token produces a query q, a key k and a value v by linear
maps. The output at position i is Σ_j softmax_j(q_i·k_j / √d_k) v_j: compare the query
against every key, turn the scores into weights with a softmax, and average the values by
those weights. Softmax is a differentiable argmax, so this is a lookup that can be trained
by gradient descent. The √d_k is there because the dot product of two independent
d_k-dimensional vectors with unit-variance components has variance d_k (Problem 2); at
d_k = 64 unscaled scores have standard deviation 8, the softmax saturates to one-hot, and
the gradient through it vanishes before training has started. Written for the whole
sequence at once, Attention(Q, K, V) = softmax(QKᵀ / √d_k) V, which is two matrix
multiplications and a row-wise softmax, and that is why it parallelises.

**Self-attention, cross-attention, causal masking and heads are variations on where Q,
K and V come from.** In self-attention all three come from the same sequence; in
cross-attention the queries come from one sequence (the decoder) and keys and values from
another (the encoder), which is how a translation model reads its source. A causal mask
sets the scores for j > i to −∞ before the softmax so position i cannot see the future,
and it is what makes a decoder a language model that can be trained on every position of
a sequence in parallel. Multi-head attention runs h attention functions in parallel on
h projections of dimension d_model / h and concatenates the outputs. What heads buy is
the ability to attend to several things at once with one softmax each, since a single
softmax must choose one mixture; in trained models individual heads specialise to previous
token, syntactic dependency, or copying, and many are redundant and prunable.

**Attention is permutation-invariant, so position must be injected.** With no positional
signal, a transformer is a set function over tokens and cannot tell "dog bites man" from
"man bites dog". Sinusoidal encodings add fixed sin and cos features of the position at
geometrically spaced frequencies; learned absolute embeddings are a table of size context
× d_model and cannot extend past the context length. RoPE rotates each pair of dimensions
of q and k by an angle proportional to the position, so that the dot product of a rotated
query and key depends only on their relative offset (Problem 7), which gives relative
position with no extra parameters and degrades gracefully somewhat past the training
length. ALiBi drops positional embeddings entirely and subtracts a linear penalty on
distance from the attention scores, which extrapolates further. Lab 9.6 shows that a
causal decoder with no positional encoding at all still learns some position from the
mask.

**A transformer block is attention plus an MLP, each wrapped in a residual connection and
a normalisation, and where you put the normalisation matters.** The block computes
x ← x + Attn(LN(x)) then x ← x + MLP(LN(x)) in the pre-LN arrangement, where the MLP
expands to 4·d_model with a GELU and projects back. The original paper put LayerNorm after
the residual sum (post-LN), which trains fine at 6 layers with warmup and diverges at
depth without it; Xiong et al. showed that pre-LN keeps gradient scale even across layers
and is why every modern model uses it. Dropout, when used, goes on the attention weights,
on each residual branch's output and on the embeddings. Parameter counting is mechanical
and you should be able to do it in your head: attention has 4·d_model² weights per layer,
the MLP 8·d_model², so about 12·d_model² per layer, plus vocab × d_model for the tied
embedding. Problem 4 does GPT-2 small and lands on 124 million.

**Three families, three uses.** Encoder-only models (BERT) see the whole sequence
bidirectionally and are trained with masked prediction, which makes them the right tool
for classification, tagging and embeddings, and useless for generation. Decoder-only
models (GPT) are causal and trained on next-token prediction, which makes them generators
and, it turned out, general-purpose learners once large enough. Encoder-decoder models
(T5, the original transformer) read with one stack and write with another joined by
cross-attention, which is natural for translation and summarisation, and has largely been
displaced by decoder-only models that treat the input as a prefix. Module 10 fine-tunes
one of the first kind and prompts and adapts the second.

**Training a transformer is Module 5's craft with three extra rules.** AdamW with β₂
around 0.95 rather than 0.999, weight decay on matrices but not on biases or norms, a
linear warmup over the first few hundred to few thousand steps then cosine decay to a
tenth of the peak, and gradient clipping at norm 1.0 are the defaults. Batch size is
measured in tokens, not sequences, and half a million tokens per step is normal at scale.
Tying the input embedding to the output softmax saves vocab × d_model parameters and
helps small models. Residual branch outputs are initialised with standard deviation
scaled by 1/√(2L) for L layers, so the residual stream's variance does not grow with
depth. Get warmup wrong and the loss spikes early; get initialisation wrong and it
plateaus; get the batch too small and it is noisy for no gain.

**Generation is a loop over the model, and the KV cache is what makes it affordable.**
Greedy decoding takes the argmax each step and repeats itself; sampling with temperature
τ divides the logits by τ before the softmax, sharpening below one and flattening above;
top-k restricts to the k most likely tokens and top-p to the smallest set whose mass
exceeds p, both to cut off the long tail where nonsense lives; a repetition penalty
down-weights tokens already emitted. Without a cache, generating token n means running the
whole prefix through every layer again, so the cost of a sequence is quadratic in its
length. The cache stores each layer's K and V for every previous token, so the new token
computes its own q, k, v, appends k and v, and attends over the stored ones: O(n) per
token. The cost moves from compute to memory, 2 × layers × heads × head_dim × 2 bytes per
token in fp16 (Problem 6), and at long contexts the cache is bigger than the weights.

**The quadratic cost is real, and FlashAttention attacks it without changing the maths.**
Computing QKᵀ for a sequence of n tokens is O(n²·d) in time and, naively, O(n²) in memory
to hold the attention matrix. FlashAttention observes that the bottleneck on a GPU is
memory bandwidth rather than arithmetic, tiles the computation so that blocks of Q, K and
V stay in fast on-chip memory, computes the softmax incrementally with a running maximum
and sum, and never writes the n × n matrix to main memory. It is exact attention, two to
four times faster and linear in memory, and it is why 8k and 32k contexts became
ordinary. PyTorch exposes it through `torch.nn.functional.scaled_dot_product_attention`,
which picks a fused kernel where one exists.

**Scaling laws turned model sizing from taste into arithmetic.** Kaplan et al. found that
loss falls as a power law in parameters, data and compute over many orders of magnitude,
and read it as "make models bigger". Hoffmann et al. reran the experiment with learning
rate schedules matched to the training length and found the optimum for a fixed compute
budget scales parameters and tokens together, at roughly 20 tokens per parameter, so a
70B model wants about 1.4 trillion tokens. The compute estimate behind both is
C ≈ 6ND FLOPs for N parameters and D tokens: 2 per parameter for the forward pass, 4 for
the backward (Problem 5). Inference costs about 2N per token. These are the numbers you
use to sanity-check any claim about training cost, and Lab 9.5 fits the power law on a
laptop.

**Mixture-of-experts and state-space models are the two departures you will hear about.**
A mixture-of-experts layer replaces the MLP with several MLPs and a router that sends each
token to one or two of them, so parameters grow with the number of experts while compute
per token does not; it buys capacity per FLOP at the cost of memory, load balancing and
serving complexity, and it is how many frontier models are built. State-space models such
as Mamba return to recurrence with a state that is updated by a learned, input-dependent
linear map, giving linear time in sequence length and constant memory per step; they match
transformers at small scale on language and are strong on very long sequences, and hybrid
architectures interleave both. Know what each trades and you can follow the Oxford LLM
course's architecture week without notes.

**Forward links.** Module 10 fine-tunes an encoder for intent classification, applies LoRA
to the attention projections you wrote here (which is why you need to know their shapes),
and builds retrieval-augmented generation, where the context window and the KV cache
decide what fits. Module 13 costs a served model in memory, and the KV cache from Lab 9.4
is the line item that grows with every concurrent user.

## Reading

- Vaswani et al., "Attention Is All You Need", 2017. Read all of it; it is eleven pages
  and you will have written most of it by the end of Lab 9.4.
- Karpathy, "Let's build GPT: from scratch, in code, spelled out" and "Let's build the
  GPT Tokenizer" (videos, free). Watch each after your own attempt at Labs 9.4 and 9.3
  respectively, then read the nanoGPT repository and diff it against your model.
- Alammar, "The Illustrated Transformer" (blog, free), as the picture to hold while
  deriving.
- Jurafsky and Martin, *Speech and Language Processing*, 3rd ed. draft (free), ch. 3
  (n-gram language models), ch. 8 and 9 (RNNs and LSTMs; transformers) and ch. 10 (large
  language models).
- Radford, Narasimhan, Salimans and Sutskever, "Improving Language Understanding by
  Generative Pre-Training", 2018; Radford et al., "Language Models are Unsupervised
  Multitask Learners", 2019. Devlin, Chang, Lee and Toutanova, "BERT", 2018. Raffel et
  al., "Exploring the Limits of Transfer Learning with a Unified Text-to-Text
  Transformer", 2020 (T5; skim sections 1 to 3).
- Sennrich, Haddow and Birch, "Neural Machine Translation of Rare Words with Subword
  Units", 2016 (BPE).
- Su et al., "RoFormer: Enhanced Transformer with Rotary Position Embedding", 2021. Press,
  Smith and Lewis, "Train Short, Test Long: Attention with Linear Biases Enables Input
  Length Extrapolation", 2021 (ALiBi).
- Xiong et al., "On Layer Normalization in the Transformer Architecture", 2020.
- Kaplan et al., "Scaling Laws for Neural Language Models", 2020; Hoffmann et al.,
  "Training Compute-Optimal Large Language Models", 2022 (Chinchilla). Read the second
  one's section 3 with a pen.
- Dao, Fu, Ermon, Rudra and Ré, "FlashAttention: Fast and Memory-Efficient Exact Attention
  with IO-Awareness", 2022, sections 1 to 3.
- Hochreiter and Schmidhuber, "Long Short-Term Memory", 1997, for the original argument
  about the gradient. Gu and Dao, "Mamba: Linear-Time Sequence Modeling with Selective
  State Spaces", 2023, abstract and figure 1 only.
- Bishop and Bishop, *Deep Learning: Foundations and Concepts* (free), ch. 12
  (transformers). Prince, *Understanding Deep Learning* (free), ch. 12 (transformers).

## Labs

All training runs use your `common/` harness and log to the MLflow experiment
`09-transformers`. Tiny Shakespeare is at `data/text/tinyshakespeare.txt` (about 1.1
million characters, 65 distinct); the TinyStories sample is the 2 percent split cached by
Module 0 under `data/hf`, from which you take the first 20 MB of text. Run `uv sync
--group llm` before Lab 9.3.

### Lab 9.1: Baselines on Tiny Shakespeare

Goal: know the numbers a transformer has to beat, and what an LSTM already achieves.

1. Split the file into the first 90 percent for training and the last 10 percent for
   validation. In `09-transformers/ngram.py` implement a bigram character model and a
   5-gram character model with add-k smoothing (tune k on validation) or interpolated
   Kneser-Ney if you want the real thing. Report validation cross-entropy in nats per
   character and perplexity. Expect roughly 2.5 nats for the bigram and roughly 1.9 to
   2.2 for the smoothed 5-gram.
2. Implement a two-layer LSTM character model with hidden size 512 in
   `09-transformers/lstm.py`, trained with truncated BPTT over windows of 256 characters,
   batch 64, AdamW 1e-3, gradient clipping at 1.0, dropout 0.2 between layers. Train for
   about 20 minutes on MPS and record the validation loss curve.
3. Sample 500 characters from the LSTM at temperature 0.8 and from the 5-gram model.
   Paste both into the notebook.

Done when: the n-gram numbers are in a table with perplexities; the LSTM reaches a
validation loss of roughly 1.5 nats per character or better; and the two samples are in
the notebook with one sentence on what the LSTM gets right that the n-gram cannot.

### Lab 9.2: Attention in NumPy

Goal: own the forward pass before PyTorch hides it.

1. In `09-transformers/attention.py` implement `scaled_dot_product_attention(q, k, v,
   mask=None)` and `multi_head_attention(x, w_qkv, b_qkv, w_out, b_out, n_heads,
   causal=False)` in NumPy, forward only, with a causal mask built from
   `np.triu` and applied as −∞ before the softmax. Use a numerically stable softmax.
2. Write `test_attention.py`: create `torch.nn.MultiheadAttention(embed_dim=64,
   num_heads=4, batch_first=True)`, copy its `in_proj_weight`, `in_proj_bias`,
   `out_proj.weight` and `out_proj.bias` into your function, run both on random input of
   shape (2, 16, 64) with and without `is_causal`-style masking (pass an explicit
   `attn_mask` to the PyTorch module), and assert the outputs agree to 1e-5. Also return
   your attention weights and compare to `need_weights=True, average_attn_weights=False`.
3. Build a toy copy task: sequences of 12 random symbols from a vocabulary of 10, and a
   target that repeats them. Train a single-layer, single-head attention model in
   PyTorch to solve it and plot the attention weight matrix for one example. It should
   show a shifted diagonal.

Done when: `test_attention.py` passes under pytest for both masked and unmasked cases, and
the attention-map figure from the copy task is in the notebook.

### Lab 9.3: BPE from scratch

Goal: a tokeniser you trained, and a measurement of what it does to the text.

1. In `09-transformers/bpe.py` implement `train_bpe(text, vocab_size)` at byte level:
   pre-split on whitespace and punctuation with a regular expression in the style of
   GPT-2's, count adjacent byte pairs within each chunk, merge the most frequent, repeat
   until the vocabulary reaches 4,096 including the 256 base bytes. Store the merge list
   in order. Implement `encode(text)` applying merges by rank and `decode(ids)`; write
   the merges and vocabulary to JSON.
2. Train on the 20 MB TinyStories sample. Time the training; a straightforward
   implementation that recounts pairs on every merge is slow, and you should be able to
   say why and make it faster by updating counts incrementally.
3. `test_bpe.py`: round-trip on 1,000 random stories including non-ASCII characters;
   check that every id is below 4,096; check that encoding a string is deterministic.
4. Compare with `tiktoken.get_encoding("gpt2")` on a 1 MB held-out slice: bytes per token
   for each (yours should land somewhere around 3.5 to 4.5, and gpt2's is roughly 4 to 5
   on this kind of English), and the fraction of your vocabulary whose byte strings also
   appear in gpt2's 50,257 tokens.
5. Tokenise "12345 + 67890 = 80235" and "The word 'strawberry' has three r's" with both
   tokenisers and print the pieces. This is Skip test question 6 made concrete.

Done when: `test_bpe.py` passes; training on 20 MB completes in under a few minutes after
your optimisation; the bytes-per-token and overlap numbers are in the notebook; and the
two tokenised examples are pasted in with a sentence each.

### Lab 9.4: GPT from an empty file (headline lab)

Goal: a decoder-only transformer you wrote, trained on two corpora, with generation and a
KV cache that you measured.

1. In `09-transformers/gpt/model.py` write `GPTConfig` (vocab_size, block_size, n_layer,
   n_head, d_model, dropout) and `GPT`: token embedding, learned position embedding,
   `n_layer` pre-LN blocks each with `CausalSelfAttention` (one fused qkv linear, heads
   split by reshape, `scaled_dot_product_attention` with `is_causal=True`, output
   projection) and an MLP with 4× expansion and GELU, a final LayerNorm, and an output
   head tied to the token embedding. Initialise linear and embedding weights with std
   0.02 and scale the two residual projections per block by 1/√(2·n_layer). Print the
   parameter count.
2. Character config on Tiny Shakespeare: 6 layers, 6 heads, d_model 384, context 256,
   batch 64, dropout 0.2, AdamW 6e-4 with β₂ = 0.95, weight decay 0.1, 100 warmup steps
   then cosine to 6e-5, gradient clipping 1.0, fp16 autocast, 5,000 iterations. About 10.6
   million parameters. Expect a validation loss of roughly 1.45 to 1.50 nats per character
   in roughly 15 to 30 minutes on MPS. Compare with Lab 9.1's LSTM.
3. BPE config on the TinyStories sample tokenised with your Lab 9.3 tokeniser: 8 layers,
   8 heads, d_model 512, context 512, batch 32 sequences (16k tokens per step), same
   optimiser settings, as many iterations as fit in an hour. About 27 million parameters.
   Report validation loss in nats per token and as perplexity, and note that it is not
   comparable to the character number.
4. In `09-transformers/gpt/generate.py` implement `generate(model, idx, max_new_tokens,
   temperature, top_k)`. Sample 300 tokens from each model at temperatures 0.5, 0.8 and
   1.2 with top-k 40 and paste the outputs.
5. Add a KV cache: give `CausalSelfAttention` an optional cache of (k, v) per layer that
   is appended to on each step, and a `forward` path that accepts one new token plus the
   cache. Check that cached and uncached generation produce identical tokens under greedy
   decoding.
6. Measure tokens per second generating 512 tokens from a 1-token prompt with and without
   the cache, batch size 1 and batch size 16, on MPS. Expect a several-fold speedup that
   grows with sequence length. Plot per-token latency against position for both paths.

Done when: `test_gpt.py` checks the parameter count against a hand formula, that a forward
pass on random tokens returns logits of the right shape, that the loss at initialisation
is near ln(vocab_size), and that cached and uncached greedy generation match; the
character model's validation loss is at or below 1.50; both models' samples are in the
notebook; and the KV-cache latency plot shows the uncached path growing with position
while the cached path stays flat.

### Lab 9.5: A scaling mini-study

Goal: see a power law come out of your own runs, and understand why Chinchilla lands
where it does.

1. Define three character-model configs on Tiny Shakespeare of roughly 1M (4 layers,
   d_model 144), 3M (4 layers, d_model 256) and 10M (Lab 9.4) parameters, with heads chosen
   so the head dimension is an integer (6 for 144 and 384, 8 for 256), context 256.
2. Train each at three token budgets, roughly 5M, 15M and 50M training tokens (adjust the
   iteration count; batch 64 × 256 is 16,384 tokens per step), with cosine decay matched
   to each run's length. That is nine runs; the small ones take minutes and the largest
   about half an hour on MPS.
3. Compute compute C = 6ND for each run and plot validation loss against C on log-log axes,
   one line per model size. Fit L(C) = a·C^(−b) + c to the lower envelope by least squares
   and report b.
4. For each budget, mark which model size gave the lowest loss, and plot the implied
   tokens-per-parameter at the optimum. Discuss in a paragraph why a fixed budget should
   split between N and D rather than go all to one, and why Chinchilla's schedule-matched
   runs moved the answer from Kaplan's to about 20 tokens per parameter.

Done when: the nine runs are in MLflow, the log-log figure with the fit is in the
notebook with the fitted exponent, and the discussion paragraph is written.

### Lab 9.6: Positional encoding ablation

Goal: test what position information buys, and what a causal model learns without it.

1. Add a `pos_encoding` option to `GPT`: `none`, `learned` (the default from Lab 9.4),
   `sinusoidal`, and `rope`. Implement RoPE in `09-transformers/rope.py` as a function
   that rotates q and k in pairs of dimensions with frequencies 10000^(−2i/d_head), and
   test that the dot product of rotated vectors at positions (m, n) equals that at
   (m + s, n + s) to 1e-5.
2. Train the 10M character model with each option for 3,000 iterations at context 256.
   Report validation loss for all four.
3. Evaluate each model on validation sequences of length 512, twice the training
   context (disable the block-size assertion for evaluation; `learned` will need its
   table extended or evaluated only to 256). Plot mean loss against token position from 0
   to 511 for each model.
4. Check the claim that a causal decoder with no positional encoding still learns
   position: it should beat a bigram baseline convincingly and trail `learned` by a
   modest margin at 256, because the causal mask leaks position through how many tokens
   each position can attend to.

Done when: the RoPE test passes under pytest; the four validation losses are in a table;
the loss-against-position figure is in the notebook; and one paragraph states which
encoding extrapolates best and why.

## Problem set

1. Show that minimising the expected per-token cross-entropy E_{x~p}[−log q(x)] over q is
   equivalent to minimising KL(p ‖ q), and that perplexity is exp of the per-token
   cross-entropy. What is the perplexity of a uniform model over |V| tokens, and what does
   a validation perplexity below the training perplexity tell you?
2. Let q and k have d independent components each with mean zero and variance one. Show
   Var(q·k) = d. For d = 64 and d = 512, give the standard deviation of the unscaled
   scores and use the softmax gradient ∂softmax_i/∂s_j = p_i(δ_ij − p_j) to argue why the
   gradient vanishes when one score is several standard deviations above the rest.
3. With A = softmax(S) row-wise and O = AV, derive ∂L/∂V and ∂L/∂S given ∂L/∂O. Check your
   ∂L/∂S against `torch.autograd` on a 3 × 3 example.
4. Count GPT-2 small's parameters from its architecture: 12 layers, d_model 768, 12
   heads, vocabulary 50,257, context 1,024, tied embeddings, LayerNorm with bias.
   Separate the attention, MLP, embedding and normalisation totals and arrive at
   roughly 124 million.
5. Derive C ≈ 6ND for training: 2 FLOPs per parameter per token forward (one multiply,
   one add) and twice that backward. Then derive 2N per token for inference. Compute the
   training FLOPs for a Chinchilla-optimal 10B-parameter model and how long it takes on
   1,000 GPUs sustaining 300 TFLOP/s each.
6. Compute the KV cache size per token per layer for a model with 32 heads of dimension
   128 in fp16, then the total for 32 layers at 8,192 tokens of context. Compare with the
   14 GB of weights for the 7B model this describes. What does that imply for the number
   of concurrent users a single 80 GB GPU can serve at that context?
7. RoPE rotates each 2-dimensional pair of q at position m by angle mθ_i, and likewise k
   at position n. Show that (R_m q)·(R_n k) = qᵀ R_{n−m} k, so the score depends on n − m
   only. Explain why applying the rotation to v would break the argument.
8. Write the gradient of the LSTM cell state c_t with respect to c_{t−k} through the
   additive update, and compare it with the gradient through k residual connections
   x_{l+1} = x_l + f(x_l). What does each need to be near one, and which is easier to
   maintain?
9. A causal model's attention weights at position t form a distribution over t entries.
   Explain what this forces at t = 1, and why in trained models the first token often
   receives a large share of attention from later positions even when it carries no
   information (the attention sink). What does this suggest about removing the first
   tokens of a long conversation to save cache memory?

## Deliverables

- `09-transformers/ngram.py`, `lstm.py`, `attention.py` with `test_attention.py`, `bpe.py`
  with `test_bpe.py`, `rope.py` with its test.
- `09-transformers/gpt/model.py`, `train.py`, `generate.py`, `configs/` and `test_gpt.py`.
- Notebook with the baseline table, the attention map, the tokeniser comparison, both
  models' samples at three temperatures, the KV-cache latency plot, the scaling figure
  with its fitted exponent and the positional-encoding table and figure.
- Write-up on the GPT and scaling work, following `writeup-template.md`, framed as a
  recommendation on how large a model to train for a fixed compute budget on a given
  corpus. The Limitations section should engage with the fact that character-level loss
  on 1.1 million characters is not the regime scaling laws were fitted in, and with what
  a nine-run fit can and cannot support.

## Stretch

- Wrap the Lab 9.4 training step in `torch.compile` and measure step time on MPS with and
  without it; then run the same script on a Colab T4, where
  `scaled_dot_product_attention` selects the Flash kernel, and compare.
- Train a small encoder with the masked language modelling objective on TinyStories (mask
  15 percent, predict the masked tokens) using the Lab 9.4 blocks without the causal mask,
  and compare its mean-pooled embeddings to the GPT's on a nearest-neighbour sentence
  retrieval task. This is the bridge to Module 10's encoder fine-tuning.
- Implement a two-expert mixture-of-experts MLP with a top-1 router and a load-balancing
  loss in one block of the 10M model and check whether it improves loss per FLOP.
- Read the `mamba_ssm` selective-scan description and implement a minimal diagonal
  state-space layer in PyTorch; train it as a drop-in for attention in the 1M model and
  compare loss at equal parameters.

## Next

Module 10 puts this module's architecture to work: fine-tuning an encoder for intent
classification on Banking77, adapting a 0.5B decoder with LoRA on the attention projections
whose shapes you now know, and building a retrieval-augmented system whose context budget
is the KV cache you just measured. The theory is done; what remains is knowing which
knob to turn.
