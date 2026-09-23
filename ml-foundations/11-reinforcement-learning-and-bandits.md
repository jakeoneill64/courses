# Module 11: Reinforcement learning and bandits

**Part IV · 1 week · Needs: Modules 5 and 9. Data: Gymnasium FrozenLake-v1, CliffWalking-v0 and CartPole-v1; simulated email campaigns.**

## Why this module

Reinforcement learning is a small part of business machine learning and a large part
of its vocabulary. Every LLM paper you read on the MSc has a section on reinforcement
learning from human feedback, and you cannot judge it without knowing what a policy
gradient is, why PPO clips it, and what a reward model can be gamed into. The Oxford
Generative AI week assumes that literacy, and the Classical Machine Learning week
covers the tabular foundations at speed. One week here makes both feel familiar.

The part of RL a business actually deploys is the bandit. Whenever you choose between
subject lines, prices, recommendations or ad creatives and see the outcome, you are
facing the explore-exploit trade, and the choice between an A/B test and a bandit is a
real decision with real money attached. A bandit earns more during the experiment; an
A/B test gives you a clean inference at the end. Knowing when each is right, and how to
evaluate a new policy from logs without running it, is the practical skill this
module leaves you with, and it is the one the Augmenting Business Decisions course
will expect you to argue about.

Structurally, the module closes two loops. The policy gradient and PPO paragraphs
explain what Module 10's RLHF and DPO sections were built on. The bandit and
off-policy evaluation labs are the bridge to Module 12, where the same email data is
analysed as a controlled experiment and as a causal question.

## Skip test

Answer cold, in writing.

1. Define V^π and Q^π. Write the Bellman expectation equation for V^π and the Bellman
   optimality equation for Q*. Why does the second have a unique solution?
2. State Q-learning and SARSA as one update each. Under an ε-greedy policy on the cliff
   gridworld, which learns the cliff-edge path and why?
3. Why is the REINFORCE gradient estimate high variance, and why does subtracting a
   baseline that depends only on the state not bias it?
4. Give one situation in which a bandit is the right tool and one in which an A/B test
   is, and the property of the situation that decides it.
5. Write Thompson sampling for Bernoulli arms with Beta priors, including the posterior
   update.
6. You have logs from a policy that chose uniformly at random 10% of the time. How do
   you estimate the value of a new deterministic policy from those logs, and what makes
   the estimate blow up?

If all six are easy, do Labs 11.4 and 11.5 only, and the write-up.

## Core ideas

