#import "../lib/template.typ": *

= Attention <ch-attention>

#chapter-meta(
  time: [6 hours],
  builds: [Scaled dot-product attention derived as a soft dictionary lookup and written in NumPy, with causal masking and multiple heads, matched to PyTorch's fused kernel; attention assembled from `tiny`'s operations, its gradients matched too; the reason for the $1 \/ sqrt(d)$ scale, measured; and a small transformer that learns to copy, with its attention drawn.],
  needs: [Chapters 1.2 and 2.2.],
)

#why[
  Chapter 2.2's neural model could see eight tokens back and no further, so a story's heroine, introduced in the first sentence, was invisible to it by the third. _Attention_ removes the window. It lets every position gather information from every earlier position, with weights computed from what those positions contain, so a model can look up the name it needs wherever it was mentioned. It is the central operation of the transformer, and so of every modern language model, and this chapter builds it from its definition.
]

#skip-test(
  rule: [If all four are easy, read the sections on scale and on learned attention, and do Labs 2.3.2 and 2.3.3.],
  [Write attention for queries $Q$, keys $K$ and values $V$, giving the shape of each tensor and of the result for a sequence of length $T$.],
  [Why are the attention scores divided by $sqrt(d)$?],
  [What does a causal mask do, and how is it applied before the softmax?],
  [What can eight heads of size 64 do that one head of size 512 cannot?],
)

== Core ideas

=== A soft dictionary

A dictionary maps keys to values: given a query, find the key that equals it and return its value. Attention makes every part of that soft. Each position $j$ of a sequence has a _key_ vector $k_j$ and a _value_ vector $v_j$. A position $i$ forms a _query_ $q_i$, scores every key by its dot product with the query, turns the scores into weights with a softmax, and receives the weighted average of the values:

$ "out"_i = sum_j a_(i j) v_j, quad a_(i j) = exp(q_i dot k_j \/ sqrt(d)) / (sum_(j') exp(q_i dot k_(j') \/ sqrt(d))). $

A query that closely matches one key retrieves almost only that key's value, and one that matches several retrieves a blend. Because every step is differentiable, the model can learn what to put in queries, keys and values. Stacking the vectors as rows of matrices gives the whole computation in three matrix operations:

$ "Attention"(Q, K, V) = "softmax"((Q K^T) / sqrt(d)) V, $

with $Q$ of shape $T times d$, $K$ and $V$ of shape $T times d$, the score matrix $T times T$, and the result $T times d$. In _self-attention_ the queries, keys and values are all computed from the same sequence by three learned linear maps, $Q = X W_Q$, $K = X W_K$, $V = X W_V$.

=== Causal masking

A language model predicts each token from the tokens before it, so position $i$ must not see positions after it, or training would teach it to copy the answer. A _causal mask_ sets the scores above the diagonal to $-infinity$ before the softmax, making their weights exactly zero:

#snippet("u2/attention.py", "numpy", caption: [Attention in NumPy, with an optional causal mask])

All positions are still computed at once: one pass over a sequence of $T$ tokens produces $T$ predictions, each using only its own past, which is what makes training on whole sequences efficient.

=== Multiple heads

A single attention computes one set of weights per position. _Multi-head attention_ splits the $d$ dimensions into $H$ heads of $d \/ H$ dimensions each, runs attention independently in each, and concatenates the results before a final linear map, $W_O$. Each head can attend to something different: one to the previous token, one to the subject of the sentence, one to the matching quotation mark. The cost is the same as one head of the full width.

#snippet("u2/attention.py", "heads", caption: [Multi-head causal self-attention for one sequence])

PyTorch provides attention as one fused operation, `scaled_dot_product_attention`, which this course's transformer uses:

#snippet("u2/attention.py", "torch", caption: [The same computation with PyTorch's kernel])

#console-part("/src/console/u2-attention.txt", to: 3, caption: [NumPy against PyTorch, and `tiny`'s gradients against PyTorch's])

