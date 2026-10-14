#import "../lib/template.typ": *

= LoRA <ch-lora>

#chapter-meta(
  time: [6 hours],
  builds: [Low-rank adapters written from their definition and attached to every projection of a model; frozen weights stored in 4 bits and dequantised on the fly; memory predicted by hand and measured; and fine-tuning compared three ways: all of SmolLM2-135M, adapters on SmolLM2-135M, and adapters on a 4-bit SmolLM2-360M.],
  needs: [Chapter 3.2. Chapter 4.7 explains quantisation in depth; this chapter needs only its first section.],
)

#why[
  Full fine-tuning changes every weight and keeps a gradient and an optimiser state for each, 16 bytes per parameter in all with AdamW, so fine-tuning a model costs several times the memory of running it, and every fine-tuned copy is as large as the original. _Low-rank adaptation_ freezes the model and trains a small correction to each weight matrix, using a few percent of the model's parameters or less. Fine-tuning becomes cheap enough for a laptop, the result is a file of tens of megabytes at most, and, with the frozen weights stored in 4 bits, a model several times larger than full fine-tuning allows fits in the same memory.
]

#skip-test(
  rule: [If all four are easy, read the sections on memory and on the comparison, and do Labs 3.3.2 and 3.3.4.],
  [For a weight matrix of $d_"out" times d_"in"$ and rank $r$, write LoRA's update and count its parameters.],
  [Why is one of LoRA's two matrices initialised to zero?],
  [Estimate the memory to fully fine-tune a 360-million-parameter model with AdamW in float32, and with rank-16 adapters on frozen 4-bit weights.],
  [Why can adapters trained on float32 weights be merged into them after training, and why is that harder with 4-bit weights?],
)

== Core ideas

=== Low-rank updates

Fine-tuning moves each weight matrix $W$ by some $Delta W$. There is good evidence that these changes have low _intrinsic dimension_. The updates that fine-tuning finds lie close to a small subspace, so a $Delta W$ of rank far below the matrix's dimensions captures most of the effect. LoRA builds that assumption in. It freezes $W$ and learns
$ Delta W = alpha / r B A, $
with $A$ of shape $r times d_"in"$ and $B$ of shape $d_"out" times r$, for a small rank $r$ such as 8 or 16. The layer computes $W x + (alpha \/ r) B A x$, and only $A$ and $B$ train: $r (d_"in" + d_"out")$ parameters instead of $d_"in" d_"out"$, about 6% for a $576 times 576$ matrix at rank 16.

#snippet("aif/lora.py", "lora", caption: [A linear layer with a low-rank adapter])

$B$ starts at zero, so $Delta W$ starts at zero and the adapted model begins exactly as the base model. $A$ starts random, so that $B$'s gradient is not zero. The scale $alpha \/ r$, with $alpha$ typically twice the rank, keeps the update's size roughly independent of the rank chosen, so a learning rate that works at one rank works at another.

#snippet("aif/lora.py", "attach", caption: [Freezing a model and adapting all seven projections of every block])

Because the adapted layer is linear, the trained adapter can be folded into the weights: $W arrow.l W + (alpha \/ r) B A$. The merged model runs exactly as fast as the original, and the same base model can instead keep many small adapters and switch between them per request.

#snippet("aif/lora.py", "merge", caption: [Merging adapters into the weights])

=== 4-bit frozen weights

Frozen weights need no gradient or optimiser state, only storage, and they can be stored coarsely. _QLoRA_ stores the frozen weights in 4 bits and dequantises each layer's weights on the fly during the forward pass, while the adapters, which are what is learned, stay in full precision. Gradients still flow through the dequantised weights to the activations and to the adapters in earlier layers, and only the frozen weights have no gradients. The course's version uses Chapter 4.7's symmetric 4-bit quantisation in groups of 64, applied to the seven projections of every block. The embedding, which the model shares with its output layer, and the normalisation gains stay in float32.

#snippet("aif/quant.py", "int4", caption: [Packing weights into 4 bits with a scale per group of 64])

Dequantising on the fly needs care. If the forward pass multiplied by the dequantised weight directly, autograd would keep that float32 weight for the backward pass, which needs it to compute the gradient with respect to the layer's input. Storing the weights in 4 bits would then save nothing during training. The layer therefore has its own autograd function, which rebuilds the weight again in the backward pass and keeps only the packed form in between, trading a second dequantisation for the memory:

#snippet("aif/quant.py", "int4-linear", caption: [A frozen linear layer stored in 4 bits, rebuilt in both passes])

QLoRA itself adds refinements that this course leaves to the reading: a 4-bit format whose levels follow a normal distribution, quantised scales, and paged optimiser state.

=== Memory, predicted and measured

Training memory has four parts: the weights, their gradients, the optimiser's state, and the activations kept for the backward pass. For full fine-tuning in float32 with AdamW, the first three cost $4 + 4 + 8 = 16$ bytes per parameter, or 2.2 GB for SmolLM2-135M. With LoRA, the frozen weights cost 4 bytes each, or about 0.53 bytes for the projections stored in 4 bits, with a 16-bit scale for every 64 of them. Only the adapters' few million parameters carry gradients and optimiser state. The embedding, kept in float32, is a large share at this size, holding 47 million of SmolLM2-360M's 362 million parameters. For a given model the activations are the same whichever parameters train, since every layer still runs forward and backward. They depend on the batch and on the model's width and depth.

#snippet("u3/lora.py", "setup", caption: [Loading, optionally quantising, and adapting a model, or with `--full` training every weight])

#snippet("u3/lora.py", "train", caption: [Training, and recording the memory in use after each forward and backward pass])

#console(read("/src/console/u3-lora.txt"), caption: [Rank-16 adapters on SmolLM2-135M])

#console(read("/src/console/u3-qlora.txt"), caption: [Rank-16 adapters on SmolLM2-360M stored in 4 bits])

#console(read("/src/console/u3-full.txt"), caption: [Every weight of SmolLM2-135M trained, on fewer conversations, for comparison])

The adapters on SmolLM2-135M train 4.9 million parameters, 3.5% of the model, and reach a held-out loss of 1.376 with a peak of 10.6 GiB. That is close to the 1.343 that full fine-tuning reached in Chapter 3.2 on the same conversations. Training every weight of the same model, in the third console, peaks at 12.6 GiB. The difference of 2 GiB is close to the 1.5 GiB the arithmetic predicts for 135 million parameters, at 16 bytes per parameter for weights, gradients and optimiser state against 4 for a frozen weight. That run, on half as many conversations, reaches 1.374, level with the adapters on all of them, and each of its steps takes only a tenth longer. Merging the adapters into the weights leaves the loss unchanged, as the algebra predicts. In 4 bits, SmolLM2-360M's frozen weights take 340 MiB, less than the smaller model's 513 MiB in float32, and on half as many conversations its adapters reach 1.181, better than either fine-tune of the smaller model. Its peak memory, 17.5 GiB, is still the largest of the three, because at batches of 4,096 tokens the activations of 32 layers of width 960 outweigh any saving in the weights. Storing weights in 4 bits pays when the weights dominate memory, as they do in models of billions of parameters. At this size, LoRA saves memory mainly by not keeping gradients and optimiser state for every weight. Each step of the 4-bit model takes three times as long, because the model is larger and every weight is rebuilt twice per step.

#keyidea[
  LoRA freezes a model and learns a low-rank correction to each weight matrix. Fine-tuning then costs memory for the frozen weights and the activations only, the frozen weights can be stored in 4 bits, and the result is a small adapter that can be merged or swapped.
]

