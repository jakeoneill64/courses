# Module 5: Training networks properly

**Part III · 2 weeks · Needs: Modules 1 and 2. Data: Fashion-MNIST and CIFAR-10 (torchvision).**

## Why this module

You know what backpropagation computes and you have built networks that trained. What
you do not yet have is the craft: the ability to sit down with a fresh architecture and
a fresh dataset, get a run working in an afternoon, know within ten minutes whether it
is healthy, and say afterwards what each choice was worth. That is the second gap you
named, and it is the one that costs people the most time in practice.

The Oxford Deep Neural Networks week assumes this craft. Its assignment hands you a
dataset and asks you to train something, report honestly, and explain what you did and
why; it does not have time to teach you that the loss at initialisation should be ln 10,
or that Adam with L2 regularisation is not the same as AdamW. This module fixes those
facts by making you build the tooling every later module runs on. The harness you
write in `common/` this fortnight trains the VAE in Module 7, the SimCLR encoder in
Module 8, the GPT in Module 9 and the fine-tunes in Module 10. Every hour spent making
it solid here is repaid several times over.

The structural point is that a training run is an experiment, and experiments need
instruments. Loss curves, gradient norms, activation statistics, throughput counters,
seeds and an ablation table are the instruments. Frameworks such as Lightning and fastai
hide them well enough that you can go years without learning what they measure. You
write your own once, slowly, so that afterwards you can use anyone's quickly.

## Skip test

Answer cold, in writing.

1. A ten-class classifier prints a loss of 6.9 on its first batch. Is that a bug? What
   should the number be, and name three causes if it is not.
2. Derive the weight variance a ReLU layer needs to preserve the variance of its input.
   Why does the answer differ from the tanh case, and what happens to the activations
   after 20 layers if you use the wrong one?
3. What does BatchNorm do differently in `train()` and `eval()` mode? Describe a bug that
   gives good training loss and terrible validation accuracy because of it.
4. Write Adam's update including bias correction. Why is the correction there, and how
   large is the first step without it?
5. You double the batch size. What should you do to the learning rate, why, and when
   does the rule break down?
6. Training loss falls smoothly to 0.02 while validation loss falls to 0.6 and then
   rises. Name the diagnosis and three remedies. What would you check first if the
   validation loss had instead sat at 2.30 throughout?

If all six are easy, do Labs 5.4 and 5.5 only, and the write-up.

## Core ideas

**A training harness is an engineering artefact, and writing one is the fastest way to
learn what frameworks hide.** The pieces are a config dataclass serialised with every
run, a data pipeline, a model registry mapping names to constructors, the loop
(forward, loss, backward, step, schedule tick), evaluation under `torch.no_grad()` in
`eval()` mode, checkpointing of model, optimiser, scheduler and epoch with resume,
MLflow logging, and `seed_everything`. None of it is hard; all of it is where bugs
live. Lab 5.1 builds it in about 400 lines and Lab 5.4 plants bugs in it so you learn
what each part's failure looks like.

**The scale of the initial weights decides whether signal survives depth.** For y = Wx
with n_in inputs and weight variance σ², Var(y_i) = n_in σ² Var(x). Xavier (Glorot)
init uses σ² = 1/n_in, or 2/(n_in + n_out) to balance the backward pass, and preserves
variance through linear or tanh layers near their linear region. A ReLU zeroes half
its inputs and halves the second moment, so He (Kaiming) init uses σ² = 2/n_in. Use
Xavier on ReLU and each layer shrinks the activation std by 1/√2: after 20 layers it is
down by 2^10 ≈ 1,000, and so is the gradient at the bottom. A fixed std of 0.01
collapses faster; too large a std saturates and gives an initial loss near 20 rather
than 2.3. PyTorch's default for `nn.Linear` and `nn.Conv2d` is Kaiming-uniform with
a = √5, which is not He init for ReLU; it is a legacy choice that BatchNorm papers over.

