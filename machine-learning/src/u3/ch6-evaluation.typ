#import "../lib/template.typ": *

= Evaluation <ch-evaluation>

#chapter-meta(
  time: [7 hours],
  builds: [An evaluation harness: multiple-choice questions scored by likelihood, with bootstrap confidence intervals and paired tests between models; the unit's base, fine-tuned and DPO models, and SmolLM2's own instruction-tuned ones, measured on ARC; the GRPO model on its own task; a larger model as judge, with its bias for position measured and cancelled; and a contamination check of a benchmark against fine-tuning data.],
  needs: [Chapters 3.2 to 3.5, and Chapter 1.6's section on the precision of a test score.],
)

#why[
  Every chapter of this unit claimed that a model got better. Those claims were measured on whatever was convenient: a held-out loss, a reward model trained on related data, a few replies read by eye. Evaluation is the discipline that makes such claims trustworthy: choosing measurements that reflect what you care about, stating their uncertainty, comparing models fairly, and knowing the ways benchmarks mislead. Results in this field are often reported without any of that, so the habit of measuring carefully is worth as much as any technique in the course.
]

#skip-test(
  rule: [If all four are easy, read the sections on judges and contamination, and do Labs 3.6.2 and 3.6.4.],
  [How is a multiple-choice question scored with a language model that only gives probabilities of tokens?],
  [A model scores 62% on 1,000 questions. Give a 95% confidence interval for its accuracy.],
  [Two models are evaluated on the same 1,000 questions. Why is a paired test more sensitive than comparing their two intervals?],
  [Name two biases of language models used as judges, and how to measure them.],
)

== Core ideas

=== Kinds of evaluation

Three kinds of measurement cover most needs. _Likelihood_ measures, such as the held-out loss of Chapter 3.2, are cheap and precise, but say nothing directly about behaviour. _Task benchmarks_ pose questions with known answers, multiple-choice or exact match, and measure accuracy. _Judgements_ compare open-ended replies, by people or by a model, and measure preference. This chapter's harness does all three on the models of this unit.

=== Multiple choice by likelihood

A multiple-choice question can be answered without generating anything. Present the question, and score each option by the probability the model assigns to it as a continuation. The option with the highest mean log-probability per token is the model's answer. Taking the mean rather than the sum stops longer options being penalised for their length.

#snippet("aif/evals.py", "choice", caption: [Scoring the options of a question by mean log-probability])

ARC, the AI2 Reasoning Challenge, poses grade-school science questions with four options, in an easy set and a challenge set that simple retrieval and co-occurrence methods fail on. Chance is about 25%.

#snippet("u3/evaluate.py", "arc", caption: [ARC questions, scored by likelihood])

=== Uncertainty

An accuracy measured on $n$ questions is an estimate, with a standard error of about $sqrt(p(1 - p) \/ n)$, as Chapter 1.6 showed. The _bootstrap_ estimates the uncertainty of any statistic without a formula: resample the questions with replacement many times, recompute the statistic each time, and take the middle 95% of the results as the interval.

#snippet("aif/evals.py", "bootstrap", caption: [Bootstrap intervals, and the paired bootstrap for a difference])

Comparing two models on the same questions calls for a _paired_ test. Questions vary widely in difficulty, and both models tend to get the easy ones right and the hard ones wrong, so that shared variation cancels in the per-question difference. McNemar's test uses only the questions on which the models disagree. If the two were equally good, each disagreement would favour either model with probability one half, and the exact binomial distribution gives the chance of an imbalance as large as observed.

#snippet("aif/evals.py", "mcnemar", caption: [McNemar's exact test])

#snippet("u3/evaluate.py", "compare", caption: [Three paired comparisons])

#console-part("/src/console/u3-evaluate.txt", to: 13, caption: [Six models on ARC, with 95% intervals, and three paired comparisons])

