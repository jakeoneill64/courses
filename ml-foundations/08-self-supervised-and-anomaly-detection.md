# Module 8: Self-supervised learning and anomaly detection

**Part III · 1 week · Needs: Modules 3, 4, 5 and 7. Data: CIFAR-10, Credit Card Fraud (ULB).**

## Why this module

Two unsupervised topics that matter more in practice than anything else in Part II or
III. The first is learning representations without labels, which is the idea under every
foundation model: pretrain on what you have in bulk, fine-tune on what you have in
scarcity. The second is finding the rare thing in a sea of normal: fraud, faults,
intrusions, the one transaction in six hundred that should not have gone through. Both
are unsupervised learning with a purpose, and both force the evaluation discipline that
the Oxford Deep Neural Networks and Security and Privacy of ML assignments will ask for,
because in neither case does the obvious metric mean what it appears to mean.

Structurally this module closes Part II's loop. The GMM from Module 3, the PCA from
Module 4 and the autoencoder from Module 7 become anomaly detectors, and you find out on
real fraud data which of them survive contact with a 0.17 percent positive rate. The
self-supervised half takes Module 5's harness and ResNet and shows that the same encoder,
trained on a task with no labels, can beat one trained with labels when labels are few.
That result, and understanding why augmentation rather than architecture produces it, is
what makes Module 9's masked and autoregressive pretraining feel inevitable rather than
arbitrary.

The business relevance needs no argument. Fraud, chargebacks, equipment failure and
account takeover are where unsupervised models earn money today, and every one of them
has an analyst on the end of the alert queue whose time is the real constraint. Learning
to set a threshold from a cost model and an alert budget, rather than from a metric, is
the habit this module leaves you with.

## Skip test

Answer cold, in writing.

1. Write the InfoNCE loss for a batch of N positive pairs. What plays the role of the
   label, and why is the mutual information it bounds capped at log N?
2. SimSiam uses no negative pairs and does not collapse. Name the two components that
   prevent it and give the argument for why removing either one collapses the embedding.
3. MAE masks 75 percent of image patches; BERT masks 15 percent of tokens. Explain the
   difference from the redundancy of each modality.
4. A fraud detector reports ROC-AUC 0.97 on a test set with 0.17 percent positives. Why is
   that number nearly uninformative, what would you report instead, and how would you
   pick the operating point?
5. In an isolation forest, why do anomalies end up in shallow leaves, and how is the path
   length normalised into a score?
6. Your autoencoder-based detector has a near-zero recall on one type of fraud that the
   supervised model catches easily. Give the mechanism and two fixes.

If all six are easy, do Labs 8.1 and 8.4 only, and the write-up.

## Core ideas

**Pretrain-then-fine-tune is the organising idea of modern machine learning, and
unlabelled data is the lever.** Labels are expensive, slow and specific to one task;
unlabelled data is nearly free and shared across all of them. Self-supervised learning
invents a supervisory signal from the data itself, trains an encoder on it, and hands the
encoder to a downstream task with a few labels. The bet is that whatever structure you
must learn to solve the invented task is the same structure the real task needs. Every
large language model, every vision foundation model and every embedding model you will
meet in Module 10 is this bet paying off, and the design question in each case is the
same: what invented task forces the right structure?

**Pretext tasks were the first answer and were superseded because they encoded the
wrong invariances.** Predicting a rotation, solving a jigsaw of patches, or colourising a
grey image each requires some understanding of objects, and each also requires
remembering things a classifier does not care about: which way is up, where the seam is,
what colour the wall was. The representations were better than random and worse than
supervised, and the gap did not close with scale. What replaced them was a task whose
solution is exactly the invariance you want: recognise two views of the same thing.