**A Markov decision process is a supervised learning problem with the labels delayed
and the data chosen by the learner.** States s, actions a, transition probabilities
P(s' | s, a), rewards r, and a discount γ in [0, 1) define it. The return is
G_t = Σ_k γ^k r_{t+k+1}, and discounting is both a preference for sooner reward and the
device that keeps infinite sums finite. A policy π(a | s) induces two value functions:
V^π(s), the expected return from s, and Q^π(s, a), the expected return from taking a
in s and following π afterwards. Everything else in RL is a method for estimating or
improving these when P is unknown, too large to enumerate, or both.

**The Bellman equations are consistency conditions, and the optimality operator is a
contraction.** Expectation: V^π(s) = Σ_a π(a | s) Σ_s' P(s' | s, a)[r + γV^π(s')].
Optimality: Q*(s, a) = Σ_s' P(s' | s, a)[r + γ max_a' Q*(s', a')]. Define the operator
T that maps a value function to the right-hand side; then ‖TV − TU‖∞ ≤ γ‖V − U‖∞
(Problem 1), so by Banach's theorem T has exactly one fixed point and iterating it
from anywhere converges geometrically at rate γ. That is why value iteration works,
why γ close to 1 makes everything slow, and why the same equations become unstable
when a function approximator breaks the contraction.

**Dynamic programming solves the MDP exactly when the model is known.** Policy
evaluation iterates the expectation equation to convergence. Policy improvement makes
the policy greedy with respect to the resulting Q; the policy improvement theorem says
this never makes it worse. Policy iteration alternates the two and converges in a
handful of rounds on small problems; value iteration folds the improvement into every
sweep and converges in more, cheaper, sweeps. Lab 11.1 runs all three on FrozenLake,
where the transition table is in `env.unwrapped.P` and the optimal policy on the
slippery 4×4 map reaches the goal only about three quarters of the time, because no
policy can do better against the ice.

**Learning from experience trades bias for variance.** Monte Carlo waits for the
episode to end and updates V(s) towards the observed return G_t: unbiased, high
variance, needs episodes to terminate. Temporal difference updates towards the
bootstrapped target r + γV(s'): biased while V is wrong, much lower variance, and
learns online from every step. TD(λ) interpolates between them with a trace. In
practice TD wins on most problems because variance is what limits learning speed, and
the bias vanishes as V converges (Problem 3).

**SARSA and Q-learning differ in one symbol, and the cliff shows why it matters.**
SARSA updates Q(s, a) towards r + γQ(s', a') using the action a' the policy actually
took: on-policy, so it learns the value of the exploring policy, including its
mistakes. Q-learning updates towards r + γ max_a' Q(s', a'): off-policy, so it learns
the value of the greedy policy no matter how it explores. On the cliff gridworld with
ε-greedy exploration, Q-learning learns the shortest path along the cliff edge and
keeps falling off during training, averaging about −50 per episode; SARSA learns the
safe path along the top, at about −25. Both converge to the same optimal policy when ε
decays to zero. Off-policy learning is what makes experience replay possible, and it is
also the source of the instability in the next paragraph.

**Exploration is a decision problem in its own right, and the good methods use
uncertainty.** ε-greedy explores uniformly and forever, which wastes trials on arms it
already knows are bad. Optimistic initialisation explores by default until each
estimate has been driven down. Upper confidence bound methods choose the action with
the highest plausible value, μ̂_a + √(2 ln t / n_a) for UCB1, so exploration
concentrates on actions that are uncertain and might be good, and the regret grows
only logarithmically in T (Problem 5). Thompson sampling keeps a posterior over each
action's value, samples one value per action, and acts greedily on the samples; it
explores in proportion to the probability that an action is best, is simple to
implement for Bernoulli rewards with Beta posteriors, and empirically matches or beats
UCB (Chapelle and Li). It is the default choice in Lab 11.4.

**Function approximation breaks the tabular guarantees, and DQN patches it with two
tricks.** Replace the Q table with a network and the fixed point may not exist: the
combination of bootstrapping, off-policy data and function approximation is the deadly
triad, and any two are fine. DQN trains anyway by storing transitions in a replay
buffer and sampling minibatches from it, which breaks the correlation between
consecutive samples, and by computing targets from a separate target network updated
only every few thousand steps, which stops the target moving with every update. The
result learned Atari from pixels in 2015 and is the reference design for value-based
deep RL; you build a small one for CartPole as the optional part of Lab 11.3.

**Policy gradient methods optimise the policy directly and are what LLM training
uses.** For a stochastic policy π_θ, the policy gradient theorem gives
∇J(θ) = E[Σ_t ∇ log π_θ(a_t | s_t) G_t]: push up the log-probability of actions in
proportion to the return that followed them. REINFORCE is that expectation estimated
from sampled episodes, and its variance is enormous because G_t is a sum of many noisy
rewards. Subtracting a baseline b(s_t) leaves the gradient unbiased (Problem 2) and, if
b ≈ V(s_t), reduces the variance by an order of magnitude; the difference G_t − V(s_t)
is the advantage. Actor-critic replaces G_t with a bootstrapped estimate from a learned
critic, trading variance for bias exactly as TD did. Lab 11.3 measures the variance
with and without the baseline.

**PPO makes policy gradient safe to run for many steps on the same data, which is why
RLHF uses it.** A large policy update can collapse performance and the on-policy
gradient offers no protection. PPO maximises a clipped surrogate,
E[min(ρ_t A_t, clip(ρ_t, 1−ε, 1+ε) A_t)] with ρ_t = π_θ(a_t | s_t)/π_old(a_t | s_t),
so the policy cannot move the probability of any action by more than a factor of about
1±ε in one round, and several epochs of minibatch updates on one batch of rollouts are
safe. In RLHF the "environment" is a prompt, the "action" is a whole response, the
reward is a model trained on human preference pairs, and a KL penalty to the reference
policy is added to the reward. Without the penalty the policy finds the reward model's
blind spots (verbose, sycophantic, keyword-stuffed responses) and exploits them; this is
reward hacking, and it is the general failure mode of every optimised proxy (Problem
8). DPO, which Module 10 used, removes the reward model and the RL loop by rewriting
the same objective as a classification loss on preference pairs.

**Bandits are MDPs with one state, and they are the RL a business runs.** With K arms
and unknown mean rewards, the regret after T pulls is T·μ* − Σ_t μ_{a_t}: the reward you
gave up by not knowing the best arm from the start. An A/B/n test is a bandit strategy
that pulls arms uniformly for a fixed horizon and then commits; its regret is linear in
the test length, but it delivers what a bandit does not, a confidence interval on every
arm's value and a valid p-value. Choose the A/B test when you need the inference (a
pricing decision that will be defended to a regulator, a feature launch that has to be
understood), when the metric is delayed, or when the arms will interact with each
other. Choose the bandit when the reward is fast and the goal is cumulative (subject
lines, ranking, creative rotation), when the arms change often, or when the cost of
exploring bad arms is real money. Lab 11.4 puts numbers on the difference.

**Contextual bandits personalise, and LinUCB is the workhorse.** When each round comes
with a feature vector x (the user, the time, the device), the arm values become
functions of x. LinUCB assumes E[r | x, a] = θ_aᵀx, maintains a ridge-regression
estimate θ̂_a per arm with covariance A_a⁻¹, and pulls the arm maximising
θ̂_aᵀx + α√(xᵀA_a⁻¹x), which is UCB with the confidence width from the regression.
It was built for news recommendation at Yahoo and is what most "personalisation
engine" products contain. Its assumptions, linear reward and stationarity, are also
what break it, and the honest limits below apply.

**Off-policy evaluation lets you score a new policy on data an old one collected.**
Given logs (x_i, a_i, r_i) from a logging policy π_0 with known propensities
π_0(a_i | x_i), the inverse propensity score estimate of a target policy π_e is
(1/n) Σ_i π_e(a_i | x_i) r_i / π_0(a_i | x_i). It is unbiased whenever π_0 gives every
action π_e might take a nonzero probability, and its variance is governed by the
importance weights: if π_0 rarely took the actions π_e prefers the weights explode and
the estimate is useless (Problem 7). Clipping the weights at a constant caps the
variance and introduces bias. The doubly robust estimator combines a reward model
(direct method) with an IPS correction of its residuals and is unbiased if either the
propensities or the reward model are right, with lower variance than IPS when both are
roughly right. This is how you avoid running a live experiment for every candidate
policy, and it is why production systems log propensities.

**The honest limits of RL in a business are delayed reward, non-stationarity and the
gap between prediction and explanation.** Bandits assume the reward arrives before the
next decision; a subject line's click does, a customer's lifetime value does not, and
attributing a delayed outcome to one action is the credit assignment problem in its
hardest form. Arm values drift: the best subject line in March is not the best in
December, so production bandits discount or window their statistics and never stop
exploring entirely (Lab 11.4). And a bandit tells you which arm is best without telling
you why; when the business asks why, or asks what would happen under an arm nobody has
tried, you need causal inference and a designed experiment, which is Module 12.

**Forward links.** The policy gradient theorem, the advantage, the KL penalty and the
clipped ratio are the machinery beneath Module 10's RLHF and DPO. Regret, propensities
and inverse propensity weighting reappear in Module 12 as the language of experiments
and causal inference, and the Hillstrom email data there is a real version of the
campaign simulated here. The bandit-versus-A/B argument returns in Module 13 as the
question of how a deployed model is allowed to change.

## Reading

- Sutton and Barto, *Reinforcement Learning: An Introduction*, 2nd ed. (free), ch. 1 to
  6 (the problem, bandits, MDPs, dynamic programming, Monte Carlo, TD) and ch. 13
  (policy gradient). Example 6.6, the cliff, is Lab 11.2.
- Lattimore and Szepesvári, *Bandit Algorithms* (free), ch. 1 to 2 (introduction and
  the bandit problem), 7 to 8 (UCB and its regret), 19 (LinUCB) and 36 (Thompson
  sampling).
- Williams, "Simple statistical gradient-following algorithms for connectionist
  reinforcement learning", 1992 (REINFORCE).
- Mnih et al., "Human-level control through deep reinforcement learning", 2015 (DQN).
- Schulman, Wolski, Dhariwal, Radford, Klimov, "Proximal Policy Optimization
  Algorithms", 2017. Section 3 is all you need.
- Chapelle and Li, "An Empirical Evaluation of Thompson Sampling", 2011.
- Li, Chu, Langford, Schapire, "A Contextual-Bandit Approach to Personalized News
  Article Recommendation", 2010 (LinUCB, and the offline evaluation method in §4).
- Dudík, Langford, Li, "Doubly Robust Policy Evaluation and Learning", 2011.
- Ouyang et al., "Training language models to follow instructions with human
  feedback", 2022. Read §3.5 and the reward-model and PPO objectives only; map every
  symbol onto this module's notation.
- Gymnasium documentation for FrozenLake, CliffWalking and CartPole: the observation
  and action spaces, the reward structure and the episode truncation limits, which
  matter for every number below.

## Labs

### Lab 11.1: Dynamic programming on FrozenLake

Goal: solve an MDP exactly and verify the Bellman equation numerically.

1. In `11-rl/dp.py` write `policy_evaluation(P, policy, gamma, tol)`,
   `policy_iteration(P, gamma)` and `value_iteration(P, gamma, tol)` over the
   transition table `env.unwrapped.P[s][a]`, a list of (probability, next_state,
   reward, terminated) tuples, for `gym.make("FrozenLake-v1", map_name="4x4",
   is_slippery=True)` and the `8x8` map, with γ = 0.99.
2. At convergence assert the Bellman optimality residual
   max_s |V(s) − max_a Σ P(s' | s, a)[r + γV(s')]| is below 1e-8, and that policy
   iteration and value iteration agree on V* to 1e-6 and on the greedy policy wherever
   the action values are not tied.
3. Run the greedy policy for 10,000 episodes with `env.reset(seed=...)` and compare the
   empirical success rate with V*(start); on 4×4 both are about 0.74 under the default
   100-step truncation. Plot V* on the grid for both maps with the policy's arrows.
4. Record the number of sweeps each method needs on each map and how it changes at
   γ = 0.9 and γ = 0.999.

Done when: the residual and agreement tests pass under pytest on both maps, the
empirical success rate is within 0.02 of V*(start), and the two value grids are in the
notebook with the sweep counts.

### Lab 11.2: SARSA and Q-learning on the cliff

Goal: reproduce the on-policy versus off-policy result and explain it.

1. In `11-rl/qlearn.py` implement `sarsa(env, episodes, alpha, gamma, eps)` and
   `q_learning(...)` with the same signature and an ε schedule argument. Use α = 0.5,
   γ = 1.0 and ε = 0.1 on `CliffWalking-v0`, 500 episodes, 10 seeds.
2. Plot mean episode return against episode for both, with a band over seeds. Expect
   Q-learning to settle near −50 and SARSA near −25, and render the greedy path of each
   on the grid: Q-learning along the cliff edge, SARSA along the top.
3. Repeat with ε decayed linearly to zero over the 500 episodes and show that the two
   greedy policies coincide and both returns approach −13, the optimal path length.
4. Run both on slippery FrozenLake 4×4 for 20,000 episodes and compare the learned
   greedy policy's success rate with Lab 11.1's optimum.

Done when: the two learning-curve figures and the path renderings are in the notebook,
the decayed-ε run reaches −13 for both methods, and a pytest test checks both learners
recover the optimal FrozenLake policy on the non-slippery map within 5,000 episodes.

### Lab 11.3: REINFORCE with a baseline on CartPole

Goal: implement a policy gradient, measure its variance, and see what a baseline buys.

1. In `11-rl/reinforce.py`: a policy network 4-64-2 with a categorical head and a value
   network 4-64-1; `collect_episode(env, policy)`; `reinforce_update(policy, value,
   episodes, baseline: bool)` using returns-to-go with γ = 0.99, the advantage
   G_t − V(s_t) when the baseline is on, Adam at 1e-3 for both networks, and one update
   per 5 episodes. Run on the CPU; the networks are too small for MPS to help.
2. Train for up to 1,000 episodes on `CartPole-v1` with 5 seeds, with and without the
   baseline. Plot the 100-episode moving average return per seed, and record the
   episode at which it first reaches 475.
3. Freeze a policy snapshot at 200 episodes, collect 200 episodes, compute the gradient
   estimate from each episode alone, and report the trace of the covariance of those
   per-episode gradients with and without the baseline. Repeat at 600 episodes.
4. Optional: a DQN in `11-rl/dqn.py` with a replay buffer of 10,000, a target network
   updated every 500 steps, ε from 1.0 to 0.05 over 10,000 steps, batch 64, Adam 1e-3,
   and the same 475 target. Compare wall time and sample efficiency.

Done when: at least four of five baseline runs reach a 100-episode average of 475
within 1,000 episodes, the baseline reduces the gradient variance at both snapshots
(expect a factor of several), and a pytest test confirms `reinforce_update` produces a
finite gradient with the expected sign on a hand-built two-step episode.

### Lab 11.4: Bandits against A/B for a marketing decision (headline lab)

Goal: put numbers on the cost of an A/B test and the risks of a bandit, on a problem
shaped like the one a marketing team actually has.

1. In `11-rl/bandits.py` write `BernoulliEnv(rates, seed)` with five subject lines at
   true conversion rates 2.0, 2.3, 2.5, 2.8 and 3.5%, a horizon of 100,000 sends, and
   agents `EpsilonGreedy(eps=0.1)`, `UCB1()` and `ThompsonBeta()` sharing a
   `select()` and `update(arm, reward)` interface. Plot cumulative regret against sends
   for each, mean and 10th to 90th percentile band over 200 replications.
2. A/B/n: compute the per-arm sample size to detect 2.8% against 3.5% at α = 0.05 with
   80% power (about 10,000 per arm with a two-proportion z-test, about 14,000 with a
   Bonferroni correction for four comparisons; Problem 6), split traffic evenly for
   that many sends, pick the winner, and send the rest to it. Over the 200 replications
   report the conversions forgone relative to an oracle that knew the best arm, and the
   fraction of replications in which the test picked the wrong arm. Compare with
   Thompson sampling's total regret on the same horizon (expect the bandit to forgo
   roughly half as many conversions, but report your numbers).
