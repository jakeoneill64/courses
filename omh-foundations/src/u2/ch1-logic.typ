#import "../lib/template.typ": *

= Digital logic <ch-logic>

#chapter-meta(
  weeks: [2 weeks],
  builds: [A CMOS inverter and NAND from discrete MOSFETs; a 4-bit adder in SN74HC logic with its ripple delay measured; a captured setup-time violation; a sequence detector designed with Karnaugh maps and built in gates; a small datapath in the Digital simulator.],
  needs: [Bench kit, logic analyser, 2N7000 and BS250 MOSFETs, the SN74HC logic set (00, 04, 08, 14, 32, 74, 86), DIP switches and LEDs, the Digital simulator.],
)

#why[
  Every SERDES, memory controller, BMC and glue FPGA in an OMH module is built from the objects in this chapter: gates, flip-flops and the timing constraints between them. "Timing closure", "metastability", "clock domain crossing" and "setup violation" are words you will hear from FPGA engineers and silicon vendors. After this chapter they are things you have caused on a breadboard and fixed.
]

#skip-test(
  rule: [If all five are easy, do Labs 2.1.1 and 2.1.3 only.],
  [Draw a CMOS NAND gate at the transistor level and explain why its output is driven strongly in both states.],
  [Given $t_"cq" = 1$ ns, $t_"logic" = 6$ ns, $t_"setup" = 0.5$ ns and $t_"hold" = 0.3$ ns, what is the maximum clock frequency? When does a hold violation occur, and does slowing the clock fix it?],
  [Why does a two-flop synchroniser reduce the metastability failure rate but not to zero? Write the MTBF expression.],
  [Design a Moore machine that detects the sequence 1-0-1 on a serial input. How many states? Is one-hot or binary encoding better on an FPGA, and why?],
  [Why does a 6T SRAM cell need exactly six transistors, and what are the two that are not part of the inverter pair for?],
)

== Core ideas

*Bits are voltage ranges with margins.* A 74HC input treats anything below $V_"IL"$ as 0 and above $V_"IH"$ as 1; outputs guarantee $V_"OL"$ and $V_"OH"$. The gap between an output's guarantee and an input's threshold is the noise margin, and it is what Chapter 1.1’s rail noise eats. Mixed 3.3 V and 5 V logic fails when $V_"OH"$ of one family is below $V_"IH"$ of the other; level shifters exist for that reason.

*CMOS: complementary pairs.* An N-channel MOSFET pulls low when its gate is high; a P-channel pulls high when its gate is low. Put them in series and parallel and you have an inverter, a NAND, a NOR. In steady state one network is off, so almost no current flows; power is spent charging and discharging capacitance at each transition. Dynamic power is roughly $C V^2 f$, which is why lowering voltage is the strongest lever and why a data-centre CPU's power scales with clock and activity.

#fig("/figures/u2-cmos-nand.svg", caption: [A CMOS NAND gate. The two P-channel transistors in parallel pull the output high if either input is low; the two N-channel transistors in series pull it low only when both are high. Lab 2.1.1 builds it from 2N7000 and BS250 parts.], width: 70%)

*NAND is universal.* Any Boolean function can be built from NANDs alone, or from NORs. Synthesis tools pick from a library of gates, but the fact that one gate suffices is why the problem is tractable.

*Boolean algebra and minimisation.* Sum of products, product of sums, De Morgan, Karnaugh maps and don't-cares. You will rarely minimise by hand after this chapter, but you must be able to read what a synthesiser did and judge whether it is what you meant.

*Combinational building blocks.* Multiplexer, decoder, encoder, comparator, half and full adder, ripple-carry adder, carry-lookahead, ALU. Ripple carry has delay linear in the width; lookahead is logarithmic at more area. This trade appears in every datapath.

*Propagation delay and the critical path.* Every gate takes time. The longest path from any input to any output is the critical path, and it bounds how fast the block can run. Synthesis timing reports are lists of critical paths.

*Latches and flip-flops.* Cross-coupled NANDs form an SR latch, the first bistable. Gate it with an enable and you have a D latch, transparent while enabled. Two latches back to back on opposite clock phases make an edge-triggered D flip-flop, which samples only at the clock edge. Sequential logic is combinational logic, flip-flops and one clock.

*Timing: setup, hold and the period constraint.* Data must be stable $t_"setup"$ before the edge and $t_"hold"$ after it. The period must satisfy $T >= t_"cq" + t_"logic,max" + t_"setup"$. Hold requires $t_"cq" + t_"logic,min" >= t_"hold"$, and the period does not appear, so a hold violation cannot be fixed by slowing the clock. Clock skew between two flops takes margin from one constraint and gives it to the other.

#fig("/figures/u2-setup-hold.svg", caption: [Setup and hold. Data launched by one clock edge must arrive $t_"setup"$ before the next and stay $t_"hold"$ after it. Lab 2.1.3 sweeps the data edge through this window and watches the flop fail.])