**Contrastive learning turns "same or different" into a likelihood, and InfoNCE is that
likelihood.** Take N pairs (x_i, x_i⁺) of two views of the same image, encode to z, and
score similarity s(z_i, z_j) = z_i·z_j / (τ ‖z_i‖ ‖z_j‖). The InfoNCE loss treats each
anchor as an N-way classification of its positive against the other 2N − 2 items in the
batch: ℓ_i = −log [exp s(z_i, z_i⁺) / Σ_{k≠i} exp s(z_i, z_k)]. Problem 1 shows its
minimum bounds mutual information, I(x; x⁺) ≥ log N − L, so with N = 512 the bound cannot
exceed 6.2 nats however good the encoder, which is one reason batch size matters. The
negatives are what stop the trivial solution of mapping everything to one point. The
temperature τ sets how sharply the softmax concentrates on the hardest negatives; too
small and a few near-duplicates dominate every gradient, too large and all negatives are
weighted alike and the loss stops discriminating (Problem 2).

**SimCLR's recipe is simple, and the augmentation set is the actual model.** Two random
augmentations of each image, a ResNet encoder, a two-layer MLP projection head, InfoNCE
on the head's output, large batches, long training. The encoder's output before the head
is what you keep; the head absorbs the invariances the loss demands so the encoder can
retain information the loss would otherwise throw away. Chen et al.'s ablations make one
thing plain: the choice of augmentations, and in particular the combination of random
resized cropping with strong colour jitter, moves the linear-probe accuracy by tens of
points, while architecture changes move it by a few. You are telling the model what does
not matter, and the representation is the complement of that. Change the augmentations
and you change the task.

**MoCo fixes the batch-size problem with a queue and a slowly moving encoder.** InfoNCE
wants many negatives, and SimCLR gets them by using batches of thousands. MoCo keeps a
queue of recent keys as negatives instead, so the number of negatives is decoupled from
the batch. The catch is that keys computed by a fast-changing encoder are inconsistent
with each other, so MoCo encodes keys with a momentum encoder whose weights are an
exponential moving average of the query encoder's, moving slowly enough that a queue of
65,536 keys stays coherent. The same momentum-encoder trick reappears in BYOL and DINO
for a different reason.

**Non-contrastive methods drop negatives entirely and should collapse, and the
interesting fact is why they do not.** BYOL trains an online network to predict a
momentum target network's embedding of the other view; SimSiam removes the momentum
encoder too and trains two branches of one network with a small predictor MLP on one
side, a stop-gradient on the other, and negative cosine similarity as the loss. With only
positive pairs the loss is minimised by a constant output, yet in practice the embedding
stays spread. Chen and He's ablations show the stop-gradient is essential and the
predictor nearly so, and their interpretation is that the pair acts like an EM algorithm:
the stopped branch plays the role of a fixed target (the E-step), the other branch fits
it (the M-step), and the predictor is what keeps the two from being identical (Problem 3).
Lab 8.2 makes you watch the collapse happen when you remove the stop-gradient. DINO is
BYOL with a vision transformer, a centring and sharpening step on the target instead of a
predictor, and the observation that the resulting attention maps segment objects with no
labels at all.

**Masked modelling is the bridge to language, and the masking ratio tells you how
redundant a modality is.** BERT hides 15 percent of tokens and predicts them; a masked
autoencoder hides 75 percent of image patches, encodes only the visible ones, and
reconstructs the pixels of the rest with a light decoder. The ratios differ because
pixels are redundant and words are not: you can fill in most of a picture from a quarter
of it, so a low mask ratio makes the task trivially solvable by interpolation, while
hiding most of a sentence leaves nothing to reason from. MAE's efficiency comes from the
encoder seeing a quarter of the patches, and its known weakness is that its linear-probe
accuracy trails contrastive methods even as fine-tuning beats them. Module 9 explains
both objectives for text and trains the autoregressive one; Module 10 fine-tunes an
encoder that was pretrained with the masked one.

**Evaluate a representation by what a cheap model can do with it, and compare fairly.**
The standard probes are a linear classifier on frozen features, k-nearest neighbours in
the feature space (no training at all), and full fine-tuning. A label-efficiency curve
plots downstream accuracy against the labelled fraction (1, 10, 100 percent) for the
self-supervised encoder and for a supervised model trained from scratch on the same
labelled subset with the same augmentations and budget. That last clause is the whole
comparison. Self-supervision wins at 1 and 10 percent by a wide margin, and roughly draws
at 100 percent on CIFAR-10; a claim that it "beats supervised" without stating the
labelled fraction is not a result.

