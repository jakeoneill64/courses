# Module 3: Clustering and mixture models

**Part II · 1.5 weeks · Needs: Modules 1 and 2. Data: scikit-learn toy sets, UCI Online Retail II.**

## Why this module

Most data a business holds has no labels. Nobody has tagged which customers are alike,
which transactions are odd, which support tickets are about the same thing. Clustering
is the first tool for that, and it is also the module where the habits of unsupervised
work are formed: there is no accuracy to report, so you have to decide what "good"
means and defend it. That is exactly what the Oxford Classical Machine Learning
assignment asks for when it puts an unlabelled dataset in front of you.

The second reason is structural. A Gaussian mixture fitted by EM is the simplest latent
variable model. The E-step is inference over a hidden variable; the M-step is learning
given that inference; the whole thing is coordinate ascent on a lower bound on the
log-likelihood. Module 7 replaces the discrete latent with a continuous one and the
exact E-step with a neural network, and calls the result a variational autoencoder. If
EM is clear now, the ELBO will be obvious then.

## Skip test

Answer cold, in writing.

1. Write the k-means objective. Show that Lloyd's algorithm never increases it and must
   terminate. Why can the result still be poor?
2. A Gaussian mixture with one component sat exactly on a single data point can drive
   the likelihood to infinity as that component's variance shrinks. What does this say
   about maximum likelihood for mixtures, and how do you fix it in practice?
3. Explain EM as coordinate ascent on a lower bound. Write the bound. When is it tight?
4. You ran k-means for k from 2 to 15 and the inertia fell monotonically. Name two ways
   to choose k, and the failure mode of each.
5. Two runs of k-means on the same data gave different clusterings. Give three possible
   reasons and what you would do about each.
6. Why does k-means fail on two concentric rings, and which two algorithms handle it?

If all six are easy, do Labs 3.4 and 3.5 only, and the write-up.

## Core ideas

**Unsupervised learning is a statement about structure, not a prediction.** The three
things people want from it are compression (describe many points with few parameters),
density estimation (how likely is this point), and structure discovery (which points
belong together). Clustering is the third, but the best clustering algorithms are
really the second in disguise, and the evaluation problem is the same for all three:
there is no ground truth, so you must argue from stability, predictive validity, or a
downstream task.

**Clustering is a statement about a metric.** Every algorithm below groups points that
are "close", and you chose what close means when you chose the features and their
scale. A feature measured in pounds spent dominates one measured in visits per year
unless you standardise. Log-transform anything heavy-tailed (money, counts) before
standardising, or the top 1% of customers become their own clusters. One-hot categorical
features make Euclidean distance meaningless in a way that is easy to miss. And in high
dimensions distances concentrate: the ratio of the farthest to the nearest neighbour
approaches one, and "close" stops meaning anything. Problem 6 makes you watch this
happen.

**k-means minimises within-cluster sum of squares by alternating two easy steps.** Fix
the centres and each point goes to its nearest one; fix the assignments and each centre
becomes the mean of its points. Each step cannot increase the objective, there are
finitely many assignments, so it terminates, at a local optimum. k-means++ seeding
(pick each new centre with probability proportional to squared distance from the
existing ones) gives an O(log k) approximation guarantee in expectation and matters far
more than the number of restarts. The assumptions are baked into the objective:
clusters are spherical, of similar size and similar spread, and every point belongs to
exactly one. When those hold it is fast, scalable and hard to beat; when they do not it
still returns k clusters, and they are wrong.