3. Non-stationary: at send 50,000, raise arm 1 from 2.0% to 4.0%. Run plain Thompson
   sampling, a sliding-window version (window 10,000) and a discounted version (factor
   0.999 on both Beta parameters each step), and plot regret against sends. Show that
   plain Thompson sampling never recovers within the horizon and say why.
4. Contextual: generate users with three features (say tenure, prior opens and a
   device flag) and arm rewards Bernoulli with logit θ_aᵀx for five random θ_a. Implement
   `LinUCB(alpha=1.0)` and compare its regret with context-free Thompson sampling over
   100,000 rounds and 50 replications.

Done when: the four regret figures are in the notebook, the A/B/n cost is stated as a
number of conversions with a band, the wrong-winner rate is reported, the sliding-window
or discounted variant recovers the new best arm within 10,000 sends of the change, and
LinUCB beats the context-free bandit by a margin outside the band.

### Lab 11.5: Off-policy evaluation

Goal: estimate what a policy would earn from logs collected by a different one.

1. In `11-rl/ope.py`, log 20,000 rounds of the Lab 11.4 stationary bandit under a
   uniform-random policy, recording arm, reward and propensity 0.2.
2. Implement `ips(logs, target_policy)`, `clipped_ips(logs, target_policy, max_weight)`
   and `doubly_robust(logs, target_policy, reward_model)` where the reward model is the
   per-arm empirical mean from a held-out half of the logs. The target policy is the
   Thompson sampler's final greedy choice from Lab 11.4 (a distribution putting most
   mass on arm 5).
