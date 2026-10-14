#import "../lib/template.typ": *

= Models as probability <ch-probability>

#chapter-meta(
  time: [5 hours],
  builds: [Linear regression solved in closed form, by gradient descent and by maximum likelihood with a learned noise level, all three agreeing to four places; softmax regression on MNIST at 92%, with its weights drawn as images; and a softmax and cross-entropy that survive any logits.],
  needs: [Chapter 1.2. Probability as in the Handbook's maths part: distributions, expectations, independence.],
)

#why[
  A loss function can look like an arbitrary choice, squared error for one problem and cross-entropy for another. Each standard loss follows from one assumption about how the data were generated and from one principle, that a model should make the observed data as probable as possible. Seeing losses this way explains when each is appropriate, what its value means, and how to derive the right one for a new problem. The same principle defines language modelling: Unit 2 trains a model to make the next token of real text as probable as possible.
]

#skip-test(
  rule: [If all four are easy, read the section on numerical stability and do Labs 1.3.3 and 1.3.4.],
  [Show that maximising the likelihood of a linear model with Gaussian noise of fixed variance is the same as minimising the mean squared error.],
  [Why minimise the negative log-likelihood instead of maximising the likelihood itself?],
  [What does a naive softmax return for the logits $(1000, 1001, 1002)$ in float32, and how is it fixed?],
  [What is the gradient of the cross-entropy loss with respect to the logits?],
)

== Core ideas

=== Models that assign probabilities

A _probabilistic model_ says, for an input $x$, how probable each possible output $y$ is: a distribution $p(y | x; theta)$ with parameters $theta$. Given a dataset of $n$ examples $(x_i, y_i)$ drawn independently, the probability the model assigns to all of them together is the product $product_i p(y_i | x_i; theta)$, the _likelihood_ of $theta$. _Maximum likelihood estimation_ chooses the $theta$ that makes it largest.

Products of thousands of probabilities underflow to zero in floating point, and their derivatives are unwieldy. The logarithm turns the product into a sum and preserves the maximiser, and negating it gives a quantity to minimise. Dividing by $n$ makes it independent of the dataset's size:

$ cal(L)(theta) = -1/n sum_(i=1)^n log p(y_i | x_i; theta). $

This _negative log-likelihood_ is the loss. Every model trained in this course, from the regression below to the language models of Unit 2, minimises one.

=== Squared error and Gaussian noise

Suppose $y$ is a linear function of $x$ plus noise drawn from a normal distribution with standard deviation $sigma$: $y = w^T x + b + epsilon$, $epsilon tilde cal(N)(0, sigma^2)$. The density of one observation is

$ p(y | x) = 1 / sqrt(2 pi sigma^2) exp(-(y - w^T x - b)^2 / (2 sigma^2)), $

so its negative logarithm is

$ -log p(y | x) = (y - w^T x - b)^2 / (2 sigma^2) + log sigma + 1/2 log 2 pi. $

For fixed $sigma$, only the first term depends on $w$ and $b$, and minimising its average is minimising the _mean squared error_. The squared error is therefore the right loss when the errors are Gaussian with the same spread everywhere. With heavy-tailed errors it lets a few outliers dominate, and Lab 1.3.1 deals with a case where the spread varies. Minimising over $sigma$ as well gives $sigma^2$ equal to the mean squared residual, so the model also learns how noisy the data are.

The program fits 200 synthetic points three ways.

#snippet("u1/regression.py", "data", caption: [A linear model with Gaussian noise of standard deviation 0.5])

The first solves the least-squares problem directly. Setting the gradient of the squared error to zero gives the _normal equations_ $X^T X w = X^T y$; `lstsq` solves them through an orthogonal factorisation of $X$, which is more accurate than forming and inverting $X^T X$.

#snippet("u1/regression.py", "closed-form", caption: [Least squares in closed form, with a column of ones for the bias])

The second minimises the mean squared error with `tiny` and gradient descent; the third minimises the full negative log-likelihood, with $log sigma$ as a third parameter so that $sigma$ stays positive.

#snippet("u1/regression.py", "descent", caption: [Gradient descent on the mean squared error])

#snippet("u1/regression.py", "likelihood", caption: [Maximum likelihood, learning the noise level too])

#console(read("/src/console/u1-regression.txt"), caption: [Three routes to the same answer])

All three agree to four decimal places, and the learned $sigma$ equals the root-mean-square residual, as the derivation predicts. The estimates differ from the true parameters by a few hundredths, the sampling error of 200 noisy points; more data would shrink it in proportion to $1 \/ sqrt(n)$.

=== Classification: logits, softmax and cross-entropy

