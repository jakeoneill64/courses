# Module 9: Write a kernel

**Part IV · 5 weeks · Needs: QEMU, your UEFI loader from Module 8, the server with a spare NVMe drive, x86_64-elf cross compiler.**

## Why this module (and what it buys OMH)

You will never ship a kernel you wrote. You will ship Linux, configured, patched and
occasionally bisected at two in the morning while a customer's Storage module is down. The
purpose of writing your own is that afterwards Linux has no mysteries at the level of
mechanism: you know what a page fault handler must do because yours does it, you know why
the scheduler needs per-CPU run queues because yours deadlocked without them, and you know
what an NVMe completion looks like because you polled for one. Storage and Blocks are
NVMe products; that driver is not optional.

Target x86-64, because it is what OMH modules will run and because its legacy makes the
platform lessons concrete. Read xv6-riscv alongside as the clean reference; port at the
end if you want to see how much was x86.

## Skip test

1. A user process touches an unmapped stack page. Trace the path from the CPU raising the
   exception to the process resuming, including every data structure the kernel consults.
2. Two cores each hold a spinlock and want the other's. How did you get here and what
   discipline prevents it? Why must the spinlock also disable interrupts?
3. Describe the state saved on a context switch between two kernel threads, and why it is
   less than the state saved on a trap from user mode.
4. Design the steps to bring up a second CPU on x86: what does the BSP send, what state
   does the AP start in, and what must be set up before it can run C code?
5. Walk an NVMe read: what does the host write where, how does the device find the data
   buffer, and how does the host learn the command completed?

If all five are easy, do Labs 9.3 and 9.5 only.

## Core ideas

**What a kernel is.** A program that owns the privileged state (Module 6) and multiplexes
the machine among programs that do not. Mechanisms: memory protection via paging, time
sharing via timer interrupts and context switches, controlled entry via syscalls, device
access via drivers. Policies (scheduling, allocation) sit on top and are separable.

**The handoff.** Your UEFI loader (Module 8) leaves you in long mode with paging on, a
memory map, a framebuffer, the RSDP and a command line. Before anything else: a serial
console for `printk`, a panic routine that dumps registers and halts, and your own GDT,
IDT and page tables so nothing depends on firmware's.

**Physical memory management.** Parse the memory map into usable ranges. Allocate frames
with a bitmap (simple) or a buddy allocator (fast, supports contiguous multi-page
allocations, which DMA needs). Track what firmware, ACPI tables and your kernel already
occupy.

**Virtual memory management.** The kernel lives in the higher half (top of the address
space) so user programs can have the bottom. A direct map of all physical memory at a fixed
offset makes physical-to-virtual translation a subtraction. Four-level page tables: map,
unmap, protect, walk, with TLB invalidation (`invlpg`) after changes. Per-process address
spaces are separate PML4s sharing the kernel half. A kernel heap (bump, then slab-style
size classes) sits on top of the page allocator.

**Interrupts and time.** IDT from Module 6. The local APIC timer is the scheduler tick;
calibrate it against the PIT, HPET or a known TSC frequency from CPUID. Keep interrupt
handlers short; defer work to a softirq-style mechanism or to threads. The TSC is the
cheap clock; make it monotonic and calibrated.

**Threads and the context switch.** A thread is a kernel stack plus saved registers. To
switch, push callee-saved registers and the stack pointer of the current thread, load the
next thread's, return into its context. That is a dozen instructions. Switching between
processes also loads a new CR3. The first entry into a new thread is faked by constructing
a stack that looks like it was switched away from.

**Scheduling.** Round-robin first; then priorities; then per-CPU run queues with idle
balancing. Sleep and wake queues for blocking on I/O or time. The idle thread `hlt`s.
Preemption happens in the timer interrupt's return path, and a `preempt_disable` count is
how you stop it in critical regions.