**Anomaly detection is several problems that share a name.** A point anomaly is odd on
its own; a contextual anomaly is normal in general but odd here (a large purchase at 3 am
from a new device); a collective anomaly is a sequence that is odd together though each
element is fine. Unsupervised detection sees unlabelled data that may contain anomalies;
semi-supervised sees a clean set of normals and scores departures from it, which is
novelty detection; supervised has labelled anomalies and is classification under extreme
imbalance. Fraud data is usually the third, but with so few labels, such delayed labels,
and such fast drift that the first two are what you run day to day. Decide which you are
doing before choosing a method, because the methods and the evaluation differ.

**Statistical and density methods score how far a point is from where the mass is.** A
z-score per feature ignores correlation; the Mahalanobis distance d² = (x − μ)ᵀ Σ⁻¹ (x − μ)
accounts for it, and under Gaussianity d² is χ² with d degrees of freedom, which gives a
threshold with a stated false-positive rate (Problem 5). Estimate μ and Σ robustly, with
`MinCovDet`, or the anomalies you are hunting inflate the covariance and hide themselves.
Module 3's GMM generalises to multimodal normals, with log-likelihood as the score; kernel
density estimation does the same without parameters and fails past a dozen dimensions.
LOF compares a point's local density with that of its neighbours, so a point in a sparse
but legitimate region is not penalised while a point near a dense cluster but not in it
is; it is O(n²) without an index and sensitive to k.

**Isolation forest is the pragmatic default, and one-class methods are its
learned-boundary cousins.** Build many random trees, each splitting a random feature at a
random value on a subsample of 256 points, and record the depth at which each point ends
alone. Anomalies are few and different, so they are isolated in a handful of splits;
normal points need many. The expected path length is normalised by the average path length
of an unsuccessful search in a binary search tree, c(n) = 2H(n − 1) − 2(n − 1)/n, to give
a score in (0, 1] (Problem 4). It is linear in n, needs no distances, handles mixed
scales tolerably, and has one hyperparameter that matters (the contamination rate, which
sets the threshold and nothing else). One-class SVM fits the tightest boundary around the
normals in a kernel space; Deep SVDD does the same with a network mapping normals to a
small hypersphere, and must be regularised or it maps everything to the centre.

**Reconstruction error is an anomaly score with a specific blind spot.** Train Module 7's
autoencoder on transactions, score each new one by ‖x − x̂‖². Anything unlike the training
data reconstructs badly. The failure is anything an over-capable decoder can reconstruct
anyway: fraud that lives on the same manifold as normal spending, or a bottleneck wide
enough to pass everything through. A VAE's negative ELBO has the same blind spot with a
better calibration story. In practice reconstruction methods shine on sensor and image
data where normal is a tight manifold, and disappoint on tabular data like fraud where
normal is diffuse and fraud is not far from it.

**Under extreme imbalance ROC-AUC flatters everything, so report what an analyst
experiences.** With roughly 150 frauds in 85,000 transactions, a detector that ranks 99 percent
of normals below the frauds has a false-positive rate of one percent and a ROC-AUC near
0.99, and it also produces 850 false alerts for every 150 true ones. Precision-recall
curves and PR-AUC live in the space the analyst sees; precision at k, for k the number of
alerts the team can review in a day, is the honest headline. A cost model closes the loop:
with c_fp the cost of a wasted review and c_fn the cost of a missed fraud, the
threshold that minimises expected cost flags when p(fraud | x) > c_fp / (c_fp + c_fn)
(Problem 7), and an alert budget is the same decision with a capacity constraint instead
of a price. Bootstrap the metric, because 150-odd positives make the point estimate noisy.

**Fraud changes because fraudsters read your rejections, and the data is stranger than
it looks.** Labels arrive weeks late through chargebacks, so today's model trained on
today's labels is a model of last month's fraud. A fixed threshold's alert rate drifts as
the score distribution moves, which you monitor with a KS test or a population stability
index between the training period and a rolling window, and recalibrate on a schedule
rather than when someone notices. Adversaries adapt, so any published or inferred rule
decays; this is the adversarial drift the SPM course discusses. Finally, the ULB dataset's
features V1 to V28 are principal components of the real ones, so a rule like "V14 below
−5" cannot be explained to a customer or a regulator, and feature attribution reads
directions in PCA space. Interpretability was traded for release, and you should say so.

