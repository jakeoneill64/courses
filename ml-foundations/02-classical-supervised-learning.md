# Module 2: Classical supervised learning

**Part I · 1 week · Needs: Module 1. Data: Adult, Bank Marketing, Telco Customer Churn, synthetic.**

## Why this module

Most business ML problems are a table with a label column, and most of them are won by a
well-evaluated gradient-boosted tree or, embarrassingly often, by logistic regression.
The Oxford Classical Machine Learning week covers this ground in five days, and its
assignment hands you a dataset and asks for a model, a justified choice of method and an
honest evaluation. What separates a good submission from an average one is rarely the
model. It is whether the cross-validation leaked, whether the metric matches the
decision, whether the probabilities mean anything, and whether the comparison to the
baseline carries an interval. This module is about that discipline as much as about the
models.

Structurally, this is where the statistical learning framework gets fixed: a loss, a
hypothesis class, empirical risk, and the gap between training and generalisation error.
Every later module is a special case with a different hypothesis class. Bagging and
boosting are Module 1's bias-variance decomposition turned into algorithms; calibration
is Module 1's claim that a loss is a likelihood, tested on real probabilities. Module 12
comes back to the churn model built here for SHAP and uplift, and Module 13 serves it.

## Skip test

Answer cold, in writing.

1. Define empirical risk and the generalisation gap. Why is the test set used exactly
   once, and what have you turned it into if you tune on it?
2. Name three ways a cross-validation estimate can be optimistic and how you would detect
   each from the pipeline code alone.
3. Write the ridge closed form. What does ridge do to the singular values of X, and what
   does standardising the features change about the solution?
4. Why does a random forest reduce variance, and what limits the reduction? Give the
   formula.
5. Gradient boosting with squared loss fits residuals. What does it fit for log loss? Why
   does a lower learning rate need more trees, and what does early stopping on a
   validation fold protect against?
6. A boosted model has ROC-AUC 0.86 and its predicted probabilities average 0.31 on a
   population with 12% positives. What is wrong, how do you fix it, and how would you
   show the fix worked?

If all six are easy, do Lab 2.5 only, and the write-up.

## Core ideas

**Learning is minimising empirical risk and hoping it tracks the true risk.** You pick a
hypothesis class H and a loss ℓ and choose f ∈ H to minimise the average loss on the
training set. The true risk is the expected loss on new data; the gap between the two is
what generalisation means, and it grows with the capacity of H and shrinks with n.
Everything you do to choose a model (features, hyperparameters, which of five
algorithms) is fitting to whatever data you chose it on. Hence three sets: train to fit,
validation to choose, test to report, and the test set is read once. Look at it twice
and it has become a validation set with an optimistic number attached. On a small
dataset cross-validation plays the validation role and the test set stays sealed until
the write-up.