**SMP.** Find application processors in the MADT. Send INIT then STARTUP inter-processor
interrupts with a real-mode trampoline address. Each AP starts in 16-bit real mode and must
be walked into long mode with the same code you already have, then load a per-CPU GDT, IDT,
TSS and a per-CPU data structure reachable from `GS`. Spinlocks (`lock xchg` or `cmpxchg`
with a pause loop) protect shared data; they must disable interrupts if the lock can be
taken from an interrupt handler. TLB shootdown: after changing a shared mapping, send an IPI
to every CPU that might have it cached.

**User mode.** Load an ELF64: parse program headers, map segments with the right
permissions into a fresh address space, set up a user stack with `argv` and `envp`, and
enter ring 3 via `iretq` or `sysretq`. Syscalls arrive via `syscall` at your `LSTAR`
handler, which swaps to the kernel stack, saves user registers, dispatches by number,
validates every user pointer (in range, mapped, correct permissions) before copying,
returns. Fork duplicates the address space (copy-on-write: share pages read-only, copy on
write fault, with reference counts). Exec replaces it. Exit frees it. Wait reaps.
Page faults are how lazy allocation, CoW and demand paging all work: the fault handler
decides whether the access was legal and fixes the mapping or kills the process.

**Devices and the block path.** PCI enumeration over configuration space (Module 5) to find
your NVMe controller and read its BAR. NVMe: map the controller registers, read
capabilities, configure and enable the controller, create the admin submission and
completion queues in memory, issue Identify, create an I/O queue pair, then read and write
blocks by writing 64-byte commands into the submission queue, ringing the doorbell, and
either polling the completion queue's phase bit or taking the MSI-X interrupt. Data
buffers are physical addresses in PRP entries. Nothing here is hard; it is simply exact.

**Filesystems.** A block cache, then a read-only FAT32 or ext2 parser to load user programs
from the drive. A VFS layer (inode, file, directory operations as tables of function
pointers) so the console, the disk and a pipe share one interface. Writing back is a
stretch; understanding the layering is the point.

**Debugging a kernel.** QEMU's gdbstub (`-s -S`) with the kernel's symbols; `-d int` to log
every interrupt; `-d guest_errors`; the monitor for `info mem`, `info tlb`, `info
registers`. A triple fault resets the machine silently unless you ask QEMU to stop. On the
server, the serial console over SOL and patience.

**Reading xv6.** It is under ten thousand lines, complete, and documented by a book. Read
it in full over two weekends near the start, then again after your kernel works. Notice
what it leaves out (SMP bring-up is there; NVMe is not) and what it does simply (the
scheduler, the trap path).

## Reading

- Arpaci-Dusseau, *Operating Systems: Three Easy Pieces*: all of the Virtualisation and
  Concurrency parts; Persistence part ch. 36 to 40 (I/O devices, disks, RAID, files).
- Cox, Kaashoek, Morris, *xv6: a simple, Unix-like teaching operating system* (RISC-V
  version) with the source. Read both fully.
- OSDev wiki: "Bare Bones", "Higher Half Kernel", "Page Frame Allocation", "Paging",
  "APIC", "APIC timer", "Symmetric Multiprocessing", "System Calls", "ELF", "PCI",
  "NVMe", "FAT". Cross-check every fact against the SDM or the spec; the wiki is right
  more often than not, which is not always.
- Intel SDM vol. 3A ch. 4, 6, 8, 10, 11 (again, now with purpose), vol. 3B ch. 17 (debug
  registers) and 18 (performance monitoring) as needed.
- NVMe Base Specification 2.0: ch. 3 (architecture, queues, doorbells), ch. 4 (memory
  structures: PRPs, SGLs), ch. 5 (admin commands: Identify, Create Queue), and the NVM
  Command Set specification (Read, Write, Flush).
- Anderson and Dahlin, *Operating Systems: Principles and Practice*, ch. 4 to 7 if OSTEP
  leaves you wanting a second treatment of concurrency.
- Linux `Documentation/arch/x86/boot.rst` if you decide to make your loader also boot
  Linux (useful for Module 12).

## Labs

Weekly milestones. Each is a working kernel; commit and tag each.

### Lab 9.1: Boot, console, exceptions

