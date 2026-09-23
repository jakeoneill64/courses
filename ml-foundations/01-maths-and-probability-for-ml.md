# Module 1: Maths and probability for ML

**Part I · 1 week · Needs: Module 0. Data: MNIST, Adult, California housing, synthetic.**

## Why this module

You already know what a gradient is and have written backpropagation, so this is not a
maths course. It is a fast pass over the specific results every later module leans on,
organised by where each shows up later rather than by textbook chapter. The SVD is here
because Module 4's PCA and recommender are the SVD; the negative log-likelihood is here
because every loss you will minimise is one; logsumexp is here because Module 3's EM and
Module 9's attention both die without it.

The Oxford Classical Machine Learning and Deep Neural Networks weeks assume this is
fluent. When a lecturer writes "the MLE under Gaussian noise is least squares" and moves
on, you want to have derived it, not to be reconstructing it while the next slide goes
by. The assignments reward the same fluency: explaining why a method fits the data is a
statement about its noise model, its prior and its loss.

Structurally, both gaps you named rest here. Unsupervised learning is density estimation
and low-rank structure, which is maximum likelihood and the SVD. The craft of training
networks is mostly conditioning, numerical stability and knowing which loss encodes which
assumption. Module 5 will cite this module more than any other.

## Skip test

Answer cold, in writing.

1. Write the SVD of a matrix A, state the best rank-k approximation to A in Frobenius
   norm and its error. Why does this make PCA and a low-rank recommender the same
   computation?
2. Derive mean squared error as a negative log-likelihood and state the noise model. Do
   the same for cross-entropy and name the distribution.
3. Show H(p, q) = H(p) + KL(p ‖ q) and prove KL ≥ 0. Why does minimising cross-entropy
   on data minimise KL to the data distribution, and what is the floor?
4. Write the bias-variance decomposition for squared error and say which term each of
   these moves: more training data, a deeper tree, L2 regularisation, averaging 100
   models.
5. Compute softmax of the logits (1000, 1000, 1000) without overflow and explain what
   logsumexp does. Why does it matter that MPS has no float64?
6. A classifier scores 0.91 on a test set of 1,000 examples. Give a 95% confidence
   interval, and say roughly how many test examples you would need to tell it apart from
   one scoring 0.92.

If all six are easy, do Lab 1.5 only, and the write-up.

## Core ideas

