# Module 7: Autoencoders, VAEs and diffusion

**Part III · 1.5 weeks · Needs: Modules 3 and 5. Data: MNIST, Fashion-MNIST, a synthetic 2-D set.**

## Why this module

This is where the two gaps you named meet. Deep generative models are unsupervised
learning done with the training craft from Module 5, and they are the hardest models in
the course to get working, because there is no accuracy to watch and a loss that goes
down can still mean nothing is being learned. The Oxford Generative AI course lists
"foundation models: autoencoders, transformers, diffusion models" in one breath, and the
Deep Neural Networks course expects you to know what a VAE optimises. Neither will have
time to derive anything. You will have derived all of it here, by hand, before writing
code.

The second reason is structural, and it is the one Module 3 promised. A Gaussian mixture
fitted by EM is coordinate ascent on the ELBO with a discrete latent and an exact E-step.
Make the latent continuous, replace the exact posterior with a network q_φ(z | x), and
optimise the bound by gradient ascent on both sets of parameters at once: that is a
variational autoencoder, and every line of the derivation is the one you already did.
Then stack a thousand latent layers, fix the encoder to be Gaussian noise, and simplify
the bound: that is a diffusion model. If you see diffusion as a VAE with a fixed encoder
and a weighted loss, the papers stop looking like magic.

The third reason is that these models earn their keep in businesses as anomaly scorers,
feature extractors and synthetic-data generators far more often than as image makers.
Module 8 uses reconstruction error on fraud data, and Module 10 assumes you know what an
"image token" is, which is a VQ-VAE codebook index.

## Skip test

Answer cold, in writing.

1. Derive the evidence lower bound for a model p(x, z) = p(x | z) p(z) and name the gap
   between it and log p(x). Why can you not maximise log p(x) directly when p(x | z) is
   a network?
2. Why does the score-function gradient estimator have high variance, and what does the
   reparameterisation trick change about the computation graph?
3. A VAE's samples are blurry. Give two distinct reasons rooted in the objective rather
   than in the architecture, and say what each implies you should change.
4. Write q(x_t | x_0) for the DDPM forward process in terms of ᾱ_t. What does the network
   in a DDPM actually predict, and why is that parameterisation trained with a uniform
   weight over t rather than the weight the variational bound gives?
5. Your VAE with a 32-dimensional latent reports that 27 dimensions have a KL term near
   zero. What has happened, why does the optimiser like it, and what are three fixes?
6. Why did diffusion displace GANs for image synthesis despite needing tens to hundreds
   of network evaluations per sample?

If all six are easy, do Labs 7.2 and 7.3 only, and the write-up.

## Core ideas

**An autoencoder is compression with a learned code, and the linear case is PCA.** An
encoder maps x to a lower-dimensional code z, a decoder maps it back, and you minimise
‖x − g(f(x))‖². With both maps linear and squared loss the global optimum spans the top-k
principal subspace (Problem 4), though the individual weights are not the components,
since any invertible transform of the code leaves the loss unchanged. A denoising
autoencoder reconstructs the clean input from a corrupted one, which stops it learning
the identity; a sparse autoencoder penalises the code so each input uses a few units.
None of these is a generative model: there is no distribution over z, so decoding a
random code gives garbage, because the encoder maps data onto a thin set with holes and
nothing tells you where the holes are.

**A prior on z fixes that and makes the likelihood intractable.** Write
p(x) = ∫ p_θ(x | z) p(z) dz with p(z) = N(0, I) and p_θ a decoder network. In Module 3 the
latent was discrete and the integral was a sum over k components. Here it has no closed
form, Monte Carlo from the prior fails beyond a few dimensions because almost every z
explains a given x terribly, and the posterior p(z | x) is just as intractable. EM's exact
E-step is gone, and you need a bound you can raise without ever computing the posterior.

**The ELBO is Module 3's bound with q made a network.** For any q(z | x),
log p(x) ≥ E_q[log p_θ(x | z)] − KL(q(z | x) ‖ p(z)), with gap KL(q(z | x) ‖ p(z | x)) as in
Module 3's Problem 4. Make q an encoder network q_φ(z | x) shared across all x (amortised
inference) and raise the bound by gradient ascent on θ and φ together. The first term is
reconstruction, how well x is explained by a code from its own posterior; the second pulls
every posterior towards the prior so codes overlap and a prior sample decodes to something
plausible. Unlike EM the bound is never tight: q_φ is restricted to a family (the
approximation gap) and shares parameters across inputs (the amortisation gap).

