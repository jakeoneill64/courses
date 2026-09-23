# Module 12: Experimentation, causality and interpretability

**Part IV · 1 week · Needs: Module 2. Data: Hillstrom email marketing, Telco Customer Churn, Adult, the Lalonde/NSW job-training data (small, fetched in Lab 12.2), synthetic.**

## Why this module

Prediction answers one question: what will happen. A business asks three more that
prediction alone cannot answer: did the change work, who should we target, and why did
the model say that. The Module 2 churn model tells you who is likely to leave; it does
not tell you who would stay if you called them, whether the retention offer you launched
actually worked, or what a regulator should make of contract type driving the score.
Those are the questions of Saïd's Augmenting Business Decisions with AI, whose subject is
how a model's output becomes a decision, and of AI Governance, which wants explanations
and fairness audits that survive scrutiny. This module is aimed squarely at both.

The common thread is that a correlation a model found is not the effect of an
intervention. Randomisation is the one place you get the causal answer for free, and the
first third of the module is about running and reading experiments without fooling
yourself. The second third approximates randomisation when you cannot have it, and turns
that machinery towards the targeting question with uplift models. The last third explains
models and separates "the model uses this" from "this causes that", because explanations
and fairness audits are read by people who will conflate the two unless you stop them.

Structurally, the disaggregated metrics and fairness statement produced here go into the
model card in Module 13, and Module 14 requires a decision component, which is the uplift
analysis of Lab 12.3 on the capstone's data.

## Skip test

Answer cold, in writing.

1. Baseline conversion is 3% and you want to detect a 0.3 percentage-point lift at 80%
   power and 5% two-sided significance. Write the sample-size formula and evaluate it.
2. A product manager checks the dashboard daily and stops the test when p < 0.05. What is
   the false-positive rate over 30 days, roughly, and why?
3. Draw a DAG with a confounder and one with a collider. Which variable do you condition
   on in each, and what happens if you get it backwards?
4. Define ATE, CATE and uplift. Why does a model of propensity to convert select the wrong
   customers for a campaign?
5. State the Shapley axioms. Why does permutation importance mislead when two features
   are correlated, and what does impurity importance do instead?
6. Define demographic parity, equalised odds and calibration by group. Which pairs can
   hold simultaneously when base rates differ?

If all six are easy, do Labs 12.3 and 12.5 only, and the write-up.

## Core ideas

**Randomisation is the gold standard because it makes treatment independent of
everything else.** Each unit has two potential outcomes, Y(1) and Y(0), and you observe
one; the average treatment effect E[Y(1) − Y(0)] is not observable for anyone. A random
coin makes the treated and control groups exchangeable, so the difference in observed
means is an unbiased estimate of it. Everything else in this module is either reading
that difference correctly or approximating the coin when you were not allowed to flip it.

**A test is designed before it runs.** Fix the metric, the minimum detectable effect, the
significance level and the power, and the sample size follows: for a conversion rate,
n per arm ≈ (z_{α/2} + z_β)² · 2p̄(1 − p̄) / δ², about 53,000 per arm for a 3% baseline and
a 0.3-point lift at 80% power. Real online effects are 1 to 2% relative, so most tests
that "showed nothing" were never powered to see anything, and the ones that showed a
large effect were selected for luck, which is the winner's curse. Write the design down
before the first user is assigned.

**Peeking inflates the false-positive rate, and daily peeking roughly quintuples it.**
The test statistic on cumulative data is a random walk, and the probability that it
crosses ±1.96 at least once in 30 looks is around 25 to 30%, not 5%. The fixes are a
fixed horizon you do not touch, alpha-spending boundaries (O'Brien-Fleming, or the crude
Bonferroni α/k), or always-valid sequential tests such as the mixture sequential
probability ratio test (Johari et al.), which pay for the freedom to stop early with
lower power at any fixed n. Lab 12.1 shows you the 25% and then makes it go away.

