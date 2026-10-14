#import "../lib/template.typ": *

= Generalisation <ch-generalisation>

#chapter-meta(
  time: [5 hours],
  builds: [Overfitting produced with 1,000 MNIST images and a network of 670,000 parameters, then reduced with weight decay, dropout, data augmentation and early stopping; and double descent reproduced with random features, the test error peaking where the parameters equal the examples and falling again beyond.],
  needs: [Chapter 1.5.],
)

#why[
  A model must predict well on data it has not seen, since doing well on the training data alone is no more than a lookup table achieves. A network large enough to be useful is also large enough to memorise its training set, noise and all, and most real projects succeed or fail on the gap between training and test performance. This chapter produces that gap on purpose, closes it with the standard tools, and then shows an effect that classical statistics did not predict, in which models past a certain size can generalise better as they grow.
]

#skip-test(
  rule: [If all four are easy, read the section on double descent and do Labs 1.6.3 and 1.6.4.],
  [What are the training, validation and test sets each for, and why must the test set not be used to choose settings?],
  [What does dropout do during training and at test time, and why are the kept activations divided by $1 - p$?],
  [Why does training on randomly shifted copies of images reduce overfitting?],
  [What is double descent, and at what model size does the test error peak?],
)

== Core ideas

=== The generalisation gap

The data a model will meet in use are assumed to come from some distribution, and the training set is a sample from it. The quantity of interest is the expected loss on fresh samples, which cannot be computed and can only be estimated on held-out data. The difference between that and the training loss is the _generalisation gap_.

An honest estimate depends on how the data are split and used. The _training set_ fits the parameters. The _validation set_ chooses everything else: architecture, learning rate, regularisation strength, the epoch to stop at. Each such choice fits the validation set a little, so its score becomes optimistic too. The _test set_ is used once, at the end, for the number you report. Any path by which test information reaches a decision, including looking at test scores while tuning, is _leakage_, and makes the reported number unreliable.

Classical statistics frames the gap as a trade-off. A model with too little capacity cannot fit the true pattern and errs systematically, which is _bias_. A model with too much fits the particular sample, noise included, so its predictions vary from sample to sample, which is _variance_. Test error is then U-shaped in model size, lowest somewhere in between.

=== Overfitting a small training set

Training a wider version of Chapter 1.5's network on a thousand images makes overfitting easy to see. With two hidden layers of 512 units it has 670,000 parameters, nearly 700 for every training image.

#snippet("u1/overfit.py", "variant", caption: [Training one variant on 1,000 images, recording training loss and validation accuracy each epoch])

#console(read("/src/console/u1-overfit.txt"), caption: [Five variants, 150 epochs each])

Without regularisation the training loss reaches zero to four decimal places, so the network has memorised its thousand images. Its validation accuracy settles near 90.5%, far below the 97.9% that Chapter 1.5's network reaches with all 55,000 training images. Each regulariser below narrows the gap a little, and together they reach 95% from the same thousand images (@fig-overfit). The test column is printed so that the book can show it. In your own work, compare the variants on validation alone and test only the chosen one.

#fig("u1-overfit", caption: [Validation accuracy per epoch for the five variants. Augmentation helps most; the combination keeps improving long after the unregularised network has stopped.]) <fig-overfit>

=== Four regularisers

_Weight decay_ pulls every weight towards zero, preferring simpler functions with smaller weights. From the probabilistic view of Chapter 1.3 it is a prior: a Gaussian prior on the weights adds $lambda norm(theta)^2$ to the negative log-likelihood, and the minimiser is the _maximum a posteriori_ estimate. With AdamW the shrinkage per step is the product of the learning rate and the decay, here $5 times 10^(-4)$. Over 1,500 steps that is modest, and so is its effect on this problem.

_Dropout_ sets each hidden activation to zero with probability $p$ during training, independently at every step, so that no unit can rely on any particular other unit being present. Dividing the surviving activations by $1 - p$ keeps their expected value unchanged, so at test time, when nothing is dropped, the network needs no adjustment:

#snippet("aif/tiny/nn.py", "dropout", caption: [Inverted dropout, active only in training mode])

