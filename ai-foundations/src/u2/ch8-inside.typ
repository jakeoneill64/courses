#import "../lib/template.typ": *

= Inside the model <ch-inside>

#chapter-meta(
  time: [7 hours],
  builds: [Tools that record every attention pattern and switch heads off; the induction heads in Chapter 2.5's model, found by their attention and confirmed by ablation; the logit lens, which reads the model's developing prediction after every layer; and a linear probe that finds the model tracking whether it is inside a quotation, against an untrained control.],
  needs: [Chapters 2.3, 2.4 and 2.5.],
)

#why[
  A trained network's weights are millions of numbers that nobody wrote, and the model does things nobody programmed. _Interpretability_ asks what algorithms those weights implement. For transformers a few tools find real structure: attention patterns show where information moves, ablations test whether a component matters, the logit lens reads the prediction as it forms, and probes test whether a property is represented. This chapter uses them to find a specific mechanism in the course's model, confirm it causally, and discover a feature it learned unprompted. The same methods, scaled up, are how researchers audit large models.
]

#skip-test(
  rule: [If all four are easy, read the sections on the logit lens and on probing, and do Labs 2.8.2 and 2.8.4.],
  [What is the residual stream, and why can every layer read from and write to it?],
  [What does an induction head do, and why does it need two layers?],
  [What does the logit lens assume, and when does that assumption fail?],
  [What does a linear probe's accuracy show, and what does it not show?],
)

== Core ideas

=== The residual stream

In Chapter 2.4's pre-norm transformer, each block adds its attention's output and then its feed-forward network's output to a running vector at each position, and never overwrites it. That vector, the _residual stream_, is a shared channel: every component reads the sum of everything written before it and adds its own contribution. Attention is the only component that moves information between positions; the feed-forward networks transform it within a position. Reading the stream after each block shows what the model knows at each depth:

#snippet("aif/inspect.py", "residual", caption: [The residual stream after the embedding and after each block])

To look at attention, and to switch individual heads off, the program replaces each attention layer's forward pass, temporarily, with one that computes the attention weights explicitly, keeps them, and scales each head's output by a mask:

#snippet("aif/inspect.py", "recording", caption: [Recording attention weights, with an optional mask over heads])

=== Induction heads

Text repeats itself: a name, a phrase, a line of dialogue. A model that has seen "Lily went to the park" earlier in a story should predict "park" after a later "Lily went to the". The mechanism that does this, found by Anthropic's interpretability researchers, is the _induction head_: at the current token A, it attends to the token that followed an earlier occurrence of A, and copies it. It needs two heads in different layers. A _previous-token head_ in an earlier layer writes into each position the identity of the token before it; the induction head then searches with a query for "the current token" against keys for "the token before me", which only that earlier head's output makes available. Chapter 2.3's two-layer copying model learned a version of the same circuit.

The standard test strips away meaning: 100 random tokens, then the same 100 again, which a model with strong induction heads predicts almost perfectly the second time. The course's model barely does, as the last line of the console below shows. Children's stories almost never repeat a long passage word for word, so copying arbitrary sequences was never worth learning. What stories repeat is names, so the program writes short stories that mention an invented name three times, a capital and two lower-case pieces that appear in no story, such as "Elgenals":

#snippet("u2/induction.py", "names", caption: [Stories that mention an invented name three times])

At its first mention, the name's second and third tokens are unpredictable; at the later mentions, a model that copies can predict them from the first token. Each head's _induction score_ is its average attention, from the first token of the name's second mention, to the token that followed the first token of its first mention:

#snippet("u2/induction.py", "score", caption: [Attention to the token after the earlier occurrence, per head])

#fig("u2-induction", width: 80%, caption: [Induction scores of all 64 heads. Six heads of layer 7 and one of layer 4 put most of their attention exactly where the mechanism predicts; the rest put little.]) <fig-induction>

Attention shows where information could flow, not that the model depends on it. An _ablation_ tests that: switch the four highest-scoring heads off and measure the loss at the second mention again, then switch four other heads off instead, as a control.

#snippet("u2/induction.py", "ablate", caption: [Switching the induction heads off, and a control])

#console(read("/src/console/u2-induction.txt"), caption: [Induction in Chapter 2.5's model])