**Cross-validation is only as honest as the pipeline inside it, and leakage is how it
lies.** k-fold CV fits k models each on k − 1 folds and scores the held-out fold;
stratified folds keep class proportions, grouped folds keep all rows of one customer
together, and time-series splits only train on the past. Leakage is any route by which a
held-out label reaches the model: a feature that is a consequence of the label (Bank
Marketing's `duration` is the length of a call whose outcome is the label),
preprocessing fitted on all rows before the split (a scaler, an imputer, a target
encoder), duplicate rows landing on both sides, feature selection on the full data.
`Pipeline` and `ColumnTransformer` exist so every fitted step lives inside the fold:
`cross_val_score(pipe, X, y, cv=StratifiedKFold(5, shuffle=True))` refits the scaler
five times, and that is the point. Read Kaufman et al. before you believe any number,
including your own.

**Linear and logistic regression are the baseline you have to beat, and the penalties
are Module 1's priors.** Ridge adds λ‖w‖² and has the closed form
w = (XᵀX + λI)⁻¹Xᵀy, which shrinks the component along the i-th singular direction by
σᵢ²/(σᵢ² + λ): the ill-conditioned directions are damped most. The lasso adds λ‖w‖₁ and
sets coefficients exactly to zero; elastic net mixes the two and behaves better with
correlated features. Neither penalty is invariant to feature scale, so a feature in pence
is penalised a hundred times harder than one in pounds; standardise inside the pipeline
(trees do not care). Logistic regression is the Bernoulli NLL with a linear logit; its
loss is convex (Problem 1), its coefficients are log-odds ratios a manager can read, and
on data with mostly additive effects it is very hard to beat, which is the lesson of Lab
2.5.

**k-nearest neighbours is the simplest model and the clearest demonstration of the
curse of dimensionality.** Predict by voting among the k closest training points; bias
falls and variance rises as k shrinks, and each query costs O(n) without an index. It
fails in high dimensions because distances concentrate: nearly all of a unit cube's
volume sits in a thin shell near its boundary, the nearest neighbour is almost as far as
the farthest, and "local" stops meaning anything (Module 3's Problem 6 makes you watch
it). The same fact is why tree ensembles, which split one feature at a time, beat
distance-based methods on wide tables, and why Module 4 reduces dimension before
searching.

**A decision tree is a greedy recursive partition, and it overfits by construction.**
CART chooses, at each node, the feature and threshold that most reduce an impurity (Gini
Σₖ pₖ(1 − pₖ) or entropy for classification, variance for regression), then recurses
until a stopping rule (`max_depth`, `min_samples_leaf`) or purity. The best split on a
numeric feature comes from sorting and scanning cumulative class counts, O(n log n) per
feature per node. Trees are invariant to monotone transforms, handle mixed types, ignore
irrelevant features and are readable when small. Grown to purity they memorise: a small
change in the data changes the first split and therefore the whole tree, which is high
variance in Module 1's sense, a weakness for one tree and the whole reason ensembles of
them work.

**Bagging and random forests average many high-variance trees, and correlation is what
limits the gain.** Bootstrap the rows, grow a deep tree on each, average. If each tree
has variance σ² and any pair has correlation ρ, the average of B trees has variance
ρσ² + (1 − ρ)σ²/B: the second term vanishes with B, the first does not. Random forests
attack ρ by considering a random subset of features at each split
(`max_features="sqrt"` for classification), decorrelating the trees at a small cost in
bias. Out-of-bag predictions give a free validation estimate. Forests are hard to
overfit with more trees and need little tuning; their failure is smooth functions and
extrapolation, which a piecewise-constant average cannot do.

**Gradient boosting is gradient descent in function space, and its hyperparameters are
step size, step shape and when to stop.** Start from a constant, then repeatedly fit a
small tree to the negative gradient of the loss with respect to the current predictions
(the residual for squared loss, y − p for log loss) and add it scaled by a learning rate
η. Lower η needs more trees and generalises better; tree size (`num_leaves` in LightGBM,
`max_depth` in XGBoost) sets how many interactions one step can express;
`min_child_samples` stops leaves fitting a handful of rows; row and column subsampling
borrow the forest's randomness; L2 on leaf values smooths them. The setting that matters
most is the number of trees, and the only honest way to choose it is early stopping on a
validation fold (`lightgbm.early_stopping(50)` as a callback). Boosting can overfit,
unlike bagging, because every tree is fitted to the errors of the last; Lab 2.3 shows
the curve turning up at η = 1.

**Support vector machines maximise the margin, and the kernel trick does it in a space
you never construct.** The SVM finds the separating hyperplane with the largest margin,
softened by a penalty C on violations; the solution depends only on the points at or
inside the margin. Because the dual sees inputs only through inner products, replacing
xᵢᵀxⱼ with a kernel k(xᵢ, xⱼ) gives a nonlinear boundary in the original space; the RBF
kernel corresponds to an infinite-dimensional feature map. SVMs scale poorly (the kernel
matrix is O(n²) memory) and `SVC` outputs are distances, not probabilities. CML covers
them properly; on this module's data a tuned SVM roughly matches logistic regression and
loses to LightGBM.

**A model's probabilities are only useful if they are calibrated, and most models' are
not.** A calibrated model's predictions of 0.7 come true 70% of the time. Logistic
regression is roughly calibrated because it minimises a proper scoring rule directly;
boosted trees and forests push scores towards the middle, SVMs have no probabilities,
and class weighting or resampling shifts the base rate. Check with a reliability diagram
(`calibration_curve`: predicted probability binned against observed frequency) and score
with Brier or log loss, which reward calibration as well as discrimination; ROC-AUC
cannot see it. Fix with Platt scaling (a logistic regression on the scores) or isotonic
regression (a monotone step function, more flexible, needs more data), fitted on data
the model did not train on, which `CalibratedClassifierCV(estimator, method="isotonic",
cv=5)` arranges. Reproduce Niculescu-Mizil and Caruana's figures in Lab 2.4.

**Every metric is a decision rule in disguise, and you should be able to say whose
decision.** Accuracy is meaningless at 12% prevalence, where always-no scores 0.88.
Precision is the fraction of the people you contacted who were worth contacting; recall
is the fraction of those worth contacting that you reached; F1 assumes the two errors
cost the same, which they never do. ROC-AUC is the probability that a random positive
outranks a random negative; it is insensitive to prevalence, a virtue for comparing
models and a vice for describing a rare-event system, since at 1% prevalence an AUC of
0.9 can coexist with precision under 10%. The precision-recall curve and its area
(`average_precision_score`) track what an operator sees at each threshold and are the
right summary under imbalance (Problem 5). Log loss and Brier judge probabilities, not
rankings. Report the two or three that match the decision and say which decision.

**The threshold comes from the cost matrix, not from 0.5, and class imbalance is mostly a
threshold problem.** With cost C_FP for a false positive and C_FN for a false negative,
predicting positive at probability p costs (1 − p)C_FP in expectation and predicting
negative costs pC_FN, so predict positive when p > C_FP/(C_FP + C_FN). If a missed
churner costs ten times an unnecessary offer, the threshold is 0.09. That is the whole
of cost-sensitive classification for a calibrated model, and it makes most resampling
unnecessary: oversampling, or SMOTE's synthetic interpolations, distorts the
probabilities you then have to recalibrate, and evidence that either helps a tuned
boosted model is thin. Prefer `class_weight` or `scale_pos_weight`, then choose the
threshold from costs, or from expected value per customer when the value varies (Lab
2.5).

**Categorical features have three treatments, and one of them leaks.** One-hot encoding
is safe, linear-model friendly and explodes on high cardinality. LightGBM and XGBoost
accept pandas `category` columns natively and find groupings of levels at each split,
usually a little better than one-hot for trees. Target encoding replaces each level with
the mean label for that level, powerful for high-cardinality columns and a direct leak
of the label into the feature unless computed out-of-fold;
`sklearn.preprocessing.TargetEncoder` does the cross-fitting, and Problem 6 shows what
happens if you do not. Ordinal encoding of an unordered categorical imposes a fake order
that trees can work around and linear models cannot.

**Search hyperparameters randomly, prune early, and compare models with paired
differences and intervals.** Random search beats grid because most hyperparameters do
not matter and grid spends its budget on them; Optuna's TPE sampler does a little better
still, and pruning kills trials already losing at fold two of five. Fifty to a hundred
trials is usually enough for a boosted tree. Then compare honestly: a single CV mean
hides its variance, so use repeated stratified CV (5 × 5 gives 25 numbers), take the
difference between two models on each shared fold (paired, so the variance is far
smaller), and report the mean difference with a t-based interval. Bengio and Grandvalet
show that overlapping training folds leave no unbiased variance estimator, so treat the
interval as slightly too narrow. A model 0.003 AUC better with an interval crossing zero
is not better, and saying so in a write-up is worth more than the 0.003.

**Forward links.** The Telco churn model returns in Module 12 for SHAP and uplift and in
Module 13 as the thing you serve and monitor. Boosted trees are the baseline every deep
model in Modules 5 to 10 must beat on tabular data, and mostly does not. Calibration
reappears for networks in Module 5 and for LLM confidence in Module 10. The leakage
discipline is the one Module 8 needs for fraud and Module 12 for experiments.

## Reading

- James, Witten, Hastie, Tibshirani, Taylor, *An Introduction to Statistical Learning
  with Applications in Python*, free. ch. 2 (statistical learning), 4 (classification),
  5 (resampling), 6 (regularisation) and 8 (trees, forests, boosting). Run the labs.
- Hastie, Tibshirani, Friedman, *The Elements of Statistical Learning*, free. ch. 9
  (trees), ch. 10 (boosting, especially §10.10 on gradient boosting) and ch. 15 (random
  forests, especially §15.4 on the variance formula).
- Murphy, *Probabilistic Machine Learning: An Introduction*, free. ch. 4 (including the
  bias-variance tradeoff), ch. 10 (logistic regression) and ch. 18 (trees, forests,
  boosting).
- Chen and Guestrin, "XGBoost: A Scalable Tree Boosting System", 2016, §2 for the
  regularised objective and second-order approximation.
- Ke et al., "LightGBM: A Highly Efficient Gradient Boosting Decision Tree", 2017, for
  histogram splits and leaf-wise growth.
- Niculescu-Mizil and Caruana, "Predicting Good Probabilities with Supervised Learning",
  2005. Reproduce its reliability diagrams in Lab 2.4.
- Kaufman, Rosset, Perlich, Stitelman, "Leakage in Data Mining: Formulation, Detection,
  and Avoidance", 2012.
- Bengio and Grandvalet, "No Unbiased Estimator of the Variance of K-Fold
  Cross-Validation", 2004, for why CV intervals are too narrow.
- scikit-learn user guide: §3.1 cross-validation, §6.1 pipelines and composite
  estimators, §1.16 probability calibration.

## Labs

### Lab 2.1: Logistic regression from an empty file

Goal: own the loss, the gradient and scikit-learn's regularisation convention.

1. Load Adult (`fetch_openml("adult", version=2)`; 48,842 rows, 14 features, about 24%
   earning over 50K). Build a `ColumnTransformer` that one-hot encodes categoricals with
   `handle_unknown="ignore"` and standardises numerics; fit it on an 80% training split
   only.
2. Implement `LogisticRegressionGD(l2, lr, n_iter)` in `02-tabular/logreg.py` with
   `fit`, `predict_proba` and `decision_function`: stable log-sigmoid via logsumexp,
   mean NLL plus (λ/2)‖w‖² with the intercept unpenalised, full-batch gradient descent.
   Add a Newton solver using the Hessian from Problem 1; it converges in under ten
   iterations.
3. Match `LogisticRegression(C=1.0, solver="lbfgs", tol=1e-8, max_iter=1000)`.
   scikit-learn minimises C Σᵢ NLLᵢ + ½‖w‖², so λ = 1/(C n) in your mean-loss convention.
   Assert max absolute coefficient difference below 1e-3 and predicted probabilities
   equal to 1e-4.
4. Plot training NLL against iteration for learning rates 0.01, 0.1, 1.0 and 10, and
   report the condition number of XᵀX before and after standardisation.

Done when: the coefficient test passes under pytest, the Newton solver reaches the same
optimum in under ten iterations, and the learning-rate figure shows one divergence.

### Lab 2.2: CART and bagging from scratch

Goal: build the tree, see it overfit, and see averaging fix it.

1. Implement `DecisionTreeGini(max_depth, min_samples_leaf)` in `02-tabular/tree.py`:
   for each feature, sort, scan cumulative class counts, take the split with the largest
   Gini decrease; recurse; predict class proportions at leaves. Vectorise the scan;
   never loop over thresholds in Python.
2. On the one-hot Adult matrix from Lab 2.1 at `max_depth=8`, match
   `sklearn.tree.DecisionTreeClassifier` test accuracy within 0.5 percentage points
   (ties break differently, so exact agreement is not expected). Time both.
3. Grow to purity and plot train and test accuracy against depth 1 to 25; mark where
   they diverge.
4. Implement `bag(make_estimator, B=100)`: bootstrap rows, fit, average `predict_proba`.
   Compare test ROC-AUC and log loss of one deep tree, your bag of 100,
   `RandomForestClassifier(100, max_features=None)` and then `max_features="sqrt"`. The
   last should win by a small margin; explain the gap with the correlation formula.

Done when: the accuracy test passes under pytest, the depth figure is in the notebook,
and the four-model table has AUC with bootstrap intervals from Module 1.

### Lab 2.3: Bias and variance of ensembles

Goal: watch bagging and boosting move different terms.

1. Use `make_friedman1(n_samples=500, noise=1.0)` with 50 resampled training sets and a
   fixed test set of 2,000. Fit `RandomForestRegressor` with 1 to 500 trees, and
   `LGBMRegressor(max_depth=3, num_leaves=8, subsample=1.0)` at learning rates 0.01, 0.1
   and 1.0 with 1 to 1,000 trees, recording test MSE after every tree.
2. Plot test MSE against number of trees for the four configurations on one axis, and
   the bias-variance decomposition from the 50 resamples (as in Lab 1.4) in a second
   panel.
3. Repeat boosting with `subsample=0.5, subsample_freq=1` and overlay.

Done when: the forest's curve flattens without turning up, boosting at η = 1.0 turns up
and at 0.01 has not converged by 1,000 trees, and the decomposition panel shows the
forest cutting variance while boosting cuts bias.

### Lab 2.4: Metrics and calibration

Goal: learn what each metric shows and hides on an imbalanced problem, and fix the
probabilities.

1. Load Bank Marketing (45,211 rows, 11.7% subscribed). Drop `duration` and write down
   why. Stratified 80/20 split.
2. Fit logistic regression, `RandomForestClassifier(500)` and a default
   `LGBMClassifier`, each in a pipeline. For each draw the ROC and PR curves side by
   side and report ROC-AUC, average precision, log loss and Brier score.
3. Reliability diagrams with ten bins for all three, before and after
   `CalibratedClassifierCV(method="isotonic", cv=5)` and `method="sigmoid"`. Report
   Brier before and after; the forest should improve most and logistic least.
4. Costs: a call costs £5, a missed subscriber forgoes £50. Plot expected cost against
   threshold for the calibrated LightGBM, mark the minimum, and compare with the
   closed-form C_FP/(C_FP + C_FN) = 0.09. Repeat with the uncalibrated model and show
   the closed-form threshold is now in the wrong place.
5. Downsample positives to 1% prevalence and refit; show ROC-AUC barely moves while
   average precision collapses.

Done when: the notebook has the ROC and PR pair, six reliability diagrams with Brier
scores, the cost curve with both thresholds marked, and the 1% experiment, each with one
sentence of interpretation.

### Lab 2.5: Churn (headline lab)

Goal: a churn model with an honest evaluation and a business decision attached.

Data: IBM's Telco Customer Churn sample, 7,043 customers, 21 columns, 26.5% churn (1,869
customers). One row per customer: demographics, services subscribed, `Contract`,
`tenure`, `MonthlyCharges`, `TotalCharges`, and the `Churn` label.