For a label that takes one of $K$ values, the natural model is a categorical distribution, $K$ probabilities that sum to one. A network cannot easily output numbers constrained like that, so it outputs $K$ unconstrained scores, _logits_ $z_1, dots, z_K$, and the _softmax_ turns them into probabilities:

$ p(y = k | x) = e^(z_k) / (sum_j e^(z_j)). $

Adding the same constant to every logit leaves the probabilities unchanged; only differences between logits matter. The negative log-likelihood of the true class $y$ is

$ -log p(y | x) = -z_y + log sum_j e^(z_j), $

the _cross-entropy_ loss. For $K = 2$ the softmax reduces to the logistic function $sigma(z) = 1 \/ (1 + e^(-z))$ of the difference of the two logits, and the loss to the binary cross-entropy.

#derivation[
  Differentiate the cross-entropy with respect to the logit $z_k$. The first term contributes $-1$ when $k = y$ and nothing otherwise; the second contributes $e^(z_k) \/ sum_j e^(z_j) = p_k$. So
  $ (partial cal(L)) / (partial z_k) = p_k - [k = y], $
  the predicted probability minus the one-hot target. The gradient is large where the model is confidently wrong and vanishes as it becomes confidently right. `tiny`'s `log_softmax` uses this result in its backward step.
]

_Softmax regression_ applies this to images: the logits are a linear function of the 784 pixels, $z = W^T x + b$, with one column of $W$ per digit.

#snippet("u1/logistic.py", "softmax-regression", caption: [Softmax regression on MNIST, trained with `tiny`])

#console(read("/src/console/u1-logistic.txt"), caption: [A linear model reaches 92% on MNIST])

Each column of $W$ is a template, a pattern of positive and negative weights over the image, and the predicted digit is the template that best matches the input (@fig-templates). The linear model's mistakes show its limit, because a 9 and a 4 differ in a few strokes that a single template per class cannot isolate. Chapter 1.5's networks, which compose many such features, remove most of these errors.

#fig("u1-templates", width: 72%, caption: [The ten columns of the trained $W$ as $28 times 28$ images: blue weights favour the digit, red weights count against it.]) <fig-templates>

=== Numerical stability

Floating point has a limited range. `exp` overflows float32 above about 88.7 and float64 above about 709, and logits larger than that are common in trained networks. A naive softmax of $(1000, 1001, 1002)$ divides infinity by infinity:

#snippet("u1/softmax.py", "naive", caption: [The softmax as written in the formula])

Because adding a constant to every logit changes nothing, subtracting the largest logit first keeps every exponent at or below zero, so the sum lies between 1 and $K$ and nothing overflows. The logarithm of the sum, needed by the loss, is computed the same way, which is the _log-sum-exp_ trick.

#snippet("u1/softmax.py", "stable", caption: [The stable softmax, log-sum-exp and cross-entropy])

#console(read("/src/console/u1-softmax.txt"), caption: [The naive and stable versions at extreme logits])

The second pair of lines shows the opposite failure. A probability of $e^(-120)$ underflows to zero in float32, so taking the logarithm of a computed softmax gives $-infinity$, while computing the log-probability directly as $z_k - log sum_j e^(z_j)$ gives the exact value, $-120$. This is why frameworks provide `log_softmax` and a cross-entropy that takes logits, and why a model should never output probabilities to a loss that takes their logarithm.

#snippet("u1/softmax.py", "gradient", caption: [The softmax-minus-one-hot gradient, checked numerically])

#hazard(title: [Pitfall])[
  PyTorch's `cross_entropy` takes _logits_, applies `log_softmax` itself, and expects targets as integer class indices or as a probability for every class. Passing probabilities, the output of a softmax, still runs: the loss applies a second softmax, the gradients shrink, and the model trains slowly to a poor result. Chapter 1.7 hides this bug in a training run for you to find.
]

=== Units: nats, bits and perplexity

A cross-entropy computed with natural logarithms is in _nats_; divided by $ln 2$ it is in _bits_, the number of bits an ideal code built from the model's probabilities would need per example. An untrained classifier over ten classes predicts each with probability $1 \/ 10$ and scores $ln 10 approx 2.30$ nats, which is where an untrained ten-class classifier's loss starts. Language models report the same quantity per token or per byte of text, and its exponential, the _perplexity_: a perplexity of 20 means the model is, on average, as uncertain as a uniform choice among 20 tokens. Unit 2 uses all three.

#inpytorch[
  `torch.nn.functional.cross_entropy(logits, targets)` computes this chapter's stable loss in one call, averaging over the batch; `binary_cross_entropy_with_logits` is its two-class form. `torch.logsumexp` and `torch.log_softmax` are the stable building blocks. The regression's closed form is `torch.linalg.lstsq`.
]