**A matrix is a linear map, and its rank is the dimension of what it can reach.** An
m × n matrix sends ℝⁿ to ℝᵐ; its column space is the set of outputs it can produce and
its rank r is that space's dimension; the other n − r input directions are sent to zero
and are invisible downstream. Low rank is sometimes the point (an embedding table, a
recommender's k factors, a rank-8 LoRA adapter in Module 10) and sometimes the disease
(a collapsed representation in Module 8). A design matrix with rank below its column
count has singular normal equations; ridge in Module 2 is the fix.

**Symmetric matrices have real eigenvalues and orthogonal eigenvectors, and every matrix
has an SVD.** For symmetric S, S = QΛQᵀ: rotate into the eigenbasis, scale, rotate back.
For any A, A = UΣVᵀ with orthogonal U and V and singular values σ₁ ≥ σ₂ ≥ ... ≥ 0; the
σᵢ² are the eigenvalues of AᵀA. Eckart and Young: the best rank-k approximation to A in
Frobenius or spectral norm is Σᵢ≤ₖ σᵢuᵢvᵢᵀ, with Frobenius error √(Σᵢ>ₖ σᵢ²). That
theorem is PCA (Lab 1.1), Module 4's recommender, and the reason a 4,096 × 4,096 weight
can be updated through two 4,096 × 8 matrices. Use `np.linalg.eigh`, not `eig`, for
symmetric matrices.

**Covariance matrices are positive semi-definite, and the condition number says how
badly a matrix will treat your optimiser.** S is PSD if xᵀSx ≥ 0 for all x; every
covariance qualifies because xᵀΣx is the variance of the projection onto x, its
eigenvectors are the principal axes and its eigenvalues the variances along them. The
condition number κ = σ_max/σ_min is, for a least-squares loss, the ratio of largest to
smallest curvature, and gradient descent at the largest stable step needs on the order
of κ iterations along the flattest direction; standardising features, batch
normalisation and Adam all attack κ. ‖x‖₁ is what makes the lasso sparse; the spectral
norm ‖A‖₂ = σ₁ bounds how much a layer can stretch a gradient passing back through it.

**The chain rule is a product of Jacobians, and backpropagation multiplies them in the
cheap order.** For f_L ∘ ... ∘ f₁ the Jacobian is J_L ⋯ J₁. A loss is scalar, so its
Jacobian is a row, and multiplying from the left, gᵀJ_L then (gᵀJ_L)J_{L−1}, keeps every
intermediate a vector: one vector-Jacobian product per layer, no Jacobian ever formed,
where forward mode would cost n times more. The Hessian is the Jacobian of the gradient;
its eigenvalues are the curvatures, its condition number the κ above, and for least
squares it is JᵀJ plus a term vanishing at a perfect fit, the Gauss-Newton
approximation.

**Probability is bookkeeping over a joint distribution, and Bayes' rule is division.**
From p(x, y): marginalise by summing out what you do not care about, condition by
dividing by a marginal, and Bayes' rule p(θ | D) = p(D | θ)p(θ)/p(D) is that division
with the joint factored the other way. Expectation is linear; variance
Var(x) = E[x²] − E[x]² is not, and that identity is the formula Lab 1.3 shows you must
never evaluate in floating point. Conditional independence given z, the assumption every
latent variable model makes, means the joint factorises once z is known; Module 3's
E-step is a posterior over z by Bayes' rule and nothing more.

**The Gaussian is the default because it has maximum entropy for a given mean and
covariance, and its covariance is an ellipse.** N(x | μ, Σ) = (2π)^(−d/2) |Σ|^(−1/2)
exp(−½(x − μ)ᵀΣ⁻¹(x − μ)); its level sets are ellipsoids with axes along the eigenvectors
of Σ and semi-axes √λᵢ, so Module 3's 2σ ellipse has semi-axes 2√λᵢ. Never invert Σ:
take the Cholesky factor L, solve Ly = x − μ, use ‖y‖² and log|Σ| = 2 Σ log Lᵢᵢ. The
Bernoulli, categorical and Poisson cover labels, classes and counts, and all four are
exponential families p(x | η) = h(x) exp(ηᵀT(x) − A(η)), where ∇A = E[T(x)], so the MLE
matches expected sufficient statistics to the data's (Module 3's M-step is weighted
averages) and the gradient T(x) − E[T] is the "observed minus predicted" form logistic
regression and softmax share.

**Every standard loss is a negative log-likelihood, and every standard regulariser a
negative log-prior.** Maximum likelihood maximises Σᵢ log p(yᵢ | xᵢ, θ). Gaussian noise
of fixed variance gives Σ(yᵢ − f(xᵢ))²/(2σ²) plus a constant: mean squared error.
Laplace noise gives mean absolute error. A categorical yᵢ with probabilities
softmax(f(xᵢ)) gives −Σ log p(yᵢ): cross-entropy. MAP adds log p(θ): a Gaussian prior
N(0, τ²I) contributes ‖θ‖²/(2τ²), which is L2 with λ = σ²/τ², and a Laplace prior
contributes |θ|/b, which is L1. So "which loss" is never taste: it is a claim about how
the targets are noisy, and switching to Huber in Lab 1.5 says you believe in outliers.

