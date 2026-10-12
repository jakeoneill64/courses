#import "../lib/template.typ": *

= Neural networks <ch-networks>

#chapter-meta(
  time: [6 hours],
  builds: [Activation scales measured through thirty layers for five initialisations, with He initialisation derived from the variance of a layer; an MNIST classifier trained to 97.9% in your own library; and its PyTorch twin, matched to `tiny` step for step for a hundred steps, then timed on the CPU and the GPU.],
  needs: [Chapters 1.2 to 1.4.],
)

#why[
  A linear model stops at 92% on MNIST, because one template per digit cannot capture the ways people write it. Composing simple functions, each a linear map followed by a nonlinearity, gives models that can represent far richer patterns, and that learn features no one designed. This chapter builds such networks in `tiny`, explains why the scale of their initial weights decides whether they can be trained at all, and puts the hand-built library side by side with PyTorch.
]

#skip-test(
  rule: [If all four are easy, read the section on initialisation and do Labs 1.5.1 and 1.5.3.],
  [Why is a stack of linear layers with no activation functions between them no more expressive than one linear layer?],
  [A layer has $n$ inputs of unit variance and a ReLU. What variance must its weights have to keep its outputs' second moment equal to its inputs'?],
  [What happens to the activations of a 30-layer ReLU network whose weights are drawn with standard deviation 0.01?],
  [Why can a small network train faster on a CPU than on a GPU?],
)

== Core ideas

=== Layers and nonlinearities

A _multilayer perceptron_ (MLP) alternates linear maps and element-wise nonlinear functions:

$ h_1 = phi(W_1^T x + b_1), quad h_2 = phi(W_2^T h_1 + b_2), quad dots, quad z = W_L^T h_(L-1) + b_L. $

The vectors $h_l$ are _hidden activations_, and the last layer outputs the logits of Chapter 1.3. Without the nonlinearity $phi$ the composition would collapse into a single linear map, since a product of matrices is a matrix. With it, each layer can carve its input space along new boundaries, and a network with one wide enough hidden layer can approximate any continuous function on a bounded region as closely as desired. Depth makes this efficient: many functions that a deep network represents compactly would need exponentially many units in a shallow one.

The usual nonlinearity is the _rectified linear unit_, $"ReLU"(z) = max(0, z)$: cheap, with a gradient of 1 wherever it is active, so gradients pass through it undiminished. `tanh` and the sigmoid saturate for large inputs, where their gradients vanish. Transformers use smooth relatives of ReLU, such as GELU and SiLU, which Unit 2 meets.

In `tiny`, a network is a tree of _modules_. A module holds parameters and sub-modules, and finds its parameters by walking its attributes:

#snippet("aif/tiny/nn.py", "module", caption: [The base class: parameters, a training flag, and calling `forward`])

#snippet("aif/tiny/nn.py", "linear", caption: [A linear layer with weights of shape (inputs, outputs), initialised with a gain])

#snippet("aif/tiny/nn.py", "mlp", caption: [An MLP: linear layers with ReLU between them and none after the last])

=== Initialisation

Before any training, a network's output depends only on its random initial weights, and their scale decides how signals travel through it. Consider a layer $z = W^T h$ with $n$ inputs, whose weights are independent, of mean zero and variance $"Var"(w)$. Each output is a sum of $n$ products, so

$ "Var"(z) = n "Var"(w) E[h^2]. $

