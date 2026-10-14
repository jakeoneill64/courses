#import "../lib/template.typ": *

= Preferences <ch-preferences>

#chapter-meta(
  time: [7 hours],
  builds: [A reward model trained on preference pairs by the Bradley–Terry model and tested on pairs it never saw; DPO derived from the reward model's objective and implemented in thirty lines; Chapter 3.2's model aligned with it; and the result judged by the reward model, with a check of what that judge rewards.],
  needs: [Chapter 3.2.],
)

#why[
  Supervised fine-tuning shows the model good answers, but it never shows it which of two plausible answers is better, or why. People judge assistants by such comparisons: this reply is clearer, that one is wrong, this one is padded. _Preference optimisation_ learns from such comparisons, and it is what turned capable base models into the assistants people use. This chapter implements the two main routes, a learned reward model and direct preference optimisation, and shows how a reward model can give high scores for properties other than quality.
]

#skip-test(
  rule: [If all four are easy, read the DPO derivation and the section on judging, and do Labs 3.4.2 and 3.4.3.],
  [In the Bradley–Terry model, what is the probability that reply $a$ is preferred to reply $b$, given rewards $r(a)$ and $r(b)$?],
  [What does the KL penalty in RLHF's objective prevent?],
  [Write the DPO loss in terms of the policy's and the reference model's log-probabilities of the two replies.],
  [What is reward hacking? Give an example a language model could find.],
)

== Core ideas

=== Preference data

A preference dataset holds prompts, each with two replies and a judgement of which is better. UltraFeedback, used here, collected replies to 64,000 prompts from a range of models and had GPT-4 rate them for instruction following, truthfulness, honesty and helpfulness. The binarised version pairs each prompt's best-rated reply, _chosen_, with a worse one, _rejected_. The program keeps pairs that fit in 640 tokens with the chat template, and takes 4,000 for training and 1,000 from the test split. Judgements by a model rather than people are cheaper and noisier, and they carry the judging model's biases, which this chapter returns to.

=== A reward model

The _Bradley–Terry_ model, from the statistics of paired comparisons, assigns each item a score and says that $a$ is preferred to $b$ with probability
$ P(a succ b) = sigma(r(a) - r(b)), $
where $sigma$ is the logistic function. Maximising the likelihood of the observed preferences gives the loss $-log sigma(r_"chosen" - r_"rejected")$, Chapter 1.3's binary cross-entropy applied to a difference of scores. A _reward model_ computes the score with a language model. Here the fine-tuned model of Chapter 3.2 reads the prompt and the reply, and a linear head reads a single number from its final hidden state at the reply's last token.

#snippet("u3/prefs.py", "hidden", caption: [The final hidden states, the model without its output layer])

#snippet("u3/prefs.py", "reward-model", caption: [A reward model: a language model and a scalar head at the last labelled token])

#snippet("u3/reward.py", "bradley-terry", caption: [Training on pairs: the chosen reply should score higher])

#console(read("/src/console/u3-reward.txt"), caption: [A reward model from SmolLM2-135M, trained on 4,000 pairs])

After 4,000 pairs the reward model ranks the chosen reply above the rejected one for 64.9% of the test pairs, against 50% for chance. Accuracy of this order is typical. The judgements it learns from are noisy, since people and models disagree with each other on a large share of such pairs, and a model of 135 million parameters picks up the commonest signals of a good reply (its relevance, structure and fluency) more easily than whether it is correct. The training loss swings from batch to batch because each batch holds only four pairs. A reward model is a learned and imperfect proxy for preference, and a model optimised against it inherits its errors.

=== From rewards to policies

With a reward model, _reinforcement learning from human feedback_ (RLHF) trains the language model, now called the _policy_ $pi$, to produce replies the reward model scores highly, while staying close to the fine-tuned starting point, the _reference_ $pi_"ref"$:
$ max_pi E_(x, y tilde pi)[r(x, y)] - beta "KL"(pi(dot | x) || pi_"ref"(dot | x)). $
Without the KL penalty, the policy finds whatever text the reward model overrates and can drift into gibberish that happens to score well. InstructGPT optimised this objective with PPO, a reinforcement-learning algorithm that samples replies, scores them, and updates the policy with the help of a value model. PPO needs four models in memory and a training loop that is hard to tune.

