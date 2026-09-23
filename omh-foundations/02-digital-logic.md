# Module 2: Digital logic

**Part I · 2 weeks · Needs: Core tier kit, Digital (hneemann) simulator.**

## Why this module (and what it buys OMH)

Every SERDES, memory controller, BMC and glue FPGA in a module is built from the
objects in this module: gates, flip-flops, and the timing constraints between them.
"Timing closure", "metastability", "clock domain crossing" and "setup violation" will
be words you hear from FPGA engineers and silicon vendors. After this module they are
things you have caused on a breadboard and fixed.

## Skip test

1. Draw a CMOS NAND gate at the transistor level and explain why the output is strong
   in both states.
2. Given t_cq = 1 ns, t_logic = 6 ns, t_setup = 0.5 ns and t_hold = 0.3 ns, what is the
   maximum clock frequency? Under what condition does a hold violation occur, and does
   slowing the clock fix it?
3. Why does a two-flop synchroniser reduce the metastability failure rate but not to
   zero? Write the MTBF expression.
4. Design a Moore FSM that detects the sequence 1-0-1 on a serial input. How many
   states? Is one-hot or binary encoding better on an FPGA and why?
5. Why does a 6T SRAM cell need exactly six transistors, and what are the two that are
   not part of the inverter pair for?

If all five are easy, do Labs 2.1 and 2.3 only.

## Core ideas

**Bits are voltage ranges with margins.** A 74HC input treats anything below V_IL as 0
and above V_IH as 1; outputs guarantee V_OL and V_OH. The gap between an output's
guarantee and an input's threshold is the noise margin, and it is what Module 1's rail
noise eats. Mixed 3.3 V and 5 V logic fails when V_OH of one family is below V_IH of the
other; level shifters exist for that reason.

**CMOS: complementary pairs.** An NMOS pulls low when its gate is high; a PMOS pulls
high when its gate is low. Put them in series and parallel and you have an inverter, a
NAND, a NOR. In steady state one network is off, so almost no current flows; power is
spent charging and discharging capacitance on each transition. Dynamic power is
roughly C·V²·f, which is why lowering voltage is the most effective lever and why a
data-centre CPU's power scales with clock and activity.

**NAND is universal.** Any Boolean function can be built from NANDs alone (or NORs). In
practice synthesis tools pick from a library of gates, but the fact that one gate
suffices is why the problem is tractable.

**Boolean algebra and minimisation.** Sum of products, product of sums, De Morgan,
Karnaugh maps, don't-cares. You will rarely minimise by hand after this module, but
you must be able to read what a synthesiser did and judge if it is what you meant.

**Combinational building blocks.** Multiplexer, decoder, encoder, comparator, half and
full adder, ripple-carry adder, carry-lookahead, ALU. Ripple-carry is O(n) delay in
the width; lookahead is O(log n) at more area. This trade appears in every datapath.

**Propagation delay and the critical path.** Every gate takes time. The longest path
from any input to any output is the critical path and bounds how fast the block can
run. Synthesis reports are lists of critical paths.

**Latches and flip-flops.** Cross-coupled NANDs form an SR latch: the first bistable.
Gate it with an enable and you have a D latch, transparent while enabled. Put two
latches back to back on opposite clock phases and you have an edge-triggered D
flip-flop, which samples only at the clock edge. Sequential logic is combinational
logic plus flip-flops plus one clock.

**Timing: setup, hold, and the clock period constraint.** Data must be stable t_setup
before the edge and t_hold after it. The clock period must satisfy
T ≥ t_cq + t_logic(max) + t_setup. Hold requires t_cq + t_logic(min) ≥ t_hold, and
notice that period does not appear, so a hold violation cannot be fixed by slowing the
clock. Clock skew between two flops eats margin from one constraint and gives it to
the other.

**Metastability.** Sample an input that is changing right at the edge and the flop can
sit between 0 and 1 for an unbounded time before resolving. You cannot prevent it for
asynchronous inputs; you can make failure rare with a two-flop synchroniser, and the
MTBF expression tells you how rare. Every reset line, button, and signal crossing
between clock domains is asynchronous.