1. Leakage hunt. `TotalCharges` is an object column with 11 blank strings, all for
   customers with `tenure=0`; decide (drop or set to zero) and record it. Check for
   duplicate `customerID`s. Ask of every column whether it would be known at prediction
   time. Cast Yes/No columns to booleans and the rest to `category`.
2. One stratified 80/20 split; the 20% is sealed. Everything below is 5-fold stratified
   CV on the 80%, tracked in MLflow.
3. Baselines: majority class, and logistic regression with one-hot and standardisation
   in a `Pipeline`. Expect ROC-AUC roughly 0.84 to 0.85.
4. LightGBM tuned with Optuna: `num_leaves` 4 to 64, `learning_rate` 0.005 to 0.2 (log),
   `min_child_samples` 5 to 100, `feature_fraction` and `bagging_fraction` 0.5 to 1.0,
   `lambda_l2` 1e-3 to 10 (log), `n_estimators=2000` with `early_stopping(50)` on the
   fold's validation part. Report each fold's AUC with `trial.report` and call
   `trial.should_prune()` so `MedianPruner` can stop losing trials. 60 trials. Expect
   roughly 0.84 to 0.86 and a gain over logistic of a point at most; write down before
   you run why (7,000 rows, mostly categorical features with near-additive effects,
   little numeric structure for trees to exploit).