At the first mention, the name's later tokens cost 11.6 nats, more than a uniform guess over the vocabulary, because the model expects ordinary words there; at the second and third mentions they cost 5.8 and 5.5. The four strongest heads, three of them in layer 7, put three-quarters or more of their attention on the induction target. Switching them off raises the loss at the second mention to 12.9 nats, above the first mention's, so the copying is gone entirely, while switching off four other heads changes it by less than a tenth of a nat. The mechanism that a model trained on varied text applies to any repeated sequence is, in this model, specialised to the repetition its training data rewarded.

Induction heads are thought to underlie much of a model's _in-context learning_, its ability to use patterns from earlier in its prompt. In the models that Catherine Olsson and colleagues studied, they formed suddenly early in training, in a phase change visible as a bump in the loss curve, and Lab 2.8.2 looks for that moment in a model of your own.

=== The logit lens

The model's prediction is made by applying the final normalisation and the output layer to the residual stream after the last block. The _logit lens_ applies the same two operations after every block, reading off what the model would predict if it stopped there:

#snippet("u2/logit_lens.py", "lens", caption: [The lens: the final norm and the output layer, applied early])

#snippet("u2/logit_lens.py", "by-layer", caption: [The lens's loss after each block, on validation text])

#console(read("/src/console/u2-logit-lens.txt"), caption: [The prediction forming, layer by layer])

#fig("u2-logit-lens", caption: [Validation loss of the logit lens after each block. The embedding alone is off the scale: with tied embeddings, its lens predicts the current token itself.]) <fig-logit-lens>

The lens shows the prediction forming. The embedding alone predicts the current token, " her", as tied embeddings make it do. After the first block the model already has a plausible continuation, " mom", which the early blocks grow more confident about; the middle blocks move to " friends", and the last two to a toy and then toys, the finished model's answer. On validation text the lens's loss falls with every block, from 5.8 nats after the first to 1.3 after the last, with the largest single drop in the seventh. Each block refines the prediction it receives instead of computing a new one, which is what the residual stream makes possible.

The lens assumes that every layer writes its intermediate guesses in the same coordinates as the last. In this small model that holds well enough to read; in larger ones the early layers read poorly, and the _tuned lens_, which learns a small correction for each layer, does better. Lab 2.8.3 builds one.

=== Probing for a feature

Dialogue changes what comes next in a story: inside quotation marks the characters speak in the first person, and the quotation must be closed. Nothing in training labelled dialogue, yet a good model of stories should track it. A _linear probe_ tests whether it does: label every position by whether it is inside a quotation, and train a linear classifier to predict the label from the residual stream at each depth.

#snippet("u2/probe.py", "labels", caption: [Inside or outside a quotation, by counting quotation marks since the story began])

#snippet("u2/probe.py", "fit", caption: [A logistic-regression probe on standardised features])

A probe needs controls. Only about one position in nine is inside a quotation, so a probe that always answers "outside" is right about 89% of the time; and some tokens are far more common inside quotations, so even features that identify only the current token beat that base rate. The program therefore also probes a model with the same architecture and random weights.

#console(read("/src/console/u2-probe.txt"), caption: [Probe accuracy at each depth, for the trained model and an untrained one])

#fig("u2-probe", caption: [Probe accuracy against depth for the trained and untrained models, with the base rate of always answering "outside".]) <fig-probe>

Both probes on the embedding beat the base rate of 89%, because some tokens occur almost only inside quotations: the punctuation that closes a quotation, and first- and second-person words such as "I", "me" and "you". Beyond that, the two models part. The untrained model's probe falls slightly with depth, as random layers blur each token's identity, while the trained model's rises to 99.4% after layer 6 and stays close to it. Knowing whether a quotation is open requires counting quotation marks back to the start of the story, so the trained model computes that state, and keeps it where a linear readout can find it, through its middle and later layers.

A probe shows that information can be read linearly from the stream, not that the model uses it. Showing use needs an intervention, such as changing the stream along the probe's direction and watching the model's behaviour change, which Lab 2.8.4 attempts.

#hazard(title: [Pitfall])[
  Interpretations need controls. Compare a probe on a trained model with the base rate and with the same probe on an untrained model; compare an ablation with ablating random components of the same size. Without them, a probe finds structure in token identity and an ablation measures damage, not function.
]

#keyidea[
  The residual stream is a shared channel that every layer reads and writes. Attention patterns show where information moves, ablations test whether a component matters, the logit lens shows the prediction forming, and probes find what is linearly represented. With controls, they reveal mechanisms no one programmed: a two-head copying circuit and a tracker of dialogue.
]

