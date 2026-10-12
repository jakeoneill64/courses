#import "../lib/template.typ": *

= Reinforcement learning with verifiable rewards <ch-grpo>

#chapter-meta(
  time: [7 hours],
  builds: [Policy gradients derived from the expected reward; GRPO implemented from scratch, with groups of sampled answers, advantages computed within each group, and a penalty for straying from the starting model; arithmetic problems generated and checked by the program, so that rewards need no judge; and SmolLM2-360M-Instruct trained against the checker, with its solve rate and the length of its answers tracked.],
  needs: [Chapters 2.7 and 3.4.],
)

#why[
  Supervised fine-tuning imitates answers and preference optimisation ranks them, but for problems whose answers can be checked, such as arithmetic, mathematics and code that must pass its tests, there is a more direct signal: whether the answer is right. Reinforcement learning against such a _verifiable reward_ lets the model find its own way to correct answers, and rewards it for the result rather than for resembling an example. This recipe, made practical by the algorithm this chapter implements, is how recent reasoning models were trained, and it needs no human judgements at all.
]

#skip-test(
  rule: [If all four are easy, read the section on GRPO and do Labs 3.5.3 and 3.5.4.],
  [Derive the policy gradient: the gradient of the expected reward with respect to the policy's parameters.],
  [Why does subtracting a baseline from the reward leave the gradient's expectation unchanged and reduce its variance?],
  [How does GRPO estimate the advantage of an answer without a learned value function?],
  [What does GRPO learn from a group in which every answer gets the same reward?],
)

== Core ideas

=== A checker for a reward

The task is arithmetic: three two-digit numbers combined with addition and subtraction, or a two-digit number times a single digit plus or minus another, set as a sentence such as "Calculate 52 + 56 - 77." with an instruction to end the reply with the final answer. The program generates problems from a seed, so there is an unlimited supply and a fixed held-out set, and the reward is 1 if the last number in the reply is exactly right and 0 otherwise.

#snippet("u3/grpo.py", "task", caption: [Problems, and a reward that checks the answer])

The reward ignores everything but that final number: the working, its length, its style. Whatever the model writes on the way is its own business, which is the point: the model is free to find whatever working helps it reach the right answer.

=== The policy gradient

A language model generating an answer $y$ to a prompt $x$ is a _policy_, a distribution $pi_theta(y | x)$ over actions, and the goal is to maximise the expected reward $J(theta) = E_(y tilde pi_theta)[r(x, y)]$. The reward is not differentiable, and neither is sampling, so the gradient comes from a trick.

#derivation[
  $nabla J = nabla sum_y pi_theta(y) r(y) = sum_y pi_theta(y) nabla log pi_theta(y) dot r(y) = E_(y tilde pi_theta)[r(y) nabla log pi_theta(y)]$, using $nabla pi = pi nabla log pi$. The expectation can be estimated by sampling answers and averaging $r(y) nabla log pi_theta(y)$. Since $sum_y pi_theta(y) nabla log pi_theta(y) = nabla sum_y pi_theta(y) = 0$, subtracting any constant $b$ from the reward leaves the expectation unchanged, while a $b$ close to the typical reward makes each sample's contribution smaller and the estimate less noisy.
]

This is REINFORCE: raise the log-probability of answers that scored above the baseline and lower it for those below. The quantity $r - b$ is the _advantage_ of an answer. For a language model, $log pi_theta(y | x)$ is the sum of the log-probabilities of its tokens, so the update spreads each answer's advantage over all of its tokens, exactly the masked log-probabilities of Chapter 3.2.

=== GRPO

PPO, the algorithm of RLHF, learns a second network, a _value model_, to predict the expected reward of each partial answer and serve as the baseline. _Group relative policy optimisation_ drops it. For each prompt it samples a group of $G$ answers, and uses the group's own rewards as the baseline: each answer's advantage is its reward minus the group's mean, divided by the group's standard deviation. An answer is good if it beat its siblings on the same problem.