**A Gaussian mixture is k-means with the assumptions made explicit and adjustable.**
Each component has a mean, a covariance and a weight; each point has a soft
responsibility for each component. EM alternates computing responsibilities given the
parameters (E-step, which is Bayes' rule) and re-estimating the parameters as
responsibility-weighted statistics (M-step, which is weighted MLE). Full covariances
handle elongated and rotated clusters; the weights handle unequal sizes; the soft
assignments give you a calibrated "how sure" for every point and a density you can use
for anomaly scores. Problem 2 shows k-means is the limit of a spherical GMM as the
shared variance goes to zero. The price is more parameters (k·d(d+1)/2 for covariances
alone) and the singularity in skip-test question 2, which you prevent by adding a small
constant to the covariance diagonal or by a prior.

**EM is coordinate ascent on the ELBO.** For any distribution q over the latent z,
log p(x) ≥ E_q[log p(x, z)] − E_q[log q(z)], by Jensen. The E-step sets q to the exact
posterior p(z | x, θ), which makes the bound tight. The M-step maximises the bound over
θ. So each round cannot decrease log p(x), which is why your implementation in Lab 3.2
asserts monotonicity and treats any violation as a bug. Hold onto this; it is the
entire conceptual content of Module 7 with q replaced by a network.

**Model selection for mixtures has an honest tool.** Because a GMM is a probabilistic
model, you can compute its log-likelihood on held-out data, and you can penalise
parameters with BIC (k log n per parameter) or AIC (2 per parameter). BIC tends to pick
the true k on synthetic data and errs towards fewer components on real data, which is
usually what a business wants. k-means has no likelihood, so it has no BIC, so people
reach for the elbow plot, which is a judgement call dressed as a method.

**Hierarchical clustering gives you all values of k at once.** Agglomerative clustering
merges the two closest clusters repeatedly; "closest" depends on the linkage. Single
linkage chains through noise; complete linkage makes compact equal-diameter blobs;
average is a compromise; Ward merges the pair that increases within-cluster variance
least and behaves like a greedy k-means. The dendrogram is genuinely useful for
communicating structure and for choosing k by eye. The cost is O(n²) memory, so it
stops at around 50,000 points.

**Density-based clustering finds shapes and admits noise.** DBSCAN calls a point a core
point if it has at least `min_samples` neighbours within `eps`, grows clusters through
core points, and labels everything unreachable as noise. It finds rings and crescents,
does not need k, and has an explicit notion of outlier. It cannot handle clusters of
different density with one `eps`. HDBSCAN fixes that by building a hierarchy over all
`eps` and extracting the most stable clusters, and is the default choice for real
messy data when you do not know k. Spectral clustering takes a third route: build a
similarity graph, embed it with the Laplacian's eigenvectors, and run k-means there,
which turns connectivity into geometry.

**Choosing k is a modelling decision, and "none" is a valid answer.** The silhouette
score compares each point's mean distance to its own cluster with its mean distance to
the nearest other cluster; it rewards convex, well-separated clusters and is misled by
anything else. The gap statistic compares the inertia curve with that of uniform
reference data and picks the k where the gap is largest; it is the only elbow method
with a null hypothesis. Stability asks whether the clustering survives resampling:
cluster two bootstrap samples, assign points to both, and compute the adjusted Rand
index between them, for each k. A real structure is stable; an artefact is not. Do all
three, report all three, and be willing to conclude that the data is one blob.

**External validation, when you have labels, is not accuracy.** Cluster labels are
arbitrary integers, so use the adjusted Rand index or normalised mutual information,
both invariant to relabelling and both corrected for chance. If you find yourself
matching cluster 3 to class "dog", stop.

**Segmentation is only useful if it is actionable and durable.** A marketing team can
act on five segments with names; it cannot act on twelve or on segment boundaries that
move every month. The recency, frequency and monetary features in Lab 3.5 are the
industry default because they are computable for every customer, interpretable, and
predictive of future spend. A segmentation earns its keep if the segments differ on an
outcome the model never saw, persist when refitted on the next period, and suggest a
different action each. Anything else is a scatter plot.

**Forward links.** Responsibilities are posterior inference; GMMs are the ancestor of
every latent variable model. k-means centres are a codebook, and vector quantisation is
how VQ-VAEs and product-quantised vector databases compress embeddings. Topic models are
mixtures over words. When Module 7 asks you to derive the ELBO, you will have already
done it here.

## Reading

- Bishop, *Pattern Recognition and Machine Learning*, ch. 9 (mixture models and EM).
  Free from Microsoft Research. The cleanest derivation in print; do it with a pen.
- Murphy, *Probabilistic Machine Learning: An Introduction*, ch. 21 (clustering) and
  §8.7 (EM).
- Deisenroth, Faisal, Ong, *Mathematics for Machine Learning*, ch. 11 (density
  estimation with GMMs), for a second angle on the M-step.
- Hastie, Tibshirani, Friedman, *ESL*, §14.3 (cluster analysis), including 14.3.11 on
  the gap statistic.
- Arthur and Vassilvitskii, "k-means++: the advantages of careful seeding", 2007.
- Ester, Kriegel, Sander, Xu, "A density-based algorithm for discovering clusters",
  1996 (DBSCAN); Campello, Moulavi, Sander, "Density-based clustering based on
  hierarchical density estimates", 2013 (HDBSCAN); McInnes and Healy, "Accelerated
  hierarchical density clustering", 2017, for the version scikit-learn implements.
- scikit-learn user guide, §2.3 Clustering. Reproduce the comparison figure yourself
  in Lab 3.3 before reading their explanation of it.

## Labs

### Lab 3.1: k-means from an empty file

Goal: own the objective and its failure modes.

1. Implement `kmeans(X, k, n_init, seed)` in NumPy: k-means++ seeding, Lloyd's
   iterations, convergence on assignment change, best-of-`n_init` by inertia.
   Vectorise the distance computation as ‖a‖² + ‖b‖² − 2a·b; never loop over points.
2. Test against `sklearn.cluster.KMeans` on `make_blobs` with 10,000 points and k = 5:
   the best-of-10 inertia should be within 1% and the ARI between the two labelings
   above 0.99.
3. Break it. Generate anisotropic blobs (apply a shear matrix), blobs with variances
   1, 2.5 and 0.5, blobs of 500, 100 and 10 points, and two concentric circles. Run
   k-means with the right k on each and plot the results.
4. Time it at n = 10⁶, d = 10, k = 20. Compare with `MiniBatchKMeans`. Note where the
   time goes with a profiler.

Done when: the test in step 2 passes under pytest, and your notebook has four failure
figures each with a one-sentence explanation naming the violated assumption.

### Lab 3.2: Gaussian mixtures by EM

Goal: implement EM correctly, in the log domain, with the monotonicity assertion.

1. Implement `GMM(k, cov_type='full', reg_covar=1e-6)` with `fit`, `predict_proba`,
   `score_samples` (per-point log density) and `bic`. Initialise from your k-means.
   Compute responsibilities in the log domain with `scipy.special.logsumexp`. Use
   Cholesky factors for the Gaussian log-density; never invert a covariance matrix.
2. After every iteration assert the total log-likelihood has not decreased by more than
   1e-8. Run on `make_blobs` and on the anisotropic blobs from Lab 3.1.
3. Compare to `sklearn.mixture.GaussianMixture` with the same initialisation: final
   log-likelihood within 0.5%, ARI above 0.99 on the blobs.
4. Plot the components as 2σ ellipses over the data. Then set `reg_covar=0`, fit k = 5
   to 6 points, and watch a component collapse onto one point with the likelihood
   climbing. Screenshot the divergence.
5. Fit k from 1 to 10 on data generated from a known 4-component mixture and plot BIC
   and AIC. Repeat with held-out log-likelihood.

Done when: the monotonicity assertion never fires on ten random seeds, step 3's test
passes under pytest, and BIC recovers k = 4 on the synthetic data.

### Lab 3.3: Hierarchical, density-based and spectral

Goal: know which algorithm to reach for by looking at the data.

1. Reproduce scikit-learn's clustering comparison figure yourself: six datasets (blobs,
   anisotropic, varied variance, circles, moons, no structure) by eight algorithms
   (your k-means, your GMM, agglomerative with Ward and single linkage, DBSCAN,
   HDBSCAN, spectral, mean shift). Fix the random seeds.
