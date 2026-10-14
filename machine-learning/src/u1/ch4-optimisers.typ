#import "../lib/template.typ": *

= Optimisers <ch-optimisers>

#chapter-meta(
  time: [5 hours],
  builds: [SGD, momentum, Nesterov momentum, RMSProp, Adam and AdamW written from their update rules and matched to PyTorch's to sixteen digits; their paths through an ill-conditioned valley; a learning-rate range test; and the warm-up and cosine schedule that Unit 2's pretraining uses.],
  needs: [Chapters 1.2 and 1.3.],
)

#why[
  The gradient gives the downhill direction but not how far to step, or how to use what earlier steps showed about the shape of the loss. The optimiser handles both. The learning rate is the setting that most often decides whether a training run succeeds. If it is too small, the loss barely falls for hours, and if it is too large, the loss diverges. This chapter derives the optimisers in common use from what goes wrong with plain gradient descent, implements each and checks that it matches PyTorch's, and ends with methods for choosing a learning rate by measurement.
]

#skip-test(
  rule: [If all four are easy, read the sections on Adam and schedules, and do Labs 1.4.3 and 1.4.4.],
  [Gradient descent minimises $f(x) = 1/2 lambda x^2$ with step size $eta$. For which $eta$ does it converge, and for which is convergence fastest?],
  [What does momentum do in a long, narrow valley, and roughly how many fewer steps can it take?],
  [What is Adam's bias correction for, and what would happen in the first steps without it?],
  [How does AdamW's weight decay differ from adding an L2 penalty to the loss when using Adam?],
)

== Core ideas

=== Gradient descent and its step size

Gradient descent repeats $theta <- theta - eta nabla cal(L)(theta)$ with a _learning rate_ $eta$. Its behaviour is easiest to see on a quadratic, which every smooth loss resembles near a minimum. On $f(x) = 1/2 lambda x^2$ the update is $x <- (1 - eta lambda) x$, so the error shrinks by the factor $|1 - eta lambda|$ each step. Descent therefore converges if $0 < eta < 2 \/ lambda$, fastest at $eta = 1 \/ lambda$, and oscillates with growing amplitude beyond $2 \/ lambda$.

A real loss curves differently in different directions. Near a minimum it is approximately $1/2 (theta - theta^*)^T H (theta - theta^*)$, where the _Hessian_ $H$ holds the second derivatives, and each eigenvector of $H$ is a direction with its own curvature $lambda_i$. A single learning rate must serve them all. It must stay below $2 \/ lambda_max$ to avoid diverging along the sharpest direction, and then progress along the flattest takes about $lambda_max \/ lambda_min$ steps to shrink the error by a constant factor. That ratio, the _condition number_ $kappa$, measures how hard a problem is for gradient descent, and a long, narrow valley has a large one.

#snippet("u1/valley.py", "valley", caption: [A quadratic valley with curvatures 1 and 50, rotated by 30 degrees])

In practice the gradient is also noisy. Training computes it on a _minibatch_ of examples rather than the whole dataset, which makes each step far cheaper and adds noise whose size shrinks as the batch grows. This _stochastic gradient descent_ is what "SGD" means. The noise also helps the parameters escape sharp minima, which tend to generalise worse.

=== Momentum

In a narrow valley, gradient descent zig-zags across the steep walls while creeping along the floor. _Momentum_ keeps a running sum of past gradients, a velocity, and steps along it:

$ b <- mu b + g, quad theta <- theta - eta b. $

Components of the gradient that keep their sign, along the valley floor, accumulate, while components that alternate, across it, cancel. With $mu$ and $eta$ tuned to the curvatures, the number of steps falls from about $kappa$ to about $sqrt(kappa)$. _Nesterov momentum_ evaluates the step as if the velocity had already been applied, which damps overshooting. In the form PyTorch uses, it steps along $g + mu b$ instead of $b$.

#snippet("aif/tiny/optim.py", "sgd", caption: [SGD with optional momentum, Nesterov momentum and weight decay, as PyTorch defines them])

=== Adaptive methods: RMSProp and Adam

Momentum still uses one learning rate for every parameter. In a network, gradients for different parameters can differ in size by orders of magnitude, for example between an embedding of a rare word and the bias of a busy layer. _RMSProp_ divides each parameter's step by a running root-mean-square of its own gradients, so each moves at a similar rate:

$ v <- alpha v + (1 - alpha) g^2, quad theta <- theta - eta g \/ (sqrt(v) + epsilon). $

_Adam_ combines this with momentum. It keeps exponential averages of the gradient, $m$, and of its square, $v$, and steps along $m \/ sqrt(v)$. Both averages start at zero, so in the first steps they underestimate their targets: after one step $m = (1 - beta_1) g$, a tenth of $g$ with the usual $beta_1 = 0.9$. Dividing by $1 - beta^t$ corrects this exactly for a constant gradient, and its effect fades as $t$ grows.

#snippet("aif/tiny/optim.py", "adam", caption: [Adam with bias correction, and AdamW's decoupled weight decay])

_Weight decay_ shrinks parameters towards zero each step, a regulariser that Chapter 1.6 studies. For SGD, decaying the weights is the same as adding $1/2 lambda norm(theta)^2$ to the loss. For Adam the two differ, because a penalty's gradient passes through the division by $sqrt(v)$, so parameters with large gradients are barely regularised. _AdamW_ applies the decay to the weights directly, outside the adaptive step, and is the default for training transformers.

#snippet("aif/tiny/optim.py", "rmsprop", caption: [RMSProp])

Each optimiser is checked against PyTorch's on the same problem, from the same starting point, for fifty steps:

#snippet("u1/optim_check.py", "pairs", caption: [Six pairs of optimisers, `tiny`'s and PyTorch's])

#console(read("/src/console/u1-optim-check.txt"), caption: [Identical to within float64 rounding])

=== Paths through a valley

The valley above has condition number 50. The program runs four optimisers from the same point until the loss falls below $10^(-8)$, with gradient descent and momentum at the step sizes that theory says are best for this valley:

#snippet("u1/valley.py", "tuned", caption: [Optimal settings for gradient descent and the heavy ball, from the two curvatures])

#console(read("/src/console/u1-valley.txt"), caption: [Steps to converge on the rotated valley])

#fig("u1-valley", caption: [The first 80 steps of each optimiser on the valley's contours, from the same starting point at the lower left. Left: gradient descent zig-zags across the valley; momentum swings further but travels faster along it. Right: RMSProp and Adam set off along the diagonal of the coordinate axes before turning down the valley.]) <fig-valley>

Momentum needs 54 steps to gradient descent's 272, five times fewer, of the order of the factor $sqrt(kappa) approx 7$ that theory predicts. The adaptive methods gain nothing here, because their per-parameter scaling is aligned with the coordinate axes and this valley is rotated, so the scaling does not undo its shape. With a constant learning rate they also settle slowly near the minimum. Adam needs a few more steps than gradient descent, and RMSProp, which has no momentum, three times as many. On neural networks the balance is reversed, because the curvature there does vary along the parameters themselves, the gradients are noisy, and nobody can compute the optimal momentum. This experiment shows only that no optimiser is best everywhere, and that the learning rate matters to all of them.

#keyidea[
  An optimiser's job is to make progress along flat directions without diverging along steep ones. Momentum does it by averaging over time, adaptive methods by rescaling each parameter, and Adam does both. All of them still need a learning rate that suits the problem.
]

