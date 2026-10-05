#import "../lib/template.typ": *

= Build a CPU <ch-cpu>

#chapter-meta(
  weeks: [4 weeks],
  builds: [A single-cycle RV32I core passing the riscv-tests suite; a five-stage pipeline with forwarding and branch prediction; the core on the FPGA running C you compiled, driving your peripheral; the M and Zicsr extensions.],
  needs: [ULX3S, riscv32 GCC toolchain, Verilator, your Chapter 2.2 UART and peripheral.],
)

#why[
  Compute is an OMH product. You will buy the CPUs, but you will size them, read their errata, argue with vendors about SMT and side channels, and tune a hypervisor around what they actually do. The only reliable way to understand a pipeline, a hazard or a branch predictor is to build one and watch it fail. After this chapter the Intel manual reads like documentation rather than scripture.
]

#skip-test(
  rule: [If all five are easy, do Labs 2.3.2 and 2.3.3 only.],
  [Encode `addi x5, x6, -4` and `sw x7, 12(x8)` by hand from the RV32I tables.],
  [Draw a five-stage pipeline and mark every forwarding path needed to run back-to-back dependent ALU instructions without stalls. Which hazard cannot be solved by forwarding?],
  [A branch resolves in the EX stage. What is the misprediction penalty in cycles, and how does a 2-bit predictor change the expected penalty for a loop of 100 iterations?],
  [What does a linker script's `MEMORY` block do, and why does bare-metal C need a `crt0` before `main`?],
  [Why does RISC-V have no condition codes and no branch delay slots?],
)

== Core ideas

*The ISA is the contract.* Software above it, hardware below it. RV32I has about 40 instructions in six regular formats (R, I, S, B, U, J). Immediates are scattered across bits so that the sign bit and the register fields are always in the same place, which simplifies the decoder. Read the specification's design rationale: every choice is there to make hardware simpler.

#fig("/figures/u2-rv32i-formats.svg", caption: [The six RV32I instruction formats. The register fields and the sign bit (bit 31) never move; the immediate bits are shuffled so the decoder's sign-extension and multiplexers stay small.])

*The datapath.* Fetch an instruction at PC; decode it into control signals and register indices; read the register file; execute in the ALU; access memory for loads and stores; write back the result. A single-cycle design does all of that in one long clock period, set by the slowest instruction (a load).

*Pipelining.* Split the datapath into stages separated by registers so five instructions are in flight. Throughput rises toward one instruction per cycle; the latency of each instruction does not fall. The period is now set by the slowest stage plus register overhead, so unbalanced stages waste time.

*Hazards.* Structural: two stages want the same resource (separate instruction and data memories, or caches, fix it). Data: an instruction needs a result not yet written back; forward it from the EX/MEM or MEM/WB registers, except a load followed immediately by a use, which must stall one cycle. Control: a branch's outcome is not known until EX, so stall, predict, or both. Flushing squashes wrongly fetched instructions by turning them into no-ops.

#fig("/figures/u2-pipeline.svg", caption: [A five-stage pipeline with the two forwarding paths into the ALU and the load-use stall. The branch resolves in EX; a misprediction flushes the two younger instructions.])

*Branch prediction.* Static (predict not taken, or backward taken), then dynamic: a branch history table of 2-bit saturating counters indexed by PC bits, a branch target buffer for where to go, and later global history and tournament predictors. Modern cores predict nearly every branch correctly and still lose tens of cycles when they miss, because their pipelines are deep.

*Memory-mapped I/O.* Peripherals live at addresses. A load from the UART status register is a bus read that the peripheral answers. Your Chapter 2.2 peripheral attaches to the data bus behind an address decoder. Loads and stores to device registers must not be cached, reordered or merged, which is why `volatile` exists in C and why the ISA has fence instructions.

*Control and status registers.* CSRs hold machine state: cycle counters, trap vectors, status. Zicsr gives `csrrw`, `csrrs` and `csrrc`. Chapter 2.5 fills them with meaning.

