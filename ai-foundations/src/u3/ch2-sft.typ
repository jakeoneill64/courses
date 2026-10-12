#import "../lib/template.typ": *

= Supervised fine-tuning <ch-sft>

#chapter-meta(
  time: [6 hours],
  builds: [Ten thousand conversations from the SmolTalk dataset, rendered with the chat template and masked so that only the assistant's words carry the loss; batches of similar lengths, padded; a full fine-tune of SmolLM2-135M's base model on the M2 Pro; and its replies compared with the base model's and with the instruction-tuned model its authors published.],
  needs: [Chapter 3.1.],
)

#why[
  A base model has learned language, facts and patterns from trillions of tokens, but not the habit of answering. _Supervised fine-tuning_ teaches that habit by training on example conversations, and it is the first and most important step from a base model to an assistant: every later step of this unit starts from its result. It is also easy to do subtly wrong, and the errors do not crash: train on the user's words as well as the assistant's and the model learns to write questions; forget the template's end marker and it never stops talking.
]

#skip-test(
  rule: [If all four are easy, read the section on what fine-tuning teaches and do Labs 3.2.2 and 3.2.3.],
  [What is loss masking in fine-tuning, and what goes wrong without it?],
  [Why batch conversations by length, and why is padding on the right harmless for a causal model?],
  [Why is a fine-tuning learning rate usually lower than a pretraining one?],
  [Name two things a model cannot learn from supervised fine-tuning on a few thousand conversations.],
)

== Core ideas

=== From conversations to training examples

A conversation is a list of messages, each with a role and content. Rendered with the chat template of Chapter 3.1, it becomes one sequence of tokens, and fine-tuning trains on it with the same next-token loss as pretraining, with one change: only some tokens count. The system's and the user's messages are context to condition on, not text to imitate, so their tokens get the label $-100$, which the loss ignores. The assistant's replies, including the `<|im_end|>` that ends each reply, carry the loss; learning to produce that token is how the model learns to stop.

#snippet("aif/chat.py", "masked", caption: [Tokens and labels for one conversation])

The loss compares the label at each position with the model's prediction from the position before it, so the labels are shifted by one relative to the inputs, as in pretraining:

#snippet("aif/finetune.py", "logprobs", caption: [Log-probabilities of the labelled tokens, and the masked mean loss])

=== The data

SmolTalk is the dataset SmolLM2's authors built for this step: about a million conversations, mostly written by larger models to cover instruction following, writing, coding, mathematics and multi-turn dialogue, with a version for the smallest models, smol-smoltalk, that leaves out tasks too hard for them. The program takes the first 10,000 conversations of one shard, keeps those with at least one assistant token after truncation to 1,024 tokens, and holds out 500 conversations of the test split.

#snippet("u3/sft.py", "data", caption: [Training and test examples])

=== Batching by length

Conversations vary from a few dozen tokens to a thousand, and a batch must be a rectangle. Padding every sequence to the longest in the batch wastes the computation spent on padding, so the program sorts the conversations by length and cuts the sorted list into batches of about 4,096 tokens each, a few long conversations or many short ones, then shuffles the batches. Each optimiser step accumulates the gradients of four batches, as in Chapter 2.5, and so learns from about 16,384 tokens: one batch that large would need more than 40 GB, most of it for the activations of 30 layers and the logits over a vocabulary of 49,152 tokens. Padding goes on the right, after each conversation's real tokens: in a causal model no real token can attend to positions after it, so padding changes nothing that matters, and its labels are $-100$.

#snippet("aif/finetune.py", "batches", caption: [Batches of similar lengths, and padding])

=== Training

#snippet("u3/sft.py", "loop", caption: [One epoch of fine-tuning])

Fine-tuning starts from a model that is already good, and the goal is to adjust it without destroying what it knows, so the learning rate is a tenth or less of pretraining's: here $10^(-4)$, with a short warm-up, cosine decay and gradient clipping. No weight decay is applied: decay pulls weights towards zero, not towards the pretrained values, and over one epoch it would only add noise. Every parameter is trained, 135 million of them, with AdamW's state: about 2 GB, easily within the M2 Pro's memory. Chapter 3.3 shows how to train a small fraction instead.

#console(read("/src/console/u3-sft.txt"), caption: [Fine-tuning SmolLM2-135M on 10,000 conversations, and three models' replies])

Fine-tuning lowers the held-out loss on the assistant's tokens from 1.626 to 1.343 nats in 80 minutes on the M2 Pro. SmolLM2's own instruction-tuned model, which its authors trained on far more and more varied conversations, reaches 1.050. The replies show the change more plainly than the loss. The base model treats each request as the start of a document and loops, repeating the question or numbering empty lines. The fine-tuned model answers in the assistant's turn and in the register of its training data, and its Python function is correct. It also shows the limits of a small model: its haiku repeats "soft" instead of scanning, and its account of boiling is fluent and wrong. So is the official model's, which explains boiling by claiming that air pressure is lower at sea level than at altitude.

=== What fine-tuning teaches

Fine-tuning on ten thousand conversations changes the model's behaviour far more than its knowledge. It learns the format, to answer in the assistant's turn and stop; a register, helpful and structured; and some skills that were latent in pretraining, such as following an instruction to write a haiku. It cannot learn much that pretraining did not already put in the weights: a model that does not know a fact will still answer, fluently and wrongly, in the new format. That observation, sometimes called the _superficial alignment hypothesis_, explains why a few thousand carefully chosen conversations can be as effective as a million mediocre ones, and why the base model's quality bounds the assistant's.

