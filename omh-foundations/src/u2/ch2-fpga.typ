#import "../lib/template.typ": *

= HDL and FPGA <ch-fpga>

#chapter-meta(
  weeks: [3 weeks],
  builds: [A hand-constrained blinky with a deliberate timing failure; a UART with a formal proof; an asynchronous FIFO proved with induction; a memory-mapped peripheral with a written register map; that register map bridged to SPI and driven from the Raspberry Pi.],
  needs: [ULX3S FPGA board, OSS CAD Suite (Yosys, nextpnr, Verilator, SymbiYosys), logic analyser, Raspberry Pi 5.],
)

#why[
  An OMH module will contain programmable logic: drive-bay backplane control, LED and presence signalling, power sequencing glue, or a test rig for a CXL or NVMe interface. More importantly, every controller chip you buy is a design like the ones you write here, and its datasheet describes registers, clock domains and FIFOs that only make sense once you have built them. The register-map peripheral from Lab 2.2.4 starts a thread that runs through Chapter 2.6 (a microcontroller drives it), Chapter 3.4 (a stretch respin puts an ECP5 on the management board) and Chapter 4.3 (a Linux driver exposes it).
]

#skip-test(
  rule: [If all five are easy, do Labs 2.2.3 and 2.2.5 only.],
  [What is the difference between `=` and `<=` inside `always_ff`, and what goes wrong if you mix them?],
  [Why can a synthesiser infer a latch from an `always_comb` block, and how do you make that impossible?],
  [Describe how an asynchronous FIFO's full and empty flags are computed safely across two clock domains.],
  [A path fails timing by 1.2 ns at 100 MHz. List four ways to fix it in the order you would try them.],
  [What is the difference between a multicycle-path constraint and a false path, and why does lying to the tool about either produce hardware that works on the bench and fails in the field?],
)

== Core ideas

*HDL describes hardware, not a program.* Every statement exists at once. A module is a circuit; instantiating it twice makes two circuits. Coming from C++, the most important habit is to think about the flops and gates a line becomes, not what it "executes".

*Two kinds of block.* `always_ff @(posedge clk)` describes flip-flops; use non-blocking `<=` so that all right-hand sides are sampled before any left-hand side updates, which is how real flops behave. `always_comb` describes gates; use blocking `=` and assign every output on every path (or give a default) so that no latch is inferred. A signal is assigned in exactly one block.

*Simulation and synthesis are different consumers.* Verilator compiles your design into C++ for fast cycle-based simulation driven from a C++ testbench, which your background makes natural. Icarus is slower and event-driven and accepts more of the language. Yosys turns the same source into a netlist of LUTs and flops; not everything simulable is synthesisable (`#` delays, unbounded loops).

*FPGA architecture.* Look-up tables of four to six inputs implement any small Boolean function; each pairs with a flip-flop; carry chains make adders fast; block RAM gives dense memory with registered ports; DSP blocks multiply and accumulate; PLLs synthesise clocks; I/O blocks handle voltage standards and serialisation. Programmable routing between them takes most of the die and most of the delay. A bitstream loaded from flash configures it all at power-on.

#fig("/figures/u2-fpga-fabric.svg", caption: [The parts of an FPGA fabric your designs map onto. Nextpnr's utilisation report counts each of these; its timing report measures the routing between them.])

*Timing analysis.* You state the clock period in a constraints file. The tool computes every path from flop to flop and reports slack, required time minus arrival time. Negative slack is a failing path. Place-and-route is an optimisation problem, so results vary from run to run; a design that only just passes will fail on the next build.

*Clock domain crossing.* A signal moving between unrelated clocks is asynchronous to the receiver. Single bits get a two-flop synchroniser. Multi-bit values must not be synchronised bit by bit, because the bits arrive on different cycles; use a handshake, or a FIFO with Gray-coded pointers so only one bit changes per increment. This is the most common cause of "works for hours, then corrupts" bugs.

#fig("/figures/u2-async-fifo.svg", caption: [An asynchronous FIFO. Each pointer is Gray-coded in its own domain and crosses through a two-flop synchroniser; "full" is computed in the write domain and "empty" in the read domain, each against a possibly stale copy of the other pointer, which is always safe.])

*Reset.* Synchronise reset release. Decide per design whether flops are reset at all: on FPGAs, initial values from the bitstream often remove the need, and unreset datapaths are smaller and faster.