1. From your UEFI loader's handoff: serial console driver with `printk` (your own
   formatter, `%d %u %x %p %s %c`), a framebuffer console that scrolls, `panic()` with
   register dump and halt.
2. Own GDT with TSS; own IDT with all 32 exception handlers that print a frame dump, plus
   stubs for vectors 32 to 255 that log and EOI.
3. Parse and print the memory map, total usable RAM, the RSDP and the MADT (CPU count).
4. Set up your own page tables: higher-half kernel, direct map of all physical memory.
   Switch to them. Unmap the firmware's identity map. Survive.

Done when: the kernel boots on QEMU and the server, prints its memory map and CPU count,
and each provoked exception dumps a correct frame.

### Lab 9.2: Memory

1. Physical frame allocator: buddy allocator with orders 0 to 10, backed by the memory
   map, with `alloc_pages(order)` and `free_pages`. Unit tests run at boot under a
   `CONFIG_SELFTEST` flag: allocate everything, free everything, check coalescing.
2. Virtual memory API: `map(addr_space, va, pa, flags)`, `unmap`, `protect`, `walk`, with
   `invlpg`. Create and destroy address spaces sharing the kernel half.
3. Kernel heap: size-class slab allocator for 16 to 4096 bytes on top of pages, with
   `kmalloc`/`kfree`, plus a large-allocation path. Poison freed memory in debug builds.
4. Guard pages under every kernel stack; confirm an overflow produces a page fault with a
   readable message rather than silent corruption.

Done when: self-tests pass, and a deliberate stack overflow reports itself.

### Lab 9.3: Time, threads, scheduler, SMP

1. Local APIC timer calibrated against the PIT (or HPET); TSC frequency from CPUID or
   calibration; `ktime_ns()` monotonic. Tick at 1 kHz.
2. Kernel threads: `kthread_create(fn, arg)`, context switch in assembly, a run queue,
   round-robin preemption from the tick, `yield`, `sleep_ms` via a timer wheel or sorted
   list, `wait_queue` with `wake_up`.
3. Spinlocks with interrupt save/restore; a lock-ordering assertion in debug builds; a
   simple mutex built on a wait queue.
4. SMP: parse the MADT, place a real-mode trampoline below 1 MiB, send INIT/SIPI/SIPI,
   bring every AP into long mode with per-CPU GDT/IDT/TSS/stack and a per-CPU struct via
   `GS` base. Each AP runs the idle loop. Per-CPU run queues with a simple work-stealing
   balance. Demonstrate `N` threads spinning on `N` cores with `top`-style output.
5. TLB shootdown IPI for kernel-half unmaps.

Done when: on the server, all cores are online, threads migrate, and a stress test with
hundreds of threads sleeping and waking runs for an hour without a lockup.

### Lab 9.4: User mode

1. ELF64 loader into a new address space; user stack with `argv`; entry via `iretq`.
2. Syscall entry via `syscall`/`LSTAR` with `swapgs` and the per-CPU kernel stack. ABI: your
   own numbering. Implement `write`, `read`, `exit`, `getpid`, `fork` (copy-on-write with
   frame refcounts), `execve`, `waitpid`, `mmap` (anonymous), `brk`, `open`/`close` for the
   console, `sleep`.
3. A user pointer validation routine used by every syscall; a test program that passes a
   kernel address and must receive `-EFAULT`, not crash the kernel.
4. Page-fault handler: lazy allocation of anonymous mappings, CoW resolution, stack growth,
   and a clean kill with a message for anything else.
5. A userland: your own tiny libc (`crt0`, syscall stubs, `printf`, `malloc` on `brk`),
   `init`, and a shell that forks and execs commands from an in-memory table. Ports of a
   few simple programs.

Done when: the shell runs on QEMU and the server, `fork` bombs are survivable, and the
`-EFAULT` test passes.

### Lab 9.5: PCI, NVMe, a filesystem

1. PCI enumeration: walk bus/device/function, print vendor/device/class, decode BARs,
   find MSI-X capabilities. Match the output of `lspci` on the server.