**Forward links.** Module 9 covers the two pretraining objectives that won for text,
masked and autoregressive, and builds the architecture they run on; the InfoNCE loss
returns as the training objective for the embedding models behind retrieval in Module 10. Module 13 turns this module's KS and PSI
checks into a monitoring job on a served model, and its model card must state the alert
budget and cost model the threshold came from.

## Reading

- Chen, Kornblith, Norouzi and Hinton, "A Simple Framework for Contrastive Learning of
  Visual Representations", 2020 (SimCLR). Read the ablation tables as carefully as the
  method. He, Fan, Wu, Xie and Girshick, "Momentum Contrast for Unsupervised Visual
  Representation Learning", 2020.
- Grill et al., "Bootstrap Your Own Latent", 2020. Chen and He, "Exploring Simple Siamese
  Representation Learning", 2021, especially section 5 on why it does not collapse.
  Caron et al., "Emerging Properties in Self-Supervised Vision Transformers", 2021 (DINO).
- He, Chen, Xie, Li, Dollár and Girshick, "Masked Autoencoders Are Scalable Vision
  Learners", 2022. van den Oord, Li and Vinyals, "Representation Learning with Contrastive
  Predictive Coding", 2018, for the InfoNCE bound.
- Balestriero et al., "A Cookbook of Self-Supervised Learning", 2023, as the reference to
  return to when a recipe detail matters.
- Liu, Ting and Zhou, "Isolation Forest", 2008. Breunig, Kriegel, Ng and Sander, "LOF:
  Identifying Density-Based Local Outliers", 2000.
- Ruff et al., "A Unifying Review of Deep and Shallow Anomaly Detection", 2021, for the
  taxonomy and the connections between methods. Chandola, Banerjee and Kumar, "Anomaly
  Detection: A Survey", 2009, for the older map.
- Aggarwal, *Outlier Analysis*, 2nd ed., ch. 1 to 4 (the problem, probabilistic models,
  linear models, proximity-based models).
- Dal Pozzolo, Caelen, Johnson and Bontempi, "Calibrating Probability with Undersampling
  for Unbalanced Classification", 2015, from the group that released the fraud dataset.
- Murphy, *Probabilistic Machine Learning: Advanced Topics* (free), ch. 32
  (representation learning).
- scikit-learn user guide, §2.7 Novelty and outlier detection, for the comparison figure
  and the API of `IsolationForest`, `LocalOutlierFactor`, `OneClassSVM` and `MinCovDet`.

## Labs

The SSL labs use your `common/` harness and the ResNet-18 from Module 5; log to the
MLflow experiment `08-selfsup`. The fraud labs are CPU-bound scikit-learn and LightGBM
work and run in minutes. Start Lab 8.1's long run first and do Lab 8.4 while it trains.

### Lab 8.1: SimCLR on CIFAR-10 (headline lab, SSL half)

Goal: a self-supervised encoder whose linear probe beats supervised training on the same
labelled fraction, and the ablation that shows what made it work.

1. Implement NT-Xent (InfoNCE) in `08-selfsup/simclr/loss.py` as
   `nt_xent(z1, z2, temperature)` over a batch of 2N normalised embeddings, with the
   positive of item i at i + N and the diagonal masked. Write `test_loss.py` comparing it
   against a brute-force double loop on random inputs to 1e-5, plus a check that
   identical positives and orthogonal negatives give a loss near zero at low temperature.
2. Build the encoder from your Module 5 ResNet-18 with the CIFAR stem (3 × 3 first conv,
   no max-pool), classifier removed, followed by a projection head 512 → 512 → 128 with
   BatchNorm and ReLU between. Augmentations per view: `RandomResizedCrop(32, scale=(0.2,
   1.0))`, horizontal flip, `ColorJitter(0.4, 0.4, 0.4, 0.1)` with probability 0.8,
   `RandomGrayscale(p=0.2)`. Write a dataset wrapper that returns two views.
