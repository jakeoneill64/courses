#import "../lib/template.typ": *

= Next-token prediction <ch-ngrams>

#chapter-meta(
  time: [6 hours],
  builds: [Unigram to 5-gram models with interpolated Kneser–Ney smoothing, counted from 100 million tokens in a few minutes; perplexity and bits per byte computed properly; samples that show what n-grams can and cannot do; and Bengio's neural language model, which beats the best of them with a context of eight tokens.],
  needs: [Chapter 2.1, and Chapter 1.3's cross-entropy.],
)

#why[
  A language model is a probability distribution over the next token given the ones before it, nothing more. The simplest such models count how often each token follows each context, and they are worth building for three reasons: they are the baseline every neural model must beat, they make the measures of language modelling, perplexity and bits per byte, concrete, and their failure, that most contexts are never seen in training, is exactly the problem that neural networks solve by learning which contexts are alike.
]

#skip-test(
  rule: [If all four are easy, read the section on Kneser–Ney and do Labs 2.2.3 and 2.2.4.],
  [Write the probability of the sentence "the cat sat" as a product of conditional probabilities, and say what a bigram model assumes about it.],
  [Why does a trigram model estimated by counting need smoothing, and what does Kneser–Ney smoothing do that adding one to every count does not?],
  [A model's cross-entropy is 2.5 nats per token. What is its perplexity, and its bits per byte at 4.16 bytes per token?],
  [Why compare models with different tokenisers in bits per byte instead of per token?],
)

== Core ideas

=== The chain rule

The probability of a sequence of tokens factorises exactly into conditional probabilities, one per token:

$ P(x_1, dots, x_n) = product_(t=1)^n P(x_t | x_1, dots, x_(t-1)). $

A language model is any way of estimating those conditionals. Training one means maximising the probability of real text, which by Chapter 1.3 means minimising the cross-entropy of each token given its predecessors, averaged over the corpus. Generating text means sampling from the conditionals one token at a time, each sample becoming part of the next context.

=== Measuring a language model

The cross-entropy per token, in nats, is the basic measure. Its exponential is the _perplexity_: a model with perplexity 20 is, on average, as uncertain about the next token as a uniform choice among 20. Both depend on the tokeniser: a tokeniser with longer tokens makes each token harder to predict and needs fewer of them. Dividing the cross-entropy by $ln 2$ and by the average bytes per token gives _bits per byte_, a measure that compares models with any tokeniser on the same text. It is also the size an ideal compressor using the model would achieve: a model at 0.5 bits per byte could store TinyStories in a sixteenth of its size.

=== N-gram models

An _n-gram_ model assumes that the next token depends only on the previous $n - 1$: a _bigram_ model looks back one token, a _trigram_ model two. Its maximum-likelihood estimate is a ratio of counts, $P(w | h) = c(h w) \/ c(h)$, where $h$ is the context and $c$ counts occurrences in the training text. The trouble is that most contexts of more than a few tokens never occur in training, and of those that do, most continuations were never seen after them. A raw count assigns those probability zero, and a single zero makes the probability of a whole test text zero and its cross-entropy infinite.

_Smoothing_ moves probability from seen to unseen events. Adding one to every count is the simplest scheme and works badly, because it gives every unseen continuation as much weight as a continuation seen once. _Absolute discounting_ subtracts a fixed amount $D$, typically 0.75, from every nonzero count and redistributes the total through a lower-order model:

$ P(w | h) = max(c(h w) - D, 0) / c(h) + (D dot N_(1+)(h dot)) / c(h) dot P(w | h'), $

where $h'$ is the context shortened by one token and $N_(1+)(h dot)$ counts the distinct tokens seen after $h$, so that contexts followed by many different tokens give more weight to the lower order. _Kneser–Ney_ smoothing changes what the lower orders count. In TinyStories "named" is frequent, but almost always after "girl" or "boy" in "a little girl named"; a unigram model built from raw counts would predict "named" in any unfamiliar context. Kneser–Ney's lower orders count instead how many _different_ contexts a token follows, its _continuation count_, so a token that is common only in one context gets little weight when that context is absent.

=== Counting at scale

Counting 5-grams with Python dictionaries over 100 million tokens would take hours and tens of gigabytes. Since the vocabulary has 8,192 tokens, 13 bits each, up to four tokens pack into one 64-bit integer, and NumPy can sort and count a hundred million of those in seconds. A 5-gram needs 65 bits, one too many, so every n-gram is kept as a pair: the integer for its context of up to four tokens, and the token that follows. Counting pairs takes two sorts, one to number the distinct contexts and one to count each context's continuations:

#snippet("u2/ngram.py", "keys", caption: [Runs of tokens as integers, and n-grams as counted (context, token) pairs])

#snippet("u2/ngram.py", "kneser-ney", caption: [Interpolated Kneser–Ney: continuation counts below the top order, and discounting and interpolation at every order above the first])

Each order's table holds the sorted contexts, with each one's total count and number of distinct continuations, and the sorted pairs with their counts; looking up a whole validation set is two vectorised binary searches, one for the context and one for the token within it. The program builds a separate model of each order on the first 100 million training tokens and scores half a million validation tokens:

#snippet("u2/ngram.py", "evaluate", caption: [Scoring the validation set with every order])

#console(read("/src/console/u2-ngram.txt"), caption: [N-gram models on TinyStories])

Each extra token of context helps, with fast-diminishing returns: the unigram model's perplexity of 340 falls to 35 with one token of context and 17 with two, then only to 12 with four. Longer contexts are seen too rarely in 100 million tokens to estimate. The sample shows the characteristic texture of n-gram text: every few words read naturally, because they were copied from real stories in pieces, but Tom becomes Billy, a muffin leads to a dark hotel, and three stories begin in eighty tokens without one of them being told.

#hazard(title: [Pitfall])[
  Compare models only on the same text, with the same tokeniser or in bits per byte, and with every token counted. Skipping the hardest tokens, such as the first few of each document, or evaluating on text that overlaps the training data, makes any model look better than it is.
]

=== A neural language model

N-grams treat every context as unrelated to every other: having seen "the little dog ran" tells them nothing about "the little cat ran". Bengio and colleagues' neural language model of 2003 fixed this by giving every token a learned vector, an _embedding_, and predicting the next token from the concatenated embeddings of the context with a neural network. Tokens that behave alike get similar embeddings, so what is learned about one context transfers to similar ones.

#snippet("u2/mlp_lm.py", "model", caption: [A neural language model with a context of eight tokens])

#snippet("u2/mlp_lm.py", "train", caption: [Training on random windows of the token file])

#console(read("/src/console/u2-mlp-lm.txt"), caption: [The neural model on the same validation tokens as the n-grams])

#fig("u2-ngram", caption: [Validation cross-entropy of every model in this chapter, with Chapter 2.5's transformer, measured on its own validation windows, for comparison. Lower is better.]) <fig-ngram>

With a context of eight tokens, the neural model beats the 5-gram model, which has the advantage of exact counts over 100 million tokens. It is limited in turn by its fixed window: it cannot use anything more than eight tokens back, and a story's characters, setting and plot are established far earlier. Chapter 2.3's attention lets every position look at every earlier one, and Chapter 2.5's transformer, trained on the same data, roughly halves the n-grams' loss (@fig-ngram).

#keyidea[
  A language model estimates the next token's distribution given the previous ones, and is judged by its cross-entropy on held-out text. Counting fails because most contexts are unseen; learned embeddings succeed because they let similar contexts share evidence.
]

#inpytorch[
  `torch.nn.Embedding(vocab, d)` is a lookup table: indexing a $V times d$ matrix by token ids, which is the same as multiplying a one-hot vector by it, without forming the vector. Its gradient touches only the rows that were looked up. The cross-entropy over a vocabulary of 8,192 is `F.cross_entropy(logits, targets)`, as in Chapter 1.3.
]