**Cross-entropy is entropy plus KL, so minimising it minimises KL to the data, and the
floor is the label noise.** H(p) = −Σ p log p is the expected code length under the
truth, H(p, q) = −Σ p log q the cost of coding with q instead, and KL(p ‖ q) = Σ p
log(p/q) the excess, so H(p, q) = H(p) + KL(p ‖ q). Gibbs' inequality, KL ≥ 0 with
equality iff p = q, follows from Jensen or from log x ≤ x − 1. Minimising cross-entropy
on data minimises KL(p_data ‖ q_θ) because H(p_data) is constant in θ, so the loss
cannot fall below H(p_data): with 5% wrong labels, a training loss heading to zero is
memorisation. KL is asymmetric, mild when q puts mass where p has none and infinite when
q misses mass p has, which is why maximum likelihood covers every mode.

**Expected squared error is bias squared plus variance plus irreducible noise, and the
three respond to different levers.** For y = f(x) + ε and f̂ trained on a random
dataset, E[(y − f̂(x))²] = (E[f̂(x)] − f(x))² + Var(f̂(x)) + σ². Bias is what you are
wrong about on average because the model class cannot represent f; variance is how much
the answer depends on which sample you drew. More data cuts variance and leaves bias
alone; a richer model class trades bias for variance; regularisation and averaging
(bagging, in Module 2) cut variance at a small cost in bias. Problem 4 derives it, Lab
1.4 measures it, and it is Module 2's vocabulary for forests and boosting.

**The law of large numbers says your sample mean converges; the central limit theorem
says how fast, and confidence intervals follow.** The mean of n independent draws with
variance σ² has standard error σ/√n and, for large n, a near-Gaussian distribution
whatever the draws' shape. A test accuracy is a mean of Bernoulli outcomes with standard
error √(p(1 − p)/n): 0.91 on 1,000 examples is 0.91 ± 0.018 at 95%, and a competitor at
0.92 sits inside the interval. When there is no formula (AUC, F1, a median) the
bootstrap does the job: resample the test set with replacement B = 1,000 times,
recompute, take the 2.5th and 97.5th percentiles. Lab 1.4 checks that such an interval
contains the truth 95% of the time, which is the only way to trust one; every number in
every write-up in this course carries an interval or a seed spread.

**Monte Carlo averages samples to estimate an expectation, and reparameterisation is
what lets you differentiate through it.** E_p[f(x)] ≈ (1/N) Σ f(xᵢ), with error falling
as 1/√N regardless of dimension. The trouble comes when p depends on parameters you are
optimising: ∇_φ E_{p_φ}[f] is not E[∇f], because the sampling distribution moves. Write
x = g(φ, ε) with ε from a fixed distribution, for a Gaussian x = μ + σε with ε ~ N(0, I),
and the expectation is over ε, so the gradient passes through g by the chain rule; that
one line makes Module 7's VAE trainable. The score-function alternative
f(x)∇ log p_φ(x) handles discrete x with variance high enough that Module 11's
REINFORCE is mostly about reducing it.

**Float32 has about seven decimal digits, float64 sixteen, and most numerical bugs are
one of three patterns.** Overflow: exp(89) exceeds float32's maximum of about
3.4 × 10³⁸, so softmax of logits near 1,000 is NaN; the fix is
softmax(z) = softmax(z − max z) and its log form logsumexp(z) = m + log Σ exp(zᵢ − m)
with m = max z, so compute log-softmax as z − logsumexp(z), never log(softmax(z)).
Cancellation: E[x²] − E[x]² on data with mean 10⁸ and variance 1 needs 17 digits and
float64 has 16; Welford's update mₖ = mₖ₋₁ + (xₖ − mₖ₋₁)/k,
Sₖ = Sₖ₋₁ + (xₖ − mₖ₋₁)(xₖ − mₖ) never forms the large intermediate. Underflow: a product
of 1,000 probabilities is zero in any precision, so likelihoods live in the log domain.
On the Mac, MPS has no float64: gradient checks run on the CPU and long float32
reductions drift.

