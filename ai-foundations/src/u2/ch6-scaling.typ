#import "../lib/template.typ": *

= Scaling laws <ch-scaling>

#chapter-meta(
  time: [6 hours, and about three hours of the GPU's time],
  builds: [Fifteen training runs at three compute budgets, five model sizes at each; the best size and loss at each budget, found by fitting isoFLOP curves; power laws fitted to the optima; and a prediction of the best loss at a budget four times larger, checked by training the model it recommends.],
  needs: [Chapters 2.4 and 2.5.],
)

#why[
  A large model is trained once, at great cost, and its size and the amount of data it sees must be chosen before the run starts. Scaling laws make that choice from cheap experiments: across many orders of magnitude, a language model's loss falls as a smooth power law in the compute spent on it, so a sweep of small runs predicts a large one. They decided the sizes of the models in use today and the number of tokens each was trained on. This chapter fits a scaling law on the course's data and model, and tests it.
]

#skip-test(
  rule: [If all four are easy, read the sections on the sweep and on what the laws are for, and do Labs 2.6.1 and 2.6.3.],
  [About how many FLOPs does training a model of $N$ parameters on $D$ tokens take, and where does the factor come from?],
  [What is an isoFLOP curve, and why does it have a minimum?],
  [What did the Chinchilla study conclude about dividing compute between parameters and tokens?],
  [Why are many widely used models trained on far more tokens than is compute-optimal?],
)

== Core ideas

=== Compute

Training a model with $N$ parameters on $D$ tokens costs about
$ C approx 6 N D $
FLOPs. The forward pass multiplies and adds each parameter once per token, 2 FLOPs; the backward pass computes gradients with respect to both the activations and the parameters, twice the forward work. Attention adds a term that grows with the sequence length, and Chapter 2.4's `train_flops_per_token` counts it, with the embedding counted once as the output layer's matrix multiplication. For a fixed budget $C$, a larger model sees proportionally fewer tokens.

=== Power laws

Jared Kaplan and colleagues found in 2020 that a transformer's loss, when nothing else limits it, falls as a power of the parameters, of the data and of the compute, each over several orders of magnitude: a straight line on logarithmic axes. Jordan Hoffmann and colleagues, training more than 400 models for the Chinchilla study of 2022, fitted the loss of a model of $N$ parameters trained on $D$ tokens as
$ L(N, D) = E + A / N^alpha + B / D^beta, $
with $E$ the irreducible loss, the entropy of the text itself, and two terms that shrink as the model and the data grow. Minimising it under the constraint $C = 6 N D$ gives an optimal size and token count that both grow as a power of the budget, and Chinchilla's exponents were both close to $1\/2$: double the compute, and the model and its data should each grow by about $sqrt(2)$, at about 20 tokens per parameter.

=== IsoFLOP curves

The most direct way to find the optimal size is to fix a budget, train several sizes on it, each with $D = C \/ (6 N)$ tokens, and see which reaches the lowest loss. Too small a model cannot represent what the data contains; too large a model has not seen enough of it. Plotted against $log N$, the losses at a fixed budget form a valley, an _isoFLOP curve_, and a parabola fitted to it locates the bottom. Repeating at several budgets gives the optimal size $N^*(C)$ and loss $L^*(C)$, and straight lines fitted to their logarithms give the power laws.

#snippet("u2/scaling.py", "shapes", caption: [Nine shapes, from 0.6M to 19M parameters, and the five trained at each budget])

The runs use sequences of 256 tokens and attention heads of 32 dimensions so that the smallest models remain sensible transformers, and every run is Chapter 2.5's training with its own warm-up and cosine schedule, ending at its own budget. That last detail matters: Kaplan's study used a schedule of fixed length for runs of every length, which made short runs look worse than they are and pushed its recommended models to be larger and its data smaller, a bias that Chinchilla's corrected.

#snippet("u2/scaling.py", "run", caption: [One run of the sweep, at a given shape and budget])

#snippet("u2/scaling.py", "isoflop", caption: [Parabolas through each budget's losses, then power laws through their minima])