=== Schedules: warm-up and decay

A constant learning rate is rarely best. Early in training, the parameters are random, the gradients large and erratic, and Adam's averages unreliable. A small learning rate that rises over the first few hundred steps, a _warm-up_, avoids early divergence. Late in training, a smaller learning rate lets the parameters settle into the bottom of the basin instead of bouncing around it. The schedule used throughout this course rises linearly during warm-up and then follows half a cosine down to a tenth of its peak:

#snippet("aif/train.py", "schedule", caption: [Linear warm-up, then cosine decay to a floor])

#fig("u1-schedule", caption: [The schedule of Unit 2's pretraining run: 500 steps of warm-up to $2 times 10^(-3)$, then cosine decay to a tenth of the peak over the remaining 17,810 steps.]) <fig-schedule>

=== Finding a learning rate

A _learning-rate range test_ trains for a few hundred steps while raising the learning rate exponentially from tiny to huge, and records the smoothed loss. The loss first barely moves, then falls quickly, then turns up and diverges.

#snippet("u1/lr_range.py", "range-test", caption: [A range test: one short run with an exponentially rising learning rate])

#console(read("/src/console/u1-lr-range.txt"), caption: [The range test for Chapter 1.5's network with AdamW])

#fig("u1-lr-range", caption: [Smoothed loss against learning rate. Training is fastest just before the loss turns up; a tenth of that rate is a safe choice for a full run.]) <fig-lr-range>

The test conflates two things, since later steps have both a higher rate and more training behind them, so it indicates only a range of suitable rates. A tenth of the rate at the minimum is a sound starting point, and is close to the $10^(-3)$ that Chapter 1.5 uses. For expensive runs a short sweep is better still: Unit 2 chose its pretraining rate by three runs of six million tokens each.