**Reparameterisation moves the randomness out of the gradient's way.** You need
∇_φ E_{q_φ}[f(z)] with φ inside the sampling distribution. The score-function estimator
E[f(z) ∇_φ log q_φ(z | x)] is unbiased but treats f as a black box, so its variance scales
with the size of f rather than with how f changes; Problem 3 measures this. Writing
z = μ_φ(x) + σ_φ(x) ⊙ ε with ε ~ N(0, I) puts the expectation over ε, and the gradient flows
through f, μ and σ by ordinary backpropagation. The price is that z must be continuous,
which is why discrete latents need the straight-through estimator or Gumbel-softmax.

**The decoder's likelihood decides what reconstruction means, and blur follows from it.**
A Bernoulli decoder on binarised pixels gives binary cross-entropy; a Gaussian with fixed
variance σ² gives squared error over 2σ², so σ silently weights the KL term. Both treat
pixels as independent given z, so when z cannot say whether a stroke is one pixel left or
right the optimal output is the average, which is a blur. Blur is the independence
assumption plus limited information in z, not an under-trained network. The KL for a
diagonal-Gaussian encoder against N(0, I) is closed form,
½ Σ_j (μ_j² + σ_j² − 1 − log σ_j²), from Module 1's problem set; log it per dimension.

**Posterior collapse is the KL term winning outright.** If the decoder can explain x
without some dimension of z, the cheapest move is to set that dimension's posterior equal
to the prior, so its KL is zero and it carries nothing. It happens early, while the encoder
is still useless, and with decoders strong enough to model the data alone. KL annealing
(β rising from 0 to 1 over the first epochs) gives the encoder time to become useful; free
bits stop penalising small KLs; a weaker decoder forces use of z. β-VAE goes the other
way on purpose: β > 1 trades reconstruction for dimensions closer to independent and often
interpretable, and sweeping β traces a rate-distortion curve with rate the KL and
distortion the reconstruction error.

**Evaluating a generative model means saying what you wanted from it.** The honest number
is the test ELBO in nats per image, or bits per dimension, −ELBO / (D ln 2) with D = 784
for MNIST. The importance-weighted bound log (1/K) Σ_k p(x, z_k) / q(z_k | x) is tighter
and converges to log p(x) as K grows, so its gap from the ELBO measures how poor q is. FID
embeds samples and real images with an Inception network, fits a Gaussian to each and
reports the Fréchet distance; it needs tens of thousands of samples, is biased upwards at
small n and is meaningless on digits. Likelihood and sample quality disagree both ways:
memorising the training set gives perfect samples and terrible held-out likelihood, and
mixing one percent noise into a good density barely moves the likelihood while visibly
breaking samples.

**GANs replace the likelihood with a learned test.** A generator G maps noise to samples;
a discriminator D is trained to tell them from data: min_G max_D E_data[log D(x)] +
E_z[log(1 − D(G(z)))]. For fixed G the optimal discriminator is
D*(x) = p_data(x) / (p_data(x) + p_g(x)), and substituting it gives 2·JS(p_data ‖ p_g) − log 4
(Problem 7), so at the optimum G minimises Jensen-Shannon divergence to the data. In
practice G maximises log D(G(z)), the non-saturating loss, because early on D wins easily
and log(1 − D(G(z))) has vanishing gradient exactly when G most needs one.

**GANs are hard because the objective is a saddle, not a minimum.** Gradient descent on a
minimax game can circle or collapse: G finds one output that fools D, D adapts, G jumps
elsewhere, and modes are visited one at a time rather than covered. With no likelihood you
cannot tell progress from motion without an external metric. Label smoothing, spectral
normalisation on D and two time-scale updates make training usable rather than reliable.
What GANs bought was sharpness, since D judges whole images and never rewards a per-pixel
mean. Diffusion displaced them because it has a stable regression loss, covers all modes
by construction and improves predictably with compute, and its sampling cost has since
been engineered down.

