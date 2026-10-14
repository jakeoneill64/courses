#import "../lib/template.typ": *

= Pretraining <ch-pretraining>

#chapter-meta(
  time: [8 hours, and about five hours of the GPU's time],
  builds: [A pipeline that trains the tokeniser on 2.2 GB of stories and encodes them into a file of 536 million tokens; a training loop with warm-up, cosine decay, gradient clipping, accumulation and mixed precision; training throughput measured four ways; and Chapter 2.4's model pretrained on 300 million tokens, from noise to coherent stories.],
  needs: [Chapters 1.4, 2.1 and 2.4.],
)

#why[
  In pretraining a language model acquires nearly everything it knows, by predicting the next token over a large body of text for as long as compute allows. Fine-tuning, preference training and tools, in Unit 3, adjust what pretraining built. The algorithm is Unit 1's training loop, but at a scale where handling the data, keeping the optimisation stable, using the hardware fully and surviving interruptions matter as much as the model. This chapter trains the course's model in full, in an afternoon, and produces the model that the rest of this unit examines and Unit 4 makes fast.
]

#skip-test(
  rule: [If all four are easy, read the sections on throughput and on the run, and do Labs 2.5.1 and 2.5.3.],
  [How many tokens does each step see with a batch of 32 sequences of 512 tokens, and how many steps make 300 million tokens?],
  [Why warm up the learning rate at the start of training with Adam?],
  [What does gradient clipping protect against, and what does it cost when nothing is wrong?],
  [When is accumulating gradients over several small batches exactly equivalent to one large batch?],
)

== Core ideas

=== The data

TinyStories, from Ronen Eldan and Yuanzhi Li, is a collection of short stories written by GPT-4 in the vocabulary of a three- or four-year-old, each prompted with a few required words and features such as dialogue or a twist. Its training split holds 2.72 million stories in 2.2 GB, and its validation split 27,630 more. The language is simple and the world it describes is small, so a model of 28 million parameters can learn both well enough to write coherent stories, and the effects of every choice in this unit are visible on a single machine.

`u2.prepare` trains Chapter 2.1's tokeniser on the training split with a vocabulary of 8,192, then encodes both splits into flat files of 16-bit token ids, with an end-of-text token between stories. Both steps run on every CPU core: the file is cut into pieces at story boundaries, each process counts or encodes its pieces, and the results are combined in order.

#snippet("aif/corpus.py", "encode-part", caption: [Encoding a file in parallel, in pieces that end at story boundaries])

#snippet("u2/prepare.py", "prepare", caption: [Train the tokeniser, then encode both splits])

#console(read("/src/console/u2-prepare.txt"), caption: [The corpus, prepared])

=== Batches

A training batch is 32 windows of 513 consecutive tokens taken at random positions in the token file; the first 512 are the input and the last 512, shifted by one, the targets. The file is opened as a NumPy _memory map_, so the operating system reads only the windows that are used and the 1 GB file never has to fit in memory at once.

#snippet("aif/train.py", "batches", caption: [Random training windows, and fixed validation windows])

Windows cross story boundaries freely. The model sees end-of-text tokens and learns that a new story begins after one, and its attention can look across the boundary into the previous, unrelated story, which it learns to ignore. Production pipelines often pack documents into windows and mask attention at their boundaries instead, which matters more for long documents of mixed kinds.

The run draws 300 million tokens' worth of windows from a file of 536 million, so it sees each token about half a time on average and almost every window is new to it. Its training loss is then a fair estimate of its loss on unseen text, and it cannot overfit in the sense of Chapter 1.6, since there is more data than the compute budget can use. Validation uses 64 fixed windows, evenly spaced through the validation file, the same at every evaluation, so that successive measurements differ only because the model changed.

=== The optimiser and its schedule

The optimiser is Chapter 1.4's AdamW with $beta_1 = 0.9$ and $beta_2 = 0.95$, and weight decay of 0.1 applied to the weight matrices but not to the normalisation gains, which set scales that decay would pull towards zero. The smaller $beta_2$ is standard for transformers. The second-moment estimate averages over roughly the last $1 \/ (1 - beta_2)$ steps, so it follows changes in the gradients' scale within about 20 steps instead of about 1,000. That avoids the oversized updates that a stale, too-small estimate produces.

#snippet("u2/pretrain.py", "setup", caption: [The model, the compiled step and the optimiser])

The learning rate rises linearly over the first 500 steps, the _warm-up_, then follows a cosine down to a tenth of its peak at the end of the run. Warm-up is needed because Adam normalises its updates. At the first step every weight moves by the full learning rate, whatever its gradient, while the network is still at its initialisation and the moment estimates rest on a single batch. Starting small lets the estimates settle and the network's scales adjust before the steps grow.

#snippet("aif/train.py", "schedule", caption: [Linear warm-up, then cosine decay to a floor])

The peak learning rate is the most important setting in the run, and the cheapest way to choose it is a set of short runs. Three runs of 6 million tokens each, with peaks of $10^(-3)$, $2 times 10^(-3)$ and $3 times 10^(-3)$ and schedules scaled to their length, reached validation losses of 2.251, 2.198 and 2.246 nats. The full run uses $2 times 10^(-3)$.