2. For DBSCAN, choose `eps` from the sorted k-distance plot (the "knee") rather than by
   trial. Show the plot.
3. Draw the Ward dendrogram for the varied-variance blobs and mark where you would cut.
4. Fill in a table: dataset by algorithm, tick or cross, and for every cross a phrase
   naming why.

Done when: the figure and the table are in your notebook, and you can say from memory
which two algorithms solve every dataset and what each costs in return.

### Lab 3.4: How many clusters, and are there any?

Goal: build the model-selection toolkit and learn to distrust it.

1. Implement the gap statistic (Tibshirani, Walther, Hastie, 2001) with B = 20 uniform
   reference datasets drawn in the bounding box of the data, or in its principal
   components for a stricter null.
2. Implement clustering stability: for each k, draw two subsamples of 80%, cluster each,
   assign all points to both by nearest centre, compute the ARI. Repeat 10 times and
   report the mean and spread.
3. On a 4-blob dataset, plot inertia, silhouette, gap, BIC (GMM) and stability against
   k from 2 to 12. Which methods agree with k = 4?
4. Now run all five on uniform noise in 5 dimensions with n = 2,000. Which methods
   claim there are clusters? Record it. This is the result you will remember.
5. Compute the Hopkins statistic for both datasets as a direct test of clusterability.

Done when: you have the two five-panel figures, and a paragraph stating which methods
you now trust, in which order, and why.

### Lab 3.5: Segment real customers (headline lab)

Goal: a segmentation you would present to a marketing lead, with evidence it is real.

Data: UCI Online Retail II (id 502), two years of transactions from a UK online
gift retailer, about a million rows across two sheets, "Year 2009-2010" and
"Year 2010-2011". Columns are Invoice, StockCode, Description, Quantity, InvoiceDate,
Price, Customer ID, Country.

1. Clean. Drop rows with no Customer ID (they are guest checkouts; note how many). Handle
   cancellations (Invoice starting with C, negative Quantity) by netting them against
   their originals or dropping both; justify. Drop non-product stock codes (POST, D, M,
   BANK CHARGES and the like). Record every rule and its row count in the notebook.