*Interfaces and buses.* Wishbone (simple, open) and AXI-Lite (the industry standard, more signals) are memory-mapped register buses: address, data, strobe or valid, ready or acknowledge. AXI-Stream carries data without addresses. Every SoC peripheral you will read a datasheet for is one of these behind a register map. Write the register map before the RTL; it is the contract with software.

*Formal verification.* SymbiYosys uses SAT solvers to prove properties of your design for all inputs up to a bound, or for ever with induction. For FIFOs, arbiters and protocol handlers it finds bugs that simulation never reaches.

*Parameterisation and reuse.* `parameter` and `generate` give you templates. Keep peripherals generic in width and depth; Chapter 2.3 instantiates them.

*Which language.* SystemVerilog's synthesisable subset with Verilator is the industry default and this course's. VHDL is equally capable and common in defence and Europe. Amaranth (Python) and Chisel (Scala) generate Verilog; LiteX builds whole SoCs from Python. Learn SystemVerilog first so you can read everyone else's code.

*Vendor tools.* Vivado (AMD), Quartus (Altera) and Radiant (Lattice) exist because the open flow covers only some parts. The concepts are identical; the constraint syntax and the GUI are not.

== Reading

- Harris and Harris, DDCA RISC-V edition, chapter 4 (HDL), the SystemVerilog columns.
- ZipCPU (Dan Gisselquist): "Building a simple UART", "Crossing clock domains", "Building a formally verified asynchronous FIFO" and the formal verification tutorial.
- Cummings, "Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!" and "Simulation and Synthesis Techniques for Asynchronous FIFO Design" (SNUG).
- Yosys manual chapters 1 to 3; the nextpnr README; the ULX3S constraints file and examples; the Verilator manual's C++ testbench sections.
- Wishbone B4 (short) and the AXI4-Lite chapter of the AMBA AXI specification.

== Labs

#lab([Toolchain, blink and a timing failure on purpose], time: [5 h])[
+ From scratch, with no example project: a top module with a PLL from the 25 MHz input to 100 MHz, a 27-bit counter and the LEDs on its top bits. Write the LPF constraints by hand from the ULX3S schematic. Build with Yosys, nextpnr-ecp5 and ecppack; load with openFPGALoader.
+ Read the nextpnr timing report end to end. Find the critical path and its slack.
+ Add a 64-bit combinational multiply feeding a flop. Read the negative slack. Fix it by pipelining; then fix it instead by lowering the PLL frequency, and note which fix you would choose and why.

#done-when(
  [The LEDs count, and both timing reports are in the notebook with the critical paths annotated.],
)
#evidence([Constraints file; the two annotated reports.])
] <lab-blink-fpga>

#lab([UART transmitter and receiver], time: [8 h])[
+ Write the register map first: TX data, RX data, status (TX busy, RX valid, framing error) and baud divisor.
+ Implement 8N1 TX as a state machine with a shift register and a baud counter. Write a Verilator testbench in C++ that decodes the line and checks each byte.
+ Implement RX with 16× oversampling and mid-bit sampling. The testbench sends bytes with slightly wrong baud rates and finds the tolerance.
+ Prove with SymbiYosys that once a start bit is detected, exactly eight data bits are sampled and the stop bit is checked.
+ On hardware, echo at 115200 through the on-board FTDI. Capture the line with the logic analyser and decode it in PulseView.

#done-when(
  [Echo works on the board, the formal proof passes, and the baud tolerance is measured in simulation.],
)
#evidence([RTL, testbench and proof files; the tolerance result; a decoded capture.])
] <lab-uart-fpga>

#lab([An asynchronous FIFO with a formal proof], time: [8 h])[
+ Implement a parameterised asynchronous FIFO: Gray-coded write and read pointers, two-flop synchronisers for the crossing pointers, full and empty computed in the correct domains.
+ Simulate with unrelated clocks (100 MHz and 37 MHz), random bursts and a scoreboard that checks order and count.
+ Prove with induction that the FIFO never overflows or underflows and delivers data in order.
+ Break the Gray coding (use binary pointers) and show the solver finds a counterexample.

#done-when(
  [The proof passes with induction, and the broken version fails with a trace you can explain.],
)
#evidence([Proof files; the counterexample trace annotated.])
] <lab-async-fifo>