**Diffusion is a hierarchical VAE with a fixed noise encoder, and its bound reduces to
denoising.** The forward process q(x_t | x_{t−1}) = N(√(1 − β_t) x_{t−1}, β_t I) uses a fixed
schedule, linear from 10⁻⁴ to 0.02 over T = 1000 originally. With α_t = 1 − β_t and
ᾱ_t = Π_{s≤t} α_s it marginalises to q(x_t | x_0) = N(√ᾱ_t x_0, (1 − ᾱ_t) I) (Problem 5), so
x_t = √ᾱ_t x_0 + √(1 − ᾱ_t) ε in one line and x_T is essentially N(0, I). The reverse model
p_θ(x_{t−1} | x_t) = N(μ_θ(x_t, t), σ_t² I) is a chain of Gaussian decoders whose ELBO is a
sum over t of KL(q(x_{t−1} | x_t, x_0) ‖ p_θ(x_{t−1} | x_t)) plus end terms. Both Gaussians
share a variance, so each KL is a squared distance between means; parameterise μ_θ through
a network ε_θ(x_t, t) that predicts the added noise and each term becomes a weighted
‖ε − ε_θ‖². Ho, Jain and Abbeel drop the weights and train
L_simple = E_{t, x_0, ε} ‖ε − ε_θ(√ᾱ_t x_0 + √(1 − ᾱ_t) ε, t)‖² with t uniform, which
Problem 6 shows down-weights small t, where the exact bound obsesses over imperceptible
detail. A reweighted ELBO is still an ELBO, so a diffusion model is a VAE.

**Sampling is the slow part, and the samplers are where the engineering went.** Ancestral
sampling runs T network evaluations of
x_{t−1} = (1/√α_t)(x_t − (β_t / √(1 − ᾱ_t)) ε_θ(x_t, t)) + σ_t z. DDIM notes the loss depends
only on the marginals q(x_t | x_0), so a non-Markovian forward process with the same
marginals is consistent with the same trained network; its deterministic reverse step
takes 50 steps with little loss and makes noise-to-image invertible. Classifier-free
guidance trains one network with the condition dropped 10 to 20 percent of the time, then
samples with ε̃ = ε_θ(x_t, ∅) + w (ε_θ(x_t, c) − ε_θ(x_t, ∅)), w around 3 to 7, trading
diversity for fidelity. Latent diffusion trains an autoencoder with an 8× spatial
downsample first and diffuses in its latent, so 512 × 512 × 3 becomes 64 × 64 × 4, 48×
fewer dimensions. That is Stable Diffusion: a VAE with a diffusion prior.

**Score matching and normalising flows are the two other roads.** The score ∇_x log p(x)
needs no normalising constant, and denoising score matching shows the optimal denoiser of
Gaussian-corrupted data gives the corrupted density's score: for DDPM,
∇_{x_t} log q(x_t) = −ε / √(1 − ᾱ_t), so ε_θ is a scaled score and ancestral sampling is a
form of Langevin dynamics. That is Song and Ermon's route and the one that generalises to
continuous time. Flows make the model invertible, x = f(z) with a tractable Jacobian, so
log p(x) = log p(z) + log |det ∂f⁻¹/∂x| exactly and inference is exact too; the cost is a
latent the size of x and layers with cheap determinants, hence coupling layers. Flows stay
the right tool for exact densities on tabular data.

**VQ-VAE is an autoencoder with a k-means codebook in the middle.** The encoder emits a
grid of vectors; each is replaced by its nearest of K codebook entries; the decoder sees
the quantised grid. Nearest-neighbour has no gradient, so the straight-through estimator
copies the decoder's gradient back onto the encoder output. The codebook updates by an
exponential moving average of the encoder outputs assigned to each entry, a running k-means
M-step and Module 3's codebook stretch made differentiable, and a commitment loss
β ‖z_e − sg(e_k)‖² keeps the encoder near the codes. The failure is codebook collapse, most
codes never selected; measure the fraction used and re-initialise dead codes from live
encoder outputs. Discrete latents matter because a grid of indices is a token sequence a
transformer can model: that is how DALL-E 1 and VQ-GAN generated images and how images
and audio enter many multimodal LLMs.

**In a business these models are mostly not image generators.** Synthetic data needs the
evaluation discipline of the model behind it: train on synthetic, test on real, report the
gap, and check nothing was memorised, because privacy is not automatic. Reconstruction
error or negative ELBO is an anomaly score meaning "unlike what I was trained on", the
natural detector without labelled anomalies, blind to anything an over-capable decoder
reconstructs anyway. An encoder's z is a feature vector for downstream models, and a
VAE's z is usually worse for that than Module 8's contrastive representations, because
reconstruction spends capacity on pixels the task ignores.