The second line checks the gradients. Attention is built from operations `tiny` already has (matrix products, a transpose, a softmax written as the exponential of `log_softmax`, and an additive mask), so Chapter 1.2's engine differentiates it without any new rule, and its gradients agree with PyTorch's to within float64 rounding error.

=== Why divide by the square root of the dimension

If the entries of $q$ and $k$ are independent with unit variance, their dot product is a sum of $d$ terms of unit variance, with standard deviation $sqrt(d)$. For $d = 64$ the scores spread over a range of about $plus.minus 16$, and a softmax of numbers that far apart puts nearly all the weight on the largest. The softmax is then _saturated_: the gradient through it is nearly zero, and the model cannot learn which keys to prefer. Dividing by $sqrt(d)$ restores unit variance whatever the dimension:

#snippet("u2/attention.py", "scale", caption: [The largest attention weight among 128 keys, with and without the scale])

#console-part("/src/console/u2-attention.txt", from: 3, command: false, caption: [Unscaled attention saturates as the dimension grows])

=== What attention costs

The score matrix has $T^2$ entries per head. Computing it takes $2 T^2 d$ FLOPs per head in total, and the weighted sum as many again, so attention's cost grows with the square of the sequence length, while everything else in a transformer grows linearly. At the 512 tokens of this unit's models the quadratic term is small, and at 100,000 tokens it dominates. Storing the matrix for the backward pass also costs memory quadratic in $T$, which Chapter 4.4's FlashAttention avoids by never storing it.

Attention also takes no account of order. Permuting the keys and values permutes the weights to match and leaves the output unchanged, so attention itself carries no information that position 3 comes before position 4. Chapter 2.4 adds that information with rotary position embeddings.

=== Attention, learned

To see what attention learns, the program trains a small transformer, Chapter 2.4's model shrunk to 64 dimensions, on a task that needs it: a sequence of 16 random tokens followed by the same 16 again. The first half is unpredictable, and each token of the second half can be predicted exactly. At a position in the second half, the next token is the one that followed the current token's earlier occurrence, 16 positions back, and so sits 15 positions back. Attending there and copying the token found solves the task.

#snippet("u2/copy_task.py", "task", caption: [Random tokens, repeated; only the repeat is scored])

#snippet("u2/copy_task.py", "model", caption: [A two-layer transformer trained on the task])

#console(read("/src/console/u2-copy.txt"), caption: [The model learns to copy, and its last layer attends 15 positions back])

#fig("u2-copy", caption: [Attention weights of the last layer's two heads for one sequence. In the second half, each position attends to the position 15 tokens earlier, which appears as the bright diagonal.]) <fig-copy>

The trained model copies the repeated half without error. In the second half, both heads of its last layer put 98% of their weight on the position 15 tokens back (@fig-copy). A one-layer model trained the same way gets about three quarters right. Lab 2.3.2 asks you to find out why, and Chapter 2.8 finds the same two-layer mechanism, the _induction head_, inside the model that Chapter 2.5 trains on stories.

#keyidea[
  Attention is a differentiable lookup: queries are scored against keys, the scores become weights by a softmax, and the result is a weighted average of values. The causal mask restricts each position to its past, as a language model requires. The $1 \/ sqrt(d)$ scale keeps the softmax from saturating, and the cost grows with the square of the sequence length.
]

#inpytorch[
  `F.scaled_dot_product_attention(q, k, v, is_causal=True)` computes this chapter's attention for tensors of shape (batch, heads, length, head size) and picks the fastest kernel for the device: FlashAttention on recent NVIDIA GPUs, and a Metal kernel on MPS. Its `attn_mask` takes either a boolean mask, `True` where attention is allowed, or an additive one. `torch.nn.MultiheadAttention` wraps the projections as well, with a different layout, and this course writes its own.
]