Fine-tuning barely moved ARC. Over both sets, the fine-tuned model scores 0.8 points below its base and the DPO model 0.5 points below the fine-tuned one. Both intervals include zero, and McNemar's test gives $p approx 0.11$ for each, so neither change can be told from chance on 3,548 questions. This is expected, because ARC measures knowledge gained in pretraining, and ten thousand conversations teach a format while adding little knowledge. The official instruction-tuned models score far lower on ARC-Easy than their bases, 50.8% against 59.4% and 66.6%, and a little lower on ARC-Challenge. Their knowledge is unlikely to have shrunk so much. A more likely explanation is that scoring raw text after "Answer:" suits a base model, while a model tuned to reply inside a chat template spreads its probability differently. An evaluation measures a model in a particular format, and a change of format can move a score as much as a change of model. The largest difference comes from scale. SmolLM2-360M beats SmolLM2-135M by 7.4 points, with an interval of 6.0 to 8.7 and a $p$-value far below 0.001. Every 135M model stays close to chance on ARC-Challenge, at about 30% against 25%.

=== The model trained on its task

#console-part("/src/console/u3-evaluate.txt", from: 13, to: 16, command: false, caption: [Arithmetic, before and after GRPO, with intervals and a paired test])

Before GRPO the model solves 64.5% of the 200 held-out problems, with an interval of 58.0% to 71.0%; after it, 74.0%, from 68.0% to 80.0%. The two intervals overlap, which might suggest the gain could be luck, but separate intervals are the wrong test for two models answering the same questions. The paired difference is 9.5 points, with an interval of 4.0 to 15.5, and McNemar's test gives $p = 0.0026$. The gain is real, though its size is known only roughly.

=== Judges and their biases

Open-ended replies have no answer key, and human judgement is slow and expensive, so a stronger model, a _language-model judge_, is often asked to compare replies. Judges have biases of their own, the best documented being a preference for whichever reply is shown first or second, a preference for longer replies, and a preference for replies in their own style. The harness asks SmolLM2-1.7B-Instruct to compare the fine-tuned model's reply with the DPO model's on 100 test prompts. It reads the judge's probabilities for the tokens "A" and "B" instead of sampling a verdict, and asks every question twice, with the order of the replies swapped.

#snippet("u3/evaluate.py", "judge", caption: [The judge's probability that reply B is better])

#console-part("/src/console/u3-evaluate.txt", from: 16, to: -2, command: false, caption: [The judge's verdicts in both orders])

The judge prefers whichever reply it reads first. The DPO reply wins with probability 0.77 when shown first and 0.23 when shown second, and the two orders pick the same winner on 1% of prompts. Averaged over both orders, the preference is 0.50 with an interval of 0.50 to 0.51. Once its position bias is removed, the judge cannot tell the two models apart, and its verdicts in either single order measure only that bias. The reward model of Chapter 3.4 preferred the DPO replies on 58% of prompts, so the two judges disagree. A model of 1.7 billion parameters, read through the probabilities of two tokens, is too weak a judge for this comparison.

Swapping and averaging cancels a position bias, but not a bias for length or style, which act the same way in both orders. A judge, like a reward model, needs calibrating. Check its verdicts against careful human judgements on a sample of comparisons before trusting it.

=== Contamination

A benchmark measures generalisation only if the model has not seen its questions. Models are trained on web-scale data that may include benchmarks, and fine-tuning data written by larger models may reproduce questions those models saw. A simple check looks for long word sequences shared between the benchmark and the training data:

#snippet("u3/evaluate.py", "contamination", caption: [13-word overlaps between ARC's questions and the fine-tuning data])

#console-part("/src/console/u3-evaluate.txt", from: -2, command: false, caption: [ARC against one shard of SmolTalk])

Two of the 3,548 ARC questions share a 13-word sequence with the fine-tuning shard, too few to move any score above. Both matches are textbook statements. One question describes air "deflected to the right in the Northern Hemisphere and to the left in the Southern Hemisphere", in the same words as a SmolTalk reply about the jet stream. The other opens with Newton's first law, which a SmolTalk reply also states. Neither conversation contains the question, though the jet-stream reply attributes the deflection to the Earth's rotation, which answers the first. That is general knowledge of the kind a benchmark exists to test. Read each match by eye, because a shared sequence is as often a stock phrase as a leaked question.

Overlap checks catch verbatim copies. They miss paraphrases, and questions whose answers were learned from other text. Contamination of the pretraining data cannot be checked without that data, which for most open-weight models is not published. For the course's own TinyStories model it can be checked, which is one reason Chapter 2.5 holds out a validation set from the start.

#keyidea[
  Report every measurement with its uncertainty, as an interval. Compare models on the same items with paired tests, cancel what you can of a judge's biases and measure the rest, and check that the test was not part of the training.
]