**Sampling from a distribution is applying the inverse CDF to uniform noise.** If
U ~ Uniform(0, 1) then F⁻¹(U) has CDF F: −log(1 − U)/λ for the exponential, a cumulative
sum and a search for a categorical (how `np.random.choice` works), Box-Muller for the
Gaussian since its inverse has no closed form. When F cannot be inverted you use
rejection sampling, MCMC, or learn a transformation of simple noise, which is what a VAE
decoder and a diffusion model both are. Lab 1.5 draws residuals from each loss's implied
density this way, so you can see that MAE believes in Laplace tails and Huber in a
Gaussian centre with exponential shoulders.

**Forward links.** The SVD is Module 4's PCA and recommender and Module 10's LoRA. The
NLL view of losses is how Module 2 picks objectives for boosted trees, how Module 7
derives the ELBO's reconstruction term, and how Module 9 reads the language-modelling
loss as compression. Condition number is Module 5's explanation for normalisation
layers and Adam. Intervals and the bootstrap sit on every results table from Module 2
on and are the whole of Module 12's A/B analysis.

## Reading

- Deisenroth, Faisal, Ong, *Mathematics for Machine Learning*, free. §2.6 to 2.8 (rank,
  linear maps), §4.2 to 4.6 (eigendecomposition, SVD, low-rank approximation), §5.1 to
  5.6 (Jacobians, backprop), ch. 6 (especially §6.5 Gaussians and §6.6 exponential
  families). Skip what you know.
- Murphy, *Probabilistic Machine Learning: An Introduction*, free. ch. 2 and 3
  (probability, the multivariate Gaussian and its ellipse), ch. 4 (MLE, MAP, the
  bootstrap, bias-variance), ch. 5 (decision theory), §6.1 to 6.2 (entropy and KL).
- Goodfellow, Bengio, Courville, *Deep Learning*, free. ch. 3 (probability and
  information theory, fast) and ch. 4 (numerical computation: §4.1 overflow and
  underflow, §4.2 conditioning).
- Petersen and Pedersen, *The Matrix Cookbook*, free. Keep it open for every matrix
  derivative in Problems 1 to 6 and check each against it.
- Welford, "Note on a method for calculating corrected sums of squares and products",
  *Technometrics*, 1962; or Knuth, *The Art of Computer Programming*, vol. 2, §4.2.2.
- Lin, Goyal, Girshick, He, Dollár, "Focal Loss for Dense Object Detection", 2017, §3
  only, for Lab 1.5.
- 3Blue1Brown, *Essence of Linear Algebra*, the chapters on linear transformations,
  change of basis and eigenvectors, for intuition only.

## Labs

### Lab 1.1: PCA two ways

Goal: see that eigendecomposition of the covariance and SVD of the data are the same
computation, and know what the components explain.

1. Load the 60,000 MNIST training images as a 60,000 × 784 float64 array in [0, 1] and
   centre it; do not standardise, since border pixels have near-zero variance.
2. Implement `pca_eig(X, k)` (covariance, `np.linalg.eigh`) and `pca_svd(X, k)`
   (`np.linalg.svd(X, full_matrices=False)`; components are rows of Vᵀ, eigenvalues
   σᵢ²/(n − 1)) in `01-maths/pca.py`, returning components, explained variance ratios
   and scores.
3. Assert both agree on explained variance to 1e-8 and on components up to sign, and
   match `sklearn.decomposition.PCA(n_components=50)` the same way. Time all three.
4. Scree plot of the first 100 eigenvalues with cumulative variance (90% and 95% arrive
   at roughly 90 and 150 components). Reconstruct ten digits at k = 2, 10, 50 and 784
   and check reconstruction MSE equals the mean of the discarded eigenvalues, which is
   Eckart-Young.
5. Plot the 2D scores coloured by digit: roughly 17% of the variance, yet the digits
   partly separate. Keep it for Module 4, where t-SNE will look much better and mean
   much less.