**Forward links.** Module 8 uses this module's autoencoder as one of five fraud detectors
and shows where it fails, then reuses reconstruction as the pretext task in masked
autoencoders. Module 9 covers the other big generative family, autoregressive models,
which factorise p(x) = Π_i p(x_i | x_{<i}) for exact likelihood at the cost of sequential
sampling; a transformer over VQ-VAE codes is the bridge. Module 10's map of the LLM
landscape assumes you can say which family a foundation model belongs to and what each
can report as a number.

## Reading

- Kingma and Welling, "Auto-Encoding Variational Bayes", 2013, then Kingma and Welling,
  "An Introduction to Variational Autoencoders", 2019, the same authors' tutorial and the
  best single source. Doersch, "Tutorial on Variational Autoencoders", 2016, for the
  geometric intuition.
- Higgins et al., "β-VAE: Learning Basic Visual Concepts with a Constrained Variational
  Framework", 2017. Burda, Grosse and Salakhutdinov, "Importance Weighted Autoencoders",
  2015, for the tighter bound you compute in Lab 7.2.
- Goodfellow et al., "Generative Adversarial Nets", 2014, including the proof of
  Proposition 1. Radford, Metz and Chintala, "Unsupervised Representation Learning with
  Deep Convolutional Generative Adversarial Networks", 2015, for the DCGAN recipe.
- Ho, Jain and Abbeel, "Denoising Diffusion Probabilistic Models", 2020. Work through
  section 3 with a pen. Nichol and Dhariwal, "Improved Denoising Diffusion Probabilistic
  Models", 2021, for the cosine schedule and learned variances.
- Song, Meng and Ermon, "Denoising Diffusion Implicit Models", 2020. Ho and Salimans,
  "Classifier-Free Diffusion Guidance", 2022. Rombach et al., "High-Resolution Image
  Synthesis with Latent Diffusion Models", 2022, sections 1 to 3.
- Song and Ermon, "Generative Modeling by Estimating Gradients of the Data Distribution",
  2019, for the score-matching view.
- van den Oord, Vinyals and Kavukcuoglu, "Neural Discrete Representation Learning", 2017
  (VQ-VAE).
- Luo, "Understanding Diffusion Models: A Unified Perspective", 2022. The clearest
  derivation from ELBO to ε-prediction; read it after your own, not before.
- Prince, *Understanding Deep Learning* (free), ch. 15 (GANs), 16 (normalising flows),
  17 (VAEs) and 18 (diffusion models). Bishop and Bishop, *Deep Learning: Foundations
  and Concepts* (free), ch. 19 (autoencoders) and 20 (diffusion models).
- Murphy, *Probabilistic Machine Learning: Advanced Topics* (free), ch. 20 (overview of
  generative models), 21 (VAEs) and 25 (diffusion), with 23 (flows) and 26 (GANs) as
  needed.
- Lilian Weng, "From Autoencoder to Beta-VAE" and "What are Diffusion Models?" (blog),
  as a second explanation when a derivation sticks.

## Labs

Training runs use your `common/` harness from Module 5 and log to the MLflow experiment
`07-generative`. Use fp16 autocast on MPS for the convolutional models and keep the loss
in float32.

### Lab 7.1: Autoencoders on Fashion-MNIST

Goal: see the linear case recover PCA, then see what nonlinearity and noise buy.

1. Implement `LinearAE(d_in=784, d_code=32)` with no biases or nonlinearities, trained by
   SGD with squared loss on centred pixels until the training loss is flat to three
   significant figures (roughly 50 to 100 epochs at lr 0.01, momentum 0.9; the
   low-variance directions converge last).
2. Fit PCA with 32 components using your `04-embeddings/pca.py`. Compare subspaces with
   `scipy.linalg.subspace_angles` between the decoder's column space and the top-32
   components, and by the Frobenius distance between the two projection matrices. Report
   both test MSEs. Check the decoder columns are not orthogonal, so not the components.
3. Implement `ConvAE(d_code=32)`: three stride-2 convolutions to a 32-dimensional code,
   mirrored with transposed convolutions. Adam 1e-3, 20 epochs. Report test MSE against
   the linear model.
4. Add a denoising variant: Gaussian noise σ = 0.3 on the input, clamped to [0, 1],
   reconstructing the clean image. Show noisy test images through both models.
