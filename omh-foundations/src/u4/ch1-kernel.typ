#import "../lib/template.typ": *

= Write a kernel <ch-kernel>

#chapter-meta(
  weeks: [5 weeks],
  builds: [A 64-bit SMP kernel for x86-64, started by both of your Chapter 2.7 loaders on QEMU and the lab server: its own consoles, GDT, IDT and page tables, a buddy allocator and slab heap, a per-CPU scheduler on every core, user processes with copy-on-write `fork` and validated system calls, a libc and shell, PCI enumeration, an NVMe driver with polled and MSI-X completion, and a read-only FAT32 filesystem on a real drive.],
  needs: [QEMU with SeaBIOS and OVMF, your Lab 2.7.1 and 2.7.2 loaders, an `x86_64-elf` cross compiler, the lab server with serial-over-LAN, and the Kingston NV3 as the sacrificial drive.],
)

#why[
  OMH will ship Linux, configured and patched by you and occasionally bisected at two in the morning while a customer's Storage module is down. Writing your own kernel first removes the mysteries of mechanism: you know what a page-fault handler must do because yours does it, why a scheduler keeps per-CPU run queues because yours deadlocked without them, and what an NVMe completion looks like because you polled for one. Storage and Blocks are NVMe products, so the driver lab is the one you may not skip. The target is x86-64, which OMH modules run. Chapter 4.4 runs this kernel as a guest of your VMM and then turns it into a hypervisor.
]

#skip-test(
  rule: [If all five are easy, do Labs 4.1.3 and 4.1.5 only.],
  [A user process touches an unmapped stack page. Trace the path from the CPU raising the exception to the process resuming, naming every data structure the kernel consults.],
  [Two cores each hold a spinlock and want the other's. How did they get there, and what discipline prevents it? Why must a spinlock that an interrupt handler also takes disable interrupts?],
  [Describe the state saved on a context switch between two kernel threads, and why it is less than the state saved on a trap from user mode.],
  [Give the steps that bring up a second x86 core: what the bootstrap processor sends, what state the application processor starts in, and what must exist before it can run C.],
  [Walk an NVMe read: what the host writes where, how the device finds the data buffer, and how the host learns that the command completed.],
)

== Core ideas

*What a kernel is.* A program that owns the privileged state of Chapter 2.5 and multiplexes the machine among programs that do not, through memory protection by paging, time sharing by timer interrupts and context switches, controlled entry by system calls, and device access by drivers. Policies such as scheduling and allocation sit on top and can change independently.

*The handoff.* Your Lab 2.7.2 loader leaves the CPU in long mode with boot services exited and passes a boot-information structure: memory map, framebuffer, RSDP and command line. Your Lab 2.7.1 loader can pass the same structure once its stage two collects the E820 map, and a kernel that boots unchanged from both depends on nothing else. The kernel's first jobs are a serial console for `printk`, a `panic` that dumps registers and halts, and its own GDT, IDT and page tables.

#fig("/figures/u4-kernel-boot-flow.svg", caption: [One kernel, two loaders. Both fill the same boot-information structure; the initialisation order on the right is the order of Labs 4.1.1 to 4.1.5.])

*Physical memory.* Parse the map into usable ranges, minus the kernel image, the loader's structures, ACPI tables and firmware runtime regions. A buddy allocator is fast and returns the contiguous power-of-two blocks that DMA needs; build it in preference to a bitmap.

*Virtual memory.* The kernel lives in the higher half and user programs in the lower. A direct map of all physical memory at a fixed offset turns physical-to-virtual translation into an addition. Four-level tables need map, unmap, protect and walk, each change followed by `invlpg`. Every process's PML4 shares its upper 256 entries, so the kernel half is identical everywhere. A slab heap sits on the page allocator, and the image links in the top 2 GiB so that `-mcmodel=kernel` code reaches it with 32-bit displacements.

#fig("/figures/u4-kernel-address-space.svg", caption: [One possible layout for your kernel. Every PML4 points its upper 256 entries at the same kernel tables, so a context switch changes CR3 without changing the kernel's view of memory.])