5. Calibrate the best model with isotonic regression on out-of-fold predictions;
   reliability diagram before and after.
6. Decision. A retention offer costs £20, succeeds on 30% of the churners it reaches,
   and a saved customer is worth twelve months of `MonthlyCharges`. The expected value
   of targeting customer i is 0.3 pᵢ · 12 mᵢ − 20; target when positive. Show the
   implied threshold on pᵢ varies with mᵢ, and compare total expected value against
   targeting the top 20% by pᵢ alone and against no campaign.
7. Comparison table: logistic, random forest, tuned LightGBM, calibrated LightGBM;
   ROC-AUC, average precision, log loss, Brier; 5 × 5 repeated stratified CV; paired
   difference from logistic with a 95% interval. Then score the sealed test set once.

Done when: the leakage notes list every rule with row counts, the table has intervals
and the paired-difference column, the calibrated model's Brier is below the
uncalibrated, the expected-value analysis names the campaign size and its value, and the
sealed test set was scored exactly once.

## Problem set

1. Write the logistic loss for one example as a function of the logit z = wᵀx. Derive
   its gradient σ(z) − y and Hessian σ(z)(1 − σ(z))xxᵀ, show the Hessian is PSD, and
   conclude the loss is convex in w. Why does adding (λ/2)‖w‖² make it strictly convex?