*Metastability.* Sample an input that is changing at the edge and the flop can sit between 0 and 1 for an unbounded time before resolving. You cannot prevent it for asynchronous inputs; you can make failure rare with a two-flop synchroniser, with $"MTBF" = e^(t_r \/ tau) \/ (T_0 f_"clk" f_"data")$, where $t_r$ is the time allowed to resolve. Every reset line, button and signal crossing between clock domains is asynchronous.

*Finite state machines.* A state register, next-state logic and output logic. Moore outputs depend on the state only; Mealy outputs also depend on the inputs. One-hot encoding uses more flops and simpler, faster logic, which is why it wins on FPGAs where flops are plentiful.

#fig("/figures/u2-fsm-101.svg", caption: [The Moore machine for Lab 2.1.4, detecting 1-0-1 with overlap. Each state is named for the longest useful suffix seen so far; only the final state asserts the output.], width: 82%)

*Registers, counters and shift registers.* A register is flops sharing a clock. A counter is a register plus an incrementer. A shift register moves bits one position per clock, and it is how UARTs, SPI and every serial protocol turn parallel into serial and back.

*Memory.* A 6T SRAM cell is two cross-coupled inverters and two access transistors, selected by a word line and read or written on bit lines. A register file is a small SRAM with several ports. A ROM is a decoder driving fixed pull-downs. Tri-state outputs let many blocks drive one wire at different times.

*Reset and asynchronous inputs.* Synchronous reset is a data input; asynchronous reset acts at once but its release must be synchronised or flops leave reset on different cycles. Glitches on combinational outputs between edges are harmless as long as nothing samples them, which is why clocked designs only look at the edge.

*Fan-out and loading.* Each input is a capacitor. Driving many inputs slows the edge; buffers restore drive.

== Reading

- Harris and Harris, _Digital Design and Computer Architecture_, RISC-V edition: chapter 1, chapter 2 (combinational), chapter 3 (sequential, especially 3.5 timing and 3.6 parallelism), chapter 5 sections 5.1 to 5.5.
- Nand2Tetris Part 1, projects 1 to 3. A weekend, worth it for the repetition.
- Ben Eater's 8-bit breadboard computer videos on the clock module, registers and the ALU. Watch for the debugging technique.
- Cummings, "Clock Domain Crossing (CDC) Design and Verification Techniques Using SystemVerilog", SNUG 2008. The first half now; the rest in Chapter 2.2.
- TI's SN74HC00, SN74HC74 and SN74HC14 datasheets: switching characteristics and the timing-waveform figures.

== Labs

#lab([Gates from transistors], goal: [see a bit come out of two switches.], time: [4 h], kit: [2N7000, BS250, potentiometer, multimeter, oscilloscope.])[
+ Build a CMOS inverter from a 2N7000 and a BS250 on 5 V. Drive the input from a potentiometer and plot $V_"out"$ against $V_"in"$ in 0.25 V steps. Find the switching threshold and the region of gain.
+ Build a two-input NAND (two P-channel in parallel, two N-channel in series). Verify its truth table with the meter.
+ Chain three inverters into a ring oscillator. Measure its frequency and compute the propagation delay per stage. Add 100 pF to one node and measure again.
+ Measure supply current at rest and while oscillating, and relate it to $C V^2 f$.

#done-when(
  [You have the transfer curve, the NAND truth table, and a measured delay per stage with an explanation of what limits it.],
  [The current measurement is reconciled with $C V^2 f$ to within a factor of two, with the capacitance estimated from the 100 pF experiment.],
)
#evidence([Transfer-curve plot; truth table; oscillator captures with and without the capacitor.])
] <lab-gates>

#lab([A 4-bit adder in SN74HC logic], goal: [build, time and then out-design a ripple-carry adder.], time: [6 h], kit: [SN74HC86N, SN74HC08N, SN74HC32N, DIP switches, LEDs with resistors.])[
+ Draw a full adder from XOR, AND and OR. Build four of them from SN74HC86N, SN74HC08N and SN74HC32N, with DIP switches for inputs and LEDs for sum and carry-out.
+ Verify against a table of 20 random additions.
+ Drive carry-in with a square wave and set $A = B = 1111$. Capture carry-in against carry-out and measure the ripple delay.
+ On paper, design 4-bit carry-lookahead logic. Count gate levels on the critical path against the ripple version.

#done-when(
  [The adder passes all 20 additions.],
  [The ripple delay is measured and compared with four times the datasheet's per-gate delays.],
  [The lookahead design is written with a gate-level delay comparison.],
)
#evidence([Wiring photograph; the addition table; delay capture; lookahead design.])
] <lab-adder>

#lab([Flip-flops and a setup-time violation], goal: [make timing physical.], time: [5 h], kit: [SN74HC00N, SN74HC74N, SN74HC14N, a potentiometer and capacitor for the adjustable delay, oscilloscope or logic analyser.])[
+ Build an SR latch from SN74HC00N gates, then a gated D latch, then a master-slave D flip-flop from two D latches. Verify each with switches.
+ Clock an SN74HC74N as a divide-by-two and confirm it on the scope.
+ Feed the SN74HC74N's D input from a signal derived from the clock through an adjustable RC delay, so that its edge sweeps across the clock edge as you turn the pot. Watch Q. Find the window where Q becomes unreliable: that window is setup plus hold.
+ Put two flops in series. Show the second flop's output is clean while the first misbehaves.