*Interrupts and time.* The GDT, TSS, IDT and APIC code of Lab 2.5.3 carries over. The local APIC timer is the scheduler tick; calibrate it and the TSC against the PIT or the HPET, and build a monotonic `ktime_ns()` on the TSC. Handlers stay short and defer work to a queue or a thread.

*Threads and the context switch.* A thread is a kernel stack plus saved registers. To switch, push the callee-saved registers, save the stack pointer, load the next thread's, pop and return: about a dozen instructions, plus a CR3 load between processes. A new thread's first run is faked with a stack that looks as if it had been switched away from.

*Scheduling.* Round-robin, then priorities, then per-CPU run queues with idle balancing. Wait queues block threads on time or I/O, and the idle thread runs `hlt`. Preemption happens on the timer interrupt's return path, and a per-CPU `preempt_disable` count holds it off in critical regions.

*SMP.* The MADT lists the application processors (APs) as local APIC or x2APIC entries. The bootstrap processor sends each an INIT inter-processor interrupt, then two STARTUP IPIs whose vector is the page number of a real-mode trampoline below 1 MiB. The AP climbs from real mode to long mode through code you already have, loads its own GDT, TSS, IDT and stack, finds its per-CPU structure through the GS base and reports in. Spinlocks (`xchg` or `lock cmpxchg`, with `pause` in the loop) must disable interrupts when a handler takes the same lock. Changing a mapping that other CPUs may cache needs a TLB shootdown: an IPI to each of them and an acknowledgement from each.

#fig("/figures/u4-kernel-smp-bringup.svg", caption: [Bringing up one application processor. The trampoline's data area carries the page-table root and stack that the AP needs to reach long mode and C.])

*User mode.* Load an ELF64 by mapping each segment with its permissions into a fresh address space, build a user stack with `argv` and `envp`, and enter ring 3 with `iretq` or `sysretq`. A `syscall` arrives at your `LSTAR` entry, which uses `swapgs` to reach the kernel stack, saves user registers, dispatches by number and validates every user pointer (in range, mapped, permitted) before copying. `fork` shares frames read-only with reference counts and copies on the first write fault; `execve` replaces the address space, `exit` frees it and `waitpid` reaps. Lazy allocation, copy-on-write and stack growth all live in the page-fault handler, which fixes the mapping or kills the process.

*Devices and the block path.* PCI enumeration over the configuration space of Lab 2.4.4 finds the NVMe controller's BAR0. Bring-up is a fixed sequence: clear `CC.EN` and wait for `CSTS.RDY` to fall; place the admin queues in memory and program `AQA`, `ASQ` and `ACQ`; set `CC.EN` and wait for ready; issue Identify; create an I/O queue pair. A command is 64 bytes in a submission queue followed by a write of the new tail to its doorbell, with data buffers given as physical addresses in PRP entries. A completion is 16 bytes whose phase bit inverts on each pass round the ring; the host polls for it or takes an MSI-X interrupt, then writes the head doorbell.

#fig("/figures/u4-kernel-nvme-queues.svg", caption: [An NVMe read on one queue pair. The driver owns the submission queue's tail and the completion queue's head, the controller the other two; the phase bit tells the driver which completions are new on this pass.])

*Filesystems.* A block cache, then a read-only FAT32 or ext2 parser that loads programs from the drive. A VFS of inode, file and directory operation tables lets the console, the disk and a pipe share one interface; the layering is the lesson.

*Debugging a kernel.* QEMU's gdbstub (`-s -S`) with your symbols; `-d int,cpu_reset` and `-d guest_errors`; `-no-reboot`, so a triple fault stops QEMU instead of restarting the guest; and the monitor's `info registers`, `info mem` and `info tlb`. On the server: the SOL console, the framebuffer through the BMC's virtual console, and patience.

*Reading xv6.* xv6 is under ten thousand lines, complete, and documented by a book. Read it fully over two weekends near the start and again once your kernel works, noting what it omits (it runs on several harts but has no NVMe driver) and what it does simply (the scheduler and the trap path).

== Reading