#snippet("aif/sample.py", "group", caption: [A group of answers to one prompt, sampled together as one batch])

#snippet("u3/grpo.py", "rollouts", caption: [Groups of answers, their rewards and their advantages])

The update maximises each token's log-probability weighted by its answer's advantage, minus $beta$ times an estimate of the KL divergence from the starting model, as in Chapter 3.4, so that the policy improves without forgetting how to write. PPO and GRPO also clip the ratio between the new and old policies' probabilities to stop one batch moving the policy too far; with one update per batch of samples, as here, the ratio is exactly 1, and the program keeps it only for its gradient, $exp(log p - "detach"(log p))$, which equals the gradient of $log p$.

#snippet("u3/grpo.py", "update", caption: [The GRPO loss: advantage-weighted log-probabilities and a KL penalty, token by token])

A group in which every answer scores the same, all right or all wrong, has no advantages and teaches nothing, so the program skips it. GRPO learns only from problems at the edge of the model's ability, where some samples succeed and some fail. That is why this checker reads the reply's last number instead of demanding a format: asked to put its answer between `<answer>` tags, SmolLM2-360M-Instruct did so in none of 30 replies, and a checker that required the tags would have scored nearly every group all zeros.

=== Training against the checker

The program trains SmolLM2-360M-Instruct for 100 steps, each with 8 problems and 8 answers per problem, and measures the solve rate on 200 held-out problems with greedy decoding before and after.

#console(read("/src/console/u3-grpo.txt"), caption: [GRPO on generated arithmetic])

#fig("u3-grpo", caption: [Mean reward and reply length per step, averaged over ten steps.]) <fig-grpo>

Before training, greedy decoding solves 64.5% of the held-out problems; after 100 steps it solves 74.0%. The training reward is lower than either figure because the groups are sampled at temperature 1, where a slip somewhere in the working is more likely, and it doubles over the run, from about 0.26 to 0.53 averaged over ten steps (@fig-grpo). The largest rise comes between steps 40 and 50, and the reward levels off over the last thirty steps. The replies also became shorter, from 81 tokens to 58 under greedy decoding and from about 96 to 73 while sampling. The reward never mentions length, so the shortening is something the policy found: a long reply has more steps in which to slip, and one that reaches the 160-token limit ends before its answer. Whether a gain of 9.5 points on 200 problems is more than luck is a question for Chapter 3.6, which answers it with a paired test.

=== What reinforcement learning adds

A useful way to read these results is through _pass\@k_, the chance that at least one of $k$ sampled answers is right. Reinforcement learning on verifiable rewards mostly raises pass\@1 towards the pass\@k the model already had: it makes the model reliably produce answers it could sometimes produce, sharpening a distribution rather than teaching new knowledge. That is why it works best on a strong base, and why at small scale it teaches format and care more than new skills. At large scale, with long answers and hard problems, the same algorithm has been observed to lengthen the model's reasoning and to produce answers that check and correct their own working.

#hazard(title: [Pitfall])[
  A reward function is a specification, and the policy will satisfy it literally. This checker reads the last number in the reply. If it read the first, the model could learn to state a guess and then work, so that its working never counted; if it accepted the right number anywhere in the reply, the model could list many numbers. Read samples throughout training, not only the curve.
]

#keyidea[
  With a checkable reward, the policy gradient trains a model on the results of its own samples. GRPO estimates each answer's advantage against the other answers to the same prompt, needs no value model, and learns only from problems the model sometimes solves.
]

#inpytorch(title: [In the libraries])[
  TRL's `GRPOTrainer` implements this algorithm with options for several updates per batch, the variants that normalise differently, and generation by vLLM, a fast inference server, since sampling dominates the time of reinforcement learning on language models. This chapter's loop generates with the course's own sampler, which is simple and slow; Chapter 4.8 shows how servers make generation fast.
]