#lab([A memory-mapped peripheral], time: [6 h])[
+ Define a Wishbone (or AXI-Lite) slave with this 32-bit register map: GPIO output, GPIO input, GPIO direction, timer counter, timer compare, timer control, interrupt status, interrupt enable, and an ID register that returns a constant.
+ Implement it. The testbench acts as bus master, walks the map, checks read-after-write, checks the timer counts and raises the interrupt at the compare value.
+ Write the register map as a table with bit fields, reset values and access types. It is the contract for Chapters 2.3, 2.6 and 4.3.

#done-when(
  [The testbench passes and the register document is committed.],
)
#evidence([RTL, testbench, the register-map document.])
] <lab-mmio-peripheral>

#lab([The register map over SPI], time: [8 h], kit: [ULX3S, Raspberry Pi 5, jumper wires, logic analyser.])[
+ Implement an SPI slave (mode 0) with a transaction format of one command byte (read or write, and the address) followed by data bytes. Bridge it to the bus from Lab 2.2.4 so every register is reachable over SPI.
+ Handle the clock domain properly: SPI's clock is asynchronous to the system clock. Either synchronise SCLK edges into the system domain (fine at low SPI rates) or run the shift register on SCLK and cross the finished byte with a handshake.
+ Drive it from the Raspberry Pi in Python with `spidev`: toggle an FPGA GPIO, read the ID register, program the timer.
+ Route the FPGA's interrupt line to a Pi GPIO and log it with `gpiomon`.
+ Capture a full transaction on the logic analyser and annotate it.

#done-when(
  [Registers read and write over SPI from the Pi, the timer interrupt reaches the Pi, and the annotated capture is in the notebook.],
)
#evidence([RTL; the Python script; the annotated capture.])
] <lab-spi-bridge>

== Problem set

+ Write an `always_comb` block that infers a latch by accident, and fix it. Write an `always_ff` block where a blocking assignment makes simulation differ from synthesis.
+ How many 18 kbit block RAMs does a 320 × 240 8-bit framebuffer need? A 640 × 480 4-bit one? Which fits an ECP5-85F with 208 such blocks?
+ Derive the baud counter for 115200 from 100 MHz. What is the frequency error, and how does it accumulate over a 10-bit frame? Compare with a 48 MHz clock.
+ List three ways a multi-bit signal crossing clock domains can be corrupted even when each bit passes through a two-flop synchroniser.
+ Write constraints for a 100 MHz system clock, a 12 MHz SPI clock treated as asynchronous, and a path from a configuration register that changes only at start-up. Name the constraint for the last one and say why it is legitimate.
+ A UART receiver oversamples at 16× and samples at the eighth tick. The transmitter's clock is 3 % fast. At which data bit does sampling drift into the wrong bit cell?
+ Why is a FIFO's "empty" flag safe to compute in the read domain but not the write domain? What goes wrong if "full" is computed in the read domain?
+ A path passes through 14 LUTs and a carry chain. Estimate the pipeline stages needed to bring it under 5 ns, and the throughput and latency costs.

== Deliverables and stretch

*Deliverables.* UART, FIFO, register-map peripheral and SPI bridge, each with a testbench, and the UART and FIFO with formal proofs; the register-map document; the annotated SPI capture.

*Stretch.* Generate 640 × 480 video over the ULX3S's HDMI connector with a character-mode framebuffer in block RAM, writable from the bus, and check the BRAM budget against the utilisation report. Reimplement the FIFO in Amaranth and compare the generated Verilog. Build a small LiteX SoC with a VexRiscv core and look at how it generates the register map and C headers.

#checklist(
  [*Lab 2.2.1:* hand-written constraints; the timing failure and both fixes annotated.],
  [*Lab 2.2.2:* UART echo on hardware; formal proof passing; baud tolerance measured.],
  [*Lab 2.2.3:* FIFO proved by induction; the binary-pointer counterexample explained.],
  [*Lab 2.2.4:* peripheral testbench passing; register map committed.],
  [*Lab 2.2.5:* SPI bridge driven from the Pi with the interrupt delivered; capture annotated.],
  [*Problem set:* all eight answered.],
  [*You can explain*, without notes: blocking versus non-blocking assignment, how an asynchronous FIFO stays correct, what slack is, and what a false path claims.],
)