- Arpaci-Dusseau, _Operating Systems: Three Easy Pieces_: the Virtualisation and Concurrency parts, and Persistence chapters 36 to 40.
- Cox, Kaashoek and Morris, _xv6: a simple, Unix-like teaching operating system_ (RISC-V edition) and its source, both in full.
- OSDev wiki: Bare Bones, Higher Half Kernel, Page Frame Allocation, Paging, APIC, APIC Timer, Symmetric Multiprocessing, System Calls, ELF, PCI, NVMe and FAT. Check each fact against the SDM or the specification; the exceptions cost days.
- Intel SDM volume 3A: paging, interrupt and exception handling, multiple-processor management (the MP initialisation protocol), the APIC and memory cache control; volume 3B's debug and performance-monitoring chapters as needed.
- NVM Express Base Specification (revision 2.4 at the time of writing): queues, controller initialisation, queue entries, PRPs, Identify and the Create I/O Queue commands. The NVMe over PCIe Transport and NVM Command Set specifications for doorbells and for Read, Write and Flush.
- Anderson and Dahlin, _Operating Systems: Principles and Practice_, chapters 4 to 7, for a second view of concurrency.
- Linux `Documentation/arch/x86/boot.rst`, if you boot Linux in Lab 4.1.6.

== Labs

Each lab is a weekly milestone; commit and tag a working kernel at each. Compile with your `x86_64-elf` cross compiler and `-ffreestanding`, `-mno-red-zone`, `-mgeneral-regs-only` and `-mcmodel=kernel`: interrupts would overwrite a red zone, and the SSE registers hold user state that you do not save on entry. Run `qemu-system-x86_64` with `-machine q35 -smp 4 -m 4G`, `-serial stdio` and `-no-reboot`, with OVMF for the UEFI loader and SeaBIOS for the BIOS one.

#lab([Boot, console and exceptions], time: [1 weekend])[
+ From the Lab 2.7.2 handoff, write a serial driver with `printk` and your own formatter (`%d %u %x %p %s %c`), a scrolling framebuffer console, and a `panic` that dumps registers and halts. Take the server's console port from the ACPI SPCR table: SOL is usually COM2 at 0x2F8, where QEMU's first port is at 0x3F8.
+ Install your own GDT with a TSS and your own IDT: 32 exception handlers that dump the frame, and stubs for vectors 32 to 255 that log and send an EOI.
+ Print the memory map and usable RAM; walk the RSDP and XSDT to the MADT and count the CPUs.
+ Build page tables for the higher half and the direct map, load CR3, unmap the loader's identity map and keep running.
+ Make your Lab 2.7.1 stage two collect the E820 map through interrupt 15h into the same structure. Boot one kernel binary from both loaders in QEMU, then from the UEFI loader on the server, signed with your db key if Lab 2.7.3 left Secure Boot on.

#done-when(
  [The kernel boots from both loaders in QEMU and from the UEFI loader on the server, printing its memory map and CPU count.],
  [Each provoked exception (`#DE`, `#UD`, `#GP`, `#PF`) dumps a correct frame.],
)
#evidence([Serial logs from QEMU and the server; the boot-information structure; one annotated exception dump.])
] <lab-kern-boot>

#lab([Memory], time: [1 weekend])[
+ Write a buddy allocator for orders 0 to 10 over the memory map, with `alloc_pages(order)`, `free_pages` and boot-time self-tests behind `CONFIG_SELFTEST` that allocate everything, free everything and check that blocks coalesce back to the starting counts.
+ Write `map(as, va, pa, flags)`, `unmap`, `protect` and `walk` with `invlpg`; create and destroy address spaces that share the kernel half.
+ Build a slab heap with size classes from 16 to 4,096 bytes (`kmalloc`, `kfree`), a path for large allocations, and poisoning of freed memory in debug builds.
+ Put an unmapped guard page under every kernel stack. An overflow faults while pushing the page-fault frame and becomes a double fault, so give `#DF` its own IST stack and make its handler name the thread and the address in CR2.

#done-when(
  [The self-tests pass on every boot.],
  [A deliberate stack overflow reports itself by name instead of corrupting memory.],
)
#evidence([Allocator statistics around the self-test; the overflow report.])
] <lab-kern-memory>