#inpytorch(title: [In the libraries])[
  Hugging Face's PEFT library wraps a model with `get_peft_model(model, LoraConfig(r=16, lora_alpha=32, target_modules=[...]))`, with `merge_and_unload()` to fold the adapters in. The `bitsandbytes` library provides QLoRA's 4-bit NF4 weights for NVIDIA GPUs, loaded through `transformers` with a `BitsAndBytesConfig`. On Apple Silicon, MLX provides its own LoRA and quantisation.
]

#reading(
  [Edward Hu and others, "LoRA: Low-Rank Adaptation of Large Language Models", ICLR 2022.],
  [Tim Dettmers, Artidoro Pagnoni, Ari Holtzman and Luke Zettlemoyer, "QLoRA: Efficient Finetuning of Quantized LLMs", NeurIPS 2023.],
  [Armen Aghajanyan, Luke Zettlemoyer and Sonal Gupta, "Intrinsic Dimensionality Explains the Effectiveness of Language Model Fine-Tuning", ACL 2021.],
  [Dan Biderman and others, "LoRA Learns Less and Forgets Less", _TMLR_, 2024.],
)

== Labs

#lab([The rank], goal: [Find how much rank fine-tuning needs.], time: [1.5 hours], code: "code/u3/lora.py")[
  + Fine-tune SmolLM2-135M with adapters of rank 1, 4, 16 and 64 on 10,000 conversations, with $alpha = 2r$.
  + Plot the held-out loss and the trainable parameters against the rank, with full fine-tuning's loss as a line.
  #done-when(
    [Your plot has four points and the full fine-tuning line.],
    [You can name the smallest rank within 0.02 nats of full fine-tuning on your machine.],
  )
  #evidence([The plot and the table behind it.])
]

