#import "lib/template.typ": *
#show: course-doc.with(unit: "2", title: "Language Models", short: "Language Models",
  subtitle: "Tokenisation, next-token prediction, attention, the transformer, pretraining, scaling laws, decoding and interpretability",
  chapters: ("Tokenisation", "Next-token prediction", "Attention", "The transformer", "Pretraining", "Scaling laws", "Decoding", "Inside the model"))
#contents()

#about-unit(unit: "2",
  intro: [Unit 2 builds a language model from an empty file and studies it from every side. It starts with the tokeniser that turns text into numbers, and with the simplest language models, counts of what follows what, which set the baseline. It derives attention, assembles the transformer that every modern language model uses, and pretrains one on 300 million tokens of children's stories in an afternoon on the M2 Pro. It then measures how loss scales with model size and data, compares the ways of turning probabilities into text, and looks inside the trained model to find the mechanisms it learned. From this unit on, programs use PyTorch, and the model, the tokeniser and the training loop live in `aif`, where Units 3 and 4 reuse them.],
  rows: (
    ([2.1], [A byte-level BPE tokeniser that matches SmolLM2's, and its compression measured], [5]),
    ([2.2], [N-gram models with Kneser–Ney smoothing, and a neural language model that beats them], [6]),
    ([2.3], [Attention in NumPy and in `tiny`, checked against PyTorch, and a model that learns to copy], [6]),
    ([2.4], [A transformer with RoPE, GQA and SwiGLU, its parameters and FLOPs counted and checked], [6]),
    ([2.5], [A data pipeline, a training loop, and a 28M-parameter model pretrained on TinyStories], [8]),
    ([2.6], [A scaling-law sweep and a prediction of a larger run's loss, checked], [6]),
    ([2.7], [Greedy, beam, temperature, top-k, top-p and min-p decoding, and the KV cache], [6]),
    ([2.8], [Induction heads found and switched off, the logit lens, and a probe for dialogue], [7]),
  ),
  before: [Finish Unit 1. Run `uv run -m u2.prepare` early: it downloads 2.2 GB of stories and encodes them, which takes a few minutes.],
  needs: [A GPU makes the unit comfortable; Chapter 2.5's run takes just under five hours on the M2 Pro, and Chapter 2.6's sweep about three. On a CPU, use the `small` preset and fewer tokens, and expect weaker stories.],
)

#include "u2/ch1-tokens.typ"
#include "u2/ch2-ngrams.typ"
#include "u2/ch3-attention.typ"
#include "u2/ch4-transformer.typ"
#include "u2/ch5-pretraining.typ"
#include "u2/ch6-scaling.typ"
#include "u2/ch7-decoding.typ"
#include "u2/ch8-inside.typ"

#signoff(unit: "2",
  chapters: ("Tokenisation", "Next-token prediction", "Attention", "The transformer", "Pretraining", "Scaling laws", "Decoding", "Inside the model"),
  review: (
    [Train a BPE tokeniser by hand on a ten-word corpus, and explain why a tokeniser trained on stories compresses code poorly.],
    [Derive attention from the problem of looking up a value by a fuzzy key, and explain why the scores are divided by $sqrt(d)$.],
    [Draw your transformer's block from memory, with the shape of every tensor, and count its parameters and FLOPs per token.],
    [Explain, with your Chapter 2.6 fit, how you would split a fixed compute budget between model size and data.],
    [Explain what an induction head does, how you found one, and what switching it off did to the loss.],
  ),
)