#lab([Time, threads, scheduling and SMP], time: [2 weekends])[
+ Calibrate the local APIC timer and the TSC against the PIT or the HPET, comparing with CPUID leaf 0x15 where the processor reports it; tick at 1 kHz and implement a monotonic `ktime_ns()`.
+ Write kernel threads: `kthread_create(fn, arg)`, a context switch in assembly, a run queue, round-robin preemption from the tick, `yield`, `sleep_ms` on a timer wheel or sorted list, and wait queues with `wake_up`.
+ Add spinlocks that save and restore the interrupt flag, a lock-order assertion in debug builds, and a mutex built on a wait queue.
+ Copy a trampoline below 1 MiB, send INIT, STARTUP and STARTUP to each AP in the MADT, and bring each to long mode with its own GDT, TSS, stack and per-CPU structure behind the GS base, running the idle loop. Add per-CPU run queues with simple work stealing, and show $N$ threads spinning on $N$ cores in a `top`-style display.
+ Implement a TLB-shootdown IPI for kernel-half unmaps.

#done-when(
  [On the server every core is online and threads migrate between cores.],
  [Hundreds of threads sleeping and waking run for an hour without a lockup.],
)
#evidence([Calibration numbers; the per-CPU display; the stress-test log with its duration.])
] <lab-kern-smp>

#lab([User mode], time: [2 weekends])[
+ Load an ELF64 into a new address space with an `argv` stack and enter it through `iretq`.
+ Enter system calls through `syscall` and `LSTAR` with `swapgs` and the per-CPU kernel stack, numbered by your own ABI: `write`, `read`, `exit`, `getpid`, `fork` (copy-on-write with frame reference counts), `execve`, `waitpid`, anonymous `mmap`, `brk`, console `open` and `close`, and `sleep`.
+ Route every system call through one user-pointer validator, and test it with a program that passes a kernel address and must receive `-EFAULT` while the kernel carries on.
+ Serve lazy anonymous mappings, copy-on-write and stack growth in the page-fault handler, and kill the process with a clear message for anything else.
+ Build a userland: a small libc (`crt0`, system-call stubs, `printf`, `malloc` on `brk`), `init`, a shell that forks and execs commands from an in-memory table, and a few ported programs.

#done-when(
  [The shell runs on QEMU and on the server.],
  [A fork bomb leaves the kernel responsive, refusing new processes cleanly when memory runs out, and the `-EFAULT` test passes.],
)
#evidence([Your ABI document; a shell session log; the page-fault kill messages.])
] <lab-kern-user>

#lab([PCI, NVMe and a filesystem], time: [2 weekends], kit: [QEMU with `-device nvme`; the server with the Kingston NV3 on its ICY DOCK adapter.])[
+ Enumerate PCI through ECAM, from the MCFG table as in Lab 2.5.4: every bus, device and function, with vendor, device, class, BARs and MSI-X capabilities. Match `lspci -nn` on the server.
+ Write the NVMe driver: map BAR0, reset and enable the controller through `CC`, `AQA`, `ASQ` and `ACQ`, issue Identify Controller and Identify Namespace, create one I/O queue pair, and read and write LBA ranges with PRP lists. Complete first by polling the phase bit, then by MSI-X with a wait queue. Test on QEMU's NVMe device first.
+ Print each controller's model and serial number, and record whether the NV3 asks for a host memory buffer in the `HMPRE` and `HMMIN` fields of Identify Controller.
+ Add a block cache with LRU replacement, a read-only FAT32 (or ext2) driver, and a VFS with `open`, `read` and `readdir` over the FAT volume and the console. Load user programs from the drive.
+ Measure sequential 4 KiB reads polled against interrupt-driven, and at queue depth 1 against 32; relate them to Little's law (Chapter 2.4) and keep them for Chapters 4.2 and 4.5.

#safety[The P4510 in the same server holds data you keep, and enumeration order follows slot numbering. Make the driver refuse every write unless Identify Controller's model number matches the NV3, and test that refusal before the first write. Partition and format the NV3 as FAT32 from Linux first.]

