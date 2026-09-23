# Module 4: Dimensionality reduction and embeddings

**Part II · 1 week · Needs: Modules 1 and 3. Data: MNIST, MovieLens ml-1m, UCI Online Retail II.**

## Why this module

Module 3 asked which points belong together. This module asks which directions matter,
and it turns out to be the more useful question: nearly every representation you will
meet from here on, from a PCA-whitened feature to a word vector to the hidden state of a
transformer, is a low-dimensional embedding of something high-dimensional, and the tools
for building, judging and searching such embeddings are the ones here. It is also where
the most abused figure in applied ML lives: the two-dimensional t-SNE or UMAP plot with
coloured blobs, presented as evidence. You will learn to make those plots, to break them
on purpose, and to write the caveat that has to accompany one.

For Oxford, this feeds Classical Machine Learning directly (PCA, factor analysis,
manifold methods) and Knowledge Graphs indirectly, since knowledge-graph embeddings are
matrix and tensor factorisation under another name. The MovieLens recommender is also
the first system in the course whose evaluation has to be argued rather than read off:
RMSE says one thing, ranking metrics another, and a popularity baseline embarrasses most
of the models people build.

Structurally, matrix factorisation is the bridge from unsupervised learning to
representation learning. Levy and Goldberg showed that word2vec factorises a
co-occurrence matrix; the autoencoder in Module 7 is PCA with a nonlinearity; the
contrastive encoder in Module 8 and the retrieval index in Module 10 both start from
"embed, then nearest neighbour", which is where Lab 4.4 ends.

## Skip test

Answer cold, in writing.

1. State PCA as maximum variance and as minimum reconstruction error and show they pick
   the same directions. What does whitening do, and when does it hurt?
2. A t-SNE plot shows five well-separated clusters of very different sizes. Name three
   things the plot does not tell you and say why, in terms of the algorithm.
3. Why can you project 10,000-dimensional vectors to 500 random dimensions and lose
   little? State the lemma and its dependence on n and ε.
4. Write the biased matrix factorisation model for ratings and the SGD updates for one
   observed rating. Why does regularisation matter more here than in most supervised
   problems?
5. Why is treating an unobserved user-item pair as a rating of zero wrong, and what do
   Hu, Koren and Volinsky do instead?
6. A recommender improves RMSE from 0.90 to 0.87 and its top-10 recommendations get
   worse. Explain how, and name two metrics you would report instead.

If all six are easy, do Labs 4.2 and 4.4 only, and the write-up.

## Core ideas

**PCA is one decomposition with three motivations, and they agree.** Centre X (n × d).
Ask for the unit direction w maximising the variance of the projection, wᵀΣw with
Σ = XᵀX/n; the Lagrangian gives Σw = λw, so w is the top eigenvector and λ the variance
captured. Ask instead for the k-dimensional subspace minimising the reconstruction
error ‖X − XWWᵀ‖²_F; the answer is the same top-k eigenvectors, because minimising the
discarded variance is maximising the kept variance (Problem 1). Or take the SVD
X = UΣVᵀ: the columns of V are the eigenvectors of XᵀX, the scores are UΣ, and truncating
at k is Module 1's Eckart-Young optimum. Use the SVD route in practice: it never forms
the d × d covariance and is what `sklearn.decomposition.PCA` does.

**How many components, whether to whiten, and what PCA assumes are one question about
the noise.** The scree plot and cumulative variance ratio are descriptive; 95% is a
convention, not a criterion. Whitening divides each score by √λᵢ so the components have
unit variance, which helps methods that assume isotropy (k-means, RBF kernels) and hurts
when the small eigenvalues are noise you have just amplified. Probabilistic PCA (Tipping
and Bishop) makes the noise explicit: x = Wz + μ + ε with z ~ N(0, I) and ε ~ N(0, σ²I);
its maximum-likelihood W spans the top-k eigenvectors and its σ² is the mean of the
discarded eigenvalues. Factor analysis gives each dimension its own noise variance,
which is the right model when features are on different scales. Both are latent
variable models fitted by EM, Module 3's GMM with a continuous Gaussian latent in place
of a discrete one. A linear autoencoder trained with squared error finds the same
subspace (Problem 2, Lab 4.1), which is why Module 7 will call the VAE "PPCA with a
neural decoder". Kernel PCA eigendecomposes a centred n × n kernel matrix instead,
buying nonlinear components at O(n²) memory and no direct reconstruction.