#inpytorch(title: [In the libraries])[
  `register_forward_hook` records activations without replacing any code; this chapter replaces `forward` because it changes attention itself. TransformerLens provides named hooks on every activation of many open models, and nnsight does the same for any PyTorch model. Sparse autoencoders, trained on the residual stream to decompose it into many interpretable features, are the main current method for going beyond single probes.
]

#reading(
  [Nelson Elhage and others, "A Mathematical Framework for Transformer Circuits", Transformer Circuits Thread, 2021.],
  [Catherine Olsson and others, "In-context Learning and Induction Heads", Transformer Circuits Thread, 2022.],
  [nostalgebraist, "Interpreting GPT: the logit lens", 2020; and Nora Belrose and others, "Eliciting Latent Predictions from Transformers with the Tuned Lens", 2023.],
  [Guillaume Alain and Yoshua Bengio, "Understanding Intermediate Layers Using Linear Classifier Probes", 2016.],
  [Adly Templeton and others, "Scaling Monosemanticity: Extracting Interpretable Features from Claude 3 Sonnet", Transformer Circuits Thread, 2024.],
)

== Labs

#lab([Previous-token heads], goal: [Find the other half of the circuit.], time: [1.5 hours], code: "code/u2/induction.py")[
  + Score every head by its average attention to the immediately preceding position, on the program's stories.
  + Switch off the strongest previous-token heads and measure the loss at the name's second mention.
  #done-when(
    [You can name the previous-token heads and their layers, and they lie below the induction heads.],
    [You have the ablation's effect, compared with a control.],
  )
  #evidence([The scores and the losses.])
]

#lab([When they form], goal: [Catch induction heads forming during training.], time: [2 hours], code: "code/u2/pretrain.py")[
  + Train the small preset on 20 million tokens, saving a copy of the model every 100 steps; change the checkpoint's file name to include the step so that copies are kept.
  + For each copy, measure the loss at the second mention of the invented names and the best induction score, and plot both with the training loss.
  #done-when(
    [Your plot shows the three curves over training.],
    [You can name the step at which induction appears, and say whether the training loss shows a bump there.],
  )
  #evidence([The plot.])
]

#lab([A tuned lens], goal: [Read early layers better.], time: [2 hours], code: "code/u2/logit_lens.py")[
  + For each layer, train a $d times d$ matrix, starting from the identity, applied to the residual stream before the lens, to minimise the KL divergence from the model's final distribution on training windows.
  + Compare the tuned lens's validation loss at each depth with the logit lens's.
  #done-when(
    [You have both curves.],
    [You can say at which depths the tuned lens helps most, and why the last layer gains nothing.],
  )
  #evidence([The plot.])
]

#lab([Steering by a direction], goal: [Test whether the dialogue feature is used.], time: [1.5 hours], code: "code/u2/probe.py")[
  + Take the difference between the mean residual stream inside and outside quotations at the layer where the probe is best.
  + Add a multiple of it to the stream at that layer during generation, at three strengths, and read the stories.
  #done-when(
    [You have samples at each strength.],
    [You can say whether adding the direction makes the model open or continue dialogue, and what that shows that the probe could not.],
  )
  #evidence([The samples and the conclusion.])
]

#problems(
  [Why can a model with one layer of attention not implement an induction head, using only the token and position information available to its keys?],
  [The invented names' second and third tokens are drawn uniformly from about 1,100 lower-case pieces. What loss does a model that knows only that have on them at the first mention, and what does a perfect copier have at the second? Why does the course's model do worse than the first at the first mention?],
  [With tied embeddings, the logit lens on the embedding layer predicts the current token. Show why, from the dot product between a token's embedding and every row of the output layer.],
  [The probe's labels are 11% "inside". What accuracy does always answering "outside" achieve, and why can an untrained model's probe do better?],
  [Ablating a head raises a loss by less than the head's role might suggest. Give two reasons why ablation can understate a component's importance.],
)

#checklist(
  [I can explain the residual stream, and read it after every block.],
  [I can find heads by their attention patterns and test them by ablation, with controls.],
  [I can explain how two heads compose into an induction head.],
  [I can apply the logit lens and a linear probe, and say what each shows and does not show.],
  [Lab 2.8.1–2.8.4 done-when criteria all hold, with evidence filed.],
)