3. Compute each estimate's bias and standard deviation over 500 replications against
   the target's true value, at log sizes 2,000, 20,000 and 200,000. Plot estimate
   against log size with bands and the truth as a line.
4. Change the logging policy to one that chooses arm 5 only 2% of the time and repeat.
   Plot the distribution of importance weights and show the IPS variance rising by
   roughly the inverse of that probability, clipping at 10 trading it for bias, and
   doubly robust sitting between.

Done when: the two figures are in the notebook, IPS is unbiased within its own standard
error at every log size under uniform logging, and you have written the rule you would
give a product team about the minimum exploration rate to log in production.

## Problem set

1. Prove that the Bellman optimality operator (TQ)(s, a) = Σ_s' P(s' | s, a)[r + γ max_a'
   Q(s', a')] satisfies ‖TQ − TQ'‖∞ ≤ γ‖Q − Q'‖∞, using |max_a f(a) − max_a g(a)| ≤
   max_a |f(a) − g(a)|. Conclude uniqueness of Q* and a bound on the error after k
   sweeps of value iteration from Q₀ = 0.
2. Derive the policy gradient theorem for the episodic case by differentiating the
   expected return under trajectory probabilities and using the log-derivative trick,
   then show E[∇ log π_θ(a_t | s_t) b(s_t)] = 0 for any b depending on the state only.
