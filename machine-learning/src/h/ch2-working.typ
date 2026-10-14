#import "../lib/template.typ": *

= How to work <h-working>

== The anatomy of a chapter

Every chapter has the same parts, in the same order.

- *The header* gives the study time, what you build, and what the chapter needs: earlier chapters, tools, hardware.
- *Why it matters* says what the chapter is for, in the course and in real machine-learning work.
- *The skip test* is four questions. If you can answer them all without looking anything up, skim the core ideas and do the labs the test names. If any is hard, work through the whole chapter.
- *Core ideas* teaches the material, in order, from first principles. Listings come from the companion code, and console listings from real runs. Callouts mark what to watch for: _Key idea_ for the central point, _Derivation_ for the mathematics worked in full, _Pitfall_ for mistakes that are easy to make, and _In PyTorch_ for how the library does what the chapter built.
- *Reading* lists the primary sources: the papers that introduced the ideas, book chapters and documentation. Read at least the abstract, method and main results of each paper with the chapter.
- *Labs* are the main part of the course. Each has a goal, a time, the code it starts from, numbered steps, _done-when_ criteria and the evidence to keep.
- *The problem set* tests understanding without a computer.
- *The completion checklist* lists what you should now be able to do. Tick a line only when you can do it.

Each unit ends with a sign-off page: a table of its chapters and a short unit review, a set of tasks to do from memory.

== Labs and done-when criteria

A lab is finished only when every done-when criterion holds. The criteria are measurable on purpose: a check passes, a loss falls below a value, an accuracy lies within a range, an explanation fits in two sentences. If you cannot meet one, the lab has shown you something you do not yet understand.

The times are what the lab takes a careful engineer who has done the reading, not counting unattended training. Some will take longer on your machine, especially the first time a tool misbehaves, so allow for that.

== The notebook and the evidence

Keep a notebook, on paper or in plain text files in a repository: for every lab, the date, what you did, what you measured, what surprised you, and the evidence each lab asks for. Keep your code in version control with one commit per lab, so that you can return to any state.

Machine learning makes this habit more important than in most programming. A training run is an experiment with many settings, and its result depends on all of them. Without a record of the settings you cannot explain or repeat the result, and within a month you will have forgotten them.

== Running experiments

The companion code follows rules that make experiments trustworthy, and your own code should follow them too.

- *Every program checks itself.* It verifies its result against an independent calculation, a reference library or an invariant, prints what it found, and exits with a non-zero status if a check fails.
- *Seeds are fixed.* Every program seeds its random number generators, so a rerun on the same machine gives the same numbers, or nearly the same, because some GPU operations are not deterministic. The text notes where that matters.
- *Settings are explicit.* Programs take options such as `--lr 2e-3` or `--epochs 8`, and print or log what they used. Chapter 2.5's training program, the longest run, writes a log of every setting and every measurement to `runs/<name>/log.jsonl`. The others print theirs.
- *One change at a time.* When comparing two settings, change only one thing between runs, and keep a baseline run you trust.
- *Small first.* Before a long run, run the same program for a few steps with a tiny model, to find bugs in minutes instead of hours. `u2.pretrain --preset tiny` exists for this purpose.
- *Long runs resume.* Chapter 2.5's run, the longest, saves checkpoints and can be restarted with `--resume` after an interruption.

== Measuring properly

Many labs ask for timings. Computers are hard to time well, and a careless measurement is worse than none, because it gives a wrong number that looks reliable.

- *Synchronise before you stop the clock.* GPU work runs asynchronously: a PyTorch call returns as soon as the work is queued. `aif.device.sync` waits for it to finish, and every timing in the course calls it.
- *Warm up, repeat, and report the median.* The first run of anything includes compilation, memory allocation and clock ramp-up. `aif.timing.median_time` runs a function several times and reports the median.
- *Measure on an idle machine.* A training run in the background, a video call or a browser full of tabs distorts every number. Laptops also change speed with their power source and temperature, so measure on mains power.
- *Name the machine.* Record the processor, the GPU, the memory and the library versions with every number. `uv run -m aif.selftest` prints them all.

== Reading papers

New methods in machine learning are published as papers, and the course asks you to read about fifty of them. A first pass takes thirty minutes: the abstract, the introduction's last paragraph, the method's main equations, and the main table of results. Ask what the paper claims, what evidence supports it, and what it compared against. A second pass, for the papers a chapter is built on, works through the method with a pen. The reading lists say which is which by placing the essential papers first.

== Getting unstuck

When something goes wrong, work through these in order.

+ *Read the whole error.* Python's traceback names the line, and PyTorch's shape errors name both shapes, which is enough to solve most problems.
+ *Print shapes and values.* Most bugs in machine-learning code are shapes that broadcast unintentionally or values that are not what you think. Check both at every step of the failing computation.
+ *Make it smaller.* Remove everything that does not affect the failure until what remains fits on a screen: a tiny model, one batch, one step. The cause is then usually obvious, and if it is not, the small case makes a good question to ask someone.
+ *Check against a reference.* Every component in the course has a reference: central differences, PyTorch, Hugging Face. Compare yours with it on the same inputs, one component at a time.
+ *Debug the training as well as the code.* If the code runs but the model trains badly, use the method of Chapter 1.7: check the initial loss, overfit one batch, and read the gradient and activation statistics.