5. Decode ten points on the line between the codes of two test images from different
   classes, for the conv and linear models. Note where the interpolation leaves the data.

Done when: the largest principal angle is below about 10 degrees and the linear AE's test
MSE is within 2 percent of PCA's, both asserted in `07-generative/ae/test_linear_ae.py`;
the conv AE beats the linear AE on test MSE; and the reconstruction and interpolation
figures are in the notebook with one sentence each.

### Lab 7.2: VAE on MNIST, derived then built (headline lab)

Goal: an ELBO you derived, a model that reports it in nats, and a β sweep that shows the
trade-off and the collapse.

1. Before any model code, write `07-generative/vae/derivation.md`: the ELBO by Jensen and
   by the KL identity, the gap as KL(q(z | x) ‖ p(z | x)), the closed-form KL between a
   diagonal Gaussian and N(0, I), the reparameterised gradient of the reconstruction term,
   and that term as a sum of 784 binary cross-entropies. Commit it before step 2.
2. Implement `ConvVAE(d_latent)` in `07-generative/vae/model.py`: the Lab 7.1 encoder with
   linear heads for μ and log σ², a sigmoid decoder, a Bernoulli likelihood on dynamically
   binarised MNIST (resample each pixel as Bernoulli of its intensity every load). Return
   reconstruction and KL separately in nats per image; log both and per-dimension KL.
3. Train `d_latent=2` for 30 epochs, Adam 1e-3, batch 128. Plot test posterior means
   coloured by digit, decode a 20 × 20 grid over the prior's inverse CDF, and traverse each
   dimension with the other at zero. Expect a test ELBO of roughly −135 nats.
4. Train `d_latent=16` for 50 epochs. Report the test ELBO in nats and bits per dimension.
   A small conv VAE with 16 to 32 latent dimensions reaches roughly −100 to −90 nats on
   binarised MNIST; if you are below −105, check the binarisation, the sum over pixels
   and the KL sign before touching the architecture.
5. Sweep β in {0.1, 1, 4, 10} at `d_latent=16`. Record both terms, a sample grid and the
   sorted per-dimension KL. Reconstruction should improve and samples degrade as β falls,
   and at β = 10 most dimensions should sit at a KL near zero. Plot reconstruction against
   KL for the four runs: your rate-distortion curve.
6. Add KL annealing (β linear from 0 to 1 over 10 epochs) to the β = 1 run and compare the
   count of active dimensions (KL above 0.1 nats) with and without it.
7. Implement the importance-weighted bound with K = 64 posterior samples per test image
   using logsumexp. Expect it to be tighter than the ELBO by roughly 2 to 5 nats.

Done when: `derivation.md` is committed before `model.py`; a pytest test checks the
closed-form KL against a 10⁵-sample Monte Carlo estimate to 0.01 nats; the 16-dimensional
model's test ELBO is in the −100 to −90 nats range; the IWAE bound exceeds the ELBO on the
same model; and the notebook has the latent grid, traversals, β sweep and per-dimension
KL plots.

### Lab 7.3: DDPM from scratch

Goal: a diffusion model you can explain step by step, on data you can plot, then on digits.

1. Implement `07-generative/ddpm/schedule.py`: `betas` linear from 1e-4 to 0.02 over
   T = 1000, `alphas`, `alpha_bars`, and `q_sample(x0, t, eps)`. Test that
   `alpha_bars[-1]` is below 1e-4 and that `q_sample` at the last step has batch mean near
   zero and variance near one.
2. On 10,000 standardised points from `make_swiss_roll` (two coordinates) or `make_moons`,
   train an MLP ε-predictor (four hidden layers of 256, sinusoidal timestep embedding) for
   20,000 steps at batch 512, Adam 1e-3. Implement ancestral sampling and plot 1,000
   samples at t = 1000, 750, 500, 250, 100, 0.
3. Implement a small UNet in `07-generative/ddpm/unet.py` for 28 × 28 × 1: residual blocks
   with GroupNorm and SiLU, two downsampling stages (channels 64, 128, 256), a sinusoidal
   timestep embedding added into every block, skip connections. Target 2 to 5 million
   parameters and print the count.
4. Train on MNIST in [−1, 1] with `L_simple`, batch 128, AdamW 2e-4, weight EMA at 0.999,
   fp16 autocast, roughly 30 to 60 minutes on MPS (around 15,000 steps). Log the loss and
   a 64-sample grid every 1,000 steps.