3. Let G_t be the Monte Carlo return and Y_t = r_{t+1} + γV(s_{t+1}) the TD(0) target
   with V the current estimate. Show E[Y_t] ≠ V^π(s_t) in general (the bias) and that
   Var(Y_t) is smaller than Var(G_t) when rewards are independent with equal variance,
   by comparing the number of random terms each contains.
4. Derive the Beta-Bernoulli posterior update: with prior Beta(α, β) and n pulls giving
   k successes, show the posterior is Beta(α + k, β + n − k). Write Thompson sampling's
   action rule and show that the probability of pulling arm a equals the posterior
   probability that a is the best arm.
5. Sketch why UCB1 achieves O(Σ_a log T / Δ_a) regret: bound the number of pulls of a
   suboptimal arm by the number of rounds in which its confidence interval still
   overlaps the best arm's, using Hoeffding's inequality for the width.
6. Compute the per-arm sample size for a two-proportion z-test to detect 2.8% against
   3.5% at α = 0.05 (two-sided) and 80% power, with and without a Bonferroni correction
   for four comparisons. Compare with the number of pulls your Thompson sampler spent
   on the four suboptimal arms in Lab 11.4 and explain the gap.
7. Show that the IPS estimator is unbiased for the value of π_e when π_0 has full
   support on the actions π_e takes, derive its variance in terms of the importance
   weights, and explain what clipping the weights at M does to each. Give the
   expression for the doubly robust estimator and say which of its two ingredients must
   be correct for unbiasedness.