Done when: the sign-invariant tests against scikit-learn pass under pytest for k = 2, 10
and 50, the three figures are in the notebook, and reconstruction error matches the
discarded eigenvalue sum to 1e-6.

### Lab 1.2: Maximum likelihood by hand and by machine

Goal: derive three MLEs, look at the likelihood surface, and confirm a library loss is
an NLL.

1. For 500 samples each from N(2, 1.5²), Bernoulli(0.3) and Poisson(4), derive the MLE
   on paper, implement `nll_gaussian`, `nll_bernoulli` and `nll_poisson`, minimise each
   with `scipy.optimize.minimize`, and assert the optimum matches the closed form to
   1e-4.
2. Contour the Gaussian log-likelihood over (μ, σ) at n = 20, 500 and 5,000; the
   curvature at the peak is the Fisher information. Show the MLE for σ² is biased at
   n = 5 over 10,000 repeats.
3. Fit `LogisticRegression(penalty=None)` to a two-feature `make_classification` set of
   1,000 points, compute the mean Bernoulli NLL of its probabilities with your
   `nll_bernoulli`, perturb each coefficient by ±0.05 and show the NLL rises every time.
   Then add `penalty="l2", C=1.0` and write down the MAP objective now minimised (C
   multiplies the summed data term, penalty ‖w‖²/2, intercept unpenalised).

Done when: the closed-form tests pass under pytest, the three surfaces are in the
notebook, and each step has one written line saying what it showed.

### Lab 1.3: Numerical stability

Goal: cause every failure in the numerical-stability paragraph and fix each one.

1. In `01-maths/stable.py`, implement `softmax_naive`, `softmax_stable`,
   `logsumexp(z, axis)` and `log_softmax_stable`. Show the naive softmax is NaN on
   `[1000, 1000, 1000]` in both precisions, the stable one is exactly `[0, 0, 1]` on
   `[-1000, 0, 1000]`, and `np.log(softmax_stable(z))` is −inf where
   `log_softmax_stable` is finite for a logit gap of 200. Test `logsumexp` against
   `scipy.special.logsumexp` including rows with −inf entries (a masked attention
   position in Module 9).
2. Draw 10⁶ samples from N(10⁸, 1). Compute the variance by E[x²] − E[x]² in float32 and
   float64, by `np.var`, and by your streaming `welford(x)`; tabulate against the
   truth, then repeat at mean 10⁴ to find where float32 starts failing.
3. Sum 10⁷ copies of 0.1 in float32 sequentially, with `np.sum` (pairwise) and with
   Kahan summation you write; compare errors against 10⁶.
4. On MPS: create a float64 tensor and read the error; compare a 10⁶-element float32
   cumulative sum on MPS with float64 on the CPU; run `torch.autograd.gradcheck` on a
   small model moved to the CPU in float64. Write the four rules you now follow in the
   notebook.

Done when: the softmax, logsumexp and Welford tests pass under pytest including the −inf
cases, the variance table shows the naive float64 formula failing at mean 10⁸, and the
notebook has the four rules.

### Lab 1.4: Bias, variance, and an interval that covers

Goal: measure the bias-variance decomposition rather than believe it, and check a
bootstrap interval's coverage.

1. Let f(x) = sin(2πx) on [0, 1] with noise σ = 0.3. Draw 200 training sets of n = 30
   and fit degrees 1 to 15 with `numpy.polynomial.Polynomial.fit`, which rescales the
   domain (print the raw degree-15 Vandermonde condition number once; it is above
   10¹⁰).
2. On a fixed 200-point test grid compute bias², variance and noise, average over the
   grid, and plot the three terms and their sum against degree alongside the empirical
   test MSE. Repeat at n = 300 and overlay; then fix degree 15 and plot the terms
   against ridge λ ∈ {10⁻⁴, 10⁻², 1}.
