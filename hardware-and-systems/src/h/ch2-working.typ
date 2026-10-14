#import "../lib/template.typ": *

= How to work <h-working>

== The anatomy of a chapter

Every chapter has the same parts in the same order, so you always know where you are.

- *The strip under the title* gives the time the chapter takes, what you will have built at the end, and exactly what it needs from the kit.
- *What this buys OMH* says why the chapter is in a course for a server company. Read it first, because it tells you what to pay attention to.
- *The skip test* is five questions. If you can answer all five cold, in writing, and would be comfortable being questioned on them, its rule tells you which labs to do, and you can skim the rest. Answer honestly, because most of the learning happens in the labs.
- *Core ideas* is the theory you need for the labs, with figures. It is deliberately dense, and each paragraph covers something you will use.
- *Reading* names specific chapters and sections. Read them before the lab that needs them.
- *Labs* make up most of the course. Each has a goal, a time estimate and a kit line, then numbered steps, then *done when* criteria and an *evidence* list.
- *The problem set* checks the theory with numbers. Answer every problem in writing with units, and check each numerical answer a second way.
- *Deliverables and stretch* list what goes into your labs repository, and what to do if you have time to spare.
- *The completion checklist* has one line per lab, one for the problem set and one for what you can explain without notes.

Each unit ends with a *sign-off* page: a table of its chapters and a set of review tasks that test whether you can connect the unit's ideas.

== The completion standard

A lab is done when every *done when* line holds and every item in its evidence list exists. A chapter is done when every line of its checklist is ticked. A unit is done when its sign-off page is complete. Do not move on with a line unticked. If something outside your control blocks a line (a part out of stock, a board at fabrication), write the reason and the date in the notebook, mark the line as deferred, and come back to it. A deferred line does not count as ticked.

Each criterion is a measurable statement, such as "the measured corner is within 5 % of the design and the plot overlays the simulation". A statement such as "the filter works" is too vague to check. You may meet a criterion by a route the lab did not describe, provided you write down what you did.

== The lab notebook

Keep one Markdown file per chapter in your labs repository. For every lab, record:

+ the date and the goal in one line;
+ the set-up, with a photograph and the instrument settings;
+ your prediction before you measure, with the arithmetic;
+ the measurement, with raw data saved as files and named in the entry;
+ the result against the prediction, and an explanation of every discrepancy larger than your stated uncertainty;
+ what you would do differently.

Scope captures go in `captures/`, raw data as CSV in `data/`, and every plot is produced by a script in `scripts/` that reads the raw data, so you can regenerate it. The notebook is also the raw material for OMH's engineering blog, through which a hardware company with no customers can earn credibility.

```text
## Lab 1.2.2  A second-order filter and its Bode plot   2026-11-14
Goal: Sallen-Key low-pass near 1 kHz, measured against its design.
Set-up: TLV2372IP on 5 V, R = 11 kΩ, C1 = 22 nF, C2 = 10 nF (measured below).
Prediction: fc = 1/(2π R √(C1 C2)) = 976 Hz, Q = 0.74; −40 dB/decade above.
Measured: data/bode-2026-11-14.csv; fc = 951 Hz (−2.6 %).
Discrepancy: C1 measures 22.9 nF; recomputed fc = 956 Hz, within 0.6 %.
Next time: measure every capacitor before building.
```

== The labs repository

Create one Git repository for the coursework, with a directory per chapter and a short README in each that links that chapter's evidence.

```text
omh-labs/
  u1/1.1-electricity/    notebook.md  captures/  data/  scripts/  sim/
  u1/1.3-sensors/        notebook.md  sensors/   data/  scripts/
  u2/2.2-fpga/           rtl/  tb/  formal/  constraints/
  u2/2.6-firmware/       firmware/  bootloader/  tools/
  u3/3.2-radio/          firmware/  ground/  sdr/
  u3/3.4-boards/         board-p/  board-f/  board-a/  board-b/  reviews/
  u3/3.5-drone/          flight/  sim/  logs/  test-cards/
  u4/4.3-drivers/        opt4048/  ads1220/  emc2101/  fpga-spi/
  u4/4.7-module-zero/    design-notes/  image/  control-plane/
```

Commit small and often, with messages that say what changed and why. Tag the commit that completes each chapter (`ch-2.6-done`), so the sign-off table can point at it.

== Habits

*Read the datasheet before any tutorial.* When a lab involves a chip, read its datasheet or reference manual chapter first and only then look at anyone else's code. OMH's engineers will routinely work from primary sources alone, for parts that have no tutorials.

*Write your own version before you use an abstraction.* Chapter 2.6 forbids TI's driverlib, Chapter 2.3 comes before any SoC generator, and your `/dev/kvm` program comes before kvmtool. Two chapters allow vendor code for set-up only and say so: C2000Ware's driverlib for peripheral initialisation in Chapter 3.1, and TI's RF driver with SysConfig settings in Chapter 3.2. Afterwards, use whatever you like and read it critically.

*Predict, then measure.* Write the number you expect before you look at the instrument. Without a prediction, a measurement cannot test your understanding.

*Treat the instrument as part of the measurement.* Chapters 1.1, 1.5 and 3.3 each include a measurement in which the instrument gives a misleading result. Learn an instrument's limits before you rely on its readings.

*Debug by bisection.* Reproduce the failure, make it smaller, measure at the midpoint, and compare with what the datasheet says should be there. When you ask for help, attach the evidence. TI's E2E forums, the EEVblog forum and the kernel mailing lists all answer questions that show the work.

*Order early and keep a supply-chain log.* Note what you ordered, when, the lead time quoted and the lead time delivered. Chapter 4.6’s cost model starts from that log.