If $h$ comes from a ReLU applied to a symmetric $z'$ of the previous layer, half of $z'$ is cut to zero and $E[h^2] = 1/2 "Var"(z')$. Keeping the variance constant from layer to layer therefore needs

$ "Var"(w) = 2 / n, $

_He initialisation_. For `tanh`, which is close to the identity near zero, the factor 2 disappears: $"Var"(w) = 1 \/ n$, _Xavier initialisation_, in its simplest form. Any other scale multiplies the variance by a constant factor at every layer, so after $L$ layers it has grown or shrunk by that factor to the power $L$.

#snippet("u1/init.py", "depth", caption: [Push a batch through thirty random layers and record the scale of each layer's output])

#snippet("u1/init.py", "schemes", caption: [Five choices of weight scale])

#console(read("/src/console/u1-init.txt"), caption: [Activation scale after 1, 10 and 30 layers of width 512])

#fig("u1-init", caption: [The standard deviation of each layer's activations, on a logarithmic scale. Only He initialisation holds it steady through thirty ReLU layers.]) <fig-init>

With a standard deviation of 0.01 the signal shrinks by a factor of about 6.3 per layer and is gone, $10^(-25)$, by the thirtieth; with 0.1 it grows and reaches $10^6$. Xavier's scale, right for `tanh`, loses half the variance at every ReLU. The gradients flowing backwards obey the same arithmetic, so a network whose activations vanish also has vanishing gradients, and cannot be trained. `tiny`'s `Linear` uses He's scale by default, and Xavier's for the last layer, which has no ReLU after it.

=== Training on MNIST

MNIST's images are scaled to $[0, 1]$ and then standardised with the training set's mean and standard deviation, so that inputs, like activations, have roughly unit scale. Five thousand training images are held back as a _validation set_, for choosing settings and watching for overfitting; the 10,000 test images are touched only at the end.

#snippet("u1/common.py", "split", caption: [Standardised images and a fixed validation split])

The network has two hidden layers of 256 and 128 units, 235,146 parameters, and trains with AdamW at the learning rate found by Chapter 1.4's range test:

#snippet("u1/mnist_tiny.py", "train", caption: [The training loop: shuffle, forward, loss, backward, step])

#console(read("/src/console/u1-mnist-tiny.txt"), caption: [Eight epochs of `tiny` on the M2 Pro's CPU])

The test accuracy of 97.9% halves the linear model's error rate twice over. Validation accuracy wobbles from epoch to epoch by a few tenths of a percentage point, partly the noise of a 5,000-image estimate and partly the training itself; the test score is one number, read once.

=== The same network in PyTorch

PyTorch computes the same things with the same arithmetic, so a twin of the network, built from `tiny`'s initial weights, should follow it exactly. PyTorch's `Linear` stores its weight as (outputs, inputs), the transpose of `tiny`'s:

#snippet("u1/mnist_torch.py", "twin", caption: [Copying `tiny`'s weights into a PyTorch network])

#snippet("u1/mnist_torch.py", "lockstep", caption: [Both networks trained on identical batches, in float64])

The usual PyTorch version follows; from Chapter 1.7 on, programs are written this way:

#snippet("u1/mnist_torch.py", "pytorch", caption: [The network and training loop in idiomatic PyTorch])

#console(read("/src/console/u1-mnist-torch.txt"), caption: [Lockstep agreement, then the network on the CPU and on the GPU])

After a hundred steps the two libraries' losses agree to $10^(-15)$. The timings carry a lesson about scale. On the CPU, PyTorch and `tiny` take about the same time, since both spend it in the same BLAS library. On the GPU the network trains _more slowly_. Each step launches dozens of small operations, and every launch costs microseconds of overhead in the driver, while the matrices involved, 128 rows by a few hundred columns, are far too small to occupy the GPU's thousands of arithmetic units. The GPU wins when there is enough work per operation, and Lab 1.5.3 finds where that happens.

#keyidea[
  A layer preserves the scale of its input when the variance of its weights is the gain of its activation divided by its number of inputs: 2 for ReLU, 1 for `tanh` or no activation. Initialisation that ignores this rule makes deep networks untrainable before training starts.
]

#inpytorch[
  `torch.nn.Module` collects parameters as `tiny`'s does, and `torch.nn.Linear(n_in, n_out)` holds a weight of shape (n_out, n_in) and computes $x W^T + b$. Its default initialisation is uniform with variance $1 \/ (3 n)$, deliberately conservative; `torch.nn.init.kaiming_normal_(w, nonlinearity="relu")` gives He's. `model.train()` and `model.eval()` switch layers such as dropout between their two behaviours, and `model.state_dict()` holds every parameter for saving.
]