#hazard(title: [Pitfall])[
  Compare settings at the end of runs of the same length. A short run's schedule decays sooner, so midway through a long run its loss is higher than a short run's at the same point, and every long schedule judged mid-run looks worse than it will finish. The best learning rate also drifts down slowly as runs get longer, so a short sweep only approximates the best rate for a long run.
]

=== The loop

#snippet("u2/pretrain.py", "loop", caption: [One optimiser step: accumulate, unscale, clip, step])

Three additions turn Unit 1's loop into one fit for long runs.

_Gradient clipping_ rescales the whole gradient whenever its norm exceeds 1.0. An unusual batch can produce a gradient many times larger than normal, and one such step can undo hours of training. Clipping limits the size of that step. When nothing is wrong the norm stays below the threshold and clipping does nothing.

_Gradient accumulation_ runs several smaller batches, adds their gradients, and steps once. Since each loss is divided by the number of batches, and every batch holds the same number of tokens, the summed gradient is exactly the gradient of the mean loss over the combined batch. A model with no batch-dependent layers trains identically and needs only the memory of the smaller batch.

_Mixed precision_ runs the forward pass in a 16-bit format inside `torch.autocast` while keeping the weights in float32. With float16, whose range is narrow, the loss is first multiplied by a large factor so that small gradients do not round to zero, and the gradients are divided by it again before clipping. `GradScaler` does both and adjusts the factor when it overflows. Chapter 4.3 examines the formats.

The program also saves the model, the optimiser's state, the random generator's state and the step number every 2,000 steps, and `--resume` continues from them exactly. A five-hour run can be interrupted by a crash, a power cut or a laptop going to sleep, and a run that cannot resume is then lost.

=== Throughput

The speed of training is measured in tokens per second, and its efficiency in _model FLOPs utilisation_: the FLOPs the model needs per token, 179 million here, times the tokens per second, as a fraction of the GPU's peak. The program trains the model for a few steps in four ways and times each:

#snippet("u2/throughput.py", "measure", caption: [Timing training steps, after five steps of warm-up and compilation])

#console(read("/src/console/u2-throughput.txt"), caption: [Training throughput on the M2 Pro])

Compilation nearly doubles throughput, from 9,400 to 18,100 tokens per second. The matrix multiplications are the same in both, and the gain comes from fusing the element-wise operations between them, which Chapter 4.2 examines. Mixed precision gains little on this machine: float16 is 5% faster than float32, and bfloat16, for which the M2 Pro's GPU has no arithmetic, is a third slower. Chapter 4.3 explains why, and why the same flag gives several times the speed on an NVIDIA GPU with tensor cores. The run therefore uses compiled float32. At 3.25 TFLOP/s it uses 48% of the GPU's nominal float32 peak, within the range of about 35% to 55% that large training runs on thousands of GPUs typically report.

=== The run

```bash
uv run -m u2.pretrain
```

#console-part("/src/console/u2-pretrain.txt", to: 6, caption: [The start of the run])

#console-part("/src/console/u2-pretrain.txt", from: -4, command: false, caption: [The end of the run])

#fig("u2-pretrain", caption: [Training loss every 50 steps and validation loss every 500, against tokens seen, with the learning-rate schedule below. The two losses track each other throughout, because with less than one pass over the data the model cannot overfit.]) <fig-pretrain>

The run took 4 hours and 44 minutes and ended at a validation loss of 1.214 nats per token, 0.421 bits per byte. That is about half of both the 5-gram model's 2.474 nats and the neural model's 2.366 from Chapter 2.2, and well below the 0.70 bits per byte that SmolLM2-135M, five times larger and trained on the web, scores on the same text in Chapter 3.1. The curve has the usual shape of a pretraining run. The loss falls steeply over the first few million tokens, as the model learns the vocabulary and the commonest phrases, then declines slowly for the rest of the run as it learns grammar, characters and plots. The last stretch, as the learning rate falls to its floor, still gains a little.

=== From noise to stories

The program logs a story sampled from the model at every evaluation. Reading them in order shows what is learned when:

#snippet("u2/stories.py", "progress", caption: [The logged samples, in order])

#console(read("/src/console/u2-stories.txt"), caption: [Samples during training, then two stories from the finished model])

Every evaluation samples with the same random seed, so the samples begin alike and the differences between them come from the model. After 8 million tokens it writes grammatical sentences with little memory: it starts mid-sentence, repeats itself and loses track of what it has said. By 33 million it has names, correctly punctuated dialogue and the opening formulas of the genre, but contradicts itself from one sentence to the next. By 131 million a scene holds together for a paragraph, with feelings that follow from events. The final model keeps a story's characters and objects for its whole length and brings it to an ending. The treasure-map story follows its prompt from the X on the map to a hole, a key and a door. Its failures are typical of a small model: details that contradict each other ("a red liquid. It was a sparkly key"), a repeated line of dialogue, and a lock that clicks shut and then opens.

