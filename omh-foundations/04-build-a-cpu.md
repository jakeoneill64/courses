# Module 4: Build a CPU

**Part II · 4 weeks · Needs: FPGA, riscv32 toolchain, Verilator, Module 3 peripherals.**

## Why this module (and what it buys OMH)

Compute is an OMH product. You will buy the CPUs, but you will size them, read their
errata, argue with vendors about SMT and side channels, and tune a hypervisor around
what they actually do. The only reliable way to understand a pipeline, a hazard or a
branch predictor is to build one and watch it fail. After this module the Intel manual
reads like documentation rather than scripture.

## Skip test

1. Encode `addi x5, x6, -4` and `sw x7, 12(x8)` by hand from the RV32I tables.
2. Draw a five-stage pipeline and mark every forwarding path needed to run
   back-to-back dependent ALU instructions without stalls. Which hazard cannot be
   solved by forwarding?
3. A branch resolves in the EX stage. What is the misprediction penalty in cycles, and
   how does a 2-bit predictor change the expected penalty for a loop of 100 iterations?
4. What does a linker script's `MEMORY` block do, and why does bare-metal C need a
   `crt0` before `main`?
5. Why does RISC-V have no condition codes and no branch delay slots?

If all five are easy, do Labs 4.2 and 4.3 only.

## Core ideas

**The ISA is the contract.** Software above it, hardware below it. RISC-V RV32I has
about 40 instructions in six regular formats (R, I, S, B, U, J); immediates are scattered
across bits so that the sign bit and the register fields are always in the same place,
which simplifies the decoder. Read the spec's design rationale; every choice is there to
make hardware simpler.

**The datapath.** Fetch an instruction from memory at PC; decode it into control
signals and register indices; read the register file; execute in the ALU; access
memory for loads and stores; write back the result. A single-cycle design does all of
that in one long clock period whose length is set by the slowest instruction (a load).

**Pipelining.** Split the datapath into stages separated by registers so five
instructions are in flight. Throughput rises toward one instruction per cycle; latency
per instruction does not fall. The clock period is now set by the slowest stage plus
register overhead, so uneven stages waste time.

**Hazards.** Structural: two stages want the same resource (separate instruction and
data memories, or a cache, fix it). Data: an instruction needs a result not yet written
back; forward it from the EX/MEM or MEM/WB registers, except a load followed
immediately by a use, which must stall one cycle. Control: a branch's outcome is not
known until EX; either stall, predict, or both. Flushing means squashing the wrongly
fetched instructions by turning them into no-ops.

**Branch prediction.** Static (predict not taken, or backward taken) then dynamic: a
branch history table indexed by PC bits with 2-bit saturating counters, a branch
target buffer to know where to go, and later global history and tournament
predictors. Modern cores predict nearly every branch correctly and still lose tens
of cycles when they miss, because pipelines are deep.

**Memory-mapped I/O.** Peripherals live at addresses. A load from the UART status
register is a bus read that the peripheral answers. Your Wishbone peripheral from
Module 3 attaches to the data bus behind an address decoder. Loads and stores to
device registers must not be cached, reordered or merged, which is why `volatile`
exists in the C and why the ISA has fence instructions.

**Control and status registers.** CSRs hold machine state: cycle counters, trap
vectors, status. RV32I plus Zicsr gives you `csrrw`, `csrrs`, `csrrc`. Module 6 fills
them with meaning.

**The toolchain, bare metal.** GCC targets `rv32i` with the ILP32 ABI. A linker script
places `.text` at your ROM address, `.data` and `.bss` in RAM, and defines symbols for
the stack top and section bounds. `crt0.S` sets the stack pointer, copies `.data` from
ROM to RAM, zeroes `.bss`, and calls `main`. `objcopy` turns the ELF into a hex file
your Verilog `$readmemh` loads into block RAM. There is no OS, no libc unless you
bring one (picolibc is small), and `printf` goes wherever your `_write` sends it.

**Compliance testing.** The riscv-tests suite and riscv-arch-test are directed tests
per instruction with a pass/fail signature. Running them is how you know your CPU is
correct rather than merely plausible.

**Performance.** Time = instructions × CPI × cycle time. Pipelining lowers CPI toward
1; hazards raise it; caches (Module 5) push it below 1 only with multiple issue.
Measure with `mcycle` and `minstret`.

**Beyond this core.** Superscalar issue, out-of-order execution with register renaming
and a reorder buffer (Tomasulo), speculative execution and precise exceptions, SIMD
and vector units, simultaneous multithreading. You will not build these; you will read
one chapter so that "Spectre exploits speculative execution across a mispredicted
branch" is a sentence with content. Server cores are this, times sixty, on one die,
sharing a cache and a memory controller.

**Reading other cores.** PicoRV32 (tiny, multi-cycle), Ibex (two-stage, production
quality, lowRISC), VexRiscv (generated, pipelined, configurable), Rocket (Chisel,
Berkeley). Read them after yours works.

## Reading

- RISC-V Unprivileged ISA spec: ch. 1 (introduction and design rationale), ch. 2
  (RV32I), ch. 7 (M extension), ch. 9 (Zicsr), and the instruction listing tables.
- Patterson and Hennessy, *Computer Organization and Design*, RISC-V ed., ch. 2 (skim
  what you know), ch. 4 (the processor: single-cycle, pipelining, hazards, branch
  prediction, exceptions).
- Harris and Harris, DDCA RISC-V ed., ch. 7 (microarchitecture). Their single-cycle
  and pipelined RV32I designs are a fine reference once yours has a shape.
- Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, ch. 3
  sections 3.1 to 3.6 (out-of-order overview, read once, do not implement).
- GNU ld manual, the "Scripts" chapter; the picolibc README.

