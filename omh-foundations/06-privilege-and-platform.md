# Module 6: Privilege and the platform

**Part II · 2 weeks · Needs: your CPU, QEMU, the server for ACPI reading.**

## Why this module (and what it buys OMH)

A hypervisor is a program that uses privilege levels to lie to another program about the
machine. A kernel is a program that uses privilege levels to share the machine. Measured
boot is a chain of privilege handoffs, each measured before the next. None of Modules 8, 9
or 12 can be understood without knowing what a trap is, what state it saves, and who is
allowed to touch which register. This module makes that concrete on your own CPU first,
then shows the same shape in x86 and ARM, the platforms OMH will actually ship.

## Skip test

1. On RISC-V, an `ecall` from U-mode arrives in M-mode. List every CSR the hardware writes
   and what the trap handler must do before it can safely use a stack.
2. What does `medeleg` do, and why does a hypervisor care about it?
3. On x86-64, a user process executes `syscall`. Which registers change, where does the
   new stack come from, and why does the kernel need a TSS at all in long mode?
4. What is the difference between the local APIC and the I/O APIC, and how does an MSI
   from a PCIe device reach a specific core?
5. Why does an operating system need ACPI on x86 but a device tree on most ARM boards,
   and what would break if both were absent?

If all five are easy, do Lab 6.1 only.

## Core ideas

**Why privilege exists.** Some operations must be reserved: changing address translation,
masking interrupts, touching devices. A privilege level is a bit (or two) of state that
the hardware consults before allowing those operations, and a trap is the controlled
transfer that happens when a less privileged program needs one. Everything that follows
is mechanism for making that transfer fast, safe and complete.

**RISC-V privilege.** Three modes: Machine (M, always present, highest), Supervisor (S,
for kernels) and User (U). CSRs per mode: `mstatus` (global interrupt enable, previous
privilege), `mtvec` (trap vector), `mepc` (return address), `mcause` (why), `mtval` (bad
address or instruction), `mscratch` (a free register for the handler), `mie`/`mip`
(interrupt enable/pending), and the S-mode twins prefixed `s`. Traps are synchronous
(exceptions: illegal instruction, misaligned access, page fault, `ecall`) or asynchronous
(interrupts: software, timer, external). All traps go to M-mode unless delegated with
`medeleg`/`mideleg`, which is how a kernel in S-mode gets its own traps and how a
hypervisor decides which the guest may handle. `mret`/`sret` return, restoring the
previous mode.

**Timers and interrupt controllers.** The Core-Local Interruptor (CLINT) provides
`mtime`/`mtimecmp` and software interrupts per hart; the Platform-Level Interrupt
Controller (PLIC) aggregates external device lines with priorities and per-hart enables.
Advanced Interrupt Architecture (AIA) adds message-signalled interrupts. The timer
interrupt is the heartbeat of every preemptive scheduler.

**Physical Memory Protection.** PMP registers in M-mode fence off address ranges from lower
modes even without paging. It is how firmware protects itself from the kernel on simple
cores.

**Paging on RISC-V.** `satp` holds the mode (Sv32, Sv39, Sv48) and root page-table
address. Page-table entries carry R/W/X/U/G/A/D bits. The A and D bits may be set by
hardware or trap for software to set. `sfence.vma` flushes the TLB. Supervisor code may not
touch U pages unless `sstatus.SUM` is set, which is a fine protection against a kernel
accidentally dereferencing a user pointer.

**x86-64 equivalents.** Rings 0 to 3 (only 0 and 3 used). Long mode makes segmentation
mostly vestigial, but the GDT must still exist with code and data descriptors and a TSS
descriptor. The IDT holds 256 gates: exceptions 0 to 31, then device interrupts. An
interrupt pushes SS, RSP, RFLAGS, CS, RIP (and an error code for some exceptions) onto a
stack, and when the privilege level changes the new stack comes from the TSS (`RSP0`), or
from the Interrupt Stack Table for critical exceptions like double fault. Control
registers: CR0 (protection, paging enable), CR3 (page-table root), CR4 (feature enables),
EFER (long mode, syscall enable, NX). Model-specific registers via `rdmsr`/`wrmsr`
configure everything else (`STAR`/`LSTAR` for the syscall entry, APIC base, VMX controls
later). `syscall`/`sysret` are the fast path, and they do not switch stacks, so the kernel
must do it with `swapgs` and a per-CPU pointer. Four-level paging (five with LA57): PML4,
PDPT, PD, PT, with 4 KiB, 2 MiB and 1 GiB pages; entries carry present, writable, user,
NX, accessed, dirty, global bits and PCIDs are the ASID equivalent.

**x86 interrupts.** The local APIC per core: timer, local vectors, inter-processor
interrupts, and the destination of everything. The I/O APIC routes legacy wired interrupts
to local APICs. MSI and MSI-X let a device write directly to a local APIC's address with a
vector number, which is why modern servers barely use the I/O APIC. x2APIC uses MSRs
instead of MMIO. Interrupt priority, EOI, spurious vectors, and the TSC-deadline timer mode
matter to your kernel and hypervisor.

