# Module 3: HDL and FPGA

**Part I · 3 weeks · Needs: ULX3S (or alternative), OSS CAD Suite, logic analyser, Nucleo or Pico for Lab 3.6.**

## Why this module (and what it buys OMH)

An OMH module will contain programmable logic somewhere: drive-bay backplane control,
LED and presence signalling, power sequencing glue, or a test rig for a CXL or NVMe
interface. More importantly, every controller chip you buy is a design like the ones
you will write here, and its datasheet describes registers, clock domains and FIFOs that
only make sense if you have built them. The register-map peripheral from Lab 3.4 is the
seed of a chain that runs through Module 7 (a microcontroller drives it), Module 11 (a
Linux driver exposes it) and Module 16 (it sits on Module Zero's management board).

## Skip test

1. What is the difference between `=` and `<=` inside `always_ff`, and what goes wrong
   if you mix them?
2. Why can a synthesiser infer a latch from an `always_comb` block, and how do you make
   that impossible?
3. Describe how an asynchronous FIFO's full and empty flags are computed safely across
   two clock domains.
4. A path fails timing by 1.2 ns at 100 MHz. List four ways to fix it, in the order
   you would try them.
5. What is the difference between a multicycle path constraint and a false path, and
   why does lying to the tool about either produce hardware that works on the bench
   and fails in the field?

If all five are easy, do Labs 3.3 and 3.6 only.

## Core ideas

**HDL describes hardware, not a program.** Every statement exists at once. A module
is a circuit; instantiating it twice makes two circuits. Coming from C++, the most
important habit is to think about what flops and gates a line becomes, not what it
"executes".

**Two kinds of block.** `always_ff @(posedge clk)` describes flip-flops; use
non-blocking `<=` so that all right-hand sides are sampled before any left-hand side
updates, which is exactly how real flops behave. `always_comb` describes gates; use
blocking `=`, assign every output on every path (or give a default) so no latch is
inferred. Signals assigned in one block are never assigned in another.

**Simulation and synthesis are different consumers.** Verilator compiles your design
into C++ for fast cycle-based simulation; you drive it from a C++ testbench, which
your background makes natural. Icarus is slower but event-driven and handles more
of the language. Synthesis (Yosys) turns the same source into a netlist of LUTs and
flops; not everything simulable is synthesisable (`#delay`, `initial` on non-FPGA
targets, unbounded loops).

**FPGA architecture.** Look-up tables (typically 4 to 6 inputs) implement any small
Boolean function; each pairs with a flip-flop; carry chains make adders fast; block
RAM provides dense memory with registered ports; DSP blocks do multiply-accumulate;
PLLs synthesise clocks; I/O blocks handle voltage standards and serialisation. Routing
between them is programmable and consumes most of the die and most of the delay. The
bitstream configures all of it at power-on from flash.

**Timing analysis.** You state the clock period in a constraints file (SDC or the
vendor equivalent). The tool computes every path from flop to flop and reports slack:
required time minus arrival time. Negative slack is a failing path. Nextpnr's report
is Module 2's Lab 2.3 for ten thousand paths at once. Place-and-route is an
optimisation problem, so results vary run to run; a design that "just" passes is a
design that will fail on the next build.

**Clock domain crossing.** Any signal moving between unrelated clocks is asynchronous
to the receiver. Single bits get a two-flop synchroniser. Multi-bit values must not be
synchronised bit by bit, because the bits arrive on different cycles; use a handshake,
or a FIFO with Gray-coded pointers so only one bit changes per increment. This is the
single most common source of "works for hours then corrupts" bugs.

**Reset.** Synchronise reset release. Decide per design whether flops reset at all;
on FPGAs, initial values from the bitstream often remove the need, and un-reset
datapaths are smaller and faster.

**Interfaces and buses.** Wishbone (simple, open) and AXI-Lite (industry standard, more
signals) are memory-mapped register buses: address, data, strobe or valid, ready or
ack. AXI-Stream is for data flowing without addresses. Every SoC peripheral you will
ever read a datasheet for is one of these behind a register map. Write your register
map down before your RTL; it is the contract with software.

**Formal verification.** SymbiYosys uses SAT solvers to prove properties of your design
for all inputs up to a bound, or forever with induction. For FIFOs, arbiters and
protocol handlers it finds bugs that simulation never reaches. You will prove your
FIFO cannot overflow.

**Parameterisation and reuse.** `parameter` and `generate` give you templates. Keep
peripherals generic in width and depth; you will instantiate them in Module 4.

**Which language.** SystemVerilog's synthesisable subset with Verilator is the
industry default and the course default. VHDL is equally capable and common in
defence and Europe. Amaranth (Python) and Chisel (Scala) generate Verilog and make
large parameterised designs pleasant; LiteX builds whole SoCs from Python. Learn SV
first so you can read everyone else's code, then use a generator when you want to.

**Vendor tools.** Vivado (AMD/Xilinx), Quartus (Intel/Altera), Radiant (Lattice) exist
because the open flow covers only some parts. You will meet them whenever a board uses
a big FPGA. The concepts are identical; the constraints syntax and the GUI are not.

## Reading

- Harris and Harris, DDCA RISC-V ed., ch. 4 (HDL). Read the SystemVerilog columns.
- ZipCPU blog (Dan Gisselquist): "Building a simple UART", "Crossing clock domains",
  "Building a formally verified asynchronous FIFO", and the formal verification
  tutorial. The best applied writing on FPGA design available.
- Cummings, "Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!"
  and "Simulation and Synthesis Techniques for Asynchronous FIFO Design" (SNUG).
- Yosys manual ch. 1 to 3; nextpnr README; the ULX3S constraints file and examples
  repository; Verilator manual sections on the C++ testbench flow.
- Wishbone B4 spec (short) and the AXI4-Lite chapter of the AMBA AXI spec.

## Labs

### Lab 3.1: Toolchain, blink, and a timing failure on purpose

1. From scratch (no example project): a top module with a PLL from the 25 MHz input to
   100 MHz, a 27-bit counter, LEDs on the top bits. Write the LPF constraints file by
   hand from the ULX3S schematic. Build with Yosys, nextpnr-ecp5, ecppack; load with
   openFPGALoader.
2. Read the nextpnr timing report end to end. Find the critical path and the slack.
3. Add a 64-bit combinational multiply feeding a flop. Rebuild. Read the negative
   slack. Fix it by pipelining. Then fix it instead by lowering the PLL frequency and
   note which fix you would choose and why.

Done when: the LEDs count, and your notebook has both timing reports with the
critical paths annotated.

### Lab 3.2: UART transmitter and receiver

1. Write the register map first: TX data, RX data, status (tx busy, rx valid, framing
   error), baud divisor.
2. Implement TX (8N1) as an FSM with a shift register and a baud counter. Verilator
   testbench in C++ that decodes the serial line and checks the byte.
3. Implement RX with oversampling (16×) and mid-bit sampling. Testbench sends bytes
   with slightly wrong baud rates and checks the tolerance.
4. Formal: prove with SymbiYosys that when a start bit is detected, exactly eight data
   bits are sampled and the stop bit is checked.
5. On hardware: echo at 115200 through the on-board FTDI. Capture the wire with the
   logic analyser and decode with PulseView.

Done when: echo works, the formal proof passes, and you have measured the baud
tolerance in simulation.

### Lab 3.3: Asynchronous FIFO with a formal proof

1. Implement a parameterised async FIFO: Gray-coded write and read pointers, two-flop
   synchronisers for the pointers crossing domains, full and empty computed in the
   correct domain.
2. Testbench with two unrelated clocks (e.g. 100 MHz and 37 MHz), random bursts, and a
   scoreboard that checks order and count.
3. Formal: prove that the FIFO never overflows or underflows and that data is delivered
   in order. Use induction so the proof is unbounded.
4. Deliberately break the Gray coding (use binary pointers) and show the formal tool
   finds the counterexample.

Done when: the proof passes with induction and the broken version fails with a trace
you can explain.

### Lab 3.4: A memory-mapped peripheral

1. Define a Wishbone (or AXI-Lite) slave with this register map at 32-bit granularity:
   GPIO output, GPIO input, GPIO direction, timer counter, timer compare, timer
   control, interrupt status, interrupt enable, and an ID register that returns a
   constant.
2. Implement it. Testbench acts as bus master, walks the map, checks read-after-write,
   checks the timer counts and raises the interrupt line at compare.
3. Write the register map as a table in markdown with bit fields, reset values and
   access type. This document is the contract with Modules 4, 7 and 11.

Done when: the testbench passes and the register document is committed.

### Lab 3.5: Video pattern generator

1. Generate 640×480 timing (or 1280×720 if the PLL cooperates) and output over the
   ULX3S's HDMI (GPDI) pins using the DVI-style TMDS encoder from the examples, or
   drive a PMOD VGA.
2. Add a framebuffer in block RAM (character or tile mode, since a full bitmap will not
   fit) and draw text. Compute the BRAM budget before you start and check it against
   the nextpnr utilisation report.
3. Add a Wishbone interface so the framebuffer is writable from the bus (Lab 3.4 style).

Done when: text you wrote appears on a monitor, and utilisation matches your estimate.

### Lab 3.6: The register map over SPI

1. Implement an SPI slave (mode 0) with a simple transaction format: one command byte
   (read/write plus address), then data bytes. Bridge it to the Wishbone bus from
   Lab 3.4 so every register is reachable over SPI.
2. Handle the clock domain properly: SPI clock is asynchronous to your system clock.
   Either synchronise SCLK edges into the system domain (fine at low SPI speeds) or run
   the shift register in the SCLK domain and cross the finished byte with a handshake.
3. Drive it from a Pico or Nucleo using a quick vendor-SDK program (this is the one
   place vendor code is allowed before Module 7, because the point is the FPGA side).
   Toggle a GPIO on the FPGA from the microcontroller. Read the ID register.
4. Route the interrupt line to a GPIO on the microcontroller.
5. Capture a full transaction on the logic analyser and annotate it.

Done when: registers read and write over SPI, the timer interrupt is visible on the
microcontroller, and the annotated capture is in your notebook.

## Problem set

1. Write an `always_comb` block that accidentally infers a latch. Explain the fix.
   Write an `always_ff` block where a blocking assignment produces a simulation
   result that differs from synthesis.
2. A 320×240 8-bit framebuffer: how many block RAMs of 18 kbit does it need? How many
   for 640×480 at 4 bits? Which fits an ECP5-85F (which has 208 such blocks)?
3. Derive the baud counter for 115200 from a 100 MHz clock. What is the frequency error
   in percent, and how does that error accumulate across a 10-bit frame? Compare with
   a 48 MHz clock.
4. List three ways a multi-bit signal crossing clock domains can be corrupted even
   when each bit passes through a two-flop synchroniser.
5. Write SDC constraints for a design with a 100 MHz system clock, a 12 MHz SPI clock
   treated as asynchronous, and a path from a configuration register that changes
   only once at start-up. Name the constraint for the last one and say why it is
   legitimate.
6. Your UART receiver oversamples at 16× and samples at the eighth tick. The
   transmitter's clock is 3% fast. At which data bit does sampling drift into the
   wrong bit cell?
7. Why is a FIFO's "empty" flag safe to compute in the read clock domain but not the
   write clock domain? What goes wrong if you compute "full" in the read domain?
8. The nextpnr report shows a path through 14 LUTs and a carry chain. Estimate how many
   pipeline stages would bring it under 5 ns, and what the throughput and latency
   costs are.

## Deliverables

- UART, FIFO, register-map peripheral, SPI bridge, all with testbenches and the
  FIFO and UART with formal proofs, in your labs repo.
- The register map document.
- Annotated logic analyser capture of an SPI transaction.

## Stretch

- Reimplement the FIFO in Amaranth and compare the generated Verilog to yours.
- Build a small LiteX SoC for the ULX3S with a VexRiscv core and look at how LiteX
  generates the register map and the C headers. You will build your own core next;
  seeing a finished one clarifies the target.
- Read the ECP5 SERDES documentation and write a page on what a "lane" is physically.

## Next

Module 4 builds a CPU from these parts. Your Wishbone peripheral becomes its first
memory-mapped device; your UART becomes its console.
