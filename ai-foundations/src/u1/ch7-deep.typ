#import "../lib/template.typ": *

= Training deep networks <ch-deep>

#chapter-meta(
  time: [6 hours],
  builds: [A 30-layer network that will not train, measured layer by layer, and made to train by initialisation, normalisation and residual connections; batch, layer and RMS normalisation written by hand and matched to PyTorch's; and three planted bugs diagnosed from training statistics alone.],
  needs: [Chapters 1.5 and 1.6. From here on, programs use PyTorch.],
)

#why[
  Depth is what makes neural networks powerful, and it is also what makes them hard to train: signals and gradients pass through every layer, and small distortions compound. Two inventions made very deep networks routine, normalisation layers and residual connections, and both sit at the heart of the transformer that Unit 2 builds. This chapter shows the failure they fix, builds them, and then turns to the other half of training deep networks in practice, finding out what is wrong when a run misbehaves.
]

#skip-test(
  rule: [If all four are easy, read the sections on residual connections and debugging, and do Labs 1.7.2 and 1.7.3.],
  [A 30-layer ReLU network uses PyTorch's default initialisation. What happens to the gradient of its first layer, and why?],
  [How does batch normalisation behave differently in training and evaluation, and what goes wrong with a batch of one?],
  [Why is a pre-norm residual network easier to train than a post-norm one?],
  [Training loss rises steadily from the first step and the gradient norm grows without bound. Name two bugs that would do this.],
)

== Core ideas

=== Gradients through many layers

By the chain rule, the gradient reaching layer $l$ is the gradient at the output multiplied by the Jacobian of every layer after it. If each multiplication shrinks the gradient by a factor, thirty of them shrink it by that factor to the thirtieth power; if each grows it, it explodes. Chapter 1.5 showed the forward version of this arithmetic. The program measures the backward version in four 30-layer networks of width 256 on MNIST, each trained for two epochs:

#snippet("u1/deep.py", "variants", caption: [Four ways to stack thirty layers])

#snippet("u1/deep.py", "grad-norms", caption: [The gradient norm of each layer's weights for one batch])

#console(read("/src/console/u1-deep.txt"), caption: [Thirty layers four ways])

#fig("u1-deep", caption: [Gradient norm of each layer's weights at initialisation, on a logarithmic scale. With PyTorch's default initialisation the first layer receives a gradient nearly ten orders of magnitude smaller than the last.]) <fig-deep>

With PyTorch's default initialisation, whose variance is a sixth of He's, the first layer's gradient is $10^(-12)$: nothing reaches it, the loss stays at $ln 10$, and the network never leaves chance. He initialisation keeps the gradients level at the start, and the network learns, but slowly and unreliably: run with other seeds, `--seed`, its accuracy after two epochs ranges from about 40% to about 85%, because nothing stops the scales drifting as the weights change. Initialisation fixes the starting point, not the journey.

=== Normalisation layers

A _normalisation layer_ rescales activations to zero mean and unit variance at every step of training, wherever the weights have drifted, and then applies a learned scale $gamma$ and shift $beta$ so that the network can undo it where that helps:

$ y = gamma dot.o (x - mu) / sqrt(sigma^2 + epsilon) + beta. $

The variants differ in which numbers the statistics $mu$ and $sigma^2$ are computed over. _Batch normalisation_ computes them per feature, over the examples in the batch. That makes each example's output depend on the others in its batch, and at evaluation time, when there may be no batch, it uses running averages accumulated during training instead:

#snippet("u1/norms.py", "batchnorm", caption: [Batch normalisation with running statistics for evaluation])

_Layer normalisation_ computes them per example, over its features, so each example is treated alone and training and evaluation behave identically; it is the choice for sequences, where batches mix lengths and positions. _RMS normalisation_ drops the mean and the shift and divides by the root-mean-square alone, which is cheaper and works as well in transformers, including the ones in this course:

#snippet("u1/norms.py", "layernorm", caption: [Layer normalisation and RMS normalisation])

#console(read("/src/console/u1-norms.txt"), caption: [All three match `torch.nn`, outputs, gradients and running statistics])