Fine-tuning also teaches only what the examples show. It never shows the model what a _worse_ answer looks like, so it cannot teach it to prefer better answers among several plausible ones; Chapter 3.4 adds that. And it imitates the training data's answers token by token, including their mistakes, rather than rewarding correct results however they are reached; Chapter 3.5 adds that.

#hazard(title: [Pitfall])[
  The chat template used in fine-tuning must be the one used in deployment, byte for byte, including whitespace and the end-of-turn token. A model fine-tuned with one template and prompted with another is in a situation it never saw, and degrades in ways that look like a weak model rather than a bug.
]

#keyidea[
  Supervised fine-tuning is pretraining's loss on conversations, with the user's tokens masked so that only the assistant's carry the loss. It teaches format and behaviour cheaply, and relies on the base model for knowledge.
]

#inpytorch(title: [In the libraries])[
  Hugging Face's TRL library provides `SFTTrainer`, which renders conversations with the tokeniser's chat template, masks everything but the assistant's turns when asked to, and can _pack_ several conversations into each sequence, with attention masks or variable-length kernels that stop them attending to each other. That packing is more efficient than this chapter's length bucketing, and correct only with those masks.
]

#reading(
  [Long Ouyang and others, "Training Language Models to Follow Instructions with Human Feedback", NeurIPS 2022, sections 3.1 to 3.5: the supervised step of InstructGPT.],
  [Chunting Zhou and others, "LIMA: Less Is More for Alignment", NeurIPS 2023.],
  [Loubna Ben Allal and others, "SmolLM2: When Smol Goes Big", 2025, section on SmolTalk.],
)

== Labs

#lab([Seeing the mask], goal: [Check what carries the loss.], time: [1 hour], code: "code/aif/chat.py")[
  + Render one multi-turn conversation from the training set, and print each token with its label, marking the masked ones.
  + Confirm that the system and user turns, the role headers and the newline after each `<|im_end|>` are masked, and that each assistant reply and its `<|im_end|>` are not.
  #done-when(
    [Your printout shows the mask exactly as described, or you have found and explained a difference.],
  )
  #evidence([The printout of one conversation.])
]

#lab([Without the mask], goal: [See what training on the user's words does.], time: [1.5 hours], code: "code/u3/sft.py")[
  + Fine-tune with every token labelled, then compare the held-out loss on assistant tokens with the masked run.
  + Generate replies to ten prompts and look for replies that continue as the user, or that ask questions instead of answering.
  #done-when(
    [You have both held-out losses.],
    [You can show at least one behaviour that differs between the two models, with examples.],
  )
  #evidence([The losses and the examples.])
]

#lab([How much and how fast], goal: [Map fine-tuning's sensitivity to data and learning rate.], time: [2 hours], code: "code/u3/sft.py")[
  + Fine-tune with 5,000 and 20,000 conversations, at learning rates of $3 times 10^(-5)$, $10^(-4)$ and $3 times 10^(-4)$.
  + Record the held-out loss of each run, and the base model's loss on a slice of TinyStories before and after, as a measure of forgetting.
  #done-when(
    [Your table has six held-out losses and six forgetting measurements.],
    [You can recommend a setting and say what the highest learning rate cost.],
  )
  #evidence([The table and the recommendation.])
]

#lab([Your own style], goal: [Teach a model a style from a small dataset of your own.], time: [2 hours], code: "code/u3/sft.py")[
  + Write 50 short conversations in a distinctive style, for example answers that always end with a one-line summary, as a JSON Lines file in the chat format.
  + Add two options to the program: one that starts from a saved run's `model.pt` instead of a model on the Hub, and one that reads conversations from your file instead of smol-smoltalk.
  + Fine-tune your Chapter 3.2 model on them for a few epochs, at a low learning rate, and test it on ten new prompts.
  #done-when(
    [At least eight of ten replies show the style.],
    [The model still answers correctly the questions it answered correctly before.],
  )
  #evidence([The dataset, the ten replies and the before-and-after comparison.])
]

#problems(
  [A conversation has a system message of 30 tokens, a user turn of 50 and an assistant reply of 120, plus template tokens. How many positions carry the loss?],
  [Why does the label of the newline after `<|im_end|>` not matter much, and why does the label of `<|im_end|>` itself matter a lot?],
  [With 4,096 tokens per batch and conversations of 300 tokens on average, how many conversations does a batch hold? How much is wasted on padding if lengths within a batch vary by 10%?],
  [Why might fine-tuning on answers written by a larger model make a small model worse at some tasks?],
  [Fine-tuning for many epochs on a small dataset lowers the training loss to near zero. What happens to held-out loss, and what does the model do?],
)

#checklist(
  [I can render conversations with a chat template and mask everything but the assistant's replies.],
  [I can batch variable-length sequences efficiently and explain why right padding is safe.],
  [I can fine-tune a model and evaluate it on held-out conversations and by its replies.],
  [I can explain what supervised fine-tuning can and cannot teach.],
  [Lab 3.2.1–3.2.4 done-when criteria all hold, with evidence filed.],
)