**Random projections preserve distances with no training, and the Johnson-Lindenstrauss
lemma says how many dimensions you need.** Multiply by a k × d Gaussian matrix scaled by
1/√k. For any n points and tolerance ε, k on the order of (log n)/ε² dimensions keeps
every pairwise distance within a factor of 1 ± ε with high probability, and d does not
appear. The constants are pessimistic:
`sklearn.random_projection.johnson_lindenstrauss_min_dim(10**6, eps=0.1)` returns
11,841, while Lab 4.5 shows 300 random dimensions keep MNIST's kNN accuracy within a
point or two of the 784-dimensional original. Reach for it when d is enormous and the
covariance is too expensive, as a preprocessing step for approximate nearest-neighbour
search, and as the null model against which PCA's "structure" should be judged.

**t-SNE turns neighbourhoods into a picture by matching two distributions, and every
design choice is about the crowding problem.** SNE defines, for each point i, a Gaussian
distribution pⱼ|ᵢ over its neighbours whose bandwidth σᵢ is set by binary search so that
the distribution's perplexity equals a user value (default 30), which makes σᵢ small in
dense regions and large in sparse ones; it then places points in 2D and minimises KL(P ‖
Q) between the high- and low-dimensional neighbour distributions by gradient descent.
The crowding problem is that a 2D disc cannot hold as many equidistant neighbours as a
100-dimensional ball, so moderately distant points get squashed together; t-SNE uses a
Student-t kernel with one degree of freedom in the low-dimensional space, whose heavy
tail lets dissimilar points sit far apart. Perplexity is effectively the number of
neighbours each point attends to, and the plot changes qualitatively between 5 and 100
(Lab 4.2).

**A t-SNE plot shows local neighbourhoods and nothing else, and the three things people
read off it are the three things it does not encode.** Cluster sizes carry no
information, because σᵢ adapts to local density: a tight cluster and a diffuse one are
both expanded to fill roughly the same area (Problem 8). Distances between clusters
carry no information, because the Student-t tail makes the gradient between far-apart
groups nearly zero, so wherever they landed early is where they stay. And apparent
clusters can be artefacts: pure Gaussian noise at low perplexity produces convincing
blobs, because the algorithm optimises for local structure that any finite sample has.
t-SNE also has no `transform` for new points and differs across seeds; two runs
disagreeing on global layout is normal.

**UMAP builds a weighted neighbour graph and lays it out, which makes it faster and
extensible and just as easy to over-read.** For each point take its `n_neighbors`
nearest neighbours, give the nearest weight 1 (the ρᵢ term) and choose σᵢ so the weights
sum to log₂(n_neighbors); symmetrise by fuzzy union (a + b − ab). Then optimise a 2D
layout by minimising the fuzzy-set cross-entropy between that graph and a low-dimensional
one whose edge weights follow a curve set by `min_dist`, with negative sampling.
`n_neighbors` (default 15) trades local against global structure as perplexity does;
`min_dist` (default 0.1) sets how tightly points may pack. UMAP is several times faster
than t-SNE, keeps more global structure in practice, and has `transform` for new points
and a supervised mode. Its caveats are the same three, and its defaults make clusters
look tighter than they are, which is more dangerous, not less.

**A two-dimensional embedding is a hypothesis generator, never evidence.** Use it to
notice that two groups of customers or two topics might differ, then test that with
Module 3's tools (stability, predictive validity, a downstream task) on the original
features. Never quantify anything on the 2D coordinates: no cluster sizes, no distances,
no k-means on the embedding as the segmentation. When one goes in a report, attach the
perplexity or `n_neighbors`, the seed, a statement that sizes and distances are not
meaningful, and ideally a second run at another setting.