#lab([Where to adapt], goal: [Measure which layers' adapters matter.], time: [1.5 hours], code: "code/aif/lora.py")[
  + Add an option to `add_lora` that adapts only attention's four projections, or only the feed-forward network's three.
  + Fine-tune with each, and with all seven, at the same rank, and compare held-out losses and trainable parameters.
  #done-when(
    [You have three losses and three parameter counts.],
    [You can say which half of the block repays its parameters better on this data.],
  )
  #evidence([The table and the conclusion.])
]

#lab([Memory, by hand and measured], goal: [Predict the memory of fine-tuning before running it.], time: [1 hour], code: "code/u3/lora.py")[
  + Predict the weights, gradient and optimiser memory for full fine-tuning, for LoRA, and for LoRA on 4-bit frozen weights, for SmolLM2-135M and -360M.
  + Measure each with the program at the same `--batch-tokens`, using `--full` for full fine-tuning and `--examples 1000` to keep the runs short, and estimate the activations as the difference between the measured peak and your prediction.
  #done-when(
    [Your predictions of the non-activation memory agree with the measurements within 15%.],
    [Your activation estimate is the same, within 15%, across the runs at the same batch size.],
  )
  #evidence([The predictions, the measurements and the activation estimates.])
]

#lab([Two adapters, one model], goal: [Serve two fine-tunes from one base model.], time: [1.5 hours], code: "code/aif/lora.py")[
  + Train two rank-8 adapters on SmolLM2-135M, one on your style data from Lab 3.2.4 and one on the general conversations.
  + Write a function that switches a model between adapters without reloading it, and show that each adapter reproduces its own fine-tune's replies.
  #done-when(
    [Switching takes under a second and the replies match each fine-tune exactly.],
    [You can state the size of each adapter on disk and compare it with the model's.],
  )
  #evidence([The code, the replies and the sizes.])
]

#problems(
  [Count the trainable parameters of rank-16 adapters on all seven projections of SmolLM2-135M, whose layers have width 576, key-value width 192 and feed-forward width 1,536, over 30 layers.],
  [Show that $B A$ has rank at most $r$, and that with $B = 0$ the gradient with respect to $A$ is zero at the first step. Why does that not stop training?],
  [Why does the scale $alpha \/ r$ keep a good learning rate roughly unchanged when $r$ changes?],
  [Merging an adapter into 4-bit weights changes them by small amounts. Why might the merged weights, requantised, differ from the trained model's behaviour?],
  [A service hosts one base model and 1,000 customers' adapters of rank 16. Estimate the memory for the adapters, and describe how a batch could mix requests for different adapters.],
)

#checklist(
  [I can implement LoRA, explain its initialisation and scale, and merge it.],
  [I can store frozen weights in 4 bits and train adapters through them.],
  [I can predict and measure the memory of full and adapter fine-tuning.],
  [I can choose a rank and the layers to adapt from measurements.],
  [Lab 3.3.1–3.3.4 done-when criteria all hold, with evidence filed.],
)
