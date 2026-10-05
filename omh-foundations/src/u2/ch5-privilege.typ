#import "../lib/template.typ": *

= Privilege and the platform <ch-privilege>

#chapter-meta(
  weeks: [2 weeks],
  builds: [Machine and user modes, precise traps, a timer interrupt, PMP and a two-call system-call ABI on your own CPU; preemptive multitasking on the FPGA; an x86-64 bare-metal program with its own GDT, IDT, APIC timer and a ring-3 system call, on QEMU and on the server; annotated ACPI and SMBIOS tables from the server.],
  needs: [Your CPU, QEMU, the lab server with serial-over-LAN.],
)

#why[
  A hypervisor is a program that uses privilege levels to lie to another program about the machine. A kernel uses them to share the machine. Measured boot is a chain of privilege handoffs, each measured before the next. None of Chapters 2.7, 4.1 or 4.4 can be understood without knowing what a trap is, what state it saves, and who may touch which register. This chapter makes that concrete on your own CPU, then shows the same shape on x86 and Arm, the platforms OMH will ship.
]

#skip-test(
  rule: [If all five are easy, do Lab 2.5.1 only.],
  [On RISC-V, an `ecall` from U-mode arrives in M-mode. List every CSR the hardware writes, and what the handler must do before it can safely use a stack.],
  [What does `medeleg` do, and why does a hypervisor care?],
  [On x86-64 a user process executes `syscall`. Which registers change, where does the kernel stack come from, and why does the kernel still need a TSS in long mode?],
  [What is the difference between the local APIC and the I/O APIC, and how does an MSI from a PCIe device reach a particular core?],
  [Why does an OS need ACPI on x86 but a device tree on most Arm boards, and what breaks if both are absent?],
)

== Core ideas

*Why privilege exists.* Some operations must be reserved: changing address translation, masking interrupts, touching devices. A privilege level is a bit or two of state the hardware consults before allowing them, and a trap is the controlled transfer that happens when a less privileged program needs one. Everything else is mechanism for making that transfer fast, safe and complete.

*RISC-V privilege.* Three modes: Machine (always present, highest), Supervisor (for kernels) and User. M-mode CSRs: `mstatus` (global interrupt enable and previous privilege), `mtvec` (trap vector), `mepc` (return address), `mcause` (why), `mtval` (bad address or instruction), `mscratch` (a free register for the handler) and `mie`/`mip` (interrupt enable and pending), with S-mode twins. Traps are synchronous exceptions (illegal instruction, misaligned access, page fault, `ecall`) or asynchronous interrupts (software, timer, external). All go to M-mode unless delegated with `medeleg` and `mideleg`, which is how a kernel in S-mode gets its own traps and how a hypervisor decides what a guest may handle. `mret` and `sret` return.

#fig("/figures/u2-trap.svg", caption: [A trap from U-mode to M-mode on RISC-V. Hardware saves only the PC, the cause and the previous mode; everything else, starting with a usable stack from `mscratch`, is the handler's job.])

*Timers and interrupt controllers.* The CLINT provides `mtime`, `mtimecmp` and software interrupts per hart; the PLIC aggregates device lines with priorities and per-hart enables; AIA adds message-signalled interrupts. The timer interrupt is the heartbeat of every preemptive scheduler.

*Physical Memory Protection.* PMP registers fence address ranges off from lower modes even without paging. It is how firmware protects itself from the kernel on simple cores.

*Paging on RISC-V.* `satp` holds the mode (Sv32, Sv39, Sv48) and the root table. Entries carry R, W, X, U, G, A and D bits. `sfence.vma` flushes the TLB. Supervisor code may not touch U pages unless `sstatus.SUM` is set, which catches a kernel dereferencing a user pointer by accident.

*x86-64 equivalents.* Rings 0 and 3. Long mode makes segmentation vestigial, but the GDT must still hold code and data descriptors and a TSS descriptor. The IDT holds 256 gates: exceptions 0 to 31, then device interrupts. An interrupt pushes SS, RSP, RFLAGS, CS and RIP (plus an error code for some exceptions), and when privilege changes the new stack comes from the TSS's RSP0, or from the Interrupt Stack Table for critical exceptions such as double fault. CR0, CR3, CR4 and EFER control protection, paging and long mode; model-specific registers configure the rest (`STAR` and `LSTAR` for `syscall`, the APIC base, later VMX). `syscall` does not switch stacks, so the kernel does it with `swapgs` and a per-CPU pointer. Four-level paging with 4 KiB, 2 MiB and 1 GiB pages; PCIDs tag the TLB.