**BatchNorm makes the activation scale a learned quantity instead of an accident of
initialisation.** Per feature it subtracts the batch mean, divides by the batch std
(plus ε), then applies a learned scale γ and shift β. Because it depends on the other
examples in the batch it has two modes: `train()` uses batch statistics and updates
running averages; `eval()` uses the running averages. Forget `model.eval()` at
validation and predictions become batch-dependent; forget `model.train()` afterwards
and the statistics freeze. Gradients flow through the mean and variance too (Problem
4), which is why BatchNorm smooths the loss landscape and allows learning rates
roughly 10× higher. It fails below a batch of about 8 to 16, where the statistics are
too noisy. LayerNorm normalises across the features of one example and is what
transformers use; GroupNorm normalises across channel groups of one example and is the
convnet drop-in when batches must be small.

**Residual connections make depth trainable by giving the gradient an identity path.**
A block computes y = x + F(x), so its Jacobian is I + ∂F/∂x and L blocks give
Π(I + J_l); the identity terms stop the product shrinking geometrically the way Π J_l
does (Problem 8). He et al.'s plot of a 56-layer plain convnet training worse than a
20-layer one, and a 56-layer residual net training better, is the whole argument.
Zero-initialising the last BatchNorm γ in each block, so every block starts as the
identity, is a one-line trick that helps. On activations: ReLU is cheap and works, but
a unit whose pre-activation is negative for every input has zero gradient and never
recovers (a dead ReLU). GELU and SiLU are smooth with gradient everywhere and are the transformer
and modern-convnet defaults; on a ResNet at this scale the difference is seed noise.

**Sanity checks before the first real run save days.** Karpathy's recipe is a sequence
and the order matters. Fix a seed. Check the loss at init: with K balanced classes and
small logits it should be ln K, 2.303 for ten; anything far off means large logits,
wrong labels or the wrong loss. Overfit one batch of 32 to near-zero loss; if you
cannot, the model or loop is broken and no data will help. Look at a batch after
augmentation, as images with labels; the wrong normalisation and the channel-order bug
are found this way and no other. Check the input statistics really are zero-mean and
unit-variance. Then run a
learning-rate range test, increasing the rate exponentially over a few hundred steps
and plotting loss against it; a good peak is a factor of 3 to 10 below where the loss
blows up. Only then start the real run.

**Optimisers differ in how they scale the step per parameter, and the differences are
derivable.** SGD with momentum keeps v ← μv + g and steps w ← w − ηv; at μ = 0.9 the
steady-state step is about 10× one gradient, which is why momentum runs use lower
rates. Nesterov evaluates the gradient after the momentum step, a look-ahead that damps
oscillation for free. RMSProp divides by a running RMS of the gradient so every
parameter moves at a similar rate. Adam combines them: m ← β₁m + (1−β₁)g,
v ← β₂v + (1−β₂)g², w ← w − η m̂/(√v̂ + ε), with m̂ = m/(1−β₁ᵗ) and v̂ = v/(1−β₂ᵗ). The
hats correct for m and v starting at zero; without them the first step is
η(1−β₁)/√(1−β₂) ≈ 3.2η per parameter instead of η, and with β₂ = 0.999 the denominator
stays too small for over two thousand steps (Problem 2). AdamW applies weight decay
directly, w ← w − ηλw, rather than adding λw to the gradient. For SGD the two are
identical; for Adam the coupled version is divided by √v̂ along with everything else,
so parameters with large gradient histories are barely regularised (Problem 3).

**The schedule is worth more than the choice of optimiser.** A constant rate must be
small enough to converge at the end and is therefore too small at the start. Warmup
then cosine is the modern default: ramp linearly from near zero over the first few
percent of training, so adaptive statistics and BatchNorm averages settle before the
large steps, then decay along a half cosine to near zero. One-cycle (Smith) is the same
shape with a higher peak; the observation behind it, super-convergence, is that a
network tolerates a very large rate briefly and trains in far fewer epochs. Rate and
batch size are coupled through gradient noise: a batch of B has gradient covariance
proportional to 1/B, and k small steps resemble one large step at k times the rate, so
the linear scaling rule multiplies the rate by the same factor as the batch, with
warmup to survive the early steps (Goyal et al., Problem 5). It holds until the batch
is so large that noise no longer matters, after which bigger batches buy nothing.