**Non-negative matrix factorisation gives parts instead of directions.** Factor a
non-negative X as WH with W (n × k) and H (k × d) both non-negative, minimising
Frobenius or KL divergence by Lee and Seung's multiplicative updates or coordinate
descent (`sklearn.decomposition.NMF`). PCA's components are orthogonal and signed, so
they cancel and resist interpretation; NMF's are additive, so on face images they are
facial parts and on a term-document matrix they are topics, each a non-negative
distribution over words, each document a non-negative mixture of topics. It is the
linear-algebra cousin of latent Dirichlet allocation, cheaper and with fewer knobs, and
on TF-IDF inputs it usually gives cleaner topics than LDA on counts (Lab 4.3).

**Matrix factorisation for ratings is PCA on a matrix that is 95% missing, and the
missingness changes everything.** Model r_ui ≈ μ + b_u + b_i + p_uᵀq_i with user and
item biases and k-dimensional factors, and minimise, over observed pairs only, Σ(r_ui −
r̂_ui)² + λ(‖p_u‖² + ‖q_i‖² + b_u² + b_i²). SGD visits each observed rating, computes e
= r − r̂ and steps p_u += η(e q_i − λ p_u), q_i += η(e p_u − λ q_i), biases likewise;
Alternating least squares fixes the item factors and solves each user's ridge regression
in closed form, p_u = (Q_uᵀQ_u + λI)⁻¹Q_uᵀr_u, then swaps; it parallelises trivially.
The biases are not decoration: a bias-only model captures most of the explained variance
and is the second baseline after the global mean. A user with three ratings is fitted
with k + 1 parameters, so regularisation is what stands between you and memorising the
training set; Lab 4.4 sweeps λ before anything else.

**Implicit feedback is not missing ratings, and treating non-interaction as a zero is
wrong in two ways.** Clicks, purchases and plays record what someone chose; the absence
of a click means "did not see" far more often than "disliked", and every observed event
is positive. Hu, Koren and Volinsky separate preference from confidence: p_ui = 1 if any
interaction and 0 otherwise, confidence c_ui = 1 + α r_ui growing with the interaction
count (α around 40 in the paper), and the loss Σ over all pairs, zeros included, of
c_ui(p_ui − x_uᵀy_i)² plus L2. Every pair is in the loss, so the naive cost is
O(|U||I|k), but the ALS update can be rewritten so the dense part YᵀY is computed once
per sweep and only each user's observed items are touched, giving O(nnz·k² + |U|k³) per
sweep.

**Recommenders are ranking systems, and RMSE is the wrong target for one.** RMSE weights
every observed rating equally, is dominated by how well you predict the middle of the
scale for heavy users, and says nothing about whether the ten items you actually show
are good. Rank instead: for each user, score every item not yet interacted with, take
the top k, and compute precision@k, recall@k and NDCG@k, which discounts hits by
log₂(position + 1) so a hit at rank 1 counts more than one at rank 10. Split by time,
not at random: a random split lets the model see a user's future when predicting her
past and inflates every metric. Always report the popularity baseline (the
most-interacted items the user has not seen); on MovieLens it is embarrassingly hard to
beat on precision@10, and a model that does not beat it has learned nothing about
individuals. Cold start, users and items with no interactions, is where factorisation
has nothing to say and content features or a bandit (Module 11) take over.

**word2vec is matrix factorisation, which makes "embedding" a single idea rather than
two.** Skip-gram with negative sampling trains a word vector and a context vector so
their dot product is high for observed (word, context) pairs and low for k randomly
sampled ones. Levy and Goldberg showed its optimum satisfies w · c = PMI(w, c) − log k:
it implicitly factorises the shifted pointwise mutual information matrix of word-context
co-occurrences. The lesson generalises. MovieLens item factors are item embeddings;
knowledge-graph nodes embedded by TransE or DistMult are factorising an adjacency
tensor; the token table in Module 9's GPT is trained by the same kind of contrastive
objective. When a paper says "embedding", ask what matrix is being factorised and under
what loss.