2. Derive the ridge closed form w = (XᵀX + λI)⁻¹Xᵀy by setting the gradient to zero.
   Substitute the SVD X = UΣVᵀ and show the prediction is Σᵢ uᵢ (σᵢ²/(σᵢ² + λ)) uᵢᵀy.
   Which directions does ridge shrink most, and why does that help when XᵀX is
   ill-conditioned?
3. Let f̂₁, ..., f̂_B have variance σ² and pairwise correlation ρ. Show
   Var((1/B) Σ f̂_b) = ρσ² + (1 − ρ)σ²/B. What does this say about adding trees to a
   forest, and how does `max_features` enter?
4. For squared loss, show the negative gradient of Σ(yᵢ − F(xᵢ))²/2 with respect to
   F(xᵢ) is the residual. For log loss with F the logit, show it is yᵢ − σ(F(xᵢ)). Write
   one round of gradient boosting for each and say what a leaf value should be under
   Newton boosting (the XGBoost objective).
5. A classifier has recall 0.8 at a false positive rate of 0.1. Compute its precision at
   prevalence 50% and at 1%. Sketch the ROC and PR curves in each case and explain why
   ROC-AUC is unchanged while PR-AUC collapses.
6. A binary label has 100 rows in level A of a categorical feature, 60 positive. Target
   encoding on the full data gives A the value 0.6. Compute the encoded value a row in A
   would receive under 5-fold out-of-fold encoding and its expected leakage. Then
   construct a feature with 1,000 levels of one row each and show full-data target
   encoding gives a perfect training-set classifier.