*x86 interrupts.* Each core's local APIC holds a timer, local vectors and inter-processor interrupts, and is the destination of everything. The I/O APIC routes legacy wired interrupts. MSI and MSI-X let a device write directly to a local APIC's address with a vector number, which is why modern servers barely use the I/O APIC. x2APIC uses MSRs instead of MMIO.

*Legacy and hidden modes.* Real mode at reset, then protected mode, then long mode, each with its own dance (Chapter 2.7 does them). System Management Mode is a hidden, more privileged mode entered by an SMI, invisible to the OS and the hypervisor; it is where firmware does power management and where attackers like to live. Microcode updates are loaded at boot.

*Armv8-A.* EL0 (user), EL1 (kernel), EL2 (hypervisor) and EL3 (secure monitor, where Trusted Firmware-A lives). Vector tables per level, indexed by type and source. TTBR0 and TTBR1 split user and kernel translation; EL2 owns a second stage. The GICv3 has a distributor, redistributors and CPU interfaces, with an ITS for message-signalled interrupts. PSCI powers cores on and off. The Raspberry Pi 5 is this.

*Platform description.* A kernel cannot discover the interrupt controller, the timer, the core count or non-enumerable buses. On x86, firmware provides ACPI tables: RSDP, XSDT, FADT, MADT (APICs and cores), SRAT (NUMA), MCFG (PCIe configuration space), and DSDT and SSDTs containing AML bytecode the kernel interprets. On embedded Arm and RISC-V a device tree does the same job statically: nodes with `compatible`, `reg` and `interrupts`, compiled to a blob the bootloader hands over. Arm servers use ACPI too.

*SMBIOS.* Tables describing the platform's identity: manufacturer, serial number, DIMMs, slots. `dmidecode` reads them; BMCs and inventory systems depend on them, and OMH's fleet identity starts there before attestation takes over.

== Reading

- RISC-V Privileged specification: chapter 1, chapter 3 (machine level, all), chapter 4 (supervisor level), and the Sv32 and Sv39 sections.
- Intel SDM volume 3A: chapters 2 to 6, the TSS parts of chapter 8, and the APIC chapters.
- OSDev wiki: GDT, IDT, Exceptions, APIC, IOAPIC, Paging, Setting Up Long Mode.
- ACPI specification chapter 5 (system description tables) and chapter 6 (`_CRS`, `_PRT`); skim the ASL reference.
- Arm's Cortex-A programmer's guide for Armv8-A: fundamentals, AArch64 exception handling, memory management. The Devicetree specification, chapters 2 and 3.

== Labs

#lab([M-mode on your CPU], time: [2 weekends])[
+ Add `mstatus` (MIE, MPIE, MPP), `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`, `mie` and `mip`; add `ecall`, `ebreak` and `mret`; on any exception or enabled interrupt save PC to `mepc`, set `mcause`, disable interrupts and jump to `mtvec`. Make exceptions precise: instructions after the faulting one must have no side effects.
+ Add a CLINT-style `mtime`/`mtimecmp` peripheral and wire the timer interrupt.
+ Write an assembly trap handler that saves all registers to a trap frame on a dedicated stack found through `mscratch`, calls a C dispatcher, restores and `mret`s. The dispatcher prints the cause and handles it or panics.
+ Test illegal instruction, misaligned load, `ecall`, and a 10 ms timer tick.
+ Two bare-metal tasks with their own stacks; the timer handler swaps saved frames. Watch two loops interleave on the UART.

#done-when(
  [All four traps are handled with the correct `mcause` and `mtval`, and two tasks alternate under timer preemption on the FPGA.],
)
#evidence([The handler source; UART logs of each trap and of the interleaved tasks.])
] <lab-mmode>

#lab([U-mode and protection on your CPU], time: [1 weekend])[
+ Add U-mode: `mret` with `MPP = 0` enters it; CSR access and `mret` in U-mode trap as illegal.
+ Implement PMP with at least two NAPOT entries. Make M-mode code and data inaccessible from U. A user program reads the timer (allowed), then writes a protected address (traps); handle it and kill the task.
+ If you built the page-table walker in Lab 2.4.5, enable Sv32 for the user task, leave the kernel unmapped, and show a page fault with `mtval` holding the address.
+ Implement a two-call ABI over `ecall`: `write(fd, buf, len)` and `exit(code)`. The user program prints through it.

#done-when(
  [A U-mode program prints through `ecall` and is killed cleanly when it touches protected memory.],
)
#evidence([The ABI document; the trap log of the kill.])
] <lab-umode>