=== Direct preference optimisation

DPO uses the fact that this objective has a closed-form optimum, which lets the reward model be eliminated.

#derivation[
  For a fixed prompt $x$, the policy that maximises expected reward minus $beta$ times the KL divergence from $pi_"ref"$ is
  $ pi^*(y | x) = 1 / Z(x) pi_"ref"(y | x) exp(r(x, y) / beta), $
  where $Z(x)$ normalises over all replies. Solving for the reward,
  $ r(x, y) = beta log (pi^*(y | x)) / (pi_"ref"(y | x)) + beta log Z(x). $
  Substitute this into the Bradley–Terry likelihood of a preference $y_w succ y_l$. The intractable $beta log Z(x)$ appears in both rewards and cancels in their difference, leaving a loss on the policy alone:
  $ cal(L) = -log sigma(beta log (pi(y_w | x)) / (pi_"ref"(y_w | x)) - beta log (pi(y_l | x)) / (pi_"ref"(y_l | x))). $
]

The policy's log-ratio to the reference acts as an _implicit reward_. Training raises the chosen reply's probability relative to the reference and lowers the rejected one's, and $beta$ sets how far the policy may move. A small $beta$ lets it move far for a given margin. All DPO needs is the summed log-probability of each reply under the policy and the reference:

#snippet("u3/dpo.py", "seq-logp", caption: [The log-probability of a reply given its prompt])

#snippet("u3/dpo.py", "setup", caption: [The policy, and a frozen copy as the reference])

#snippet("u3/dpo.py", "loss", caption: [The DPO update])

The reference's log-probabilities need no gradients, and could be computed once for the whole dataset in advance. The program computes them as it goes, which is simpler and costs two extra forward passes per step, one for each reply.

=== Judging the result

The implicit reward can rank the test pairs, which measures whether DPO learned the training preferences. Whether the policy's own replies got better needs a judge. The program generates a reply to each of 200 test prompts with the policy before and after DPO, and asks the reward model which it prefers.

#snippet("u3/dpo.py", "judge", caption: [Replies before and after DPO, scored by the reward model])

#console(read("/src/console/u3-dpo.txt"), caption: [DPO on 4,000 pairs, judged by the reward model])

The implicit reward ranks 62.7% of the test pairs correctly, close to the 64.9% of the reward model trained on the same pairs. On held-out preferences, the DPO policy ranks replies about as well as a dedicated reward model of the same size. The reward model prefers the policy's own replies on 58% of 200 prompts. With 200 prompts that figure is uncertain by about seven points either way (Chapter 3.6 computes such intervals), so DPO helped, though by less than its training margins suggest. The replies also grew, from 168 tokens on average to 191, close to the limit of 200. The next section explains why that matters to the verdict. The jump in elapsed time between steps 700 and 900 was not caused by DPO. The machine ran short of memory and swapped for about three quarters of an hour. A long run that needs much of the memory should have the machine to itself.

=== What the judge rewards

A reward model learns whatever distinguishes chosen from rejected replies in its data, including properties other than quality. In UltraFeedback, as in most preference data, the chosen reply is longer on average, so a reward model learns to favour length, and a policy optimised against it learns to write long replies. This is _reward hacking_, a case of Goodhart's law: a measure that becomes a target ceases to be a good measure. Judging the DPO model with a reward model trained on the same data, as above, inherits that reward model's blind spots. Chapter 3.6 brings in an independent judge and measures its biases too.

#keyidea[
  Preference data teach a model to rank replies. A reward model learns a score from paired comparisons by the Bradley–Terry model. DPO does without the reward model and uses the policy's log-probability ratio to a frozen reference as an implicit reward. Every judge has biases, and a policy trained against it will exploit them.
]

#inpytorch(title: [In the libraries])[
  TRL provides `RewardTrainer`, `DPOTrainer` and `PPOTrainer`, along with variants of DPO such as IPO and KTO that change the loss's shape or need only single judgements rather than pairs. They precompute the reference's log-probabilities where possible and handle the chat template, truncation and padding of the two replies.
]