#done-when(
  [`ls` in your shell lists the FAT filesystem on the NV3 in the server.],
  [The table of polling against interrupts and queue depth 1 against 32 is in the notebook.],
)
#evidence([`lspci -nn` beside your enumeration; the decoded Identify data; the throughput table.])
] <lab-kern-nvme>

#lab([Choose one], time: [2 weekends])[
- *Networking:* a virtio-net or e1000 driver in QEMU, ARP, IPv4, UDP and a `udp_echo` program.
- *A RISC-V port:* the kernel on QEMU's `virt` machine over OpenSBI, with Sv39, the PLIC, the timer through SBI and `virtio-blk`, plus a page on what was specific to x86.
- *Booting Linux:* your Lab 2.7.2 loader also boots a Linux `bzImage` through the x86 boot protocol, with an initrd and a command line, as your Chapter 4.4 VMM will inside a virtual machine.

#done-when(
  [The chosen option works and has a notebook page documenting it.],
)
] <lab-kern-choose>

== Problem set

+ Design your system-call ABI: register assignments, the error convention, how a call with seven arguments works, and how you would add a call without breaking old binaries. Compare with Linux and justify each difference.
+ A 64 GiB machine with 4 KiB pages: how much memory do the page tables take if every page is mapped once? With 2 MiB pages? Why does the direct map use 1 GiB pages where it can?
+ Write the TLB-shootdown protocol for unmapping a kernel-half page on a 32-core machine: what is sent, who acknowledges, what the sender may do meanwhile, and what happens if a target has interrupts disabled for a long time.
+ Why must interrupts be disabled between saving the outgoing thread's state and loading the incoming thread's stack pointer? Where can they be re-enabled, and what goes wrong one instruction earlier?
+ Copy-on-write `fork`: give the reference-count protocol for a frame shared by three processes as each writes in turn. What happens if one of them exits, and if one `mmap`s over the region?
+ NVMe completion queues use a phase bit instead of a valid flag. Explain why, and what the host must do when the queue wraps. A 4 KiB read takes 90 µs at queue depth 1: what IOPS does Little's law predict at depths 1 and 32 if nothing saturates, and why will your Lab 4.1.5 table disagree at 32?
+ Your spinlock spins on `xchg`. Why add `pause`? Why is a plain store with a compiler barrier enough for the unlock? Which ordering does x86 give you for free here that RISC-V does not?
+ A user program passes `write` a 4 KiB buffer that spans a mapped page and an unmapped one. Show the check sequence that avoids both a kernel fault and a time-of-check-to-time-of-use race with a thread that `munmap`s concurrently.
+ Measure your kernel's interrupt latency and context-switch cost on the server with the TSC, and explain each contribution.

== Deliverables and stretch

*Deliverables.* A tagged kernel per milestone that boots on QEMU and the server, with a README of what works, what does not and how to run the self-tests; the NVMe throughput table; your ABI document.

*Stretch.* POSIX signals, delivered on return to user mode through a trampoline, so that `SIGSEGV` reaches a handler instead of killing the process. A filesystem write path with a journaling scheme you design, and a crash test that kills QEMU mid-write and checks consistency on remount. Make your loader measure the kernel into PCR 9 through the EFI TCG2 protocol, as GRUB does for the files it loads, and check that your Lab 2.7.4 event-log replay still matches.

#checklist(
  [*Lab 4.1.1:* one kernel boots from both loaders in QEMU and from the UEFI loader on the server, with correct exception frames.],
  [*Lab 4.1.2:* allocator self-tests pass on every boot; a stack overflow reports itself.],
  [*Lab 4.1.3:* every server core online with threads migrating; an hour of sleep-and-wake stress without a lockup.],
  [*Lab 4.1.4:* the shell on QEMU and the server; a fork bomb survived; `-EFAULT` returned.],
  [*Lab 4.1.5:* `ls` of the FAT volume on the NV3; the polling, interrupt and queue-depth table.],
  [*Lab 4.1.6:* the chosen option working and documented.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: the page-fault path, why spinlocks disable interrupts, what a context switch saves, how an AP comes up, and an NVMe read from doorbell to completion.],
)