3. Train 100 epochs, batch 512, fp16 autocast on MPS, temperature 0.5, SGD with momentum
   0.9, lr 0.12 (0.06 per 256), weight decay 5e-4, 10-epoch warmup then cosine; AdamW at
   1e-3 is an acceptable alternative. LARS is not needed at this batch size. Expect
   roughly 2 to 3 hours on the Mac, so start it before dinner or run it on a Colab T4.
   Log the loss and, every 10 epochs, a kNN accuracy on frozen features.
4. Evaluate the frozen encoder output (512-dim, before the head): kNN with k = 200 and
   cosine similarity on the training features; a linear probe trained with Adam for 100
   epochs on frozen features with only flip and crop augmentation. Expect roughly 78 to 85
   percent linear-probe accuracy at 100 epochs; treat 75 percent as the bar.
5. Label efficiency. Draw stratified subsets of 10 percent (5,000) and 1 percent (500) of
   the training labels. For each fraction train three things with the same budget and
   augmentations: a supervised ResNet-18 from scratch, a linear probe on the SSL encoder,
   and a full fine-tune of the SSL encoder at lr 1e-3 for the head and 1e-4 for the
   encoder. Plot accuracy against fraction on a log axis for all three, plus your Module 5
   full-label result.
6. Temperature ablation with 30-epoch runs at τ ∈ {0.1, 0.5, 1.0}, reporting kNN accuracy.
   Optional: one run with colour jitter removed, to see the augmentation claim directly.

Done when: `test_loss.py` passes under pytest; the 100-epoch encoder's linear probe is
above 75 percent; the label-efficiency figure shows the SSL probe and fine-tune above the
supervised baseline at 1 and 10 percent with the numbers in a table; and the temperature
ablation is in the notebook with a sentence on which τ won and why.

### Lab 8.2: SimSiam and the collapse you were promised

Goal: see that positives alone can work, and see exactly what happens when you remove the
one line that makes it work.

1. Implement SimSiam in `08-selfsup/simsiam/model.py`: the Lab 8.1 encoder, a projection
   MLP to 2048 dimensions with BatchNorm, a predictor MLP 2048 → 512 → 2048, and the
   symmetrised loss −½ [cos(p_1, sg(z_2)) + cos(p_2, sg(z_1))] with `sg` implemented as
   `.detach()`.
2. Train 30 epochs, batch 256, SGD 0.06, cosine, same augmentations as Lab 8.1. Every 100
   steps log the per-dimension standard deviation of the ℓ2-normalised projection output
   averaged over dimensions; a healthy run sits near 1/√2048 ≈ 0.022.
3. Ablate: remove the stop-gradient and train again; then restore it and remove the
   predictor. Plot the std trace for all three runs on one axis; the ablations should fall
   towards zero within the first epoch or two.
4. kNN accuracy for the healthy run; compare with the 30-epoch SimCLR runs from Lab 8.1.

Done when: the three std traces are on one figure, the healthy run's std stays near 0.02
while the ablations collapse, and the notebook states the kNN accuracy of the healthy
run against SimCLR at equal epochs.

### Lab 8.3: Masked autoencoding, lite

Goal: make MAE concrete before Module 9 builds transformers in earnest.

1. Split CIFAR-10 images into 4 × 4 patches (64 per image), flatten to 48-dim vectors, and
   mask a random 75 percent. Encode the 16 visible patches with a small transformer (four
   layers, width 192, four heads, learned position embeddings) using
   `torch.nn.TransformerEncoder`; a two-layer conv encoder on the masked image is an
   acceptable fallback if you would rather not touch attention until Module 9.
2. Decode with a two-layer transformer (width 128) over all 64 positions, mask tokens
   included, to predict the pixels of masked patches only. Loss is MSE on per-patch
   normalised pixels of the masked patches.
3. Train 50 epochs, batch 256, AdamW 1.5e-4 with cosine. Show eight test images as
   original, masked and reconstructed.
4. Linear probe on the mean-pooled encoder output over all 64 patches with no masking.
   Expect this to trail SimCLR noticeably, plausibly somewhere in the 45 to 60 percent
   range; state your number and the gap.

Done when: the reconstruction figure is in the notebook, the linear-probe number is
reported against Lab 8.1's, and one paragraph explains why masked modelling's linear
probe lags while its fine-tuning does not.