#reading(
  [Rafael Rafailov and others, "Direct Preference Optimization: Your Language Model is Secretly a Reward Model", NeurIPS 2023.],
  [Long Ouyang and others, "Training Language Models to Follow Instructions with Human Feedback", NeurIPS 2022, sections 3.5 and 3.6: reward modelling and PPO.],
  [Ganqu Cui and others, "UltraFeedback: Boosting Language Models with High-Quality Feedback", 2023.],
  [Prasann Singhal, Tanya Goyal, Jiacheng Xu and Greg Durrett, "A Long Way to Go: Investigating Length Correlations in RLHF", 2023.],
  [Ralph Bradley and Milton Terry, "Rank Analysis of Incomplete Block Designs", _Biometrika_ 39, 1952.],
)

== Labs

#lab([Bradley–Terry by hand], goal: [Fit scores to comparisons without a neural network.], time: [1 hour], code: "code/u3/reward.py")[
  + Invent ten comparisons among four items, A to D, including at least one inconsistent cycle.
  + Fit a score per item by gradient descent on the Bradley–Terry loss with `tiny`, and report each item's predicted win probability against each other.
  #done-when(
    [Your fitted probabilities match the observed win rates where the data allow, and you can explain how the fit handles the cycle.],
  )
  #evidence([The data, the fit and the explanation.])
]

#lab([What the reward model likes], goal: [Measure the reward model's preference for length.], time: [1.5 hours], code: "code/u3/reward.py")[
  + Score every chosen and rejected reply in 500 test pairs, and compute the correlation between reward and reply length.
  + Take 50 chosen replies, truncate each to half its length at a sentence boundary, and compare the rewards of the full and truncated versions.
  #done-when(
    [You have the correlation and the 50 paired comparisons.],
    [You can say how much of the reward model's accuracy could be explained by length alone, by scoring the test pairs with length as the only reward.],
  )
  #evidence([The correlation, the comparisons and the length-only accuracy.])
]

#lab([The role of β], goal: [Measure how far the policy moves at different values of β.], time: [2 hours], code: "code/u3/dpo.py")[
  + Run DPO with $beta$ of 0.03, 0.1 and 0.3, and measure for each the implicit-reward accuracy, the reward model's win rate and the mean reply length.
  + Measure each policy's KL divergence from the reference on 100 test prompts, estimated from sampled replies.
  #done-when(
    [Your table has four measurements for each $beta$.],
    [You can describe the trade-off $beta$ controls from your numbers.],
  )
  #evidence([The table and the description.])
]

#lab([DPO without fine-tuning first], goal: [Find out why preference optimisation starts from a fine-tuned model.], time: [1.5 hours], code: "code/u3/dpo.py")[
  + Add an option to the program that starts the policy and the reference from SmolLM2-135M's base model instead of your fine-tune, and run DPO from there.
  + The program's judge compares a policy with its own starting point. Change it to compare each DPO model with your fine-tuned model, and compare their replies.
  #done-when(
    [You have both models' win rates against the fine-tuned model and five pairs of replies.],
    [You can explain the difference in terms of what DPO's loss can and cannot teach.],
  )
  #evidence([The win rates, the replies and the explanation.])
]

#problems(
  [Show that the Bradley–Terry model is unchanged by adding a constant to every score. The reward model's head has a bias, initialised to zero: what is its gradient during training, and so what value does it keep?],
  [Derive the optimal policy of the KL-regularised objective for a single prompt with two possible replies.],
  [In DPO, what happens to the loss if the policy assigns both replies exactly the reference's probabilities? What is its gradient?],
  [Why does DPO's implicit reward depend on the reference model, and what goes wrong if the reference is a poor model?],
  [A reward model's accuracy on held-out pairs is 70%. Does that make it a good judge of a policy trained against it? Why or why not?],
)

#checklist(
  [I can explain the Bradley–Terry model and train a reward model with it.],
  [I can state RLHF's objective and explain the role of its KL penalty.],
  [I can derive DPO's loss and implement it.],
  [I can judge a preference-optimised model and recognise reward hacking.],
  [Lab 3.4.1–3.4.4 done-when criteria all hold, with evidence filed.],
)