**Once you have embeddings, the operation you will run most is nearest-neighbour search,
and exact search stops scaling around a million vectors.** Brute force costs O(nd) per
query: fine for 3,706 MovieLens items and for 100,000 documents with a good BLAS, not
for 10⁸. FAISS's `IndexFlatL2` and `IndexFlatIP` are the exact baselines; `IndexIVFFlat`
clusters the vectors with k-means (Module 3's codebook) and searches only the `nprobe`
nearest cells, trading recall for a 10 to 100× speedup; `IndexHNSWFlat` builds a
hierarchical navigable small-world graph and walks it, giving high recall at millisecond
latency for a large memory footprint. Always measure recall@10 against the exact index
before trusting an approximate one; Module 10's retrieval-augmented generation is this
paragraph with sentence embeddings as the vectors.

**Forward links.** The linear autoencoder of Lab 4.1 becomes Module 7's nonlinear one
and then the VAE, which is PPCA with a neural decoder. The contrastive objective inside
word2vec is the ancestor of Module 8's SimCLR loss. The item embeddings and their
nearest-neighbour index are Module 10's RAG pipeline with movies instead of passages.
Knowledge-graph embeddings in KDG are factorisations of relation tensors, and the
popularity baseline and time split return in Module 11's bandit and Module 12's
experiments as the null models an intervention must beat.

## Reading

- Deisenroth, Faisal, Ong, *Mathematics for Machine Learning*, free, ch. 10 (PCA from
  four angles, including the latent-variable one). Do the derivations with a pen.
- Murphy, *Probabilistic Machine Learning: An Introduction*, free, ch. 20
  (dimensionality reduction: PCA, PPCA, factor analysis, autoencoders, manifold methods).
- Hastie, Tibshirani, Friedman, *ESL*, free, §14.5 (PCA, sparse PCA, kernel PCA) and
  §14.6 (non-negative matrix factorisation, archetypal analysis).
- van der Maaten and Hinton, "Visualizing Data using t-SNE", 2008. Read §2 and §3 for
  SNE, the crowding problem and the Student-t fix.
- McInnes, Healy, Melville, "UMAP: Uniform Manifold Approximation and Projection for
  Dimension Reduction", 2018. §3 (the computational view) is enough; §2 is optional
  category theory.
- Wattenberg, Viégas, Johnson, "How to Use t-SNE Effectively", *Distill*, 2016. Play
  with every interactive figure before Lab 4.2.
- Koren, Bell, Volinsky, "Matrix Factorization Techniques for Recommender Systems",
  *IEEE Computer*, 2009. Short and complete; the SGD and ALS in Lab 4.4 come from here.
- Hu, Koren, Volinsky, "Collaborative Filtering for Implicit Feedback Datasets", 2008.
  §4 has the confidence weighting and the fast ALS derivation you will implement.
- Levy and Goldberg, "Neural Word Embedding as Implicit Matrix Factorization", 2014.
- Lee and Seung, "Learning the parts of objects by non-negative matrix factorization",
  *Nature*, 1999.
- Johnson, Douze, Jégou, "Billion-scale similarity search with GPUs", 2017 (skim, for
  the IVF and PQ ideas).

## Labs

### Lab 4.1: PCA, whitening and the linear autoencoder

Goal: prove to yourself that three derivations and one network find the same subspace.

1. Write `04-embeddings/pca.py` with a `PCA(k, whiten=False)` class exposing `fit`,
   `transform` and `inverse_transform`, computed both by eigendecomposition of the
   covariance and by SVD of the centred data. On the 60,000 × 784 MNIST training matrix
   check both against `sklearn.decomposition.PCA(50)` up to sign.
2. Scree and cumulative variance plots; reconstructions at k = 2, 10, 50 and 200; report
   how many components reach 95% (roughly 150).
3. With `whiten=True`, verify the transformed covariance is the identity to 1e-6. Run
   your Module 3 k-means with k = 10 on 50 whitened and unwhitened components and
   compare ARI against the digit labels; whitening should hurt a little here, and you
   should be able to say why.
4. Train a linear autoencoder on MPS, 784 → 50 → 784 with no nonlinearity and MSE loss,
   Adam at 1e-3 for 20 epochs. Form the projection matrix onto its 50-dimensional encoder
   subspace and onto PCA's, and report the Frobenius norm of their difference (target
   below 0.05) and the principal angles via `scipy.linalg.subspace_angles`. The
   individual weight vectors will not match PCA's; the subspace will.