The batch statistics use the biased variance, dividing by $n$, while the running variance is updated with the unbiased one, dividing by $n - 1$. That detail is PyTorch's convention and a good example of what matching an implementation to the last digit catches.

=== Residual connections

A _residual connection_ adds a block's input to its output: $h_(l+1) = h_l + f_l (h_l)$. Each block then learns a correction to an identity map instead of a whole new representation, and the derivative of $h_(l+1)$ with respect to $h_l$ is $I + partial f_l \/ partial h_l$: the identity term carries gradients straight from the loss to every layer, however deep the network. Dividing each branch by $sqrt(L)$ keeps the sum of thirty branches from growing with depth.

Where the normalisation goes matters. _Post-norm_ adds the branch to the residual path and then normalises the sum, $h_(l+1) = "Norm"(h_l + f_l (h_l))$, as the original transformer did; _pre-norm_ normalises the branch's input and leaves the residual path clean, $h_(l+1) = h_l + f_l ("Norm"(h_l))$. At a learning rate of $10^(-3)$, the post-norm network is unstable: it reaches 63% in the console, and with seeds 1, 2 and 3 it reaches 57% once and stays at chance twice, while the pre-norm residual network reaches 96.6% in two epochs. Post-norm is trainable, but it needs care: at a learning rate of $10^(-4)$ it reaches 94% in one epoch, and with a warm-up it tolerates more. Pre-norm, which every transformer in this course uses, simply works.

#fig("u1-blocks", caption: [Three ways to build a layer: plain, post-norm residual and pre-norm residual. Only the last leaves an unobstructed path from output to input; post-norm puts a normalisation on it after every layer.]) <fig-blocks>

#keyidea[
  Normalisation keeps every layer's activations at a healthy scale throughout training, and residual connections give gradients a direct path through any depth. Together, in the pre-norm arrangement, they make depth almost free to train.
]

=== When training goes wrong

Most failed training runs do not crash. They train to a disappointing number, or plateau, or diverge after hours, and the cause can be anywhere: the data, the model, the loss, the optimiser, or the loop that connects them. Debugging them is a skill with a method.

Before training, check that the initial loss is what chance predicts, $ln K$ for $K$ classes, and that the model can drive the loss to nearly zero on a single small batch; a model that cannot overfit one batch has a bug, not a capacity problem. During training, log more than the loss: the gradient norm, the scale of activations and logits, the learning rate, and an accuracy. Each common bug leaves a characteristic pattern in these numbers. Change one thing at a time, keep a known-good run to compare with, and distrust any result that you cannot reproduce.

`u1/mystery.py` contains three runs of Chapter 1.5's network, labelled A, B and C, each with one bug planted in it, and a clean run for comparison. Lab 1.7.3 asks you to diagnose them from their statistics before reading the code. This is the clean run:

#console(read("/src/console/u1-mystery-clean.txt"), caption: [The clean run: the reference against which the mystery runs are read])

Its loss starts at 2.317, close to $ln 10$; the gradient norm settles below 1 after an early peak; the logits stay in the tens; the validation accuracy reaches 96%.

#hazard(title: [Pitfall])[
  A bug that only lowers final accuracy by a few points is the hardest kind to find, because the run looks healthy. Compare against a baseline you trust, from a paper, a library or your own earlier run, and treat any unexplained shortfall as a bug until shown otherwise.
]

#inpytorch[
  `torch.nn.BatchNorm1d`, `LayerNorm` and `RMSNorm` are this chapter's layers. `module.register_forward_hook` and `register_full_backward_hook` attach functions that see every layer's activations and gradients, the basis of any training monitor. `torch.autograd.set_detect_anomaly(True)` finds the operation that first produced a NaN, at a large cost in speed.
]

#reading(
  [Sergey Ioffe and Christian Szegedy, "Batch Normalization", ICML 2015.],
  [Kaiming He, Xiangyu Zhang, Shaoqing Ren and Jian Sun, "Deep Residual Learning for Image Recognition", CVPR 2016.],
  [Ruibin Xiong and others, "On Layer Normalization in the Transformer Architecture", ICML 2020: pre-norm against post-norm.],
  [Andrej Karpathy, "A Recipe for Training Neural Networks", 2019, a practitioner's checklist.],
)