2. NVMe driver: map BAR0, reset and configure the controller (`CC`, `AQA`, `ASQ`, `ACQ`),
   admin queue pair, Identify Controller and Namespace, create one I/O queue pair, `read`
   and `write` for LBA ranges with PRP lists, completion by polling the phase bit, then by
   MSI-X interrupt with a wait queue. Test on QEMU `-device nvme` first, then on the
   server's sacrificial drive. Triple-check the drive selection before the first write.
3. Block cache with LRU; a read-only FAT32 driver (or ext2); a VFS with `open`, `read`,
   `readdir` over both the FAT and the console device. Load user programs from the drive
   instead of the in-memory table.
4. Measure: sequential 4 KiB reads with polling versus interrupts; queue depth 1 versus 32.
   Relate the numbers to Module 5's Little's law and note them for Module 13.

Done when: `ls` in your shell lists the FAT filesystem on the real NVMe drive, and the
throughput table is in your notebook.

### Lab 9.6: Choose one

- **Networking**: a virtio-net (QEMU) or e1000 driver, ARP, IPv4, UDP, and a `udp_echo`
  program. Ethernet frames into the kernel are a healthy dose of "hardware lies".
- **RISC-V port**: rebuild the kernel for QEMU `virt` on top of OpenSBI: Sv39, PLIC, CLINT
  via SBI, `virtio-blk` for storage. Write a page on what was x86-specific.
- **Booting Linux**: make your UEFI loader also boot a Linux bzImage via the boot protocol
  with an initrd and a command line. This is exactly what Module 12's VMM will do inside a
  VM.

Done when: the chosen option works and is documented.

## Problem set

1. Design your syscall ABI: register assignments, error convention, how a syscall with
   seven arguments works, and how you would add a syscall without breaking old binaries.
   Compare with Linux's choices and justify each difference.
2. A 64 GiB machine with 4 KiB pages: how much memory do the page tables take if every
   page is mapped once? With 2 MiB pages? Why does the direct map use 1 GiB pages where it
   can?
3. Write the TLB shootdown protocol for unmapping a kernel-half page on a 32-core machine:
   what is sent, who acknowledges, what the sender may do meanwhile, and what happens if a
   target CPU has interrupts disabled for a long time.
4. Why must interrupts be disabled between saving the outgoing thread's state and loading
   the incoming thread's stack pointer? Where exactly can they be re-enabled, and what
   goes wrong one instruction earlier?
5. CoW fork: describe the refcount protocol for a frame shared by three processes as each
   writes in turn. What happens if a process with a shared frame `exit`s? What if it
   `mmap`s over the region?
6. NVMe completion queues use a phase bit rather than a "valid" flag. Explain why, and what
   the host must do when the queue wraps.
7. Your spinlock uses `xchg` in a loop. Why add `pause`? Why must the unlock be a plain
   store with a compiler barrier and not a locked instruction? Which memory ordering does
   x86 give you for free here that RISC-V would not?
8. A user program passes a pointer to a buffer that spans a mapped page and an unmapped
   page. Your `write` syscall copies 4 KiB. Show the exact check sequence that avoids both
   a kernel fault and a time-of-check-to-time-of-use race with another thread that
   `munmap`s concurrently.
9. Estimate the interrupt latency and the context switch cost of your kernel on the server
   using the TSC, then explain each contribution.

## Deliverables

- A tagged kernel per milestone, booting on QEMU and the server, with a `README` that
  states what works, what does not, and how to run the self-tests.
- Throughput table from the NVMe driver.
- Your ABI document.

## Stretch

- Signals: delivery on return to user mode, a trampoline for handler return, `SIGSEGV` to a
  handler instead of a kill.
- A write path for the filesystem with a journaling scheme you design, and a crash test
  that kills QEMU mid-write and verifies consistency on remount.
- Run your kernel as a guest inside your own Module 12 VMM.

## Next

Module 10 turns to the kernel OMH will actually ship. You will read Linux with the map you
now carry in your head, trace it live, and write modules for it.