### Lab 8.4: Credit card fraud (headline lab, anomaly half)

Goal: five unsupervised detectors, a semi-supervised variant and a supervised upper bound
on real fraud data, compared the way an analyst would experience them.

Data: Credit Card Fraud (ULB), from OpenML as `CreditCardFraudDetection`: 284,807
transactions over two days in September 2013 by European cardholders, 492 frauds (0.172
percent). Columns are Time (seconds from the first transaction), V1 to V28 (principal
components of undisclosed features), Amount and Class.

1. Split by time: the first 70 percent of rows by Time is training, the last 30 percent
   test. Record the fraud count in each. Log-transform Amount, standardise using training
   statistics only. Write `08-selfsup/fraud/evaluate.py` with `pr_auc`,
   `precision_at_k(scores, y, k)` and a bootstrap over test rows (1,000 resamples) giving
   95 percent intervals, tested against `sklearn.metrics.average_precision_score` and a
   hand computation on a ten-row toy.
2. Unsupervised detectors trained on the training split without labels, in
   `08-selfsup/fraud/detectors.py`: Mahalanobis distance with `MinCovDet` (score is d²);
   your Module 3 GMM with k chosen by BIC over 1 to 8, score −log-likelihood;
   `IsolationForest(n_estimators=300)`; `LocalOutlierFactor(n_neighbors=50, novelty=True)`
   on a 50,000-row subsample; and a Module 7 autoencoder (30 → 16 → 8 → 16 → 30, MSE,
   20 epochs) with reconstruction error as score.
3. Semi-supervised: refit each detector on the training rows with Class = 0 only and
   score the test set again.
4. Supervised upper bound: `lightgbm.LGBMClassifier` with `scale_pos_weight` set to the
   class ratio, 500 trees, learning rate 0.05, early stopping on the last 15 percent of
   the training period by time. Score with predicted probability.
5. Compare everything on the test period by PR-AUC with bootstrap intervals, precision
   and recall at alert budgets of 100 and 500, and ROC-AUC in the last column so the
   contrast is visible. Realistic expectations: the supervised model's PR-AUC lands
   somewhere around 0.7 to 0.85 on a time split; isolation forest and the other
   unsupervised methods sit far below, often under 0.3; ROC-AUC is above 0.9 for nearly
   everything, which is the lesson.
6. Cost model. Take c_fp = £5 for an analyst review and c_fn as the median fraud Amount in
   the training period. Compute the cost-optimal threshold for the supervised model and
   its alert count; then compute the best achievable precision under a budget of 100
   alerts per day (scale the test period to days). Write the two-paragraph alert-budget
   analysis that would go to the fraud team.

Done when: `evaluate.py` tests pass under pytest; the comparison table has PR-AUC with
intervals, precision at 100 and 500, and ROC-AUC for every detector in both training
regimes; the supervised model's PR-AUC is above 0.6; at least one unsupervised detector's
precision at 100 is reported with its interval; and the cost-model threshold and alert
count are stated with the assumptions.

### Lab 8.5: Drift and recalibration

Goal: show that a threshold fixed on one period does not mean the same thing on the next.

1. Split the test period into its first and last quarter by Time. For the supervised and
   isolation-forest scores, compare score distributions between the two with a
   two-sample KS test (`scipy.stats.ks_2samp`) and a population stability index over 20
   quantile bins of the first quarter; report both.
2. Fix the Lab 8.4 threshold on the first quarter and count alerts per 10,000 transactions
   in each subsequent quarter. Plot the alert rate over time.
3. Design a recalibration policy: recalibrate to a target alert rate when PSI exceeds 0.2
   or the alert rate leaves a tolerance band, and implement it as a function that takes a
   window of scores and returns a threshold. Show the alert rate under the policy.
4. Write down what you cannot test here: the dataset spans two days, and real drift is
   over months with labels arriving late. Say what data you would need.

Done when: KS statistic, p-value and PSI are reported for both detectors, the alert-rate
plot with and without recalibration is in the notebook, and the policy is a tested
function in `08-selfsup/fraud/drift.py`.