5. Implement `sample_ancestral(model, n)` and `sample_ddim(model, n, steps=50, eta=0)`.
   Time both for 256 samples and show the grids side by side.
6. FID is meaningless here, so train a small convnet to above 99 percent on MNIST, classify
   10,000 samples from each sampler, and report the class histogram and mean maximum
   softmax. Good samples put every class between roughly 7 and 13 percent with mean
   confidence above 0.9.

Done when: the schedule tests pass; the swiss-roll trajectory figure is in the notebook;
both samplers give legible digits, DDIM at 50 steps is at least 15× faster than 1000
ancestral steps and within a few points of it on mean confidence; and the histogram and
confidence numbers are reported for both.

### Lab 7.4: A small DCGAN, to see it go wrong

Goal: watch instability and mode collapse, then apply the standard fixes. One afternoon.

1. Implement `07-generative/gan/dcgan.py`: generator from 100-dim noise through transposed
   convolutions with BatchNorm and ReLU to 28 × 28 × 1 with tanh; discriminator with strided
   convolutions and LeakyReLU 0.2. Adam 2e-4, β_1 = 0.5, batch 128.
2. Train with the minimax loss for 10 epochs, logging both losses and a sample grid per
   epoch. Note whether the generator loss flattens as the discriminator's goes to zero.
3. Switch to the non-saturating loss, then add one-sided label smoothing (real targets
   0.9), optionally spectral normalisation via
   `torch.nn.utils.parametrizations.spectral_norm`.
4. Provoke collapse: generator lr 1e-3, discriminator updated once per five generator
   steps. Run the samples through the Lab 7.3 classifier and show the histogram
   concentrating on a few digits.
5. Score the best GAN with the Lab 7.3 metric and compare to the DDPM.

Done when: four sample grids (minimax, non-saturating, smoothed, collapsed) with loss
curves and class histograms are in the notebook, plus one paragraph on what each change
did and how you knew.

### Lab 7.5: VQ-VAE on Fashion-MNIST

Goal: a discrete latent that is honestly used, and why it matters for Module 9.

1. Implement `VectorQuantizerEMA(num_codes=512, dim=64, decay=0.99, commitment=0.25)` in
   `07-generative/vqvae/quantizer.py`: nearest-code lookup, straight-through gradient, EMA
   of code counts and sums with Laplace smoothing, commitment loss. Test that a batch equal
   to the codebook passes through unchanged and that gradient reaches the encoder output.
2. Encoder to a 7 × 7 grid of 64-dimensional vectors, matching decoder, MSE loss, 30
   epochs, Adam 2e-4.
3. Log codebook usage each epoch: distinct codes selected on the test set and the
   perplexity of the usage distribution. Expect somewhere between a third and most of the
   codebook; below about 20 percent, re-initialise dead codes from random encoder outputs
   and note the effect.
4. Show reconstructions and the 7 × 7 index map for eight test images. Change one index by
   hand and decode.
5. Write down what a generative model over this latent needs: p(index_1, ..., index_49)
   over 512 symbols. A transformer is exactly that, and Module 9 builds one.

Done when: the quantizer tests pass; test MSE is within 30 percent of the Lab 7.1 conv AE;
codebook usage is plotted over training and stated as a number; and the reconstruction
and index-map figures are in the notebook.

## Problem set

1. Derive log p(x) ≥ E_q[log p(x | z)] − KL(q(z | x) ‖ p(z)) two ways: from Jensen's
   inequality on log ∫ q(z | x) p(x, z) / q(z | x) dz, and from the identity
   log p(x) = ELBO + KL(q(z | x) ‖ p(z | x)). Show the gap is that KL. Explain why, unlike
   Module 3, you cannot make it zero by choice of q.
2. Derive KL(N(μ_1, diag σ_1²) ‖ N(μ_2, diag σ_2²)) in closed form, then specialise to a
   standard normal second argument. Write its gradient with respect to μ_1 and log σ_1²
   and check both against `torch.autograd` on random inputs.
3. Let z ~ N(μ, 1) and f(z) = z². The exact gradient of E[f(z)] with respect to μ is 2μ.
   Write the score-function estimator f(z) (z − μ) and the reparameterised estimator
   2(μ + ε), show both are unbiased, and estimate the variance of each numerically from
   10⁵ samples at μ ∈ {0, 1, 2, 5}. Explain the trend in one sentence.