**Variance is the enemy, and there are honest ways to reduce it.** CUPED (Deng et al.)
regresses the metric on a pre-experiment covariate, typically the same metric last
month, and analyses the residual, cutting variance by a factor of 1 − ρ²; with ρ = 0.5
that is 25% fewer users for the same power. Ratio metrics such as revenue per session are
not means over independent units when the randomisation unit is the user, and the delta
method gives the right variance: Var(Ȳ/X̄) ≈ (1/μ_X²)[Var(Y) − 2(μ_Y/μ_X)Cov(X, Y) +
(μ_Y²/μ_X²)Var(X)]/n. Before any of this, check the sample ratio with a chi-square test
on arm counts; if it fails, the assignment is broken and the result is void.

**Most experiment failures are organisational, not statistical.** Novelty effects fade
and primacy effects grow, so a one-week test on a UI change measures curiosity.
Guardrail metrics (latency, errors, unsubscribes) must be pre-registered so a win on the
overall evaluation criterion cannot hide harm. Segment fishing after the fact, testing
twenty subgroups and reporting the one at p < 0.05, is the multiple-comparisons problem
in a business suit. Kohavi's rule: most ideas fail, and an organisation that cannot bear
that will quietly stop running real tests.

**Without randomisation you need a causal model, and a DAG is how you write one down.**
A confounder X that causes both treatment T and outcome Y mixes its effect into the
observed association; the backdoor criterion says conditioning on a set that blocks every
path from T to Y entering T through an arrow identifies the effect. A collider is caused
by both T and Y; conditioning on it opens a closed path and manufactures association from
nothing, as when you analyse only customers who complained. Identification (is the effect
a function of the observed distribution at all) is a question about the graph; estimation
comes afterwards, and no estimator rescues a wrong graph.

**The estimators are one idea with different failure modes.** Regression adjustment fits
Y on T and X and reads off the coefficient, and is wrong if the functional form is.
Propensity methods fit e(X) = P(T = 1 | X) and weight units by 1/e(X) (controls by
1/(1 − e(X))) or match treated units to similar controls; they are wrong if the propensity
model is, and unstable when propensities near 0 or 1 give huge weights, which is why you
trim. The doubly robust (AIPW) estimator combines both and is consistent if either model
is right. Difference-in-differences removes fixed group differences with a pre-period and
needs parallel trends; instrumental variables need a variable that moves T but not Y
directly; regression discontinuity compares units just either side of a threshold rule.
Each rests on an assumption the data cannot test.

**Uplift is the difference between who will buy and who will buy because you acted.**
Sort customers by (buys untreated, buys treated): sure things buy regardless, lost causes
never do, persuadables buy only if treated, sleeping dogs buy only if left alone. A
propensity model ranks sure things top; an uplift model ranks persuadables top, and they
are different people. The target is CATE(x) = E[Y(1) − Y(0) | X = x]. The S-learner fits
one model with T as a feature and tends to shrink the effect away; the T-learner fits a
model per arm and differences them, adding two models' noise; the X-learner (Künzel et
al.) imputes each unit's counterfactual from the other arm's model and wins when arms are
unbalanced; causal forests (Athey and Wager) split on effect heterogeneity with honest
sample splitting. Evaluate with the Qini curve, cumulative incremental conversions
against fraction targeted, sorted by predicted uplift, against the diagonal. All of it
needs a randomised or well-identified treatment; uplift on observational campaign data
recovers the old targeting rule, not the effect.

**An explanation answers a specific question, and global and local are different
questions.** Global: which features does the model use across the population. Local: why
this prediction for this customer. Impurity importance, the default in tree libraries,
sums the loss reduction at each feature's splits and is inflated by high-cardinality and
continuous features. Permutation importance shuffles a feature and measures the loss
increase, which is honest about reliance but falls to zero for a feature whose correlated
twin can stand in for it, so two near-duplicates both look useless. Partial dependence
averages the prediction as one feature varies; ICE curves draw it per individual and
reveal the interactions the average hides.