=== The sweep

```bash
uv run -m u2.scaling
```

#console(read("/src/console/u2-scaling.txt"), caption: [Fifteen runs, the fitted laws, and the prediction checked])

#fig("u2-scaling", caption: [Left, the isoFLOP curves: validation loss against model size at three budgets, with fitted parabolas and their minima. Right, the best loss at each budget on logarithmic axes, the fitted power law extended to four times the largest budget, and the run that tested it.]) <fig-scaling>

Every budget has a clear valley, and its bottom moves to larger models as the budget grows: about 1.7M parameters at $10^14$ FLOPs, 3.0M at $4 times 10^14$ and 5.0M at $1.6 times 10^15$ (@fig-scaling). The best size grows as $C^0.39$, more slowly than Chinchilla's $C^(1\/2)$, so the best number of tokens grows faster, from about 6 tokens per parameter at the smallest budget to 7 and then 11, all below Chinchilla's 20. Neither difference is surprising at this scale. The counts include the embedding table, which with a vocabulary of 8,192 holds 84% of the smallest model's parameters and 31% of the largest's, and every run uses the same learning rate, which suits some sizes better than others; Labs 2.6.2 and 2.6.4 measure both effects.

The best loss falls as $C^(-0.110)$, and extrapolated to $6.4 times 10^15$ FLOPs it predicts 1.470 for a model of about 8.6M parameters. The nearest shape, 8.46M parameters, trained at that budget reaches 1.561, 5.8% above the prediction. The miss has a clear cause. Each fourfold increase in compute cut the best loss by 17%, then by 11%, and the test run's by 10%: the gains shrink as the loss approaches the entropy of the text itself, the floor $E$ of Chinchilla's law, and a straight line on logarithmic axes has no floor. Fitted to all fifteen runs, the three-term law of Lab 2.6.1 puts the floor near 1.27 nats and predicts the test run within about 1%.

=== What the laws are for

Scaling laws answer the planning question, what size of model for this budget, and they predict the result before it is paid for. Groups that train large models fit laws like this chapter's on small runs of their own data and architecture, and they also use them to compare ideas: a change to the architecture or the data that shifts the whole line down is worth the same as a multiple of the compute.

Compute-optimal is optimal for training only. A model is trained once and then used, perhaps for trillions of tokens, at a cost per token proportional to its size, so a smaller model trained on more data than is compute-optimal can be cheaper over its life. Meta's Llama 3 8B was trained on 15 trillion tokens, nearly 2,000 per parameter; SmolLM2-135M, which Unit 3 uses, on 2 trillion, about 15,000 per parameter. Loss keeps falling with more tokens at a fixed size, only more slowly, and the laws say how slowly.

The laws have limits. They hold for one corpus, tokeniser, architecture and recipe, and must be refitted when any of them changes. They assume fresh data: repeating data costs little for a few epochs and then quickly stops helping, so the largest runs are now constrained by the supply of good text. And they predict loss, not abilities: some capabilities appear to arrive suddenly with scale, although much of that suddenness comes from all-or-nothing measures of success that hide steady improvement underneath.

#hazard(title: [Pitfall])[
  A power law fitted over one or two orders of magnitude can be extrapolated a little, not far. Small errors in the exponent grow with the distance, and effects that the fit never saw, such as running out of unique data or an unstable learning rate at large width, appear at scale. Test a prediction at a budget just beyond the fit, as this chapter does, before trusting it further.
]

#keyidea[
  Loss falls with compute roughly as a power law, flattening as it nears the entropy of the text. At a fixed budget there is a best model size, which grows as a power of the budget, and a sweep of small runs fits both laws and predicts a larger run. Deployed models are often trained well beyond compute-optimal, because a smaller model is cheaper to use.
]

#inpytorch(title: [In practice])[
  `torch.utils.flop_counter.FlopCounterMode` counts the FLOPs of any PyTorch model, a check on hand-derived formulas such as `train_flops_per_token`. `scipy.optimize.curve_fit` fits the three-term law to a set of runs, as Lab 2.6.1 does. Parametrisations such as µP make the best learning rate transfer from small models to large ones, which keeps a sweep's small runs honest about the large one.
]