#inpytorch(title: [In the libraries])[
  EleutherAI's `lm-evaluation-harness` runs hundreds of benchmarks with standardised prompts and likelihood scoring like this chapter's, and Hugging Face's `lighteval` is similar. Both make results comparable across papers only when the prompt format, the few-shot examples and the scoring rule are reported, which is less often than it should be.
]

#reading(
  [Peter Clark and others, "Think You Have Solved Question Answering? Try ARC, the AI2 Reasoning Challenge", 2018.],
  [Lianmin Zheng and others, "Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena", NeurIPS 2023.],
  [Evan Miller, "Adding Error Bars to Evals: A Statistical Approach to Language Model Evaluations", 2024.],
  [Bradley Efron and Robert Tibshirani, _An Introduction to the Bootstrap_, Chapman and Hall, 1993, chapters 6 and 13.],
)

== Labs

#lab([Prompt formats], goal: [Measure how much an accuracy depends on its prompt format.], time: [1.5 hours], code: "code/u3/evaluate.py")[
  + Score ARC-Easy with three formats: the harness's; one that lists the options with letters and scores the letter; and the harness's with the sum of log-probabilities instead of the mean.
  + Do it for the base and the fine-tuned 135M models.
  #done-when(
    [Your table has six accuracies with intervals.],
    [You can say whether the ranking of the two models depends on the format.],
  )
  #evidence([The table.])
]

#lab([How many questions?], goal: [Plan an evaluation's size from the difference you want to detect.], time: [1 hour], code: "code/aif/evals.py")[
  + From your ARC results, estimate the per-question standard deviation of the difference between the base and fine-tuned models.
  + Compute how many questions a paired comparison would need to detect a difference of one percentage point with 80% probability.
  + Check your estimate by subsampling ARC to that many questions repeatedly and counting how often McNemar's test is significant.
  #done-when(
    [Your computed and simulated answers agree within a factor of two.],
  )
  #evidence([The calculation and the simulation.])
]

#lab([Calibrating the judge], goal: [Compare the judge with your own judgement.], time: [2 hours], code: "code/u3/evaluate.py")[
  + Judge 40 of the harness's pairs yourself, blind to which model wrote which reply.
  + Compute the judge's agreement with you, averaged over both orders, and with the reward model of Chapter 3.4.
  + Test the judge's length bias by comparing each reply with a version padded by a neutral final paragraph.
  #done-when(
    [You have both agreement rates with intervals.],
    [You can state the judge's preference for padded replies with an interval.],
  )
  #evidence([Your judgements, the agreement rates and the padding test.])
]

#lab([Contamination by paraphrase], goal: [Find what overlap checks miss.], time: [1.5 hours], code: "code/u3/evaluate.py")[
  + For ARC's questions, find the nearest conversation in the fine-tuning shard by embedding similarity, using Chapter 3.7's embedding model or a simple bag of words.
  + Read the ten closest pairs and decide which are genuine paraphrases.
  #done-when(
    [You have the ten pairs with your judgement of each.],
    [You can state how many likely paraphrases the 13-word check missed.],
  )
  #evidence([The pairs and the count.])
]

#problems(
  [A model scores 55% on 400 questions and another 60% on the same questions. They disagree on 80 questions, 50 in favour of the second. Is the difference significant by McNemar's test?],
  [Why does the bootstrap resample questions, not answers? What would resampling the models' answers measure?],
  [A judge prefers whichever reply is shown first 70% of the time. Show that averaging over both orders removes the bias from a comparison, and say what it does to the comparison's variance.],
  [Why does scoring options by mean rather than total log-probability matter for questions whose options differ in length? When could it hurt?],
  [A benchmark's questions appear verbatim in a model's pretraining data. Describe two effects on its accuracy that could make the contamination hard to notice.],
)

#checklist(
  [I can score multiple-choice benchmarks by likelihood and explain the choices involved.],
  [I can compute bootstrap intervals and paired tests, and plan an evaluation's size.],
  [I can use a language-model judge while measuring and cancelling its biases.],
  [I can check a benchmark for contamination and explain the check's limits.],
  [Lab 3.6.1–3.6.4 done-when criteria all hold, with evidence filed.],
)