#reading(
  [Xavier Glorot and Yoshua Bengio, "Understanding the Difficulty of Training Deep Feedforward Neural Networks", AISTATS 2010.],
  [Kaiming He, Xiangyu Zhang, Shaoqing Ren and Jian Sun, "Delving Deep into Rectifiers", ICCV 2015, section 2.2.],
  [Simon Prince, _Understanding Deep Learning_, MIT Press, 2023, chapters 3, 4 and 7. Free online.],
)

== Labs

#lab([Predicting the scale], goal: [Check the variance argument quantitatively, and extend it to a new activation.], time: [1.5 hours], code: "code/u1/init.py")[
  + For each scheme in the program, predict the ratio of successive layers' scales from the variance formula, and compare it with the measurement.
  + Add GELU, $x Phi(x)$ with $Phi$ the standard normal distribution function. Find by experiment the weight variance that keeps its activations steady, and compare it with $2 \/ n$.
  #done-when(
    [Your predicted ratios match the measured ones within 5% for the four ReLU schemes.],
    [You have GELU's gain, measured to two significant figures.],
  )
  #evidence([The table of predicted and measured ratios, and the GELU experiment.])
]

#lab([Width and depth], goal: [See what capacity buys on MNIST.], time: [1.5 hours], code: "code/u1/mnist_tiny.py")[
  + Train MLPs in `tiny` with one hidden layer of 32, 128, 512 and 2048 units, and with two, four and eight hidden layers of 256.
  + Record parameters, test accuracy and seconds per epoch for each.
  #done-when(
    [Your table covers all seven networks.],
    [You can say where extra capacity stopped helping, and whether width or depth was the better use of parameters.],
  )
  #evidence([The table and a plot of accuracy against parameters.])
]

#lab([When the GPU wins], goal: [Find the size at which the GPU overtakes the CPU for this kind of network.], time: [1.5 hours], code: "code/u1/mnist_torch.py")[
  + Time one epoch of the PyTorch network on both devices at batch sizes 32, 128, 512 and 2048, and at hidden widths 256, 1024 and 4096.
  + Find the crossover points and relate them to the matrix sizes in Chapter 1.1's ladder.
  #done-when(
    [You have both timings for all twelve combinations.],
    [You can predict, for a new width and batch size, which device will be faster.],
  )
  #evidence([The timing table and your rule of thumb.])
]

#lab([Inside the network], goal: [Look at what the first layer learned and how the hidden units behave.], time: [1.5 hours], code: "code/u1/mnist_tiny.py")[
  + Draw 32 of the first layer's 256 weight vectors as $28 times 28$ images, as Chapter 1.3 drew the linear model's templates.
  + Measure the fraction of hidden units that output exactly zero, per layer, on the test set, and find any units that are zero for every input.
  #done-when(
    [You can describe the kinds of feature the first layer detects, with examples.],
    [You have the fraction of zeros in each layer and a count of units that never activate.],
  )
  #evidence([The images, the fractions and the count.])
]

#problems(
  [Show that two stacked linear layers, $W_2^T (W_1^T x + b_1) + b_2$, equal one linear layer, and give its weight and bias.],
  [Count the parameters of an MLP with layer widths 784, 256, 128, 10, and check the program's figure of 235,146.],
  [Derive $E["ReLU"(z)^2] = 1/2 "Var"(z)$ for $z$ symmetric about zero. Where does the argument use the symmetry?],
  [The output of `tanh` saturates at $plus.minus 1$. If the pre-activations of a layer have standard deviation 5, what fraction of units have gradients below 0.01?],
  [PyTorch's default initialisation has variance $1 \/ (3 n)$. By what factor does it shrink a ReLU network's activations per layer, and after 30 layers?],
)

#checklist(
  [I can explain why nonlinearities are needed and what ReLU's advantages are.],
  [I can derive He and Xavier initialisation from the variance of a layer.],
  [I can train an MLP in `tiny` and in PyTorch and show that they agree.],
  [I can explain when a GPU is slower than a CPU, and measure where it overtakes.],
  [Lab 1.5.1–1.5.4 done-when criteria all hold, with evidence filed.],
)