*The bare-metal toolchain.* GCC targets `rv32i` with the ILP32 ABI. A linker script places `.text` in ROM, `.data` and `.bss` in RAM, and defines symbols for the stack top and section bounds. `crt0.S` sets the stack pointer, copies `.data` from ROM to RAM, zeroes `.bss` and calls `main`. `objcopy` turns the ELF into a hex file that `$readmemh` loads into block RAM. There is no OS, and no libc unless you bring one (picolibc is small).

*Compliance testing.* riscv-tests and riscv-arch-test are directed tests per instruction with a pass or fail signature. Running them is how you know your CPU is correct rather than plausible.

*Performance.* Time = instructions × CPI × cycle time. Pipelining lowers CPI toward 1; hazards raise it; only multiple issue pushes it below 1. Measure with `mcycle` and `minstret`.

*Beyond this core.* Superscalar issue, out-of-order execution with register renaming and a reorder buffer, speculation with precise exceptions, SIMD and vector units, simultaneous multithreading. You will not build these; you will read enough that "Spectre exploits speculative execution across a mispredicted branch" is a sentence with content. Server cores are this, times sixty, sharing a cache and a memory controller.

*Reading other cores.* PicoRV32 (tiny, multi-cycle), Ibex (two-stage, production quality), VexRiscv (generated, pipelined) and Rocket (Chisel, Berkeley). Read them after yours works.

== Reading

- RISC-V Unprivileged ISA specification: chapter 1 (introduction and rationale), chapter 2 (RV32I), the M extension, Zicsr, and the instruction listing tables.
- Patterson and Hennessy, _Computer Organization and Design_, RISC-V edition: chapter 2 (skim what you know) and chapter 4 (the processor: single-cycle, pipelining, hazards, branch prediction, exceptions).
- Harris and Harris, DDCA RISC-V edition, chapter 7 (microarchitecture), as a reference once yours has a shape.
- Hennessy and Patterson, _Computer Architecture: A Quantitative Approach_, sections 3.1 to 3.6 (out-of-order overview; read once, do not implement).
- The GNU ld manual's "Scripts" chapter and the picolibc README.

== Labs

#lab([Single-cycle RV32I], time: [3 weekends])[
+ Write the decoder as a table from the specification, not from memory. Implement the register file (x0 wired to zero), the ALU, the immediate generator, the PC logic, the load/store unit with byte and halfword handling, and the control unit.
+ Instruction and data memory as block RAM initialised from hex; a data bus with an address decoder placing RAM low and your peripheral and UART above it.
+ A Verilator testbench in C++ that loads a hex file, runs N cycles and exposes register and memory state, with a `tohost`-style mechanism for tests to report pass or fail.
+ Build riscv-tests for `rv32ui-p-*` and run every one. Fix until all pass.
+ Write `crt0.S`, a linker script and a C `main` that prints "hello" through your UART, compiled with `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`, and watch it in simulation.

#done-when(
  [All `rv32ui` tests pass and your C program prints through your UART in simulation.],
)
#evidence([Test log; `crt0.S`; linker script; the UART output.])
] <lab-single-cycle>

#lab([A five-stage pipeline], time: [2 weekends])[
+ Insert pipeline registers between IF, ID, EX, MEM and WB. Add forwarding from EX/MEM and MEM/WB into the ALU inputs, and the load-use detector and stall.
+ Resolve branches in EX with predict-not-taken and a flush. Re-run riscv-tests.
+ Add a 2-bit predictor with a small branch target buffer. Re-run.
+ Add `mcycle` and `minstret`. Port a small benchmark (a Dhrystone-like loop, or CoreMark if it builds). Measure CPI for single-cycle-equivalent, pipelined and predicted configurations.

#done-when(
  [Tests pass on the pipeline and the notebook has a CPI table for the three configurations with each difference explained.],
)
#evidence([Test logs; the CPI table.])
] <lab-pipeline>

#lab([On the FPGA at speed], time: [1 weekend])[
+ Synthesise for the ULX3S at 50 MHz. Find the critical path (usually the ALU or the forwarding multiplexer) and push toward the highest frequency you can close with margin.
+ Boot from block RAM with the console on the FTDI UART.
+ Run a program that configures your timer, polls for the compare match and toggles LEDs; then read a button through the GPIO input.
+ Toggle a GPIO each cycle (divided down) and confirm the real clock and `mcycle` against the scope.