**Finite state machines.** State register plus next-state logic plus output logic.
Moore outputs depend on state only; Mealy outputs also depend on inputs. One-hot
encoding uses more flops but simpler, faster logic, which is why it wins on FPGAs
where flops are plentiful.

**Registers, counters, shift registers.** A register is parallel flops sharing a
clock. A counter is a register plus an incrementer. A shift register moves bits one
position per clock, and it is how UARTs, SPI and every serial protocol turn parallel
into serial and back.

**Memory.** A 6T SRAM cell is two cross-coupled inverters and two access transistors,
selected by a word line and read or written on bit lines. A register file is a small
SRAM with multiple ports. ROM is a decoder driving fixed pull-downs. Tri-state
outputs and shared buses let many blocks drive one wire at different times, which is
how memory buses worked before point-to-point serial links took over.

**Reset and asynchronous inputs.** Synchronous reset is a data input; asynchronous
reset acts immediately but its release must be synchronised or flops come out of
reset on different cycles. Glitches on combinational outputs are normal between
edges and are harmless as long as nothing samples them, which is why clocked designs
only look at the edge.

**Fan-out and loading.** Each input is a capacitor. Driving many inputs slows the
edge. Buffers exist to restore drive.

## Reading

- Harris and Harris, *Digital Design and Computer Architecture*, RISC-V ed.,
  ch. 1 (all), ch. 2 (combinational), ch. 3 (sequential, especially 3.5 timing and
  3.6 parallelism), ch. 5 (building blocks: 5.1 to 5.5).
- Nand2Tetris Part 1, projects 1 to 3 (gates, ALU, memory in their HDL). A weekend;
  worth it for the sheer repetition.
- Ben Eater's 8-bit breadboard computer videos on the clock module, registers and the
  ALU. Watch for the debugging technique, not to build the whole thing.
- Cummings, "Clock Domain Crossing (CDC) Design and Verification Techniques Using
  SystemVerilog" (SNUG 2008). Read the first half now; the rest in Module 3.

## Labs

### Lab 2.1: Gates from transistors

Goal: see a bit come out of two switches.

1. Build a CMOS inverter from a 2N7000 and a BS250 on 5 V. Drive the input from a
   potentiometer and plot V_out against V_in in 0.25 V steps. Find the switching
   threshold and the gain region.
2. Build a two-input NAND (two PMOS in parallel, two NMOS in series). Verify the truth
   table with the meter.
3. Chain three inverters into a ring oscillator. Measure the frequency on the scope and
   compute the per-stage propagation delay. Add a 100 pF load to one node; observe.
4. Measure supply current at rest and while oscillating. Relate to C·V²·f.

Done when: you have the transfer curve, the truth table, and a measured propagation
delay with an explanation of what limits it.

### Lab 2.2: A 4-bit adder in 74HC

Goal: build, time, and then out-design a ripple-carry adder.

1. Draw a full adder from XOR, AND and OR. Build four of them from 74HC86, 74HC08 and
   74HC32. Wire DIP switches for inputs and LEDs for the sum and carry-out.
2. Verify against a table of 20 random additions.
3. Drive the carry-in with a square wave and A = B = 1111. Scope carry-in against
   carry-out and measure the ripple delay.
4. On paper, design 4-bit carry-lookahead logic. Count gate levels on the critical
   path versus the ripple version. Build it if you have the ICs.

Done when: the adder is correct, the ripple delay is measured, and the lookahead
design is written with a delay comparison.

### Lab 2.3: Flip-flops and a setup-time violation

Goal: make timing physical.

1. Build an SR latch from two 74HC00 gates. Then a gated D latch. Then a master-slave
   D flip-flop from two D latches. Verify with switches.
2. Using a 74HC74, clock a divide-by-two and confirm on the scope.
3. Feed the 74HC74's D input from a signal that changes near the clock edge: derive
   D from the clock itself through an adjustable RC delay so that its transition
   sweeps across the edge as you turn the pot. Watch Q on the scope. Find the window
   where Q becomes unreliable. That window is setup plus hold, seen live.