#reading(
  [Daniel Jurafsky and James Martin, _Speech and Language Processing_, third edition draft, chapter 3: n-gram language models, perplexity and smoothing.],
  [Stanley Chen and Joshua Goodman, "An Empirical Study of Smoothing Techniques for Language Modeling", _Computer Speech and Language_ 13(4), 1999.],
  [Yoshua Bengio, Réjean Ducharme, Pascal Vincent and Christian Jauvin, "A Neural Probabilistic Language Model", _JMLR_ 3, 2003.],
  [Claude Shannon, "Prediction and Entropy of Printed English", _Bell System Technical Journal_ 30(1), 1951.],
)

== Labs

#lab([Perplexity by hand], goal: [Compute a language model's measures with a pen before trusting a program's.], time: [1 hour], code: "code/u2/ngram.py")[
  + On the corpus "the cat sat. the cat ran. the dog sat.", treating words and full stops as tokens, write down the bigram counts and the maximum-likelihood bigram model.
  + Compute the probability, cross-entropy and perplexity of "the dog ran." under it, and explain the result.
  + Repeat with add-one smoothing.
  #done-when(
    [Your two perplexities are correct and you can explain why the first is infinite.],
  )
  #evidence([The working, on paper or in the notebook.])
]

#lab([Smoothing compared], goal: [Measure what Kneser–Ney buys.], time: [1.5 hours], code: "code/u2/ngram.py")[
  + Add add-one smoothing and plain absolute discounting with raw lower-order counts to the program, as alternatives to Kneser–Ney.
  + Compare all three on bigrams, trigrams and 4-grams on the validation tokens.
  #done-when(
    [Your table has nine cross-entropies.],
    [You can explain, with an example from TinyStories, a context in which Kneser–Ney's lower order helps.],
  )
  #evidence([The table and the example.])
]

#lab([Data and order], goal: [See which models are limited by data.], time: [1 hour], code: "code/u2/ngram.py")[
  + Run the program with `--train-tokens` of 3, 10, 30, 100 and 300 million.
  + Plot cross-entropy against training tokens for each order.
  #done-when(
    [Your plot has five curves.],
    [You can say which orders are still improving at 300 million tokens and explain why.],
  )
  #evidence([The plot and the explanation.])
]

#lab([Context length], goal: [Measure what more context gives the neural model.], time: [1.5 hours], code: "code/u2/mlp_lm.py")[
  + Train the neural model with contexts of 2, 4, 8 and 16 tokens, keeping everything else fixed.
  + Plot validation loss against context length, alongside the n-gram results of the same orders.
  #done-when(
    [You have four neural results and can compare each with the n-gram of the same context.],
    [You can explain why the neural model's advantage grows with context.],
  )
  #evidence([The plot and a paragraph.])
]

#problems(
  [Show that perplexity is the geometric mean of the inverse probabilities the model assigns to the tokens of the test text.],
  [A model assigns probability 0.25 to every token. What are its cross-entropy in nats and bits, its perplexity, and its bits per byte at 4 bytes per token?],
  [How many distinct 5-grams could a vocabulary of 8,192 tokens form? Why is that number irrelevant to the memory a counted 5-gram model needs?],
  [In absolute discounting, show that the probabilities of all tokens after a context sum to one when the lower-order model's do.],
  [The neural model has 11.5 million parameters, most of them in its output layer. Which part would you shrink first to make it smaller without hurting it much, and why?],
)

#checklist(
  [I can state the chain rule of probability and what an n-gram model assumes.],
  [I can compute cross-entropy, perplexity and bits per byte, and convert between them.],
  [I can explain smoothing, absolute discounting and Kneser–Ney's continuation counts.],
  [I can explain why a neural language model generalises across contexts where counts cannot.],
  [Lab 2.2.1–2.2.4 done-when criteria all hold, with evidence filed.],
)