**Regularisation trades training fit for generalisation, and for images augmentation is
the strongest kind.** Weight decay of 5e-4 is standard for CIFAR ResNets under SGD and
0.01 to 0.1 for AdamW on transformers; the numbers are not comparable because of the
decoupling. Dropout helps fully connected layers and adds little to convnets with
BatchNorm. Label smoothing puts (1−ε) + ε/K on the true class and ε/K elsewhere, stops
the network driving logits to infinity for an already tiny loss, and improves
calibration (Problem 6). Augmentation encodes invariances: random crop with 4 pixels of
padding and horizontal flip are worth 5 to 7 points of CIFAR-10 accuracy on their own.
Cutout blanks a random 16×16 square; Mixup trains on convex combinations of image pairs
and their labels; CutMix pastes a patch from one image onto another and mixes labels
by area; RandAugment applies N random operations of magnitude M. On a 30-epoch CIFAR run,
crop, flip, Cutout and label smoothing are the right set; Mixup and RandAugment need
roughly 100 epochs or more before they help.

**Loss curves are the primary instrument, and every shape has a short list of causes.**
Training loss stuck at ln K: the rate is far too high or low, the network is dead,
labels are shuffled independently of inputs, or gradients never reach the parameters.
Training loss falling while validation sits flat from epoch one is a data bug, not
overfitting: wrong normalisation at validation, a transform mismatch, `eval()`
forgotten. Training falling and validation falling then rising is overfitting; the
remedies are more data, more augmentation, more regularisation, a smaller model, in
that order.
Validation accuracy above what the model should achieve is leakage. Spikes are a bad
batch at a high rate, an fp16 overflow or a warmup too short; a spike that never
recovers means NaN weights or a NaN running variance.

**Gradient pathologies are visible if you instrument them.** After `backward()`, log each
layer's gradient L2 norm and activation std every 100 steps. Vanishing shows as a
constant-factor shrinkage per layer towards the input, exploding as the reverse. The
per-layer ratio of update to weight size, roughly η‖g‖/‖w‖, should sit near 1e-3; 1e-1
is too hot, 1e-5 too cold, and this one number diagnoses a bad rate faster than the loss
does. Clipping by global norm (`torch.nn.utils.clip_grad_norm_`; 1.0 is the transformer
default) bounds what one bad batch can do; if it fires on most steps the rate is wrong.

**Mixed precision is a throughput tool with two failure modes, and the Mac supports half
of it.** Under `torch.autocast` matmuls and convolutions run in float16, which halves
activation memory and, on tensor-core GPUs, gives a 2 to 4× speedup; reductions, losses
and BatchNorm statistics stay in float32. Float16's smallest normal value is about 6e-5,
so small gradients underflow; CUDA uses `torch.amp.GradScaler` to scale the loss up
before `backward()` and the gradients down after. On MPS autocast to float16 works and
the smoke test measured it; treat loss scaling as unavailable and watch whether the
smallest per-layer gradient norms drop to zero under fp16 but not fp32.
Throughput is measured, not guessed: samples per second rises with batch size until the
GPU saturates; `DataLoader` workers matter only if transforms are the bottleneck (macOS
spawns workers, so guard the script with `if __name__ == "__main__"` and keep MPS
tensors out of them); `torch.profiler` says whether time is in forward, backward, the
step or waiting for data.

**Compute is countable, so count it before you start.** A dense layer costs n_in·n_out
multiply-accumulates per example; a convolution costs H_out·W_out·C_out·C_in·k²
(Problem 7). Two FLOPs per MAC is the forward cost; backward is about twice forward, so
a training step is roughly 3× the forward. Multiply by dataset size and epochs, divide
by measured FLOPs per second, and you have a predicted wall time; achieved over peak
(utilisation) is typically 20 to 40% for a convnet this size on the Mac. For
transformers the rule of thumb is 6 FLOPs per parameter per token, which budgets
Module 9's GPT in Lab 5.6.

**Reproducibility has a floor you set and a ceiling you accept.** `seed_everything`
seeds `random`, NumPy and PyTorch, and a seeded `torch.Generator` goes to the
`DataLoader`. On CUDA, `torch.use_deterministic_algorithms(True)` removes most residual
nondeterminism at a speed cost; MPS has no such switch, and small run-to-run variation
is normal. So a single run's accuracy is a sample: two seeds of the same CIFAR-10 config
differ by about 0.1 to 0.3 points, and a claimed improvement smaller than that is noise.
Report mean ± std over at least two seeds, three when it is close.