#reading(
  [Zhihong Shao and others, "DeepSeekMath: Pushing the Limits of Mathematical Reasoning in Open Language Models", 2024, section 4: GRPO.],
  [Ronald Williams, "Simple Statistical Gradient-Following Algorithms for Connectionist Reinforcement Learning", _Machine Learning_ 8, 1992: REINFORCE.],
  [John Schulman and others, "Proximal Policy Optimization Algorithms", 2017.],
  [DeepSeek-AI, "DeepSeek-R1: Incentivizing Reasoning Capability in LLMs via Reinforcement Learning", 2025.],
  [Zichen Liu and others, "Understanding R1-Zero-Like Training: A Critical Perspective", 2025.],
)

== Labs

#lab([Policy gradients on a bandit], goal: [See REINFORCE work where every quantity is visible.], time: [1 hour], code: "code/u3/grpo.py")[
  + A policy chooses one of five arms, with logits as its parameters; arm $k$ pays 1 with probability $0.1 + 0.2 k$. Train it with REINFORCE in `tiny` or PyTorch, with and without a running-mean baseline.
  + Plot the probability of the best arm against steps for both, over five seeds.
  #done-when(
    [Both learn to prefer the best arm, and your plot shows the baseline's effect on the spread across seeds.],
  )
  #evidence([The code and the plot.])
]

#lab([Group size], goal: [Measure how the group size affects learning.], time: [2 hours], code: "code/u3/grpo.py")[
  + Train with groups of 4, 8 and 16 answers per prompt, adjusting the number of prompts so that each step samples 64 answers.
  + Record the fraction of groups skipped for having no spread of rewards, and the held-out solve rate.
  #done-when(
    [Your table has the skipped fraction and the solve rate for each size.],
    [You can explain the trade-off from the numbers.],
  )
  #evidence([The table and the explanation.])
]

#lab([pass\@k], goal: [Find out whether training taught new skills or sharpened old ones.], time: [1.5 hours], code: "code/u3/grpo.py")[
  + For 100 held-out problems, sample 16 answers each from the model before and after training, at temperature 1.
  + Compute pass\@1, pass\@4 and pass\@16 for both models, using the unbiased estimator from 16 samples.
  #done-when(
    [Your table has six numbers.],
    [You can say whether the gain at pass\@1 exceeds the gain at pass\@16, and what that implies.],
  )
  #evidence([The table and your interpretation.])
]

#lab([Hacking the checker], goal: [Watch a policy exploit a weak reward.], time: [1.5 hours], code: "code/u3/grpo.py")[
  + Weaken the reward so that it accepts the right number anywhere in the reply, and train again.
  + Read 20 replies from the end of training, and compare the held-out solve rate under the strict checker.
  #done-when(
    [You can show replies that score under the weak reward without answering properly, or explain why the policy did not find them in 100 steps.],
  )
  #evidence([The replies and both solve rates.])
]

#problems(
  [Show that $E_(y tilde pi)[nabla log pi(y)] = 0$, and use it to explain why a baseline does not bias the gradient.],
  [A group of 8 answers has rewards 1, 0, 0, 0, 0, 0, 0, 0. Compute each answer's GRPO advantage. How does the update treat the one success relative to a group with four successes?],
  [Why does GRPO divide by the group's standard deviation? What happens on very easy and very hard problems, and why have some variants removed it?],
  [Why does the KL estimate $exp(r) - r - 1$, with $r = log pi_"ref" - log pi$, never go negative, and why is it preferred to $-r$?],
  [Sampling an answer of 160 tokens costs 160 forward passes; training on it costs one forward and backward pass over 160 tokens. Which dominates a GRPO step, and what does that suggest about where to optimise?],
)

#checklist(
  [I can derive the policy gradient and explain the role of a baseline.],
  [I can implement GRPO, with group advantages and a KL penalty.],
  [I can design a verifiable reward and recognise ways it can be exploited.],
  [I can evaluate what reinforcement learning added with pass\@k.],
  [Lab 3.5.1–3.5.4 done-when criteria all hold, with evidence filed.],
)