_Data augmentation_ trains on transformed copies of the data that should not change the answer, here shifts of up to two pixels in each direction. It teaches the network an invariance the data imply but a thousand images do not show, and is the most effective of the four here, as it usually is wherever such invariances are known:

#snippet("u1/overfit.py", "shift", caption: [Random shifts, applied afresh to every batch])

_Early stopping_ keeps the parameters from the epoch with the best validation score. The console's "best val" column shows what it would gain over the final epoch for each variant: a little for the unregularised network, more for those whose validation accuracy fluctuates.

#hazard(title: [Pitfall])[
  Dropout and batch normalisation behave differently in training and in evaluation. Forgetting `model.eval()` before measuring leaves dropout on, and the measured accuracy is lower and noisy; forgetting `model.train()` afterwards trains without it. Every evaluation function in this course switches modes and restores them.
]

=== The precision of a test score

A test accuracy is an estimate from a finite sample. If a model's true accuracy is $p$ and the test set has $n$ independent examples, the measured accuracy has a standard error of $sqrt(p(1 - p) \/ n)$. For $p = 0.95$ and $n = 10,000$ that is 0.22 percentage points, so a 95% confidence interval spans about $plus.minus 0.43$ points. Differences between models smaller than that, such as weight decay's 91.43% against dropout's 91.39% above, are not evidence that one model is better. Unit 3 returns to the statistics of evaluation. Until then, ask how large a difference must be before it means something.

=== Double descent

The U-shaped picture predicts that a model with far more parameters than training examples should generalise terribly. Modern networks, with millions of parameters trained on thousands of examples, routinely do not. A simple setting shows how this can happen. Fix $p$ random features of each image, $phi(x) = "ReLU"(W x) \/ sqrt(p)$ with $W$ random and never trained, and fit a linear model on them by least squares. With $p$ smaller than the number of examples $n$ the fit is the usual least-squares solution. With $p > n$ infinitely many solutions fit the training data exactly, and the pseudo-inverse picks the one with the smallest norm.

#snippet("u1/double_descent.py", "features", caption: [Random ReLU features and the minimum-norm least-squares fit])

Four hundred training images get one-hot targets, a fifth of them with random labels to make the effect clear:

#snippet("u1/double_descent.py", "noise", caption: [Randomising a fifth of the labels])

#console(read("/src/console/u1-double-descent.txt"), caption: [Test error and weight norm against the number of features])

#fig("u1-double-descent", caption: [Test error against the number of random features, on a logarithmic scale. The error falls, rises to a sharp peak where features equal examples, and falls again, below the earlier minimum.]) <fig-double-descent>

The test error first follows the classical U, lowest near 100 features, then climbs to a peak of 88% at exactly 400 features, where the number of parameters equals the number of examples. There the model can just interpolate the training data, including its noisy labels. It has only one way to do so, which needs enormous weights, and the weight norm peaks at 118. Beyond the threshold, many solutions interpolate the data, the minimum-norm one among them is smooth, and the test error falls again, to 29% at 8,000 features, well below the classical minimum. This is _double descent_. Large networks trained by gradient descent behave similarly, with the optimiser's own preference for small, simple solutions playing the part of the minimum norm.

#keyidea[
  Generalisation depends on the data, the model's capacity and the inductive bias of the training procedure together. Regularisers and augmentation shrink the gap by encoding prior knowledge about good solutions. Past the interpolation threshold, size itself can help, because among the many functions that fit, training finds simple ones.
]

#inpytorch[
  `torch.nn.Dropout(p)` implements inverted dropout and obeys `model.eval()`. Weight decay is an optimiser argument, `torch.optim.AdamW(params, weight_decay=0.1)`. Image augmentations live in `torchvision.transforms`, and `torch.linalg.pinv` computes the pseudo-inverse used above.
]