#reading(
  [Christopher Bishop and Hugh Bishop, _Deep Learning: Foundations and Concepts_, Springer, 2024, chapters 4 and 5: single-layer networks for regression and classification.],
  [Kevin Murphy, _Probabilistic Machine Learning: An Introduction_, MIT Press, 2022, sections 4.2 and 10.2: maximum likelihood and logistic regression.],
  [Pierre Blanchard, Desmond Higham and Nicholas Higham, "Accurately Computing the Log-Sum-Exp and Softmax Functions", _IMA Journal of Numerical Analysis_ 41(4), 2021.],
)

== Labs

#lab([When the noise varies], goal: [Use maximum likelihood to model noise that varies with the input.], time: [1.5 hours], code: "code/u1/regression.py")[
  + Generate data whose noise grows with $x$: $sigma(x) = 0.1 + 0.5|x_1|$.
  + Fit a model that predicts both the mean and $log sigma(x)$ as linear functions of $x$, by maximum likelihood in `tiny`.
  + Compare its fitted mean with least squares, and its predicted $sigma$ with the truth at five values of $x_1$.
  #done-when(
    [Your model recovers $sigma(x)$ within 20% at all five points.],
    [You can explain why least squares gives a reasonable mean but no account of the spread.],
  )
  #evidence([The code, the comparison table, and a plot of the data with the predicted $plus.minus 2 sigma$ band.])
]

#lab([Logistic and two-class softmax regression], goal: [Confirm that binary logistic regression is softmax regression with two classes.], time: [1 hour], code: "code/u1/logistic.py")[
  + Restrict MNIST to the digits 3 and 8. Train a logistic regression with one output, the sigmoid and the binary cross-entropy, in `tiny`.
  + Train a softmax regression with two outputs on the same data.
  + Show that the difference of the softmax model's two logits behaves like the logistic model's single logit.
  #done-when(
    [Both models reach the same test accuracy within half a percentage point.],
    [You can state the exact relation between the two parameterisations.],
  )
  #evidence([Both accuracies and your derivation of the relation.])
]

#lab([A stable binary cross-entropy], goal: [Write losses that are exact at any logit.], time: [1 hour], code: "code/u1/softmax.py")[
  + Write a binary cross-entropy from a logit, `bce(z, y)`, that is exact for $z$ from $-1000$ to $1000$, using $log(1 + e^(-|z|))$.
  + Test it in float32 and float64 against a high-precision reference from Python's `decimal` module.
  + Add a gradient check to show that its derivative is $sigma(z) - y$.
  #done-when(
    [Your function matches the reference to within a relative error of $10^(-6)$ in float32 at every test point.],
    [The gradient check passes.],
  )
  #evidence([The function, the error table and the check.])
]

#lab([Reading the weights], goal: [Interpret a linear classifier and its mistakes.], time: [1 hour], code: "code/u1/logistic.py")[
  + Draw the ten weight templates from your own run.
  + For the three most common confusions, show two misclassified test images each, with the model's top two probabilities.
  + Add the squared value of every pixel as 784 extra features and retrain. Report the accuracy and explain what the extra features can and cannot express.
  #done-when(
    [You can explain each confusion from the templates.],
    [You have the accuracy with the extra features, and a reason for the change.],
  )
  #evidence([The images, the probabilities and the explanation.])
]

#problems(
  [Derive the loss that maximum likelihood gives when the noise follows a Laplace distribution, $p(epsilon) prop e^(-|epsilon| \/ b)$. Which statistic of the residuals does it make the bias estimate?],
  [Show that the softmax is unchanged by adding a constant to every logit, and that it is changed by multiplying them by a constant. What does the multiplier do to the distribution?],
  [A classifier outputs the probability 0.9 for the correct class on every example. What is its cross-entropy in nats and in bits? What accuracy might it have?],
  [Why is $log(1 + e^z)$ computed as $max(z, 0) + log(1 + e^(-|z|))$? Which goes wrong in float32 for $z = 100$ and for $z = -100$ in the naive form?],
  [The normal equations can be solved by inverting $X^T X$. Explain, with the condition number, why `lstsq` is preferred, and give a dataset on which inversion fails.],
)

#checklist(
  [I can derive the mean squared error and the cross-entropy from maximum likelihood, and say what each assumes.],
  [I can explain logits, the softmax and the gradient of the cross-entropy.],
  [I can compute softmax, log-softmax and cross-entropy stably, and explain why the naive forms fail.],
  [I can convert a loss between nats, bits and perplexity.],
  [Lab 1.3.1–1.3.4 done-when criteria all hold, with evidence filed.],
)