7. Write expected cost as a function of threshold t for a calibrated model with score
   density f(p), costs C_FP and C_FN, and prevalence π. Differentiate and show the
   minimiser is t* = C_FP/(C_FP + C_FN), independent of f and π. Then let the value of a
   true positive vary by customer and derive the per-customer rule used in Lab 2.5.
8. With n rows and k folds, each model trains on n(k − 1)/k rows. Explain why the
   k-fold estimate is pessimistically biased for small k and why its variance rises as k
   approaches n. Simulate: for n = 500 with logistic regression on a synthetic problem,
   estimate bias and variance of the CV accuracy for k ∈ {2, 5, 10, n} against the true
   test accuracy over 200 repeats.

## Deliverables

- `02-tabular/logreg.py` and `02-tabular/tree.py` with pytest tests against
  scikit-learn.
- `02-tabular/churn/` with `prepare.py`, `train.py` and `evaluate.py`, every model as an
  MLflow run, and the comparison table generated by code rather than typed.
- Notebook with all five labs' figures and the Lab 2.4 and 2.5 tables.
- Write-up on the churn model, following `writeup-template.md`. The Limitations section
  should engage with the fact that the data is a single undated snapshot, so nothing
  here tests how the model behaves as the customer base drifts, and with how sensitive
  the campaign recommendation is to the three assumed cost parameters.

## Stretch

- Replicate one row of Grinsztajn, Oyallon, Varoquaux, "Why do tree-based models still
  outperform deep learning on typical tabular data?", 2022: a tuned MLP against LightGBM
  on Adult, same CV, same budget.
- Add `monotone_constraints` to the churn LightGBM for `tenure` and `Contract` length,
  and measure what the constraint costs in AUC and buys in plausibility.
- Implement split conformal prediction on top of the calibrated churn model and check
  its coverage on the sealed test set.
- Read Chen and Guestrin §2.2 and implement Newton boosting leaf values in a 50-line
  boosted-stumps regressor; compare with first-order boosting on Friedman 1.

## Next

Module 3 removes the label column. The evaluation discipline carries over unchanged, but
without a metric to cross-validate you will have to argue from stability and
predictive validity instead, and the churn features you cleaned here become the
starting point for asking whether customers form groups at all.