**Evaluation discipline turns runs into evidence.** Split 5,000 of CIFAR-10's 50,000
training images off as validation and tune on it; touch the test set once, at the end.
The unit of evidence is the ablation table: one row per change, everything else fixed,
mean ± std over seeds, sorted by effect. Write the rows with predicted numbers before
you run them, then fill in the measured ones; Lab 5.5 makes you do it for seven tricks.

**Forward links.** The harness is reused verbatim by Modules 6 to 10. BatchNorm's batch
dependence is why SimCLR in Module 8 needs large batches and why LayerNorm wins in
Module 9's transformer, whose residual stream is the identity path of this module at
scale. AdamW, warmup-cosine and gradient clipping are the Module 9 and 10 defaults;
the linear scaling rule and gradient accumulation are how you fit a large effective
batch on a small GPU. The FLOPs accounting returns as the 6ND rule in Module 9 and the
latency budget in Module 13.

## Reading

- Karpathy, "A Recipe for Training Neural Networks", 2019 (blog). Read it before Lab 5.1
  and again after Lab 5.4; it is this module's checklist.
- Goodfellow, Bengio, Courville, *Deep Learning* (free), ch. 8 (optimisation) and ch. 11
  (practical methodology).
- Bishop and Bishop, *Deep Learning: Foundations and Concepts* (free), ch. 7 to 9.
- Zhang, Lipton, Li, Smola, *Dive into Deep Learning* (free), ch. 12 (optimisation) and
  ch. 8 (modern convnets; §8.5 BatchNorm and §8.6 ResNet). Run the code.
- Prince, *Understanding Deep Learning* (free), ch. 6 to 9.
- Howard and Gugger, ch. 13 (convnets, BatchNorm, one-cycle) and ch. 16 (the training
  process).
- Glorot and Bengio, "Understanding the difficulty of training deep feedforward neural
  networks", 2010; He, Zhang, Ren, Sun, "Delving Deep into Rectifiers", 2015.
- Ioffe and Szegedy, "Batch Normalization: Accelerating Deep Network Training by
  Reducing Internal Covariate Shift", 2015; the title's explanation is now thought wrong,
  and Santurkar et al., "How Does Batch Normalization Help Optimization?", 2018, has the
  current one.
- He, Zhang, Ren, Sun, "Deep Residual Learning for Image Recognition", 2015.
- Kingma and Ba, "Adam: A Method for Stochastic Optimization", 2015; Loshchilov and
  Hutter, "Decoupled Weight Decay Regularization", 2019.
- Smith, "A disciplined approach to neural network hyper-parameters: Part 1", 2018;
  Goyal et al., "Accurate, Large Minibatch SGD: Training ImageNet in 1 Hour", 2017.
- DeVries and Taylor, "Improved Regularization of Convolutional Neural Networks with
  Cutout", 2017; Zhang, Cissé, Dauphin, Lopez-Paz, "mixup: Beyond Empirical Risk
  Minimization", 2018; Müller, Kornblith, Hinton, "When Does Label Smoothing Help?", 2019.
- Micikevicius et al., "Mixed Precision Training", 2018.
- David Page, "How to Train Your ResNet", parts 1 to 8 (myrtle.ai blog, 2018 to 2019).
  The best account in print of what each trick is worth on CIFAR-10.
- Karpathy, *Neural Networks: Zero to Hero*, the makemore videos on activations,
  gradients and BatchNorm (part 3) and manual backpropagation (part 4).

## Labs

### Lab 5.1: Harness v1 and the sanity checks

Goal: a harness you understand line by line, and the checks you run before every run.

1. Create `common/` as a package. `config.py`: `@dataclass class TrainConfig` (name,
   model, dataset, epochs, batch_size, lr, weight_decay, optimizer, schedule,
   warmup_frac, label_smoothing, seed, amp, num_workers, device, checkpoint_dir) with
   `from_cli()`. `seed.py`: `seed_everything(seed)`. `data.py`: `build_loaders(cfg)`
   returning train, val and test loaders, with 5,000 images split off the training set
   by a seeded generator and separate train and eval transforms. `models.py`:
   `MODEL_REGISTRY` and `build_model(cfg)`. `train.py`: a `Trainer` with `fit()`,
   `evaluate(loader)`, `save(path)` and `load(path)`, logging to MLflow and writing
   `last.ckpt` and `best.ckpt` with model, optimiser, scheduler and epoch.
   `sanity.py`: `loss_at_init(model, loader, num_classes)`, `overfit_one_batch(model,
   batch, steps=500)`, `check_input_stats(loader)`, `show_batch(loader, path)` and
   `lr_range_test(model, loader, lr_min=1e-6, lr_max=10, steps=300)`.