#inpytorch[
  `torch.optim` provides every optimiser here, with `param_groups` for settings that differ between parameters, such as no weight decay for biases and normalisation weights. Schedules live in `torch.optim.lr_scheduler`, or are written as this course writes them, setting `group["lr"]` each step. `torch.nn.utils.clip_grad_norm_` rescales the gradient when its norm exceeds a limit, a guard against the occasional huge step.
]

#reading(
  [Gabriel Goh, "Why Momentum Really Works", _Distill_, 2017.],
  [Diederik Kingma and Jimmy Ba, "Adam: A Method for Stochastic Optimization", ICLR 2015.],
  [Ilya Loshchilov and Frank Hutter, "Decoupled Weight Decay Regularization", ICLR 2019.],
  [Leslie Smith, "Cyclical Learning Rates for Training Neural Networks", WACV 2017, section 3.3: the range test.],
)

== Labs

#lab([The divergence threshold of gradient descent], goal: [Find the divergence threshold of gradient descent and compare it with theory.], time: [1 hour], code: "code/u1/valley.py")[
  + On the valley, run gradient descent at step sizes from 0.01 to 0.05 and record the final loss after 200 steps.
  + Locate the step size at which it diverges and compare it with $2 \/ lambda_max$.
  + Repeat with the curvature 50 changed to 200 and note how the best step size and the steps to converge change.
  #done-when(
    [Your measured threshold agrees with $2 \/ lambda_max$ to within 2%.],
    [You can state how the steps to converge scale with the condition number, with your measurements.],
  )
  #evidence([The table of final losses and the threshold for both valleys.])
]

#lab([Tuning momentum], goal: [Map how steps to converge depend on $mu$ and $eta$.], time: [1.5 hours], code: "code/u1/valley.py")[
  + Run heavy-ball momentum on a grid of $mu$ from 0 to 0.95 and $eta$ from 0.01 to 0.1, recording steps to reach a loss below $10^(-8)$.
  + Mark the theoretical optimum on your grid.
  + Repeat with Nesterov momentum and compare the size of the good region.
  #done-when(
    [Your heat map shows the region where momentum beats gradient descent's 272 steps.],
    [You can say which of the two methods is less sensitive to its settings.],
  )
  #evidence([Both heat maps and a paragraph comparing them.])
]

#lab([SGD against Adam on MNIST], goal: [Compare the two optimisers on a neural network.], time: [1.5 hours], code: "code/u1/mnist_tiny.py")[
  + Train Chapter 1.5's network for three epochs with SGD at learning rates 0.01, 0.03 and 0.1, momentum 0.9, and with AdamW at $3 times 10^(-4)$, $10^(-3)$ and $3 times 10^(-3)$.
  + Plot the six training-loss curves on one chart, and record the validation accuracy of each.
  #done-when(
    [You have six curves and six accuracies.],
    [You can say which optimiser was more forgiving of a badly chosen learning rate, and support it from the chart.],
  )
  #evidence([The chart, the accuracies and the conclusion.])
]

#lab([Range test and schedule], goal: [Choose a learning rate by measurement and test a schedule.], time: [1 hour], code: "code/u1/lr_range.py")[
  + Run the range test three times with different seeds, `--seed 1`, `2` and `3`, and record the rate at the minimum each time.
  + Train the network for eight epochs at the suggested rate with a constant rate, and with warm-up over one epoch and cosine decay.
  #done-when(
    [Your three range tests agree within a factor of two.],
    [You have the final validation accuracy of both runs and can say whether the schedule helped.],
  )
  #evidence([The three range-test plots and the two learning curves.])
]

#problems(
  [Show that gradient descent on $f(x) = 1/2 lambda x^2$ converges in one step at $eta = 1 \/ lambda$. Why is this step size not available in a real network?],
  [After $t$ steps with a constant gradient $g$, what are Adam's $m$ and $v$ before and after bias correction? What step does it take?],
  [Adam's step is roughly $eta$ in size for every parameter whatever its gradient's scale. Why does that make Adam's learning rate easier to transfer between models than SGD's?],
  [A training run with batch size 32 works at learning rate $10^(-3)$. You raise the batch size to 512. Give two rules of thumb for the new learning rate and say when each applies.],
  [With weight decay $lambda$ and learning rate $eta$, by what factor does AdamW shrink a weight per step in the absence of gradient? Over 18,000 steps at $eta = 2 times 10^(-3)$ and $lambda = 0.1$?],
)

#checklist(
  [I can explain the step-size limit and the role of the condition number for gradient descent.],
  [I can derive momentum, RMSProp and Adam from the problems each one addresses, including bias correction.],
  [I can explain the difference between L2 regularisation and decoupled weight decay.],
  [I can choose a learning rate with a range test or a short sweep, and explain warm-up and decay.],
  [Lab 1.4.1–1.4.4 done-when criteria all hold, with evidence filed.],
)