**SHAP gives local attributions with an axiomatic guarantee, and TreeSHAP makes them
exact for trees.** The Shapley value is the unique attribution satisfying efficiency
(attributions sum to prediction minus baseline), symmetry, dummy and additivity, a
weighted average of a feature's marginal contribution over all 2^d coalitions. KernelSHAP
samples coalitions; TreeSHAP (Lundberg et al.) uses the tree structure to compute exact
values in O(TLD²), which is why it is instant on your LightGBM. A SHAP value explains the
model's function, not the world: if the model uses tenure because tenure proxies for
contract type, SHAP faithfully credits tenure. LIME fits a local linear surrogate and is
a cheaper, less stable answer to the same question; counterfactual explanations ("you
would have been approved with £2,000 more income") are what a customer actually wants.
Rudin's argument is that high-stakes decisions should use an inherently interpretable
model, sparse linear or rule-based, because the accuracy gap on tabular data is usually
small and an explanation of a black box is itself a model that can be wrong.

**Fairness has several definitions, and they cannot all hold at once.** A protected
attribute is rarely a feature, but proxies (postcode, relationship status, name) carry
it. Demographic parity asks that the selection rate P(Ŷ = 1 | A) be equal across groups;
equalised odds (Hardt, Price, Srebro) asks that TPR and FPR be equal; calibration within
groups asks that a score of 0.7 mean 70% in every group. With unequal base rates an
imperfect classifier cannot satisfy demographic parity and equalised odds together
(Problem 8), and Chouldechova shows calibration and equal error rates conflict likewise.
Reweighing the training data or setting group-specific thresholds buys one metric at the
price of another and of accuracy; which to buy is a policy decision. A governance
committee needs the rates by group before and after, the metric you chose and why, what
it cost, and what you did not measure.

**Forward links.** Module 13 puts the disaggregated metrics and the fairness statement
into the model card, treats drift as a change in the population you calibrated on, and
maps high-risk uses onto the EU AI Act's obligations for data governance and human
oversight. Module 14 requires a decision component: an uplift-style targeting analysis
with a stated cost and margin, which is Lab 12.3 on the capstone's data.

## Reading

- Kohavi, Tang, Xu, *Trustworthy Online Controlled Experiments*, ch. 1-3, 17-19 and 22.
- Facure, *Causal Inference for the Brave and True* (free), ch. 1-12 (potential outcomes
  through doubly robust estimation) and 20-22 (heterogeneous effects and uplift).
- Hernán and Robins, *Causal Inference: What If* (free), ch. 1-3 and 12-13 (IP weighting
  and standardisation).
- Molnar, *Interpretable Machine Learning* (free), the chapters on permutation feature
  importance, PDP and ICE, Shapley values and SHAP.
- Barocas, Hardt, Narayanan, *Fairness and Machine Learning* (free), ch. 2-3.
- Deng, Xu, Kohavi, Walker, "Improving the Sensitivity of Online Controlled Experiments
  by Utilizing Pre-Experiment Data", 2013 (CUPED); Johari, Koomen, Pekelis, Walsh,
  "Peeking at A/B Tests", 2017.
- Künzel, Sekhon, Bickel, Yu, "Metalearners for estimating heterogeneous treatment
  effects using machine learning", 2019; Athey and Wager, "Estimating Treatment Effects
  with Causal Forests: An Application", 2019; Radcliffe and Surry, "Real-World Uplift
  Modelling with Significance-Based Uplift Trees", 2011.
- Lundberg and Lee, "A Unified Approach to Interpreting Model Predictions", 2017;
  Lundberg et al., "From local explanations to global understanding with explainable AI
  for trees", 2020 (TreeSHAP); Rudin, "Stop explaining black box machine learning models
  for high stakes decisions and use interpretable models instead", 2019.
- Hardt, Price, Srebro, "Equality of Opportunity in Supervised Learning", 2016;
  Chouldechova, "Fair prediction with disparate impact", 2017.
- Hillstrom, "The MineThatData E-Mail Analytics And Data Mining Challenge", 2008, for the
  dataset description and the published arm-level results you will reproduce.

## Labs

Run `uv sync --group causal` first.

### Lab 12.1: A/B testing by simulation

Goal: own the arithmetic well enough to know when a dashboard is lying.

1. `ab/power.py`: `sample_size(p_base, mde, alpha=0.05, power=0.8)` and `power(n, p_base,
   mde)`. Check by simulation: 2,000 tests at the computed n with the effect present, and
   a rejection fraction within 0.02 of 0.80. Cross-check with
   `statsmodels.stats.power.NormalIndPower`.
2. `ab/peeking.py`: 1,000 A/A tests, 1,000 users per arm per day for 30 days at 5%
   conversion, a z-test on cumulative data each day. Report the fraction ever below
   p = 0.05; expect roughly 25 to 30%. Histogram of the first-crossing day.
3. `ab/sequential.py`: mSPRT for a difference in proportions with a normal mixing prior
   (τ set from the MDE), or O'Brien-Fleming alpha spending over 30 looks. Rerun step 2 and
   show the ever-cross rate at or under 5%; add a true 10% relative lift and report power
   at day 30 against the fixed-horizon test.
4. `ab/cuped.py`: a pre-period covariate with correlation ρ to the outcome;
   θ = Cov(Y, X)/Var(X) and Y_adj = Y − θ(X − X̄). Variance reduction over 1,000 replicates
   at ρ = 0.5 and 0.7 (expect about 25% and 50%) with the estimate still unbiased.
5. `ab/delta.py`: users with Poisson session counts and lognormal revenue; revenue per
   session per arm; the naive interval treating sessions as independent against the delta
   method over users and a user-level bootstrap. Coverage over 1,000 replicates: naive well
   below 95%, the other two close to it.

Done when: pytest asserts `sample_size(0.03, 0.003)` lies in [52,000, 55,000], simulated
power is within 0.02 of 0.8, the peeking rate is in [0.20, 0.35], the sequential rate is
at most 0.06 and delta coverage is in [0.93, 0.97]; the four figures are in the notebook.

### Lab 12.2: Causal estimators on a known DAG, then on Lalonde

Goal: see which estimators recover a known effect, and how a collider ruins them.

1. `estimators.py`: simulate n = 5,000 with X ~ N(0, 1), T ~ Bernoulli(σ(0.8X)),
   Y = 2.0T + 1.5X + ε, so the ATE is 2.0. A second version adds a collider C = T + Y + ε
   and a mediator M on a path T → M → Y.
2. `naive_diff`, `regression_adjust`, `ipw` (logistic propensity, Hájek-normalised
   weights, propensities clipped to [0.02, 0.98]) and `aipw`. Over 500 replicates, bias
   and standard deviation of each; everything but naive within 0.1 of 2.0.
3. Add C to the adjustment set: every estimator biased. Add M: the estimate shrinks to the
   direct effect. Add a quadratic term to the treatment equation and omit it from the
   propensity model: IPW fails, AIPW with a correct outcome model survives.
4. Lalonde: `dowhy.datasets.lalonde_dataset()` gives the 445-row NSW experimental sample,
   whose benchmark is the difference in 1978 earnings between 185 treated and 260
   controls, about $1,800. Replace the controls with the CPS comparison sample (about
   16,000 rows, from Dehejia's data page); the naive difference is about −$8,500. Run
   regression adjustment, clipped IPW, propensity matching and AIPW with bootstrap CIs,
   report which land within $1,000 of the benchmark, and run dowhy's placebo-treatment
   and random-common-cause refuters on the best.

Done when: the bias and SD table for four estimators × three adjustment sets is in the
notebook with a pytest test asserting the correct-set estimators are within 0.1 over 200
replicates; the Lalonde table with CIs is there; a paragraph explains why the CPS
comparison is hard (positivity: most CPS controls look nothing like NSW participants).

### Lab 12.3: Hillstrom email uplift (headline lab)

Goal: a targeting decision with a stated cost and margin, and proof it beats the
obvious alternative.

Data: `data/hillstrom/hillstrom.csv`, 64,000 customers randomised in thirds to a men's
merchandise email, a women's merchandise email, or no email. Features: recency (months),
history_segment and history (past-year spend), mens and womens (bought in category),
zip_code, newbie, channel. Outcomes over the following two weeks: visit, conversion,
spend.

1. Check the randomisation: arm shares with a chi-square sample-ratio test, and covariate
   balance with standardised mean differences under 0.05 for every feature and arm pair.
2. ATE of each email on visit and conversion as differences in proportions with Wald CIs,
   and on spend with a bootstrap. Expect visit rates near 10.6% (no email), 18.3% (men's)
   and 15.1% (women's), conversion near 0.6%, 1.25% and 0.9%: uplifts of roughly 7.7 and
   4.5 points on visit.
3. CATE for men's email against no email on visit, 70/30 split:
   `econml.metalearners.TLearner` and `XLearner` with LightGBM base learners, and
   `econml.dml.CausalForestDML(model_y=LGBMRegressor(), model_t=LogisticRegression(),
   discrete_treatment=True, n_estimators=500, min_samples_leaf=50)`. Repeat on conversion:
   at a 1% base rate with 21,000 per arm, CATE on conversion is barely estimable, and
   that is a finding.
4. `uplift/qini.py`: sort the held-out 30% by predicted uplift; cumulative incremental
   visits (treated minus control, scaled to equal size) against fraction targeted; the
   diagonal for random; the Qini coefficient as the area between. Curves for all three
   learners and a decile bar chart of observed uplift.
5. The decision: state a cost per email (say $0.10) and a margin per conversion
   (Hillstrom's converters spend about $115 on average; take a stated fraction). Profit
   of emailing the top fraction q by predicted uplift, using visit uplift times the
   observed conversion-per-visit rate; choose q; compare with everyone and nobody.
6. Propensity against uplift: fit P(visit) on the no-email arm alone, target the top 30%
   by propensity and separately by uplift, compute the realised uplift of each set on
   held-out data (randomisation lets you), report the Jaccard overlap, and plot
   propensity against uplift with the four quadrants named.

Done when: the ATE table with CIs matches the published figures within noise; Qini curves
for three learners against random are in the notebook with coefficients; the profit curve
and chosen q are stated; the realised uplift of the two targeted sets is reported with
their overlap; pytest checks `qini` against a hand-computed six-row example.

### Lab 12.4: SHAP on the Module 2 churn LightGBM

Goal: learn what each importance measure measures by breaking them.

1. Load the Module 2 model from its MLflow run, or retrain from its logged parameters.
   `shap.TreeExplainer(model)(X_test)`, then `shap.plots.beeswarm`, and
   `shap.plots.scatter` for tenure and for Contract, coloured by the strongest
   interaction.
2. `shap.plots.waterfall` for a confident churner (p > 0.9), a confident stayer
   (p < 0.05) and a borderline customer (0.45 to 0.55).
3. Mean |SHAP|, `sklearn.inspection.permutation_importance` (test set, 10 repeats,
   negative log loss) and LightGBM gain importance side by side, with the Spearman
   correlation of the three rankings.
4. Add `MonthlyCharges_dup = MonthlyCharges + N(0, 0.01)`, retrain, recompute all three:
   permutation importance of both collapses, gain splits arbitrarily between them, SHAP
   splits but the pair's sum is roughly preserved. Table before and after.
5. A dependence plot for TotalCharges (roughly tenure × MonthlyCharges) and a paragraph on
   what "changing TotalCharges" could even mean.

Done when: the beeswarm, two dependence plots, three waterfalls and the before-and-after
importance table are in the notebook; pytest asserts SHAP values plus base value equal
the model's log-odds output within 1e-4 on 100 rows.

### Lab 12.5: Fairness audit on Adult

Goal: a fairness audit a governance committee could act on.

Data: Adult from OpenML, 48,842 rows, income above $50k as the label at about 24% base
rate; sex and race as protected attributes. The base rate is about 30% for men and 11%
for women.

1. Train the Module 2 LightGBM pipeline twice: without sex and race as features, and with.
2. `fairness.py`: `group_metrics(y, p, g, threshold)` returning selection rate, TPR, FPR,
   PPV and a ten-bin calibration table per group; then demographic parity difference and
   ratio (the four-fifths rule), equalised odds difference (the larger of the TPR and FPR
   gaps) and the largest calibration gap.
3. Show the proxy: even without sex, selection rates differ by sex; train a classifier to
   predict sex from the remaining features (relationship's Husband and Wife values leak
   it; expect an AUC above 0.9).
4. Mitigate once: group-specific thresholds chosen on validation to equalise TPR and FPR
   (Hardt et al.), or reweighing (Kamiran and Calders) so group and label are independent
   under the training weights. Report the accuracy cost and the effect on demographic
   parity and calibration; equalised-odds thresholds break calibration, so show it.
5. `fairness/summary.md`: one page for a governance committee: what was measured, the
   table, the trade-off chosen and why, what was not measured (intersections, individual
   fairness), and a recommendation.

Done when: the per-group table for both models, the three fairness metrics before and
after mitigation, the proxy AUC and the one-page summary are in the repo; pytest checks
`group_metrics` against a hand-computed eight-row example.

## Problem set

1. Derive the two-sample z-test sample size for a difference in proportions from the
   distributions of the test statistic under the null and the alternative. Compute n per
   arm for a 3% baseline, a 0.3-point MDE, α = 0.05 two-sided and 80% power, and show
   Kohavi's rule of thumb n ≈ 16σ²/δ² gives nearly the same number.
2. Derive the delta-method variance for a ratio of means Ȳ/X̄ by first-order Taylor
   expansion, and state when the naive per-session variance is too small.
3. Show algebraically why peeking inflates α: the cumulative z-statistics z_1, ..., z_k
   form a correlated random walk, and P(max_i |z_i| > 1.96) increases in k. Compute it
   exactly for k = 2 with equal increments from the bivariate normal, then simulate k = 30.
4. Let A and B be independent and C = A + B + ε. Simulate 10,000 points and show
   corr(A, B) ≈ 0 overall and clearly negative conditional on C being in its top decile.
   Explain with the DAG.
5. For the DAG Z → X, X → T, X → Y, T → M → Y, T → C ← Y: state the backdoor criterion,
   list every valid adjustment set for the effect of T on Y, and say why {X, M} and
   {X, C} are wrong.
6. Prove E[TY / e(X)] = E[Y(1)] under consistency, positivity 0 < e(X) < 1 and
   T ⊥ Y(1) | X, and hence that the IPW estimator is unbiased for the ATE. State what
   happens to its variance as e(X) → 0 for some units.
7. Let f(x₁, x₂, x₃) = 2x₁ + x₂ + 3x₁x₂ + x₃ with binary features and the all-zero
   baseline. Compute the Shapley values at (1, 1, 1) by hand, check efficiency, and say
   which features receive the interaction and why.
8. With base rates p_a ≠ p_b and equalised odds, P(Ŷ = 1 | A) = TPR·p_A + FPR·(1 − p_A)
   differs across groups unless TPR = FPR. Conclude that demographic parity and equalised
   odds are incompatible for any non-trivial classifier. Then sketch Chouldechova's
   result: with equal PPV and unequal base rates, FPR and FNR cannot both be equal.
9. Six customers have predicted uplift 0.3, 0.2, 0.1, 0, −0.1, −0.2; the first, third and
   fifth were treated with outcomes 1, 1, 0 and the rest were controls with outcomes 0,
   1, 1. Compute the Qini curve and coefficient by hand and compare with random targeting.

## Deliverables

- `12-causal/ab/power.py`, `peeking.py`, `sequential.py`, `cuped.py` and `delta.py`, with
  the tests in Lab 12.1.
- `12-causal/estimators.py` with its tests; `12-causal/uplift/qini.py` and the Hillstrom
  analysis; `12-causal/shap/` with the additivity test; `12-causal/fairness/fairness.py`,
  its tests and `summary.md`.
- Notebook with all figures and tables from the five labs.
- Write-up on the Hillstrom uplift analysis, following `writeup-template.md`. The
  Limitations section must engage with the two-week outcome window, the estimability of
  CATE on a 1% conversion rate, and the external validity of a 2008 catalogue retailer's
  customers to whoever you imagine deploying this for.

## Stretch

- Put bootstrap or conformal intervals on CATE and report their coverage on a synthetic
  dataset with known heterogeneous effects.
- Learn a targeting policy directly with `econml.policy.DRPolicyTree` and compare its
  profit with thresholding the causal forest.
- Bayesian A/B testing with expected loss as the stopping rule; compare its error rates
  with mSPRT on the Lab 12.1 simulations.
- Difference-in-differences and a synthetic control on a simulated regional launch, with
  a placebo test on an untreated region.

## Next

Module 13 takes the churn model, its SHAP explanations and its fairness table and puts
them behind an API with tests, drift monitoring and a model card, then runs a network
from C++ via ONNX and maps four systems onto the EU AI Act. The fairness table you just
made is a section of that card.