## Labs

### Lab 4.1: Single-cycle RV32I

1. Write the decoder as a table from the spec, not from memory. Implement the register
   file (x0 hardwired to zero), the ALU, the immediate generator, the PC logic, the
   load/store unit with byte and halfword handling, and a control unit.
2. Instruction and data memory as block RAM initialised from hex. Data bus with an
   address decoder: RAM below a boundary, your Wishbone peripheral and UART above it.
3. Verilator testbench in C++ that loads a hex file, runs N cycles, and exposes
   register and memory state. Add a `tohost`-style mechanism so tests can signal pass
   or fail.
4. Build riscv-tests for `rv32ui-p-*`. Run every one. Fix until all pass.
5. Write `crt0.S`, a linker script, and a C `main` that prints "hello" through your UART
   register map, compiled with `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`.
   Run it in simulation; watch the UART decode in the testbench.

Done when: all rv32ui tests pass and your C program prints through your UART.

### Lab 4.2: Five-stage pipeline

1. Insert pipeline registers between IF, ID, EX, MEM, WB. Add forwarding from EX/MEM
   and MEM/WB into the ALU inputs. Add the load-use hazard detector and stall.
2. Branches resolve in EX with predict-not-taken and a flush. Re-run riscv-tests.
3. Add a 2-bit predictor with a small branch target buffer. Re-run.
4. Add `mcycle` and `minstret`. Port a small benchmark (a Dhrystone-like loop, CoreMark
   if you can get it building, or your own mix). Measure CPI single-cycle-equivalent
   versus pipelined versus predicted.

Done when: tests pass on the pipelined core and your notebook has a CPI table for the
three configurations with an explanation of each difference.

### Lab 4.3: On the FPGA at speed

1. Synthesise for the ULX3S. Target 50 MHz first. Read the timing report; find the
   critical path (usually the ALU or the forwarding mux); fix it. Push toward the
   highest frequency you can close with margin.
2. Boot from block RAM containing your program. Console over the FTDI UART.
3. Run a program that configures your Wishbone timer, waits for the compare match by
   polling the status register, and toggles the LEDs. Then read the GPIO input from a
   button.
4. Measure the real clock with the scope on a GPIO toggled every cycle divided down,
   and confirm `mcycle` against wall-clock time.

Done when: your C runs on your CPU on the FPGA, drives your peripheral, and `mcycle`
agrees with the scope.

### Lab 4.4: Extensions

1. Add the M extension: a multi-cycle multiplier and divider with a stall. Re-run
   `rv32um` tests. Compare benchmark CPI with and without.
2. Add Zicsr fully (all three CSR instruction forms with the immediate variants).
3. Add `fence` and `fence.i` as no-ops for now with a comment on what they must do once
   there are caches. You will make them real in Module 5.

Done when: `rv32um` and CSR tests pass.

### Lab 4.5: Read three other cores

Read Ibex's pipeline, VexRiscv's generated Verilog for a similar configuration, and
PicoRV32. Write one page: where your design is the same, where it differs, and three
things you would change in yours having read theirs. Note in particular how Ibex
handles exceptions precisely in a pipeline, because Module 6 will need it.

Done when: the page is committed.

## Problem set

1. Hand-encode: `lui x1, 0x12345`; `jal x0, -16`; `bne x2, x3, +32`; `sb x4, -1(x5)`.
   Decode `0x00A28293` and `0xFE0508E3`.
2. A single-cycle design has stage delays IF 300 ps, ID 200 ps, EX 350 ps, MEM 400 ps,
   WB 150 ps, and pipeline registers cost 50 ps. Compute clock period and per-instruction
   latency for single-cycle and pipelined designs, and the speedup for a long program
   with no hazards.
3. A program is 25% loads, 20% branches; 40% of loads are followed by a dependent
   instruction; branches mispredict 15% of the time with a 2-cycle penalty. Compute CPI
   on your pipeline.
4. Draw the forwarding logic as a truth table over the source register of the
   instruction in EX and the destination registers in MEM and WB, including the
   priority when both match.
5. Why must the load-use hazard stall rather than forward? Draw the timing.
6. Explain why RISC-V's immediate encodings put the sign bit at bit 31 in every format
   and what that saves in the decoder.
7. A branch predictor uses 10 bits of PC to index 1,024 2-bit counters. Two hot
   branches alias. Describe the interference and one mitigation.
8. Amdahl: a workload spends 30% of its time in a routine you can make 4× faster with
   the M extension. What is the overall speedup? What if you also make loads 20%
   faster?
9. Write a linker script fragment placing `.text` at 0x0000_0000 (ROM, 64 KiB),
   `.data` and `.bss` at 0x1000_0000 (RAM, 32 KiB), with a stack at the top of RAM and
   symbols for `crt0` to copy `.data` and zero `.bss`.
10. Read the Spectre v1 paper abstract and explain, in terms of your pipeline plus a
    hypothetical cache, what speculative execution would have to do for the attack
    to work. Does your core speculate?

## Deliverables

- Pipelined RV32IM core passing riscv-tests, running on the FPGA at a documented
  frequency, with the benchmark CPI table.
- `crt0.S`, linker script and a small runtime you will reuse in Modules 5 and 6.
- The comparison page from Lab 4.5.

## Stretch

- Replace predict-not-taken with a gshare predictor and measure.
- Add a simple two-issue in-order front end for ALU-ALU pairs and measure CPI.
- Add compressed instructions (C extension) and measure code size and CPI.
- Run the riscv-arch-test framework instead of riscv-tests and compare coverage.

## Next

Module 5 gives your CPU caches, an external SDRAM, and a memory model, then looks at how
the same ideas scale to PCIe and CXL on a real server.