#done-when(
  [Your C runs on your CPU on the FPGA, drives your peripheral, and `mcycle` agrees with the scope.],
)
#evidence([The achieved frequency and its timing report; the scope capture.])
] <lab-cpu-fpga>

#lab([Extensions], time: [1 weekend])[
+ Add the M extension: a multi-cycle multiplier and divider with a stall. Run the `rv32um` tests and compare benchmark CPI with and without it.
+ Implement Zicsr fully, including the immediate forms.
+ Add `fence` and `fence.i` as no-ops, with a comment saying what each must do once there are caches. Chapter 2.4 makes them real.

#done-when(
  [`rv32um` and the CSR tests pass.],
)
#evidence([Test logs; the CPI comparison.])
] <lab-extensions>

#lab([Read three other cores], time: [4 h])[
Read Ibex's pipeline, VexRiscv's generated Verilog for a similar configuration, and PicoRV32. Write one page: where your design is the same, where it differs, and three things you would change having read theirs. Note how Ibex keeps exceptions precise in a pipeline, because Chapter 2.5 needs it.

#done-when(
  [The page is committed.],
)
] <lab-other-cores>

== Problem set

+ Hand-encode `lui x1, 0x12345`, `jal x0, -16`, `bne x2, x3, +32` and `sb x4, -1(x5)`. Decode `0x00A28293` and `0xFE0508E3`.
+ Stage delays are IF 300 ps, ID 200 ps, EX 350 ps, MEM 400 ps and WB 150 ps, and pipeline registers cost 50 ps. Compute clock period and per-instruction latency for single-cycle and pipelined designs, and the speedup for a long program with no hazards.
+ A program is 25 % loads and 20 % branches; 40 % of loads are followed by a dependent instruction; branches mispredict 15 % of the time with a 2-cycle penalty. Compute CPI on your pipeline.
+ Write the forwarding logic as a truth table over the EX instruction's source register and the MEM and WB destination registers, including the priority when both match.
+ Why must the load-use hazard stall rather than forward? Draw the timing.
+ Explain why RISC-V puts the sign bit at bit 31 in every format and what that saves in the decoder.
+ A predictor uses 10 PC bits to index 1,024 2-bit counters and two hot branches alias. Describe the interference and one mitigation.
+ A workload spends 30 % of its time in a routine the M extension makes four times faster. What is the overall speedup? What if loads also become 20 % faster?
+ Write a linker-script fragment placing `.text` at 0x0000_0000 (64 KiB of ROM) and `.data` and `.bss` at 0x1000_0000 (32 KiB of RAM), with the stack at the top of RAM and the symbols `crt0` needs.
+ Read the Spectre v1 paper's abstract and explain, in terms of your pipeline plus a hypothetical cache, what speculation would have to do for the attack to work. Does your core speculate?

== Deliverables and stretch

*Deliverables.* A pipelined RV32IM core passing riscv-tests, running on the FPGA at a documented frequency, with the CPI table; `crt0.S`, the linker script and a small runtime reused in Chapters 2.4 and 2.5; the comparison page from Lab 2.3.5.

*Stretch.* Replace predict-not-taken with gshare and measure. Add a two-issue in-order front end for ALU pairs. Add the C extension and measure code size and CPI. Run riscv-arch-test instead of riscv-tests and compare coverage.

#checklist(
  [*Lab 2.3.1:* all `rv32ui` tests passing on the single-cycle core; C prints through your UART.],
  [*Lab 2.3.2:* the pipelined core passes; CPI table for three configurations.],
  [*Lab 2.3.3:* the core runs on the ULX3S at a recorded frequency; `mcycle` checked against the scope.],
  [*Lab 2.3.4:* `rv32um` and CSR tests pass.],
  [*Lab 2.3.5:* the one-page comparison committed.],
  [*Problem set:* all ten answered.],
  [*You can explain*, without notes: the five stages, each hazard type and its fix, how a 2-bit predictor works, and what `crt0` does before `main`.],
)
