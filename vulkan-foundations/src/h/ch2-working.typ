#import "../lib/template.typ": *

= How to work <h-working>

== The anatomy of a chapter

Every chapter has the same parts, in the same order.

- *The header* gives the study time, what you build, and what the chapter needs: earlier chapters, tools, hardware.
- *Why it matters* says what the chapter is for, in the course and in real GPU work.
- *The skip test* is four or five questions. If you can answer them all without looking anything up, skim the core ideas and do the labs the test names. If any is hard, work through the whole chapter.
- *Core ideas* teaches the material, in order, from first principles. Listings come from the companion code, and console listings from real runs. Callouts mark what to watch for: _Key idea_ for the central point, _Pitfall_ and _Hazard_ for mistakes that are easy to make, and _Coming from OpenGL_ for the comparison.
- *Reading* lists the primary sources: sections of the specification, the Vulkan Guide, papers and vendor documents. Read them with the chapter, not afterwards.
- *Labs* are the heart of the course. Each has a goal, a time, the code it starts from, numbered steps, _done-when_ criteria and the evidence to keep.
- *The problem set* tests understanding without a computer.
- *The completion checklist* lists what you should now be able to do. Tick it honestly.

Each unit ends with a sign-off page: a table of its chapters and a short unit review, a set of tasks to do from memory.

== Labs and done-when criteria

A lab is finished when every done-when criterion holds, not when the steps have been followed. The criteria are measurable on purpose: a program passes its own check with validation on, a number falls within a range, a message has been recorded, an explanation fits in two sentences. If you cannot meet one, the lab has found something you do not yet understand, which is what labs are for.

The times are what the lab takes a careful engineer who has done the reading. Some will take longer on your machine, especially the first time a tool misbehaves; budget for it.

== The notebook and the evidence

Keep a notebook, on paper or in plain text files in a repository: for every lab, the date, what you did, what you measured, what surprised you and the evidence each lab asks for. Keep your code in version control with one commit per lab, so that you can return to any state.

The notebook is how you notice that a measurement does not match the last one, and how you explain a result months later. It is also the record that the sign-off pages refer to.

== Using the companion code

The companion code is complete: every project builds and passes its own checks. Most labs ask you to change it, extend it or break it on purpose. Work in a copy, and when a lab asks you to write something new, write it yourself before you look at any reference: the point is the attempt. When you compare afterwards, look for differences in approach, not only in output.

The code follows a few rules you can rely on:

- *Every program checks itself.* It verifies its results against a CPU reference or an invariant, prints a result line, and exits with a non-zero status on failure.
- *Validation is on by default.* Programs run with the validation layer and synchronisation validation enabled, and fail if the layer reports an error. Set `VKF_VALIDATION=0` only to measure performance.
- *Options are explicit.* Programs take options such as `--n 1000000` or `--out image.png`, and their defaults run in a few seconds.
- *Comments are rare.* The volumes explain the code; a comment in the code states only something the volumes cannot, such as a gotcha or a constraint.

== Measuring properly

Many labs ask for timings. GPUs are hard to time well, and a careless measurement is worse than none, because it looks like knowledge.

- *Turn validation off.* The validation layers slow every API call, and synchronisation validation slows submission considerably. Every timing in the course is taken with `VKF_VALIDATION=0`.
- *Time the GPU on the GPU.* Wall-clock time around a submission includes the driver, the operating system and the wait. Timestamp queries, introduced in Chapter 2.5, measure the work on the device itself.
- *Warm up, repeat, and report the median.* The first run of anything includes compilation, page faults and clock ramp-up. Run several times and report the median, with the spread.
- *Know your clocks.* GPUs change clock speed with load and temperature, and laptops change it with power source. Measure on mains power, with the machine otherwise idle, and say so.
- *Name the machine.* Record the GPU, the driver version and the operating system with every number.

== Getting unstuck

When something goes wrong, work through these in order.

+ *Read the validation message.* Find the VUID it cites in the specification, and read the rule in context. Most problems end here; Chapter 1.6 shows how.
+ *Make it smaller.* Remove everything that does not affect the failure until what remains fits on a screen. The result is usually obvious, and if not, it is a good question to ask someone.
+ *Look at the GPU's state.* Capture the program with RenderDoc, or with Xcode on macOS, and inspect the buffers and images before and after the failing command. Print from the shader with debug printf.
+ *Check the specification, then the Vulkan Guide.* The specification is long but precise, and its valid-usage lists answer most questions about what is allowed.
+ *Compare with the companion code.* The reference version of each project shows one correct way to do it.

When a program behaves differently on two machines, suspect undefined behaviour first: a missing barrier, an uninitialised image, an out-of-bounds access. Conformant drivers run a valid program the same way, apart from documented differences such as floating-point precision; an invalid program they may run however they like.