== Labs

#lab([Depth, measured], goal: [Find how deep each kind of network can usefully go.], time: [1.5 hours], code: "code/u1/deep.py")[
  + Train the plain He-initialised network and the pre-norm residual network at depths 5, 10, 20, 30 and 50, two epochs each, with three seeds per setting: `--kinds "plain, He init" "pre-norm residual" --depth 5 --seed 1`, and so on.
  + Plot validation accuracy against depth, with the spread across seeds.
  #done-when(
    [You have both curves with their spreads.],
    [You can state the depth beyond which the plain network becomes unreliable on your machine.],
  )
  #evidence([The plot and the table behind it.])
]

#lab([Taming post-norm], goal: [Make the post-norm network train, and measure what it needed.], time: [1 hour], code: "code/u1/deep.py")[
  + Train the post-norm network at learning rates from $3 times 10^(-5)$ to $10^(-3)$, with and without a linear warm-up over 500 steps: `--kinds post-norm --lr 3e-4 --warmup 500`, and so on.
  + Record the validation accuracy of each.
  #done-when(
    [Your table shows the highest learning rate at which post-norm trains, with and without warm-up.],
    [You can explain the difference using the gradient norms at the start of training.],
  )
  #evidence([The table and the gradient-norm comparison.])
]

#lab([Three mystery runs], goal: [Diagnose training bugs from their statistics alone.], time: [1.5 hours], code: "code/u1/mystery.py")[
  + Run `uv run -m u1.mystery --case A`, then B, then C. Their output is below.
  + For each, write down which numbers depart from the clean run's, what bug would cause that pattern, and how you would confirm it. Only then read `run` and check.
  #console(read("/src/console/u1-mystery-a.txt"), caption: [Case A])
  #console(read("/src/console/u1-mystery-b.txt"), caption: [Case B])
  #console(read("/src/console/u1-mystery-c.txt"), caption: [Case C])
  #done-when(
    [You named all three bugs before reading the code.],
    [For each, you can point to the statistic that gave it away.],
  )
  #evidence([Your three written diagnoses, dated before you read the code.])
]

#lab([A training monitor], goal: [Build the tool you will use on every later run.], time: [2 hours], code: "code/u1/deep.py")[
  + Write a class that attaches forward and backward hooks to every `Linear` layer of a model and records, each $n$ steps, the standard deviation of its outputs and the norm of its weight gradient.
  + Use it on the four deep networks and draw the statistics as heat maps of layer against step.
  #done-when(
    [Your monitor works on any `torch.nn.Module` without changes to the model.],
    [Your heat maps show the difference between the plain and pre-norm networks over training, not just at initialisation.],
  )
  #evidence([The monitor's code and the heat maps.])
]

#problems(
  [For a residual network $h_(l+1) = h_l + f_l (h_l)$, write $partial h_L \/ partial h_0$ as a product, and expand it to show the term that passes the gradient unchanged.],
  [Batch normalisation with a batch of one example: what does it output during training, and why is the network then unable to learn?],
  [Why does RMS normalisation work almost as well as layer normalisation in transformers? What does dropping the mean give up?],
  [A residual network adds 30 branch outputs of variance $v$ each to an input of variance 1. Without the $1 \/ sqrt(L)$ scaling, what is the output variance? With it?],
  [A run's loss is fine for 10,000 steps, then becomes NaN. List four possible causes and the first thing you would check for each.],
)

#checklist(
  [I can explain vanishing and exploding gradients, and measure them layer by layer.],
  [I can implement batch, layer and RMS normalisation and explain how they differ.],
  [I can explain residual connections and why pre-norm trains more easily than post-norm.],
  [I can debug a training run systematically from its statistics.],
  [Lab 1.7.1–1.7.4 done-when criteria all hold, with evidence filed.],
)