5. Fit PPCA from the eigenvalues (or by EM) and check σ² equals the mean of the
   discarded eigenvalues.

Done when: the sign-invariant test against scikit-learn and the whitened-covariance test
pass under pytest, and the autoencoder's projection matrix is within 0.05 of PCA's in
Frobenius norm with every principal angle under 5 degrees.

### Lab 4.2: Breaking t-SNE and UMAP

Goal: reproduce the failure modes so you never present one as a finding.

1. On 10,000 MNIST points (50 PCA components first, as the t-SNE paper recommends), run
   `TSNE` at perplexity 2, 5, 30 and 100 with a fixed seed and plot the four side by
   side coloured by digit. Then run perplexity 30 with three seeds.
2. Two Gaussians in 50 dimensions, 500 points each, standard deviations 1 and 10, well
   separated. t-SNE at perplexity 30 and measure the convex-hull area each cluster
   occupies; the ratio should be near 1 despite a variance ratio of 100.
3. 500 points of pure N(0, I) noise in 100 dimensions at perplexity 2, 5 and 30. Run
   HDBSCAN on the 2D output to count the "clusters" at perplexity 2.
4. Repeat steps 1 to 3 with `umap.UMAP` at `n_neighbors` 5, 15, 50 and 200 and
   `min_dist` 0.0 and 0.5. Time both methods on all 70,000 MNIST points and record the
   ratio. Use `UMAP.transform` on the 10,000 test digits and check they land on the
   right clusters.
5. Write the caveat paragraph you will attach to every 2D embedding in a report from now
   on: what it shows, what it does not, the settings and seed.

Done when: the notebook has the perplexity grid, the seed triptych, the equal-area
result with the measured ratio, the noise figure with an HDBSCAN count, the UMAP grid
with the timing ratio, and the caveat paragraph.

### Lab 4.3: NMF topics

Goal: a parts-based decomposition you can read.

1. Take the distinct product `Description` strings from Online Retail II (roughly 5,000
   after lower-casing and stripping), or `fetch_20newsgroups` if you want longer
   documents. TF-IDF with `min_df=5`, English stop words, unigrams and bigrams.
2. Fit `NMF(n_components=20, init="nndsvda", beta_loss="frobenius", max_iter=400)` and
   print the top ten words per component. Name each topic in two words or mark it junk.
3. Refit with `beta_loss="kullback-leibler", solver="mu"` and compare. Then fit
   `LatentDirichletAllocation(n_components=20)` on raw counts; note which method gives
   more nameable topics and how long each took.