#keyidea[
  Pretraining is next-token prediction at scale: random windows from a large corpus, AdamW with warm-up, decay and clipping, and as many tokens per second as the hardware allows. With less than one pass over the data, the training loss is a fair estimate of the loss on new text, and the compute budget, which runs out before the data does, limits the model.
]

#inpytorch[
  `torch.compile`, `torch.autocast`, `torch.amp.GradScaler` and `torch.nn.utils.clip_grad_norm_` are this chapter's tools, and `torch.optim.lr_scheduler` offers schedules ready-made. Hugging Face's `datasets` library streams corpora too large for one disk. Andrej Karpathy's nanoGPT and llm.c are compact, readable implementations of the same training at larger scale, and torchtitan and Megatron-LM are what large runs use.
]

#reading(
  [Ronen Eldan and Yuanzhi Li, "TinyStories: How Small Can Language Models Be and Still Speak Coherent English?", 2023.],
  [Aakanksha Chowdhery and others, "PaLM: Scaling Language Modeling with Pathways", 2022: section 4 defines model FLOPs utilisation.],
  [Mitchell Wortsman and others, "Small-Scale Proxies for Large-Scale Transformer Training Instabilities", ICLR 2024: what warm-up, learning rate and normalisation do to stability.],
  [Andrej Karpathy, nanoGPT, 2023, and "Let's reproduce GPT-2 (124M)", 2024: a complete pretraining run, explained.],
)

== Labs

#lab([Your run], goal: [Pretrain the model you will use for the rest of the course.], time: [1.5 hours of work, and the run], code: "code/u2/pretrain.py")[
  + Run `uv run -m u2.pretrain`. On a machine much slower than the M2 Pro, use `--preset small --tokens 100e6` instead and expect weaker stories.
  + Plot your training and validation losses from `runs/tinystories-28m/log.jsonl`, and read the samples at a few points.
  #done-when(
    [Your run finished, or resumed and finished, and saved `model.pt`.],
    [With the base preset, your final validation loss is within 0.03 nats of this chapter's.],
  )
  #evidence([The plot and the final line of the log.])
]

#lab([A learning-rate sweep], goal: [Choose a learning rate the way large runs do.], time: [2 hours], code: "code/u2/pretrain.py")[
  + Train the base model on 20 million tokens with peak learning rates of $5 times 10^(-4)$, $10^(-3)$, $2 times 10^(-3)$, $3 times 10^(-3)$ and $5 times 10^(-3)$, each with its own name.
  + Plot the final validation loss against the learning rate on a logarithmic axis.
  #done-when(
    [Your plot has five points and a clear minimum, or you extend the range until it does.],
    [You can state the range of learning rates within 0.02 nats of the best.],
  )
  #evidence([The plot.])
]

#lab([What keeps it stable], goal: [Find which of warm-up, clipping and $beta_2$ this run depends on.], time: [2 hours], code: "code/u2/pretrain.py")[
  + At a peak learning rate of $5 times 10^(-3)$ and 20 million tokens, train once as is, once without warm-up (`--warmup 0`), once without clipping (`--clip 0`) and once with $beta_2 = 0.999$ (`--beta2 0.999`), each with its own `--name`.
  + Plot the loss and the gradient norm from each log.
  #done-when(
    [Your table has the four final losses.],
    [You can point to a loss spike, or its absence, and explain it from the gradient norms.],
  )
  #evidence([The table and the plots.])
]

#lab([Checking gradient accumulation], goal: [Show that accumulation reduces memory and leaves the gradients unchanged.], time: [1 hour], code: "code/u2/pretrain.py")[
  + Make the loop print the loss at every step. Run 20 steps, `--tokens 327680`, with `--batch 32` and with `--batch 8 --accum 4`, both with `--no-compile` and the same seed; the random generator then draws the same windows for both.
  + Compare their losses step by step, and their speed and memory.
  #done-when(
    [The two runs' losses agree to within rounding, or you can explain any difference.],
    [You have both runs' tokens per second and peak memory.],
  )
  #evidence([The comparison.])
]

#problems(
  [The run draws 586,000 windows of 513 tokens from 536 million possible starting positions. About how many windows are drawn twice?],
  [Training needs 179 MFLOP per token. How long would the run's 300 million tokens take on a GPU sustaining 400 TFLOP/s?],
  [Show that summing the gradients of $k$ batches' losses, each divided by $k$, gives the gradient of the mean loss over the combined batch when the batches are the same size. Name two things that would break the equality.],
  [At Adam's first step, with bias correction and $epsilon$ negligible, how far does each weight move? What does that suggest about the first steps of training at a high learning rate?],
  [The validation loss is measured on 64 windows of 512 tokens, and per-token losses have a standard deviation of about 1.5 nats. Estimate the standard error of the validation loss if tokens were independent, and say whether the true error is larger or smaller.],
)

#checklist(
  [I can prepare a corpus for training: a tokeniser, a token file and a held-out split.],
  [I can write a training loop with warm-up, decay, clipping, accumulation and mixed precision, and explain each part.],
  [I can measure training throughput and model FLOPs utilisation.],
  [I can run, monitor and resume a long training run, and read its curves.],
  [Lab 2.5.1–2.5.4 done-when criteria all hold, with evidence filed.],
)