#lab([x86-64 bare metal in QEMU and on the server], time: [2 weekends])[
Use a Multiboot2 stub loaded by GRUB, or the Limine bootloader, so this lab is about the CPU; Chapter 2.7 replaces the stub with your own loader.
+ Set up a GDT with 64-bit code and data descriptors and a TSS with RSP0 and one IST entry. Set up an IDT whose 32 exception handlers dump the saved frame to the 16550 at 0x3F8.
+ Trigger `#DE`, `#UD`, `#PF` (read CR2) and `#DF` via a stack overflow into an unmapped guard page, and confirm the IST stack saved you.
+ Enable the local APIC (x2APIC if offered), calibrate its timer against the PIT or TSC, and print a tick every 10 ms with a proper EOI.
+ Set `LSTAR`, `STAR` and `SFMASK`, enable `EFER.SCE`, enter ring 3 via `iretq`, execute `syscall` and return with `sysretq`, swapping stacks with `swapgs` and a per-CPU structure in GS.
+ Run the same binary on the server through a GRUB entry with the serial console over SOL, and note what differs.

#done-when(
  [The four exceptions print correctly, the APIC timer ticks, and a ring-3 system call round-trips on QEMU and on the server.],
)
#evidence([Serial logs from both machines.])
] <lab-x86-bare>

#lab([Read your server's ACPI and SMBIOS], time: [5 h])[
+ `acpidump`, `acpixtract` and `iasl -d` the DSDT and SSDTs. Find the PCI root bridge `_CRS` and check its MMIO windows against `lspci`'s bridge resources. Find the `_PRT` and trace how a legacy interrupt on your NIC's slot would route.
+ Parse the MADT by hand from the hex: count local APICs, I/O APICs and interrupt source overrides; compare with `lscpu` and `/proc/interrupts`.
+ From the MCFG compute the address of your NIC's extended configuration space and confirm it against Lab 2.4.4.
+ Draw the NUMA distance table from the SRAT and SLIT if present.
+ With `dmidecode`, record the system and board serials and each DIMM's part number and speed; note which the BMC exposes over Redfish (Chapter 2.7).

#done-when(
  [The annotated MADT, the cross-checked root-bridge resources and the verified extended-configuration address are in the notebook.],
)
#evidence([Annotated hex and ASL excerpts.])
] <lab-acpi>

== Problem set

+ Trace an `ecall` from U-mode on RISC-V: which CSRs change, in what order the handler must save state, and where the return address comes from. Repeat for a timer interrupt arriving in M-mode with interrupts enabled.
+ Why does the handler need `mscratch` (or `swapgs` on x86)? Describe the bug you get without it when a user program sets SP to garbage before `ecall`.
+ What does delegating the timer interrupt to S-mode change about who runs when? Why would a hypervisor delegate page faults but not external interrupts?
+ On x86-64, a `#PF` occurs in ring 3. List every value pushed, where the stack comes from and what CR2 holds. A `#DF` then occurs on a corrupted stack: what saves you?
+ Compute the Sv39 walk for VA 0xFFFF_FFC0_0001_0000 and explain why the address must be sign-extended from bit 38.
+ Compare the path of a PCIe MSI to a handler on x86 (device write, local APIC, vector, IDT) and on Arm (device write, GIC ITS, LPI, redistributor, vector table). Where does each store the vector-to-handler mapping?
+ Why is SMM a problem for a hypervisor's security model? What can measured boot do about it, and what can it not?
+ Write the device-tree node for your timer at 0x4000_0000 with an interrupt on PLIC source 3, then the equivalent ACPI `Device` with `_HID` and `_CRS`. What does a driver key on in each?
+ What goes wrong if two cores take the timer interrupt through one shared trap stack? Fix it.

== Deliverables and stretch

*Deliverables.* Your CPU with M and U modes, PMP, traps, a timer, preemptive tasks and a two-call ABI; the x86-64 bare-metal program running on QEMU and the server; annotated ACPI and SMBIOS notes.

*Stretch.* Add S-mode with delegation and run a tiny S-mode kernel under your M-mode firmware: the shape of OpenSBI. Port Lab 2.5.3 to the Pi 5 at EL1 with vector tables, the generic timer and the GIC. Mark which CSRs from Lab 2.5.1 acquire virtual twins in the RISC-V Hypervisor extension.

#checklist(
  [*Lab 2.5.1:* precise traps with correct causes; timer preemption of two tasks on the FPGA.],
  [*Lab 2.5.2:* U-mode program using your ABI and killed on a PMP violation.],
  [*Lab 2.5.3:* exceptions, APIC timer and ring-3 system call on QEMU and the server.],
  [*Lab 2.5.4:* MADT parsed by hand; root-bridge windows and extended configuration space cross-checked.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: what hardware saves on a trap and what software must, delegation, how x86 finds a kernel stack, and how an MSI becomes a handler call on x86 and Arm.],
)