3. Coverage. Fix true accuracy p = 0.9, n = 500. Over 2,000 repeats compute the Wald
   interval p̂ ± 1.96√(p̂(1 − p̂)/n), the Wilson interval and a percentile bootstrap with
   B = 1,000, and record whether each contains 0.9; expect roughly 0.93 to 0.96 for
   Wilson and bootstrap, Wald a little lower. Repeat at p = 0.99 and watch Wald fall
   well short.
4. Bootstrap a real number: the ROC-AUC of a `LogisticRegression` on the Adult test
   split with `scipy.stats.bootstrap(..., paired=True, method="BCa")`.

Done when: the three-term plot's sum tracks the empirical error at every degree, the
coverage table has all six numbers, and you have one sentence on why Wald fails at
p = 0.99.

### Lab 1.5: The loss zoo (headline lab)

Goal: implement the losses you will spend the course minimising, verify every gradient
two ways, and expose each loss's noise model.

1. In `01-maths/losses.py`, implement NumPy functions returning `(loss, grad)` with
   respect to the prediction: `mse`, `mae`, `huber(delta=1.0)`, `bce_with_logits`,
   `softmax_ce_with_logits` (via logsumexp), `kl_diag_gaussians(mu1, logvar1, mu2,
   logvar2)` and `focal_bce_with_logits(gamma=2.0, alpha=0.25)`, batched and
   mean-reduced. Derive each gradient on paper first, into `derivations.md`.
2. Write `finite_difference_grad(f, x, eps=1e-6)` (central differences, float64) and a
   pytest checking every analytic gradient at 20 random points to relative error 1e-6.
   MAE at zero residual and Huber at ±δ will not pass; test away from the kinks and say
   why.
3. A second pytest builds the same inputs as float64 CPU tensors, calls
   `torch.nn.functional.mse_loss`, `l1_loss`, `huber_loss`,
   `binary_cross_entropy_with_logits`, `cross_entropy` and your own PyTorch focal and
   KL, and asserts loss and `torch.autograd.grad` match yours to 1e-8. Check
   `bce_with_logits` at logits ±1,000 and `softmax_ce_with_logits` at magnitude 10⁴
   stay finite.
4. Noise models. For each regression loss ℓ(r), normalise p(r) ∝ exp(−ℓ(r)) on a grid,
   build the CDF, sample 10⁵ residuals by inverse CDF and histogram them with
   `scipy.stats.norm` and `laplace` overlaid: Gaussian for MSE, Laplace for MAE, a
   Gaussian core with exponential tails crossing at δ for Huber. For BCE, exp(−ℓ) over
   y ∈ {0, 1} sums to one; for focal loss plot the sum over p ∈ [0.01, 0.99] and conclude
   it is not the NLL of any distribution over the label, which is why its probabilities
   are miscalibrated.
5. Train the same two-layer MLP on California housing with MSE, MAE and Huber on MPS,
   clean and with 5% of training targets multiplied by 10. Report test MAE and MSE in a
   3 × 2 table.

Done when: every gradient passes both tests under pytest, the stability checks pass, the
residual histograms and focal-loss plot are in the notebook with a sentence on
calibration, and the table shows Huber and MAE degrading less than MSE under
contamination.

## Problem set

1. Assume yᵢ = f(xᵢ; θ) + εᵢ with εᵢ ~ N(0, σ²) independent. Write the likelihood, take
   the log, and show the MLE for θ minimises Σ(yᵢ − f(xᵢ; θ))². Then assume
   yᵢ ~ Categorical(softmax(f(xᵢ; θ))) and show the MLE minimises cross-entropy. What
   changes in the first case if σ² is also learned?
2. Put a prior N(0, τ²I) on θ. Show the MAP estimate under Gaussian noise minimises
   Σ(yᵢ − f(xᵢ))² + λ‖θ‖² and give λ in terms of σ² and τ². Repeat with a Laplace prior
   of scale b and identify the L1 penalty. Which prior puts more mass near zero, and
   what does that imply for sparsity?