**x86 legacy and hidden modes.** Real mode at reset, protected mode, then long mode, each
requiring specific dances (Module 8 does them). System Management Mode is a hidden, more
privileged mode entered by an SMI, invisible to the OS and the hypervisor; it is where
firmware does power management and where attackers love to live. Microcode updates are
loaded by firmware or the kernel at boot. The kernel and hypervisor sit on top of all of
this and can only trust it if it was measured.

**ARMv8-A.** Exception levels EL0 (user), EL1 (kernel), EL2 (hypervisor), EL3 (secure
monitor, where Trusted Firmware-A lives). Exception vectors are a table per level, indexed
by type and source. Translation via TTBR0/TTBR1 with two ranges for user and kernel, and a
second stage owned by EL2. The Generic Interrupt Controller (GICv3/v4) has distributor,
redistributors and CPU interfaces, with ITS for message-signalled interrupts. PSCI is the
firmware interface for powering cores on and off. The Pi 5 is this.

**Platform description.** A kernel cannot discover which interrupt controller exists, where
the timer is, how many cores there are, or what buses are not enumerable. On x86, firmware
provides ACPI tables: RSDP, XSDT, FADT, MADT (APICs and cores), SRAT (NUMA), MCFG (PCIe
configuration space), DSDT and SSDTs containing AML bytecode that the kernel interprets to
manage devices and power. On embedded ARM and RISC-V the device tree does the same job
statically: a tree of nodes with `compatible` strings, `reg` addresses and `interrupts`
properties, compiled from DTS to a binary blob the bootloader hands over. Servers on ARM
use ACPI too. Module 11 makes you write device tree bindings; Module 8 makes you read your
server's ACPI.

**SMBIOS.** Tables describing the platform's identity: manufacturer, serial number, DIMMs,
slots. `dmidecode` reads them. The BMC and inventory systems depend on them, and OMH's
fleet identity will start from them before attestation takes over.

## Reading

- RISC-V Privileged ISA spec: ch. 1 (introduction), ch. 3 (machine level, all), ch. 4
  (supervisor level), ch. 10 (Sv32, Sv39).
- Intel SDM vol. 3A: ch. 2 (system architecture overview), ch. 3 (protected mode memory
  management), ch. 4 (paging), ch. 5 (protection), ch. 6 (interrupt and exception
  handling), ch. 8 (task management, just the TSS in 64-bit mode), ch. 10 and 11 (APIC).
- OSDev wiki: GDT, IDT, Exceptions, APIC, IOAPIC, Paging, Setting Up Long Mode. Fast,
  accurate, and pitched exactly right for someone who has read the SDM chapter.
- ACPI specification, ch. 5 (system description tables), ch. 6 (device configuration:
  `_CRS`, `_PRT`), and skim ch. 19 (ASL reference).
- ARM Cortex-A Series Programmer's Guide for ARMv8-A: ch. 3 (fundamentals), ch. 10 (AArch64
  exception handling), ch. 12 (memory management).
- The devicetree specification, ch. 2 and 3.

## Labs

### Lab 6.1: M-mode on your CPU

1. Add CSRs: `mstatus` (MIE, MPIE, MPP), `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`,
   `mie`, `mip`. Add `ecall`, `ebreak`, `mret`, and trap entry: on any exception or enabled
   interrupt, save PC to `mepc`, set `mcause`, disable interrupts, jump to `mtvec`. Make
   exceptions precise in your pipeline: instructions after the faulting one must not have
   side effects (this is why you read Ibex in Module 4).
2. Add a CLINT-style `mtime`/`mtimecmp` peripheral to the bus and wire the timer interrupt.
3. Write a trap handler in assembly that saves all registers to a trap frame on a dedicated
   stack (using `mscratch`), calls a C dispatcher, restores, `mret`s. The C dispatcher
   prints the cause and either handles or panics.
4. Test: illegal instruction, misaligned load, `ecall`, and a timer interrupt every 10 ms
   that prints a tick.
5. Preemptive multitasking: two bare-metal "tasks" with their own stacks; the timer handler
   swaps the saved register frame. Watch two loops interleave on the UART.

Done when: all four traps are handled with correct `mcause`/`mtval`, and two tasks
alternate under timer preemption on the FPGA.

### Lab 6.2: U-mode and protection on your CPU

1. Add U-mode: `mret` into U with `MPP = 0`. In U-mode, CSR access and `mret` trap as
   illegal.
2. Implement PMP with at least two entries in NAPOT mode. Mark M-mode code and data
   inaccessible from U. Run a user program that reads the timer (allowed) and then writes
   to a protected address (traps). Handle the fault, print it, and kill the task.
3. If you did Lab 5.5, enable Sv32 for the user task: map its code and stack, leave the
   kernel unmapped, and show a page fault with `mtval` holding the faulting address.
4. Implement a two-syscall ABI over `ecall`: `write(fd, buf, len)` and `exit(code)`. Your
   user program prints through it.