2. Build a per-customer table from year one only: recency in days from the period end,
   frequency (distinct invoices), monetary (net revenue), plus tenure, mean basket
   value, distinct products, and the fraction of orders returned. Plot the marginals.
   Log-transform the heavy-tailed ones, then standardise.
3. Cluster with your k-means, your GMM and HDBSCAN. Choose k with silhouette, gap, BIC
   and stability from Lab 3.4; they will not all agree, so write down how you decided.
4. Profile each segment: size, median recency, frequency and monetary, and two or three
   words that a marketer would recognise (for example "lapsed high-value", "new
   one-off", "frequent low-basket"). Plot the segments in the first two principal
   components and in RFM space.
5. Test predictive validity. Assign every customer to a segment using year one only.
   Compute each customer's year-two revenue. Do the segments differ on it? Run a
   one-way ANOVA or a Kruskal-Wallis test and, more importantly, plot the distributions.
6. Test durability. Refit the whole pipeline on year two alone and compute the ARI
   between the year-one and year-two segment labels for customers present in both.
   State what value you would accept before shipping a segment-based campaign.
7. Write one action per segment, and one metric that would tell you within a quarter
   whether that action worked.

Done when: k is justified by at least two criteria plus the stability check, the
year-two revenue differs across segments with a plot showing it, the year-over-year
ARI is reported with a stated acceptance threshold, and every segment has a name, a
size, a profile and an action.

## Problem set

1. Show that for fixed assignments the centroid that minimises the within-cluster sum
   of squares is the mean. Then show that each Lloyd step is non-increasing and that
   the algorithm terminates. Give a small example where it stops at a poor local
   optimum.
2. Take a GMM with equal weights and shared covariance σ²I. Write the responsibilities
   and take σ → 0. Show the E-step becomes hard assignment to the nearest mean and the
   M-step becomes the mean update, so EM becomes Lloyd's algorithm.
3. Derive the M-step for a full-covariance GMM: means, covariances and mixing weights.
   Use a Lagrange multiplier for the constraint that the weights sum to one.
4. Prove log p(x) ≥ E_q[log p(x, z)] − E_q[log q(z)] for any q, and show the gap is
   KL(q ‖ p(z | x)). Conclude that setting q to the posterior makes the bound tight
   and that EM never decreases the log-likelihood.
5. Count the parameters of a k-component GMM in d dimensions for spherical, diagonal
   and full covariances. Write BIC and AIC for it. For what n does BIC's penalty per
   parameter exceed AIC's, and why does this make BIC conservative on large datasets?
6. Draw n = 1,000 points uniformly in the unit cube for d in {2, 10, 100, 1,000}. For
   each, compute the ratio of the maximum to the minimum distance from a random query
   point. Plot the ratio against d. Explain what this does to k-means in d = 1,000 and
   what you would do before clustering embeddings of that size.
7. Compute the silhouette score by hand for six points in two clusters of your choosing.
   Then construct a dataset where the silhouette prefers k = 2 but the data plainly has
   three groups. What property of the silhouette are you exploiting?
8. Lloyd's algorithm costs O(nkd) per iteration. Naive agglomerative clustering costs
   O(n³) and O(n²) memory; state the Lance-Williams update and explain how it brings
   the time down. At what n does agglomerative become infeasible on 32 GB?
9. In Lab 3.5, 3% of customers may produce 40% of revenue. Is that a cluster or the
   tail of a Pareto distribution? Design the check that distinguishes them, and say what
   each answer implies for how you would treat those customers.

## Deliverables

- `03-clustering/kmeans.py` and `gmm.py` with pytest tests that compare against
  scikit-learn.
- Notebook with all five labs' figures and the two tables from Labs 3.3 and 3.4.
- Write-up on the retail segmentation, following `writeup-template.md`. The Limitations
  section should engage with Problem 9 and with what the missing guest checkouts do to
  your conclusions.

## Stretch

- Fit `sklearn.mixture.BayesianGaussianMixture` with a Dirichlet process prior to the
  retail features and watch it switch components off. Compare its effective k to your
  BIC choice.
- Implement k-medoids (PAM) and run it with Manhattan distance on the retail data.
  Which segments change?
- Use k-means as a codebook: cluster the 384-dimensional sentence embeddings of the
  product Descriptions into 256 centres, replace each embedding with its centre index,
  and measure how much nearest-neighbour recall you lose. This is product quantisation,
  and it is how vector databases fit in memory.
- Cluster the product descriptions with HDBSCAN on UMAP-reduced embeddings, and check
  whether the resulting product groups explain any of your customer segments.

## Next

Module 4 asks the other unsupervised question: not which points belong together, but
which directions matter. PCA is the same trick you used to initialise and visualise
here, made rigorous, and matrix factorisation is a GMM's cousin for ratings data.