## Problem set

1. For N pairs (x_i, y_i) drawn from p(x, y) and a critic f, write the InfoNCE loss L_N.
   Show the optimal critic is proportional to p(y | x) / p(y), and that at the optimum
   I(x; y) ≥ log N − L_N. Conclude that the bound cannot exceed log N, and compute it for
   N = 512 and N = 4,096.
2. Differentiate ℓ_i with respect to the similarity s_ik of a negative k and show the
   gradient weight is the softmax probability of that negative. Explain what τ → 0 and
   τ → ∞ do to the distribution of gradient over negatives.
3. Consider a Siamese network trained to minimise E ‖f(x_1) − f(x_2)‖² over positive pairs
   only. Show that any constant f is a global minimum. Now treat one branch as a fixed
   target and the other as a regression onto it: give the two-line argument for why the
   fixed points of this alternating procedure need not be constant, and what the
   predictor adds.
4. For an isolation tree on n points drawn without ties, show the expected path length of
   a random point is the average path length of an unsuccessful search in a binary search
   tree, c(n) = 2H(n − 1) − 2(n − 1)/n, with H the harmonic number. Write the anomaly
   score s(x) = 2^{−E[h(x)]/c(n)} and state its value when E[h(x)] equals c(n), tends to
   zero, and tends to n − 1.
5. Show that if x ~ N(μ, Σ) in d dimensions then (x − μ)ᵀ Σ⁻¹ (x − μ) ~ χ²_d. Compute the
   99.9 percent threshold for d = 30 and the expected number of false alerts on 85,000
   Gaussian transactions at that threshold. Explain why the empirical rate on the fraud
   data will differ.
6. A detector flags 500 of 85,000 test transactions and catches 120 of 150 frauds.
   Compute precision, recall, F1 and the false-positive rate. Explain in two sentences
   why the ROC curve for such a detector hugs the top-left corner while the PR curve does
   not.
7. Let a detector output a calibrated p = p(fraud | x). With cost c_fp per false alert and
   c_fn per missed fraud, write the expected cost of flagging when p > t and derive the
   optimal t. What does the rule become when the analyst can review at most k cases?
8. A 1 percent fraction of CIFAR-10's training set is 500 images. How many per class? A
   linear probe on a 512-dimensional frozen representation has 5,130 parameters; explain
   why it can still reach 60 percent or more from 500 examples while a ResNet-18 from
   scratch on the same 500 images cannot.

## Deliverables

- `08-selfsup/simclr/loss.py`, `train.py` and `test_loss.py`; `08-selfsup/simsiam/model.py`;
  `08-selfsup/mae/`.
- `08-selfsup/fraud/detectors.py`, `evaluate.py` with `test_evaluate.py`, and `drift.py`
  with its tests.
- Notebook with the label-efficiency figure and table, the SimSiam collapse figure, the
  MAE reconstructions, the full fraud comparison table and the drift plots.
- Write-up on the fraud detection work, following `writeup-template.md`, addressed to a
  fraud operations lead. The Limitations section should engage with the two-day span of
  the data and with what the PCA-anonymised features do to any explanation you can offer
  a customer or regulator.

## Stretch

- Run SimCLR for 400 epochs on a Colab T4 with the identical code and report how far the
  linear probe moves; the published CIFAR-10 numbers at 1,000 epochs are above 90 percent.
- Implement BYOL's momentum target encoder on top of Lab 8.2 and check whether it still
  needs the predictor to avoid collapse.
- Fit `sklearn.svm.OneClassSVM` and a Deep SVDD on the fraud training normals and add both
  to the Lab 8.4 table; note Deep SVDD's collapse without the bias-free and
  weight-decay constraints from Ruff et al.
- Treat the fraud problem as positive-unlabelled learning: assume only 30 percent of
  frauds in training are labelled, and compare a PU-adjusted classifier against training
  on the labels you have.

## Next

Module 9 takes the two objectives that won for text, masked prediction from this module's
MAE and autoregressive prediction, and builds the architecture they run on. Attention
arrives as soft retrieval, GPT is written from an empty file, and the tokeniser and KV
cache you add make the Oxford LLM course's architecture week feel like revision.