4. Choose k: held-out reconstruction error for k ∈ {5, 10, 20, 40, 80} on a 20% split of
   documents, and a simple coherence (mean pairwise document co-occurrence of each
   topic's top ten words). Say which k you would ship.

Done when: the 20-topic top-words table is in the notebook with names, the NMF and LDA
comparison has timings, and the k choice is justified by both curves.

### Lab 4.4: MovieLens recommender (headline lab)

Goal: build the classic recommender stack from scratch and evaluate it the way it would
be judged in production.

Data: MovieLens ml-1m, 1,000,209 ratings from 6,040 users on 3,706 rated movies (ids
run to 3,952), 1 to 5 stars, timestamps from 2000 to 2003, every user with at least 20
ratings. Files are `::`-separated; `movies.dat` is latin-1 with pipe-separated genres.

1. Load into pandas and map user and movie ids to contiguous indices. Two splits: a
   random 80/20 for comparison with published numbers, and a time-based split holding
   out each user's most recent 20% of ratings, which is the honest one. Count the test
   movies absent from training under each.
2. Baselines: global mean (RMSE about 1.12), then user and item biases by alternating
   closed-form updates with λ = 5 (about 0.91 to 0.93 on the random split). Popularity
   baseline for ranking: the ten most-rated movies the user has not seen.
3. Implement `BiasedMF(k=50, lr=0.005, reg=0.02, epochs=25)` in `04-embeddings/mf.py`
   with SGD in NumPy, or in PyTorch with `nn.Embedding` and Adam. Sweep `reg` over
   {0.005, 0.02, 0.05, 0.1} and k over {10, 50, 100} on a validation fold; plot train and
   validation RMSE per epoch and watch the weakly regularised run overfit. Target
   roughly 0.86 to 0.88 on the random split at k = 50; expect a few hundredths worse on
   the time split, and say why.
4. Implement `ALS(k=50, reg=0.1, iters=15)` solving each user's and item's ridge problem
   in closed form; assert the training objective never increases and match the SGD RMSE
   within 0.01.
5. Binarise (rating ≥ 4 is an interaction) and implement Hu, Koren and Volinsky's
   weighted ALS with α = 40, k = 50, λ = 0.1 using the YᵀY trick; 15 sweeps in NumPy
   should run at under a minute per sweep on the Mac. Evaluate precision@10, recall@10
   and NDCG@10 on the time split, excluding training items from the candidates, against
   the popularity baseline and against a top-10 from ranking the explicit MF's predicted
   ratings. Implicit ALS should beat both; explicit MF ranked by predicted rating will
   struggle to beat popularity.
6. UMAP the item factors from the implicit model to 2D, colour by primary genre, and
   label a few well-known titles.
7. Cold start: report the ranking metrics separately for users with fewer than 30
   training ratings.

Done when: the tests in `04-embeddings/tests/` pass (ALS objective monotone, SGD within
0.01 RMSE of ALS, metric functions agreeing with hand-computed values on a five-user toy
example), RMSE is in range on the random split with the sweep figure showing overfitting
at low `reg`, the ranking table has all three metrics for popularity, explicit MF and
implicit ALS on the time split, and the genre-coloured UMAP is in the notebook with the
caveat from Lab 4.2.

### Lab 4.5: Random projections

Goal: see Johnson-Lindenstrauss work in practice with far fewer dimensions than the lemma
asks for.

1. Project 10,000 MNIST points from 784 to k ∈ {10, 50, 100, 300} with
   `GaussianRandomProjection` and with your own scaled Gaussian matrix; confirm they
   agree in distribution.
2. For 100,000 random pairs, histogram the ratio of projected to original distance at
   each k; report mean and standard deviation and compare the spread with the 1/√k
   prediction.
3. kNN classification (k = 5) on the projected training set against the 10,000 test
   digits at each k, alongside PCA to the same k. Expect roughly 90% at k = 50, climbing
   to within a point or two of the 784-dimensional accuracy by k = 300, with PCA ahead
   at every k.
4. Compute `johnson_lindenstrauss_min_dim(10000, eps=0.1)` and contrast it with what
   step 2 shows you actually needed for 10% distortion on most pairs.

Done when: the four distortion histograms and the kNN accuracy curve are in the
notebook, with one sentence on why PCA wins and when random projection would still be
the right choice.

## Problem set

1. Maximise wᵀΣw subject to ‖w‖ = 1 with a Lagrange multiplier and show the solution is
   the top eigenvector. Then show that for an orthonormal W (d × k) the reconstruction
   error ‖X − XWWᵀ‖²_F equals tr(Σ) − tr(WᵀΣW) up to a factor of n, so minimising it is
   the same problem.
2. A linear autoencoder x̂ = D E x with E (k × d) and D (d × k) minimises ‖X − X EᵀDᵀ‖²_F.
   Show any optimum has DE equal to the projection onto the top-k principal subspace
   (Baldi and Hornik, 1989), and explain why E's rows need not be the principal
   components themselves.
3. State the Johnson-Lindenstrauss lemma with the bound k ≥ 4 log n / (ε²/2 − ε³/3).
   Compute k for n = 10⁶ and ε = 0.1 and compare with
   `johnson_lindenstrauss_min_dim`. Then estimate empirically, for 10,000 MNIST points,
   the smallest k at which 99% of pairs are within 10%, and explain the gap.
4. Fix the item factors Q and derive the ALS update for one user's factors p_u under
   squared loss with L2 penalty λ, as a ridge regression on the items that user rated.
   State its cost and how it changes for the implicit-feedback loss where every item
   contributes.
5. Derive the SGD gradients for the biased MF objective with respect to μ, b_u, b_i, p_u
   and q_i for one observed rating, including the regularisation terms. Explain why μ is
   usually fixed at the global mean rather than learned.
6. Construct a user with five candidate items and true relevances such that model A has
   lower RMSE than model B on predicted ratings but a worse precision@2 and NDCG@2.
   Explain in one sentence why RMSE permits this.
7. Count the parameters of biased MF at 6,040 users, 3,706 items and k = 50, and the
   memory in float32. Compare with a dense 6,040 × 3,706 ratings matrix in float32 and
   as uint8, and compute the density of ml-1m. How many parameters per observed rating
   does the model spend?
8. In t-SNE each σᵢ is chosen so that the perplexity of pⱼ|ᵢ equals a constant. Show
   that scaling a cluster's coordinates by a factor c rescales its σᵢ by c and leaves
   every pⱼ|ᵢ within the cluster unchanged, so the low-dimensional layout cannot depend
   on the cluster's original spread. What does this imply about comparing cluster sizes
   in a plot?

## Deliverables

- `04-embeddings/pca.py`, `04-embeddings/mf.py` (`BiasedMF`, `ALS`, `ImplicitALS`) and
  `04-embeddings/metrics.py` (precision@k, recall@k, NDCG@k) with pytest tests in
  `04-embeddings/tests/`.
- `04-embeddings/movielens/` with the data preparation, the sweeps and the evaluation
  script, every run tracked in MLflow.
- Notebook with all five labs' figures, the topics table, the recommender comparison
  table and the Lab 4.2 caveat paragraph.
- Write-up on the recommender, following `writeup-template.md`. The Limitations section
  should engage with the fact that offline ranking metrics on logged ratings measure
  agreement with what people chose to rate, not what they would have enjoyed if shown
  (exposure bias), and with what a dataset from 2000 to 2003 can and cannot say about a
  system you would deploy now.

## Stretch

- Implement hierarchical Poisson factorisation (Gopalan, Hofman, Blei, 2015) on the
  binarised MovieLens counts and compare its ranking metrics with weighted ALS.
- Index the item factors with FAISS `IndexFlatIP`, `IndexIVFFlat` and `IndexHNSWFlat`;
  measure recall@10 against exact search and query latency for each. Then embed the
  movie titles with a sentence-transformer and compare the two neighbourhoods.
- Implement skip-gram with negative sampling on the TinyStories subset in PyTorch, build
  the shifted PMI matrix explicitly, take its SVD, and compare the two embeddings on
  nearest-neighbour agreement, which is Levy and Goldberg's experiment in miniature.
- Fit a mixture of probabilistic PCAs to MNIST by EM and compare its held-out
  log-likelihood with a GMM on 50 PCA components from Module 3.

## Next

Module 5 turns from representations to the craft of training the networks that produce
them. The linear autoencoder you trained here is the first network of the course whose
result you could verify against a closed form; from now on there is no closed form, and
the harness, the debugging checklist and the ablation table are what stand in for it.