#reading(
  [Jared Kaplan and others, "Scaling Laws for Neural Language Models", 2020.],
  [Jordan Hoffmann and others, "Training Compute-Optimal Large Language Models", NeurIPS 2022: the Chinchilla study.],
  [Niklas Muennighoff and others, "Scaling Data-Constrained Language Models", NeurIPS 2023: what repeated data is worth.],
  [Greg Yang and others, "Tensor Programs V: Tuning Large Neural Networks via Zero-Shot Hyperparameter Transfer", 2022: µP.],
)

== Labs

#lab([The three-term law], goal: [Fit Chinchilla's parametric form to your runs.], time: [2 hours], code: "code/u2/scaling.py")[
  + Fit $L(N, D) = E + A \/ N^alpha + B \/ D^beta$ to all sixteen runs, by least squares on the losses.
  + Minimise the fitted law at a budget of $6.4 times 10^15$ FLOPs, and compare the optimal size with the isoFLOP method's.
  #done-when(
    [You have the five fitted constants.],
    [The two methods' optimal sizes agree within a factor of two, or you can explain why they do not.],
  )
  #evidence([The fit and the comparison.])
]

#lab([Counting parameters], goal: [See how the choice of what to count changes the law.], time: [1 hour], code: "code/u2/scaling.py")[
  + Refit the optimal-size power law using the parameters without the embedding.
  + Compare the two exponents and the scatter of the optima about each line.
  #done-when(
    [You have both exponents.],
    [You can say which count gives the cleaner law for these models, and why the embedding matters more for small ones.],
  )
  #evidence([The two fits.])
]

#lab([Smaller and longer], goal: [Measure the price of a model smaller than compute-optimal.], time: [2 hours], code: "code/u2/scaling.py")[
  + Train a model about a quarter of the predicted optimal size at $6.4 times 10^15$ FLOPs on the same budget, then on twice and four times the budget.
  + Find the compute at which it matches the optimal model's loss, by interpolation.
  #done-when(
    [Your table has the three runs.],
    [You can state the extra training compute the smaller model needs, and the number of tokens served after which it is the cheaper choice overall.],
  )
  #evidence([The table and the calculation.])
]

#lab([One learning rate for all], goal: [Test an assumption of the sweep.], time: [2 hours], code: "code/u2/scaling.py")[
  + At a budget of $4 times 10^14$ FLOPs, train the smallest and the largest of that budget's shapes with learning rates of $10^(-3)$, $3 times 10^(-3)$ and $10^(-2)$.
  + Record the six losses.
  #done-when(
    [You can say whether the best learning rate depends on size here.],
    [You can say which way a size-dependent best rate would bias the fitted exponent.],
  )
  #evidence([The six losses and the argument.])
]

#problems(
  [With $C = 6 N D$ and 20 tokens per parameter, what size and token count are compute-optimal at $10^24$ FLOPs?],
  [If the best loss falls as $C^(-0.05)$, how much more compute lowers it by 10%?],
  [Explain why the backward pass costs about twice the forward pass's FLOPs for a linear layer.],
  [Generating a token costs about $2 N$ FLOPs. A model will serve $10^13$ tokens. Compare the lifetime compute of a compute-optimal model with that of one half its size trained on enough extra tokens to match its loss, if that takes twice the training compute.],
  [Why does a fixed-length learning-rate schedule bias a sweep towards larger models?],
)

#checklist(
  [I can count training FLOPs and plan runs at a fixed compute budget.],
  [I can find compute-optimal sizes from isoFLOP curves and fit power laws to them.],
  [I can predict a larger run's loss from small ones and test the prediction.],
  [I can explain why deployed models are trained beyond compute-optimal, and the limits of scaling laws.],
  [Lab 2.6.1–2.6.4 done-when criteria all hold, with evidence filed.],
)