2. Register `mlp` (784-512-256-10, ReLU, optional BatchNorm1d and dropout) and train it
   on Fashion-MNIST (60,000 train, 10,000 test, 28×28 greyscale; mean 0.2860, std
   0.3530). Adam, lr 1e-3, batch 128, 20 epochs, no augmentation. Expect roughly 89 to
   90% test accuracy, the known ceiling for an MLP here.
3. Run every sanity check before training and record the numbers: loss at init within
   0.05 of ln 10 = 2.303 once the final layer is scaled down (note what the default init
   gives); one batch of 32 overfitted below 0.01 loss in under 500 steps; input mean
   within 0.05 of 0 and std within 0.05 of 1; the saved batch image; the range-test plot
   with your chosen peak marked.
4. Kill a run halfway with Ctrl-C, resume from `last.ckpt`, and confirm the final
   accuracy is within 0.2 points of an uninterrupted run with the same seed.
5. `common/tests/test_harness.py`: sanity checks pass on the MLP, a checkpoint
   round-trips to identical weights, train and val indices are disjoint, and two runs
   with the same seed give the same first-batch loss.

Done when: `uv run pytest common` passes, the MLP reaches at least 89% test accuracy in
a tracked run, resume works, and the five sanity-check outputs are in the notebook with
a sentence each.

### Lab 5.2: Initialisation and normalisation

Goal: see vanishing and exploding signal with your own instruments, then fix it.

1. Register `plain_cnn(depth=20, width=64, norm, init)`: 3×3 convolutions with no
   shortcuts, `norm` in {none, batchnorm}, `init` in {small (normal, std 0.01), xavier,
   he}, global average pooling and a linear head.
2. Write `common/instrument.py` with `ActivationStats` and `GradStats`: forward and
   backward hooks returning a DataFrame indexed by layer with output std and
   weight-gradient L2 norm.
3. On CIFAR-10 (50,000 train, 10,000 test; mean (0.4914, 0.4822, 0.4465), std (0.2470,
   0.2435, 0.2616)) record both statistics at init for the six init × norm combinations
   on one batch of 256. Plot activation std against depth on a log axis and gradient
   norm against depth, one line per config.
4. Train each config for one epoch with SGD, lr 0.05, momentum 0.9; record the
   statistics and loss curve again. Train the two best for 5 epochs.
5. Record the fraction of dead ReLUs per layer for the small-init and He-init nets
   after one epoch.

Done when: the plot shows small-init activations collapsing by many orders of magnitude
before layer 20, Xavier decaying by roughly 1/√2 per layer, and He and every BatchNorm
variant flat; the un-normalised small-init and Xavier nets train markedly slower over
one epoch than the He and BatchNorm ones (expect them still above 1.5 loss while the
others are below 1.2); and you have three sentences on why BatchNorm makes the init
choice nearly irrelevant.

### Lab 5.3: Optimiser and schedule study

Goal: know what optimiser, schedule and batch size are each worth under a fixed budget.

1. Write `resnet18_cifar(width)` now (Lab 5.5 finishes it) and use `width=32`, roughly
   2.8M parameters, so a 15-epoch run takes about 5 to 8 minutes on the Mac.
2. Common settings: crop and flip, 15 epochs, fp16 autocast, two seeds. Optimiser row at
   batch 256 with one epoch of warmup then cosine: SGD momentum 0.9 nesterov at peak lr
   0.1 with coupled weight decay 5e-4; Adam at 1e-3 with the same coupled 5e-4; AdamW at
   1e-3 with decoupled weight decay 0.05.
3. Schedule row, SGD at batch 256: constant lr 0.05; warmup-cosine to peak 0.1 (write
   `WarmupCosine` as a `LambdaLR`); `OneCycleLR(max_lr=0.2, pct_start=0.25)`.