#done-when(
  [A capture shows the single flop failing, with the data-to-clock offset measured at the failure.],
  [The notebook explains why the two-flop version is better and why it is not perfect, using the MTBF expression.],
)
#evidence([Captures of the failure and of the two-flop result.])
] <lab-setup-violation>

#lab([A finite state machine in gates], goal: [go from a specification to hardware without code.], time: [5 h], kit: [SN74HC74N, gates, SN74HC14N for debouncing, push button.])[
+ Specify a 1-0-1 sequence detector as a Moore machine. Draw the state diagram and transition table; choose a binary encoding.
+ Derive next-state and output equations with Karnaugh maps.
+ Build it from SN74HC74N flops and gates, clocked by hand through a debounced button (RC plus SN74HC14N). Verify with sequences that include overlaps.
+ Redo the design on paper with one-hot encoding and compare the logic.

#done-when(
  [The breadboard machine detects 1-0-1 including overlapping occurrences.],
  [Both encodings are in the notebook with their equations and gate counts.],
)
#evidence([State diagram, K-maps, both sets of equations, a video or capture of a test sequence.])
] <lab-fsm>

#lab([A datapath in Digital], goal: [rehearse the objects Chapter 2.3 will need.], time: [6 h], kit: [The Digital simulator by hneemann.])[
+ Build an 8-bit register file with two read ports and one write port, an 8-bit ALU (add, subtract, and, or, xor, shift), and a multiplexer-based datapath connecting them.
+ Add a small ROM as instruction memory with a hand-assembled encoding of your design: opcode, destination and two sources.
+ Add a program counter and a decoder. Run a six-instruction program that shows a result on an LED array. Single-step it.

#done-when(
  [Your hand-encoded program runs and you can say what happens in each clock cycle.],
)
#evidence([The Digital file committed; a one-page description of your instruction encoding.])
] <lab-datapath>

== Problem set

+ Prove that NAND is functionally complete by constructing NOT, AND, OR and XOR from NANDs alone. Count gates for XOR.
+ A path has $t_"cq" = 0.8$ ns, combinational delay between 2.1 ns and 7.4 ns, $t_"setup" = 0.6$ ns and $t_"hold" = 0.4$ ns, and the receiving flop's clock arrives 0.5 ns after the sender's. Compute the maximum frequency and check hold. Repeat with the skew negated.
+ A synchroniser's flops have $tau = 30$ ps and $T_0 = 20$ ps; the clock is 200 MHz; the asynchronous input toggles at 10 MHz. Compute MTBF for one flop and for two in series.
+ Design a 3-bit Gray-code counter and argue why Gray code matters for the asynchronous FIFO pointers in Chapter 2.2.
+ A CMOS block switches 50 pF per cycle at 1.0 V and 3 GHz. Compute dynamic power, then at 0.8 V and 2.4 GHz. Why do server CPUs have dozens of voltage and frequency states?
+ Build a 4:1 multiplexer from a 2-to-4 decoder and AND-OR logic, then from three 2:1 multiplexers. Compare gate counts and delay.
+ From the SN74HC04 datasheet at 3.3 V, extract $V_"IH"$, $V_"IL"$, $V_"OH"$ and $V_"OL"$ and compute both noise margins. Repeat for an SN74HC output driving a 5 V SN74HCT input, and for an SN74HCT output driving a 3.3 V SN74LVC input; say which pairing is safe.
+ Show that a ripple-carry adder's delay grows linearly with width and a carry-lookahead adder's logarithmically. Where does the area go?
+ A single-cycle "data valid" pulse must cross from a 100 MHz domain to a 33 MHz domain. Why does a synchroniser alone lose pulses, and what handshake fixes it?

== Deliverables and stretch

*Deliverables.* The notebook with the transfer curve, the ripple delay, the setup-violation capture and the FSM derivation; the Digital datapath file, which Chapter 2.3 replaces with Verilog.

*Stretch.* Build a 4-bit SRAM from SN74HC573 latches with address decoding and SN74HC245 tri-state outputs, written and read from switches. Read the LVDS and CML sections of a SERDES primer and write half a page on why gigabit signalling abandoned single-ended CMOS levels.

#checklist(
  [*Lab 2.1.1:* transfer curve, NAND truth table, delay per stage, and the current reconciled with $C V^2 f$.],
  [*Lab 2.1.2:* adder verified on 20 cases; ripple delay measured against the datasheet; lookahead design written.],
  [*Lab 2.1.3:* a captured setup or hold failure with the offset measured; the two-flop result.],
  [*Lab 2.1.4:* the detector works with overlaps; both encodings derived.],
  [*Lab 2.1.5:* the Digital datapath runs a hand-assembled program.],
  [*Problem set:* all nine answered; problems 2 and 3 checked numerically.],
  [*You can explain*, without notes: why a hold violation is independent of the clock period, what metastability is and why synchronisers only reduce it, and why FPGAs prefer one-hot state machines.],
)