#reading(
  [Dzmitry Bahdanau, Kyunghyun Cho and Yoshua Bengio, "Neural Machine Translation by Jointly Learning to Align and Translate", ICLR 2015: attention's origin.],
  [Ashish Vaswani and others, "Attention Is All You Need", NeurIPS 2017, section 3.2.],
  [Nelson Elhage and others, "A Mathematical Framework for Transformer Circuits", Anthropic, 2021: attention heads as readers and writers of a residual stream.],
)

== Labs

#lab([Attention by hand], goal: [Compute attention on paper for a sequence of three positions.], time: [1 hour], code: "code/u2/attention.py")[
  + Choose three positions with two-dimensional queries, keys and values of your own. Compute the causal attention output by hand, without the scale.
  + Check your numbers with `attention()`, after removing its scale or multiplying your queries by $sqrt(2)$.
  #done-when(
    [Your hand computation matches the program to three decimal places.],
  )
  #evidence([The working and the program's output.])
]

#lab([One layer against two], goal: [Find out why a one-layer model copies poorly.], time: [2 hours], code: "code/u2/copy_task.py")[
  + Train the copy task with `--layers 1` and `--layers 2`, three seeds each with `--seed`, and record the accuracies.
  + Draw the attention of every head of every layer for one sequence in each case.
  + Describe what the first layer of the two-layer model does, and why the one-layer model cannot easily do the same.
  #done-when(
    [Your table has six accuracies and your figures show every head.],
    [Your explanation names what information the second layer needs and where it comes from.],
  )
  #evidence([The table, the figures and the explanation.])
]

#lab([Without the scale], goal: [Measure how saturation slows learning.], time: [1 hour], code: "code/u2/copy_task.py")[
  + Patch the model's attention to omit the $1 \/ sqrt(d)$ scale; the simplest way is to multiply the queries by $sqrt(d)$ before calling the kernel.
  + Train the copy task with and without the patch and plot the loss curves, with heads of 32 and of 128 dimensions.
  #done-when(
    [You have four loss curves.],
    [You can say how much the missing scale slowed learning at each head size, and why the effect grows with the size.],
  )
  #evidence([The plot and a paragraph.])
]

#lab([The quadratic cost], goal: [Measure attention's time and memory against sequence length.], time: [1 hour], code: "code/u2/attention.py")[
  + Time materialised causal attention, as in `attention()` but in PyTorch on your device, for 8 heads of 64 dimensions and lengths from 256 to 8,192, and record the peak memory.
  + Time `scaled_dot_product_attention` at the same lengths.
  + Fit the times to $a T^2$ and say at what length attention would take as long as the rest of a layer of Chapter 2.5's model.
  #done-when(
    [Your table and plot cover at least six lengths for both implementations.],
    [Your fitted constant predicts the 8,192 measurement within 20%.],
  )
  #evidence([The table, the plot and the prediction.])
]

#problems(
  [Show that permuting the keys and values together, with the same permutation, leaves the output of non-causal attention unchanged.],
  [Count the FLOPs of causal multi-head attention for $T = 512$, $d = 512$ and 8 heads, separately for the projections and for the scores and weighted sum.],
  [If every key is identical, what does attention output, whatever the queries? What if every query is zero?],
  [Why does setting masked scores to $-infinity$ give exactly zero weight, while setting them to $-10^9$ gives nearly zero? When could the difference matter?],
  [A head always attends to the previous position. Write down queries and keys, using a position-dependent component, that would produce that pattern.],
)

#checklist(
  [I can derive attention as a soft lookup and give the shape of every tensor in it.],
  [I can implement causal multi-head attention and check it against PyTorch.],
  [I can explain the $1 \/ sqrt(d)$ scale and the quadratic cost.],
  [I can read an attention pattern and say what a head is doing.],
  [Lab 2.3.1–2.3.4 done-when criteria all hold, with evidence filed.],
)