3. Prove H(p, q) = H(p) + KL(p ‖ q). Prove Gibbs' inequality KL(p ‖ q) ≥ 0 with equality
   iff p = q, once via Jensen and once via log x ≤ x − 1. Give two distributions on
   three outcomes for which KL(p ‖ q) and KL(q ‖ p) differ by more than a factor of ten.
4. Derive E[(y − f̂(x))²] = (E[f̂(x)] − f(x))² + Var(f̂(x)) + σ² for y = f(x) + ε, stating
   where independence of ε from the training set is used and why the cross term
   vanishes. For a kNN regressor, write bias and variance as functions of k under a
   Lipschitz assumption on f and say which way each moves as k grows.
5. State Eckart-Young for the Frobenius norm. For a random 200 × 100 matrix with singular
   values decaying as 1/i, compute the rank-10 truncated SVD error and compare against
   ten other rank-10 approximations (Gaussian random projections, the first ten columns,
   a rank-10 NMF). Confirm none beats it.
6. Show softmax(z + c·1) = softmax(z) for any scalar c. Derive
   ∂softmax(z)ᵢ/∂zⱼ = sᵢ(δᵢⱼ − sⱼ), write the Jacobian as diag(s) − ssᵀ, show it is
   symmetric PSD with the all-ones vector in its null space, and connect that null
   direction to the shift invariance. Derive the gradient of cross-entropy with respect
   to the logits and confirm it is s − y.
7. A classifier scores 0.91 on n = 1,000. Compute the 95% Wald and Wilson intervals.
   Find the n at which the half-width falls below 0.005, and the n per model for a
   two-sample test to detect 0.91 against 0.92 at α = 0.05 with 80% power. Explain why
   scoring both models on the same test set and testing the paired disagreements
   (McNemar) needs far fewer examples, and what you must record to do it.
8. Derive the closed form of KL(N(μ₁, diag(σ₁²)) ‖ N(μ₂, diag(σ₂²))) in d dimensions.
   Specialise to μ₂ = 0, σ₂ = 1 in terms of μ and log σ², the form Module 7's VAE uses.
   Check against `kl_diag_gaussians` from Lab 1.5 and `torch.distributions.kl_divergence`
   on two `Normal` distributions.

## Deliverables

- `01-maths/pca.py`, `01-maths/stable.py` and `01-maths/losses.py`, each with pytest
  tests in `01-maths/tests/` against NumPy, SciPy, scikit-learn and PyTorch as the labs
  specify.
- `01-maths/derivations.md` with the eight problem-set solutions and the gradient
  derivation for every loss in Lab 1.5.
- Notebook with all five labs' figures and the variance, coverage and outlier tables.
- Write-up on Lab 1.5, following `writeup-template.md`, framed as "choosing a loss is
  choosing a noise model" for a manager deciding between MSE and Huber on a forecasting
  problem with outliers. The Limitations section should engage with what a
  finite-difference check cannot tell you at the kinks and with the precision float32 on
  MPS lost that you only noticed because you looked.

## Stretch

- Stream MNIST in chunks of 5,000 rows, accumulate the covariance with a Welford-style
  update, check against Lab 1.1, then compare `sklearn.decomposition.IncrementalPCA`.
- Derive and implement the natural gradient for a Gaussian's (μ, σ²) via the Fisher
  information and show it beats plain gradient descent on Lab 1.2's NLL.
- Implement the score-function and reparameterised estimators of ∇_μ E_{N(μ,1)}[x²] and
  compare their variances over 1,000 samples: the argument for reparameterisation in
  one plot.
- Read Higham, "The accuracy of floating point summation", 1993, and add pairwise
  summation to Lab 1.3's comparison.

## Next

Module 2 puts this to work on tabular data: ridge is the Gaussian prior from Problem 2,
logistic regression is Problem 1's Bernoulli NLL with a linear f, and the intervals from
Lab 1.4 go on every number in its model comparison table. The bias-variance
decomposition becomes the explanation for why bagging and boosting work.