4. Show that a linear autoencoder x̂ = W_2 W_1 x with rank-k product and squared loss has
   its global minimum at any W_2 W_1 equal to the projection onto the top-k principal
   subspace of the data covariance. Use the Eckart-Young theorem. Explain why W_2's
   columns need not be the eigenvectors, and why SGD will not in general make them so.
5. From q(x_t | x_{t−1}) = N(√(1 − β_t) x_{t−1}, β_t I), derive
   q(x_t | x_0) = N(√ᾱ_t x_0, (1 − ᾱ_t) I) by induction, using the fact that a sum of
   independent Gaussians is Gaussian. Compute ᾱ_T for the linear schedule numerically.
6. Write the DDPM variational bound as L_0 + Σ_t L_{t−1} + L_T. Derive the mean of
   q(x_{t−1} | x_t, x_0) using Bayes' rule on Gaussians, and show each L_{t−1} is
   (1 / 2σ_t²) ‖μ̃_t(x_t, x_0) − μ_θ(x_t, t)‖² up to a constant. Substitute the
   ε-parameterisation of μ_θ and obtain the weight
   β_t² / (2σ_t² α_t (1 − ᾱ_t)) on ‖ε − ε_θ‖². Plot that weight against t for the linear
   schedule and say which time steps L_simple up-weights relative to the bound.
7. For the GAN objective with G fixed, show the optimal discriminator is
   D*(x) = p_data(x) / (p_data(x) + p_g(x)). Substitute it back and show the value is
   2·JS(p_data ‖ p_g) − log 4. What is the value at the global optimum, and what does the
   discriminator output there?
8. Your Lab 7.2 model reports a test ELBO of E nats per image on 28 × 28 binarised
   MNIST. Write the conversion to bits per dimension and evaluate it for E = −90 and
   E = −100. Explain what an ELBO of exactly −784 · ln 2 nats would mean about the model.
9. A Gaussian decoder with a learned per-pixel variance σ_θ(z) has reconstruction term
   −½ Σ_i [(x_i − μ_i)² / σ_i² + log σ_i² + log 2π]. Show that if the mean fits some
   pixel exactly the term is unbounded above as σ_i → 0, and relate it to the singularity
   in Module 3's skip-test question 2. Propose two fixes and say what each does to the
   ELBO's meaning.

## Deliverables

- `07-generative/ae/` with `linear_ae.py`, `conv_ae.py` and `test_linear_ae.py`.
- `07-generative/vae/derivation.md`, `model.py`, `train.py` and `test_vae.py` (closed-form
  KL against Monte Carlo, reconstruction term sanity).
- `07-generative/ddpm/schedule.py`, `unet.py`, `sample.py` and `test_schedule.py`.
- `07-generative/gan/dcgan.py` and `07-generative/vqvae/quantizer.py` with
  `test_quantizer.py`.
- Notebook with all five labs' figures, the β-sweep rate-distortion plot, and the
  classifier-metric table comparing DDPM ancestral, DDIM and the GAN.
- Write-up on the VAE and DDPM as a pair, following `writeup-template.md`, framed as a
  recommendation on which to use for a synthetic-data or anomaly-scoring task. The
  Limitations section should engage with Problem 8 and with why the test ELBO and the
  classifier metric can rank your models differently.

## Stretch

- Make the MNIST DDPM class-conditional and implement classifier-free guidance with 10
  percent condition dropout. Sweep the guidance weight from 0 to 8 and plot the Lab 7.3
  classifier's confidence against the diversity within each class.
- Replace the linear schedule with Nichol and Dhariwal's cosine schedule and their learned
  interpolated variance, and compare sample quality at 50 DDIM steps.
- Implement RealNVP with affine coupling layers on the two-moons data from Lab 7.3 and
  report the exact test log-likelihood. Then plot the learned density on a grid and
  compare it to a 10-component GMM from Module 3.
- Install `diffusers` in a scratch environment, load a small pretrained Stable Diffusion
  checkpoint, and inspect the VAE stage alone: encode an image, print the latent shape,
  decode it, and measure the reconstruction error. That is the "latent" in latent
  diffusion.

## Next

Module 8 uses this module's autoencoder and Module 3's GMM as two of five anomaly
detectors on real fraud data, and turns reconstruction into a pretext task for learning
representations without labels. The ELBO stays; what changes is that the objective stops
being about generating and starts being about what the encoder learns on the way.