Done when: a U-mode program runs, calls `write` via `ecall`, and is killed cleanly when it
touches protected memory.

### Lab 6.3: x86-64 bare metal in QEMU

Use a Multiboot2 stub loaded by GRUB, or the Limine bootloader, so this lab is about the
CPU and not booting (Module 8 replaces the stub with your own).

1. From the 32-bit or 64-bit entry, set up a GDT with 64-bit code and data descriptors and
   a TSS with an `RSP0` and one IST entry. Load it. Set up an IDT with handlers for all 32
   exceptions that dump the saved frame to the serial port (16550 at 0x3F8, polling).
2. Trigger `#DE` (divide by zero), `#UD`, `#PF` (touch an unmapped address; read CR2), and
   `#DF` via a stack overflow into an unmapped guard, and confirm the IST stack saved you.
3. Enable the local APIC (x2APIC via MSR if QEMU offers it), program the timer in periodic
   mode, calibrate it against the PIT or the TSC, and print a tick each 10 ms with a
   proper EOI.
4. Set `LSTAR`, `STAR`, `SFMASK`; enable `EFER.SCE`; enter ring 3 via `iretq` into a user
   page; execute `syscall`; return with `sysretq`. Swap stacks correctly with `swapgs` and a
   per-CPU structure in `GS`.
5. Run the same binary on the server via a GRUB entry (serial console over SOL). Observe
   what differs.

Done when: the four exceptions print correctly, the APIC timer ticks, and a ring-3 syscall
round-trips on QEMU and on the server.

### Lab 6.4: Read your server's ACPI and SMBIOS

1. `acpidump` then `acpixtract`; `iasl -d` the DSDT and SSDTs. Find the PCI root bridge
   `_CRS` and confirm the MMIO windows against `lspci`'s bridge resources. Find the `_PRT`
   and trace how a legacy interrupt on your NIC's slot would route.
2. Parse the MADT by hand from the hex dump: count local APICs (cores and threads), I/O
   APICs, and interrupt source overrides. Compare with `lscpu` and `/proc/interrupts`.
3. Read the MCFG and compute the address of your NIC's extended configuration space. Read
   it from `/dev/mem` (or via sysfs) and confirm it matches Lab 5.4.
4. Find the SRAT and SLIT if present; draw the NUMA distance table.
5. `dmidecode`: system serial, board serial, each DIMM's part number and speed. Note which
   fields the BMC exposes over Redfish (Module 8).

Done when: your notebook has the annotated MADT, the root bridge resources cross-checked,
and the extended configuration space address computed and verified.

## Problem set

1. Trace an `ecall` from U-mode on RISC-V step by step: which CSRs change, in what order the
   handler must save state, and where the return address comes from. Then do the same for
   a timer interrupt arriving while in M-mode with interrupts enabled.
2. Why does the trap handler need `mscratch` (or `swapgs` on x86)? Describe the bug you get
   without it when a user program sets the stack pointer to garbage before `ecall`.
3. What does delegating the timer interrupt to S-mode via `mideleg` change about who runs
   when? Why would a hypervisor delegate page faults but not external interrupts?
4. On x86-64, a `#PF` occurs in ring 3. List every value pushed to the stack, where the
   stack comes from, and what CR2 holds. Now a `#DF` occurs while handling that `#PF` on a
   corrupted stack: what saves you?
5. Compute the Sv39 walk for VA 0xFFFF_FFC0_0001_0000 and explain why the address must be
   sign-extended from bit 38.
6. Compare the interrupt paths for a PCIe MSI on x86 (device write → local APIC → vector →
   IDT) and ARM (device write → GIC ITS → LPI → redistributor → vector table). Where does
   each system store the vector-to-handler mapping?
7. Why is SMM a problem for a hypervisor's security model? What does measured boot do about
   it, and what can it not do?
8. Write the device-tree node for your Wishbone timer at 0x4000_0000 with an interrupt on
   PLIC source 3. Then write the equivalent as an ACPI `Device` with `_HID`, `_CRS` memory
   and interrupt descriptors. What does an OS driver key on in each case?
9. Explain what would go wrong if two cores took the same timer interrupt handler using
   one shared trap stack. Fix it.

## Deliverables

- Your CPU with M and U modes, PMP, traps, timer, preemptive tasks and a two-call ABI.
- The x86-64 bare-metal program running on QEMU and the server.
- Annotated ACPI and SMBIOS notes from the server.

## Stretch

- Add S-mode with delegation and run a tiny S-mode "kernel" under your M-mode "firmware".
  You have now built the shape of OpenSBI and can read its source with recognition.
- Port Lab 6.3 to the Pi 5 at EL1 with a bare-metal EL2 stub (the Pi's firmware enters
  the kernel at EL2). Set up the vector table, the generic timer and the GIC.
- Read the RISC-V Hypervisor extension chapter and mark which CSRs from Lab 6.1 acquire
  a virtual twin.

## Next

Part III begins with firmware. Module 7 takes you to a microcontroller, where there is no
privilege level and no MMU, and you write everything from the reset vector up.