4. Batch row, SGD warmup-cosine: batch 128 at peak 0.05; batch 512 at 0.05 (unscaled);
   batch 512 at 0.2 (linear scaling). Record seconds per epoch alongside accuracy.
5. Eight distinct configs, sixteen runs, about two hours on the Mac. Tabulate val
   accuracy as mean ± std with epoch time, and plot the three learning-rate curves.

Done when: the eight-row table is in the notebook and you have written three
conclusions with their supporting numbers: which optimiser wins at 15 epochs (expect
SGD nesterov ahead of Adam by 1 to 3 points with AdamW close behind, but report what
you measure), by how much warmup-cosine and one-cycle beat constant, and how much of the
gap between batch 512 and 128 the linear scaling rule recovers.

### Lab 5.4: The bug hunt

Goal: recognise the eight most common training bugs from their symptoms, blind.

1. Write `05-training/bugs/inject.py`. It copies `common/` and the Lab 5.1 script into
   `05-training/bugs/run_<seed>/`, applies three of eight bugs chosen with
   `random.Random(seed)` as marker-to-replacement patches on `# BUG-SITE: name` lines,
   and writes their names to `sealed_<seed>.json`. The eight: `optimizer.zero_grad()`
   removed; `model.eval()` removed at validation; normalisation with the wrong std
   (0.0353 for 0.3530); training labels shifted by one modulo 10; `F.softmax` applied
   before `nn.CrossEntropyLoss`; validation indices drawn from the training set; images
   and labels shuffled independently; learning rate 100× too high. Use the `mlp` with
   BatchNorm and dropout 0.2 so the `eval()` bug has a symptom.
2. For seeds 0, 1 and 2, run the injected script for 5 epochs with the instruments on.
   Using only the loss curves, per-layer gradient norms, confusion matrix,
   predicted-class histogram and sanity-check outputs, write the three bugs you believe
   are present with one line of evidence each in `diagnosis_<seed>.md`. Commit. Then
   open the sealed file; the commit order is your proof.
3. With the answers known, fix each bug alone and confirm which symptom it owned. One of
   the eight floors the loss near 1.46 while accuracy keeps rising; work out why.
4. Write `05-training/bugs/symptoms.md`: one row per bug with the symptom, the
   instrument that shows it, and the pre-training check that catches it. Note how you
   separated the look-alike pairs (100× lr and missing `zero_grad` both blow up; wrong
   normalisation and shifted labels both plateau).

Done when: at least seven of the nine planted bugs are identified blind with the commit
order proving it, the table has eight complete rows, and any check you lacked has been
added to `common/sanity.py` with a test.

### Lab 5.5: ResNet on CIFAR-10 above 93% (headline lab)

Goal: a strong, fast, reproducible CIFAR-10 result and an ablation table that says what
each trick was worth.

1. `05-training/cifar/resnet.py`: `ResNet18CIFAR(width=64, num_classes=10)`. A 3×3
   stride-1 stem of `width` channels and no max-pool, four stages of two BasicBlocks at
   widths (1, 2, 4, 8) × width and strides (1, 2, 2, 2), 1×1 projection shortcuts where
   the shape changes, global average pooling, linear head. 11.17M parameters at width
   64 (11,173,962 for the standard layout); assert it in a test. Zero-init each block's
   second BatchNorm γ.
2. Data: `RandomCrop(32, padding=4)`, `RandomHorizontalFlip()`, normalise, then your own
   `Cutout(size=16)` (one zeroed square per image, centre uniform, may overhang). Eval:
   normalise only. If Lab 5.6 shows the loader is the bottleneck, hold CIFAR-10 as one
   uint8 tensor (about 150 MB) on the device and do crop, flip and Cutout as batched
   tensor ops.
3. Training: batch 256, SGD momentum 0.9 nesterov, peak lr 0.2 (linear scaling from 0.1
   at 128), weight decay 5e-4 on conv and linear weights but not BatchNorm parameters or
   biases, `nn.CrossEntropyLoss(label_smoothing=0.1)`, one-cycle with `pct_start=0.15`
   or a 3-epoch linear warmup then cosine to zero, 35 to 40 epochs, fp16 autocast,
   `channels_last`. Validate on the 5,000 split every epoch; test once.