#reading(
  [Nitish Srivastava, Geoffrey Hinton, Alex Krizhevsky, Ilya Sutskever and Ruslan Salakhutdinov, "Dropout: A Simple Way to Prevent Neural Networks from Overfitting", _JMLR_ 15, 2014.],
  [Chiyuan Zhang, Samy Bengio, Moritz Hardt, Benjamin Recht and Oriol Vinyals, "Understanding Deep Learning Requires Rethinking Generalization", ICLR 2017.],
  [Mikhail Belkin, Daniel Hsu, Siyuan Ma and Soumik Mandal, "Reconciling Modern Machine-Learning Practice and the Classical Bias–Variance Trade-off", _PNAS_ 116(32), 2019.],
  [Preetum Nakkiran and others, "Deep Double Descent: Where Bigger Models and More Data Hurt", ICLR 2020.],
)

== Labs

#lab([Learning curves], goal: [Measure how accuracy grows with data, the most reliable way to improve a model.], time: [1 hour], code: "code/u1/overfit.py")[
  + Train the unregularised network on 500, 1,000, 5,000, 20,000 and 55,000 images, with as many epochs as it takes for the training loss to stop falling.
  + Plot validation error against training-set size on logarithmic axes and fit a straight line.
  #done-when(
    [You have five points and a fitted slope.],
    [You can predict from the fit how many images would halve the error of the 1,000-image model, and say how much you trust the prediction.],
  )
  #evidence([The plot, the fit and the prediction.])
]

#lab([Tuning without leaking], goal: [Choose regularisation strengths by validation and report a single test score.], time: [1.5 hours], code: "code/u1/overfit.py")[
  + On the 1,000-image problem, search weight decay in {0, 0.1, 0.5, 2} and dropout in {0, 0.25, 0.5}, with augmentation on, judging by the best validation accuracy.
  + Test the chosen setting once. Give a 95% interval for its test accuracy.
  #done-when(
    [Your search covers all twelve settings, judged only on validation.],
    [Your report has one test score with its interval.],
  )
  #evidence([The validation table, the choice and the test result.])
]

#lab([Memorising noise], goal: [Reproduce the observation that started the rethinking of generalisation.], time: [1 hour], code: "code/u1/overfit.py")[
  + Train the unregularised network on 1,000 images whose labels are replaced by random ones.
  + Record the epochs needed to reach 100% training accuracy, compared with real labels, and the validation accuracy.
  #done-when(
    [The network fits random labels perfectly, and you have the number of epochs for both cases.],
    [You can explain what this implies about parameter counts as a measure of overfitting.],
  )
  #evidence([Both learning curves and the explanation.])
]

#lab([What moves the peak], goal: [Explore double descent's dependence on noise and regularisation.], time: [1.5 hours], code: "code/u1/double_descent.py")[
  + Rerun the sweep with label noise of 0%, 20% and 40%.
  + Replace the pseudo-inverse with ridge regression, $(Phi^T Phi + lambda I)^(-1) Phi^T Y$, at three values of $lambda$, and rerun.
  #done-when(
    [You have six curves of test error against features.],
    [You can say how noise and $lambda$ change the peak, and why ridge regression suppresses it.],
  )
  #evidence([The curves and your explanation.])
]

#problems(
  [A model scores 96.0% and another 96.3% on a test set of 10,000 images. Is the second better? What if the same test images were used, and the two disagree on only 150 of them?],
  [Show that minimising the negative log-likelihood plus $lambda norm(theta)^2$ finds the most probable parameters under a Gaussian prior. What is the prior's variance?],
  [With dropout $p = 0.5$ on a layer of 512 units, how many different sub-networks can a training step use? Why might averaging over them help?],
  [Name an augmentation that would be harmful for MNIST, and one that would be harmless for photographs of animals but harmful for photographs of text.],
  [At exactly $p = n$ features, why does the minimum-norm solution have a very large norm? Relate your answer to the smallest singular value of the feature matrix.],
)

#checklist(
  [I can explain the roles of the training, validation and test sets, and recognise leakage.],
  [I can apply weight decay, dropout, augmentation and early stopping, and explain how each works.],
  [I can give the uncertainty of a test score and judge whether a difference is meaningful.],
  [I can explain double descent and the role of the interpolation threshold.],
  [Lab 1.6.1–1.6.4 done-when criteria all hold, with evidence filed.],
)