4. Replace the single flop with two in series. Show that the second flop's output is
   clean even when the first is misbehaving.

Done when: you have a scope capture of the flop failing and a written explanation of
why the two-flop version is better and why it is not perfect.

### Lab 2.4: A finite state machine in gates

Goal: go from a specification to hardware without writing code.

1. Specify a 1-0-1 sequence detector as a Moore machine. Draw the state diagram and
   the transition table. Choose a binary encoding.
2. Derive the next-state and output equations with K-maps.
3. Build it from 74HC74 flops and gates. Clock it manually with a debounced button
   (RC plus 74HC14 Schmitt inverter). Verify with sequences.
4. Redo the design with one-hot encoding on paper. Compare the logic.

Done when: the breadboard machine detects the sequence, and your notebook has both
encodings with the equations.

### Lab 2.5: A datapath in Digital

Goal: rehearse the objects Module 4 will need.

1. In Digital (hneemann), build an 8-bit register file with two read ports and one
   write port, an 8-bit ALU (add, sub, and, or, xor, shift), and a mux-based datapath
   connecting them.
2. Add a small ROM as "instruction memory" with a hand-assembled encoding of your
   own design: opcode, destination, two sources.
3. Add a program counter and a decoder. Run a 6-instruction program that computes
   something visible on an LED array. Single-step it.

Done when: your hand-encoded program runs in the simulator and you can explain what
happens in each clock cycle.

## Problem set

1. Prove that NAND is functionally complete by constructing NOT, AND, OR and XOR
   from NANDs alone. Count gates for XOR.
2. A path has t_cq = 0.8 ns, combinational delay between 2.1 ns (min) and 7.4 ns
   (max), t_setup = 0.6 ns, t_hold = 0.4 ns, and the receiving flop's clock arrives
   0.5 ns later than the sending flop's. Compute the maximum frequency and check hold.
   Now make the skew negative and repeat.
3. A synchroniser has flops with resolution time constant τ = 30 ps and a metastability
   window T_0 = 20 ps, the clock is 200 MHz and the asynchronous input toggles at
   10 MHz. Compute MTBF for one flop and for two in series.
4. Design a 3-bit Gray-code counter: state diagram, next-state equations, and an
   argument for why Gray code matters for the async FIFO pointers you will build in
   Module 3.
5. A CMOS block has 50 pF of switched capacitance per cycle at 1.0 V and 3 GHz.
   Compute dynamic power. What does it become at 0.8 V and 2.4 GHz? Why do server
   CPUs have dozens of voltage and frequency states?
6. Build a 4:1 mux from a 2-to-4 decoder and AND-OR logic, then from three 2:1
   muxes. Compare gate counts and delay.
7. From the 74HC04 datasheet at 3.3 V, extract V_IH, V_IL, V_OH, V_OL and compute the
   high and low noise margins. Repeat for a 74HC output driving a 5 V-only
   74HCT input, and a 74HCT output driving a 3.3 V 74LVC input; say which pairing is
   safe.
8. Show that a ripple-carry adder's delay grows linearly with width and a
   carry-lookahead adder's grows logarithmically. Where does the area go?
9. A design has a 100 MHz domain and a 33 MHz domain. A single-bit "data valid"
   pulse must cross from fast to slow. Why does a synchroniser alone lose pulses,
   and what handshake fixes it?

## Deliverables

- Notebook with the transfer curve, ripple delay, setup-violation capture, and the FSM
  derivation.
- The Digital datapath file committed to your labs repo. Module 4 will replace it
  with Verilog.

## Stretch

- Build a 4-bit SRAM from 74HC latches with address decode and tri-state outputs
  (74HC245). Read and write it from switches.
- Read the LVDS and CML sections of a SERDES primer and write half a page on why
  gigabit signalling abandoned single-ended CMOS levels entirely.

## Next

Module 3 replaces the breadboard with a hardware description language and an FPGA. Every
concept here maps directly: `always_ff` is a flip-flop, `always_comb` is gates, the
timing report is Lab 2.3 at scale.