8. Write the RLHF objective E[r_φ(x, y)] − β KL(π_θ(· | x) ‖ π_ref(· | x)) and explain,
   in terms of the reward model being an imperfect proxy fitted on finite preference
   data, why the KL term is there, what happens as β → 0, and how you would detect
   reward hacking from the generated text and from the reward-model score
   distribution.

## Deliverables

- `11-rl/dp.py`, `qlearn.py`, `reinforce.py`, `bandits.py` and `ope.py`, with pytest
  tests for the Bellman residual, the FrozenLake policy recovery, the REINFORCE
  gradient sanity check, the Beta posterior update, and IPS unbiasedness on a
  two-arm toy problem with known value.
- Notebook with the figures from all five labs, including the value grids, the two
  cliff paths, the CartPole learning curves, the four regret figures and the two
  off-policy figures.
- Write-up on the bandit-versus-A/B decision, following `writeup-template.md`, written
  as the recommendation you would give a marketing lead. The Limitations section
  should engage with what a simulation with known, stationary Bernoulli arms leaves out
  of a real campaign (delayed conversions, drift, interference between sends) and with
  what the A/B test delivers that the bandit cannot.

## Stretch

- Implement PPO for CartPole and then for `LunarLander-v3` (needs `gymnasium[box2d]`),
  with generalised advantage estimation, and plot the clipped fraction per update.
- Implement the offline evaluation protocol of Li et al. (2010) §4 for a contextual
  bandit, which replays logged data to evaluate a new bandit algorithm rather than a
  fixed policy, and compare it with your IPS estimates.
- Write a tiny RLHF: a reward model that scores Module 9 GPT samples by a simple
  proxy (say, how many words are in a target vocabulary), REINFORCE with a KL penalty
  to the original model, and a plot of proxy reward against KL. Then look at the
  samples at high reward and describe the hacking.
- Model the delayed-reward problem: conversions arrive with a random delay of up to
  7 days. Adapt Thompson sampling to treat pending outcomes as censored and measure
  the regret penalty of the delay.

## Next

Module 12 takes the same email campaign and asks the questions a bandit cannot answer:
whether the difference between arms is real, how large it is with a confidence
interval, and which customers it works on. The propensities you logged here become the
weights in causal inference, and the A/B test you costed becomes an experiment analysed
properly.