4. Expect 94 to 95% test accuracy and roughly 30 to 60 s per epoch on the Mac, so 25 to
   40 minutes. 94% is the well-known bar: Page's cifar10-fast reached it in 79 s on a
   V100 in 2018 and Keller Jordan's airbench94 in a few seconds on an A100. If the Mac
   needs more than 90 minutes, run on a Colab T4 (15 to 20 minutes), code unchanged.
5. Ablations, `05-training/cifar/ablate.py`: baseline plus seven single removals: no
   augmentation; no Cutout; no label smoothing; no weight decay; constant lr 0.05 in
   place of the schedule; no BatchNorm (identity in its place, He init, lr 0.02 so it
   trains at all, which is part of the result); no residual connections at the same
   depth. Two seeds each at a 20-epoch budget: sixteen runs, roughly 4 to 6 hours on the
   Mac queued overnight or about 2 hours on a T4. The script skips any config that
   already has a finished MLflow run, so it survives a disconnect.
6. Write `05-training/ablations.md`: the table sorted by mean drop from baseline with
   std, a sentence per row on mechanism, and above it, unedited, the ranking you
   predicted before running.

Done when: a single tracked run reaches at least 93.0% test accuracy from random
initialisation with wall time and device recorded; the parameter-count and output-shape
tests pass; the ablation table has eight rows of mean ± std over two seeds; and
`ablations.md` ranks the tricks with your prediction preserved above the result.

### Lab 5.6: Throughput and the compute budget

Goal: know where the time goes and predict a run's wall time before starting it.

1. `05-training/cifar/bench.py`: training samples per second for `ResNet18CIFAR(64)`
   (forward, backward, step; `torch.mps.synchronize()` before reading the clock; 20
   warm-up then 50 timed steps) at batch 64, 128, 256, 512 and 1,024, fp32 and fp16
   autocast, synthetic data on the device. Plot samples/sec against batch size.
2. With the real `DataLoader` at batch 256 and `num_workers` in {0, 2, 4, 8}, measure
   end-to-end samples/sec; the gap to step 1 is the pipeline's cost. Compare with
   GPU-side augmentation.
3. Profile 20 steps with `torch.profiler.profile(activities=[ProfilerActivity.CPU])` and
   `record_function` blocks around data, forward, backward and step; print
   `key_averages().table(sort_by="cpu_time_total", row_limit=20)`.
4. Write `count_flops(model, input_shape)` by hand for conv and linear layers and check
   it against `torch.utils.flop_counter.FlopCounterMode` on the CPU at batch 1: about
   0.56 GMACs, 1.1 GFLOPs, per image forward. Multiply by 3 for a training step and by
   50,000 × 35 for the run; divide by your Lab 5.5 wall time for achieved FLOPs/s, and by
   the M2 Pro's peak (roughly 5.7 or 6.8 TFLOPS fp32 for the 16- and 19-core parts) for
   utilisation.
5. Write the compute budget for Module 9's GPT in one paragraph: 6 FLOPs per parameter
   per token, a 10M-parameter model, 20M tokens seen, your achieved rate, the predicted
   minutes and the assumptions. Module 9 checks it.

Done when: the two throughput plots and the profiler table are in the notebook, the
analytic FLOP count matches `FlopCounterMode` within 5%, you have a utilisation figure
for the Mac, and the budget paragraph names a number of minutes and its assumptions.

## Problem set

1. For y = Wx followed by ReLU, with W entries independent, mean zero, variance σ², and
   x symmetric about zero, show E[ReLU(y_i)²] = ½ n_in σ² E[x²]. Conclude that σ² = 2/n_in
   preserves the second moment and that Xavier's 1/n_in halves it per layer. Compute the
   activation scale after 20 layers under each.
2. With m₀ = v₀ = 0 and a constant gradient g, show m_t = (1−β₁ᵗ)g and v_t = (1−β₂ᵗ)g²,
   so Adam's corrected estimates are exact. Compute the uncorrected step at t = 1 in
   units of η for β₁ = 0.9, β₂ = 0.999, and the number of steps until the uncorrected v
   is within 10% of g².
3. Write SGD's update for L + (λ/2)‖w‖² and show it equals w ← (1−ηλ)w − η∇L. Write
   the same for Adam and show the decay term is divided by √v̂ + ε. Construct a
   two-parameter quadratic where coupled L2 and decoupled decay reach different fixed
   points under Adam.
4. For one BatchNorm feature over a batch of B, with μ, σ², x̂_i = (x_i − μ)/√(σ² + ε)
   and y_i = γx̂_i + β, derive ∂L/∂γ, ∂L/∂β and ∂L/∂x_i from ∂L/∂y_i. Show Σ_i ∂L/∂x_i = 0
   and Σ_i x̂_i ∂L/∂x_i = 0, and say what each means about the directions in which the
   layer's input gradient cannot move.
5. Model the minibatch gradient as ∇L + ξ with Cov(ξ) = Σ/B. Show that k SGD steps with
   batch B and rate η, assuming the gradient is constant over the k steps, match one
   step of batch kB and rate kη in expectation and in noise covariance. State what the
   assumption excludes and why warmup helps.
6. For K classes with target (1−ε) + ε/K on the true class and ε/K elsewhere, find the
   softmax output that minimises the cross-entropy and show the optimal logit gap
   between the true class and any other is ln(1 + K(1−ε)/ε). Evaluate it for K = 10,
   ε = 0.1, and compare with the one-hot case.
7. Compute the multiply-accumulates of a 3×3 convolution with C_in = C_out = 64 on a
   32×32 map, then of the whole `ResNet18CIFAR(64)` forward pass including the
   projection shortcuts. Convert to FLOPs, multiply out the training FLOPs for 40 epochs
   of CIFAR-10, and predict the wall time at 1.5 TFLOPS achieved.
8. For y = x + F(x), write ∂y/∂x and the gradient through L stacked blocks. If each
   ∂F/∂x has spectral norm at most c < 1, bound the gradient norm through L blocks
   between (1−c)^L and (1+c)^L, and contrast with c^L for the plain network. Say what
   this predicts for the per-layer gradient-norm plot in Lab 5.2.
9. List every tensor a BasicBlock's backward pass keeps (conv inputs, BatchNorm inputs
   and saved statistics, ReLU masks) and count elements per image for each stage of
   `ResNet18CIFAR(64)`. Multiply for batch 256 in fp32, explain what fp16 autocast
   halves and what it does not (master weights, optimiser state), and check against
   `torch.mps.current_allocated_memory()` after one training step.

## Deliverables

- `common/` (config, seed, data, models, train, sanity, instrument) with `common/tests/`
  passing under pytest; every later module imports it.
- `05-training/harness/fmnist.py`, `init_study.py`, `optim_study.py`;
  `05-training/cifar/resnet.py`, `train.py`, `ablate.py`, `bench.py` with
  `tests/test_resnet.py` (parameter count, output shape, FLOPs within 5% of
  `FlopCounterMode`); `05-training/bugs/inject.py`, `diagnosis_*.md`, `symptoms.md`;
  `05-training/ablations.md`.
- Notebook with all six labs' figures and tables.
- Write-up on the CIFAR-10 result and ablation, following `writeup-template.md`. The
  Limitations section should engage with what a 20-epoch, two-seed ablation can and
  cannot say about the 35-epoch result, and how far a CIFAR-10 ranking of tricks
  transfers to a dataset of a different size and kind.

## Stretch

- Reproduce the rest of Page's bag of tricks: a fixed whitening stem, test-time
  augmentation with flips, and the 8-layer ResNet he ends with. Aim for 94% in under 10
  epochs, then read airbench94's code and list the tricks you have not met.
- Add an exponential moving average of the weights
  (`torch.optim.swa_utils.AveragedModel`) to the harness and measure its effect at 20
  and 40 epochs.
- Measure the gradient noise scale during the Lab 5.5 run (McCandlish et al., "An
  Empirical Model of Large-Batch Training", 2018) and check whether it predicts where
  the linear scaling rule broke in Lab 5.3.
- Train the same network on CIFAR-100 with the same recipe and record how much of the
  ablation ranking survives.

## Next

Module 6 uses the harness unchanged on a real, small vision dataset and spends its week
on the two things this module took as given: what a convolution actually costs, and
what to do when you have 3,680 labelled images rather than 50,000, which is to start
from someone else's weights. The ablation-table habit carries straight over.
