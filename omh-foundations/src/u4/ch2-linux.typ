#import "../lib/template.typ": *

= Linux kernel internals <ch-linux>

#chapter-meta(
  weeks: [3.5 weeks],
  builds: [Kernels built, booted and debugged on QEMU, the lab server and the Raspberry Pi 5, and a crash dump analysed; traces from `write(2)` to a UART and from sysfs to the TMP117; a character-device module with an RCU list, clean under KASAN, KCSAN and lockdep; scheduler and memory measurements; two bisections, one on hardware; and the signed node kernels that Chapter 4.7 ships, with OMH's kernel policy.],
  needs: [The lab server with the P4510 and the NV3, the Pi 5 with its Lab 2.7.5 TMP117 overlay and a 3.3 V USB-to-serial adapter, QEMU, the long-term and Raspberry Pi kernel trees, and `fio`, `perf`, `bpftrace`, `trace-cmd`, `rt-tests`, `virtme-ng` and `crash`.],
)

#why[
  Every OMH module ships a Linux kernel that you configure, harden, patch, sign and update for years. Compute needs the scheduler's isolation and the memory manager's huge pages and NUMA policy; Storage and Blocks live in the block layer and the NVMe driver; Clusters is namespaces and cgroups; Signals is `perf`, ftrace and eBPF made into a product. Chapter 4.1 gave you the map. This chapter is the territory: reading a very large codebase efficiently, tracing it live on both of Module Zero's architectures, finding the commit that broke something, and writing code that runs safely inside it. Its last lab builds the node kernels that Chapter 4.7 ships.
]

#skip-test(
  rule: [If all five are easy, do Labs 4.2.2 to 4.2.4 and 4.2.7.],
  [Trace `write(2)` on a tty from the system-call entry to the UART driver, naming the subsystems crossed.],
  [What does RCU guarantee to readers, what does it require of writers, and why is it everywhere in the networking and VFS code?],
  [Describe blk-mq's queue model and why it matches NVMe better than the old single-queue block layer.],
  [A page fault hits a file-backed `mmap` region. What does the kernel consult, in what order, and when does it touch the disk?],
  [A vendor's out-of-tree module taints the kernel. What does that mean technically, and what are the consequences for OMH shipping one?],
)

== Core ideas

*Finding your way.* `arch/` holds entry code, paging and interrupt controllers; `kernel/` the scheduler, time, locking, RCU and tracing; then `mm/`, `fs/`, `block/`, `drivers/`, `net/`, `include/linux/` and `Documentation/`. Navigate with `clangd` over `make compile_commands.json`, and learn why code is as it is from `git log -S`, `git blame` and LWN's kernel index. Kconfig configures (`menuconfig`, `localmodconfig`, `scripts/config`); Kbuild produces the image, modules and an optional initramfs.

*Processes and threads.* `task_struct` represents both; a thread shares `mm`, files and signal handlers through `clone` flags. `fork` copies on write and `execve` loads through a `binfmt` handler. Namespaces virtualise global resources and cgroup v2 limits CPU, memory and I/O; with a root filesystem they make a container, which is all a Clusters node runs.

*Scheduling.* Classes in priority order are stop, deadline, real-time, fair and idle, and since 6.12 `sched_ext` lets a BPF program supply one more. The fair class has been EEVDF since 6.6, running the eligible task with the earliest virtual deadline. Per-CPU run queues balance across scheduling domains built from the topology. `isolcpus`, `nohz_full`, `rcu_nocbs`, IRQ affinity and cpusets isolate latency-critical work; Compute will pin vCPU threads with them.

*Memory.* Nodes and zones, the buddy allocator (`alloc_pages`), SLUB (`kmalloc`, `kmem_cache_create`), `vmalloc`, the page cache, VMAs and the fault path through `handle_mm_fault`, reclaim through the multi-generational LRU, transparent huge pages, NUMA policy, and memory cgroups with the OOM killer; read `/proc/meminfo` and `/proc/vmstat` fluently. The Pi's kernel uses 16 KiB pages, so its huge page is 32 MiB and every page-size-dependent number changes.

*VFS and the block layer.* `super_block`, `inode`, `dentry` and `file` with their operations tables, and the page cache behind `address_space`. A `bio` enters blk-mq in the submitting CPU's software context, which maps to a hardware context whose `queue_rq` hands it to the driver; for NVMe a hardware context is one queue pair with its own MSI-X vector. An I/O scheduler (`none`, `mq-deadline`, `bfq`) may sit between them, device-mapper stacks targets above (dm-crypt is "encrypted at rest"), and io_uring's rings mirror NVMe's queues.

#fig("/figures/u4-linux-blk-mq.svg", caption: [blk-mq with eight CPUs and four NVMe queue pairs. The highlighted request is submitted on CPU 5 and completes on CPU 4 or 5 through vector 3.])

*Interrupts and deferred work.* Hard IRQ handlers run with their line masked and stay short. Softirqs (networking, block, timers, RCU) run on interrupt return or in `ksoftirqd`, and tasklets are giving way to BH workqueues. Ordinary workqueues and threaded IRQs run in process context and may sleep; NAPI mixes interrupts with polling. `/proc/interrupts` and `/proc/softirqs` show where the time went.

*Concurrency.* Spinlocks (`spin_lock_irqsave` when a hard IRQ shares the data, `spin_lock_bh` when a softirq does), sleeping mutexes, reader-writer locks, seqlocks, per-CPU variables, atomics and RCU. An RCU reader brackets its walk with `rcu_read_lock()` at almost no cost; a writer publishes with `rcu_assign_pointer()` and frees the old version only after every reader that might hold it has finished (`synchronize_rcu()` or `call_rcu()`). For ordering, `smp_load_acquire()` with `smp_store_release()` is usually what you want. Lockdep checks lock order, KCSAN finds data races and KASAN finds use-after-free; KCSAN and KASAN exclude each other, so keep two debug configurations.

#fig("/figures/u4-linux-rcu.svg", caption: [An RCU grace period. The writer waits only for readers already running when it published; later readers see the new version and do not extend the wait.])

*Time.* Clocksources (TSC, HPET, the Arm generic timer), clockevents, hrtimers, tickless idle, `ktime_get()` and jiffies. Timekeeping is subtle; use the kernel's.

*System calls and entry.* `entry_SYSCALL_64` in `arch/x86/entry/entry_64.S`, the system-call table, `SYSCALL_DEFINE`, `copy_from_user()` with SMAP (PAN on arm64), the vDSO for `clock_gettime`, and the `ptrace` and `seccomp` hooks on the path.

#fig("/figures/u4-linux-write-path.svg", caption: [`echo hi > /dev/ttyS1` on the server. The system call only queues bytes and enables the transmit interrupt; the 8250 interrupt handler moves them into the UART.])

*The device model.* `kobject` with sysfs as its view; `bus_type`, `device` and `device_driver`, matched and probed; `udev` reacting to uevents. Chapter 4.3 lives here.

*Modules.* Loadable objects linked against exported symbols (`EXPORT_SYMBOL`, `EXPORT_SYMBOL_GPL`), with parameters, init and exit functions, version magic and optional signatures. Out-of-tree, unsigned and proprietary modules taint the kernel with flags O, E and P, and upstream and distributions decline bug reports from tainted kernels. A vendor module must be rebuilt for every kernel update and signed when the boot chain enforces signatures.

*Observability.* `printk`, `dynamic_debug`, ftrace (`function_graph`, tracepoints, `trace-cmd`), kprobes and uprobes, eBPF through `bpftrace` and libbpf, `perf`, kgdb, and kdump with `crash`. Signals is a product built from these.

*Security.* Linux Security Modules (SELinux, AppArmor, Landlock), IMA (file hashes extended into the TPM, Chapter 2.7), lockdown, seccomp, and hardening options such as `CONFIG_HARDENED_USERCOPY`, `CONFIG_RANDOMIZE_BASE`, `CONFIG_STACKPROTECTOR_STRONG` and `CONFIG_INIT_ON_ALLOC_DEFAULT_ON`. Mainline does not enable lockdown under Secure Boot (distributions patch that in), so your node kernels force it. A storage appliance's kernel configuration is a security decision.

*The process.* Mailing lists, `git format-patch`, `scripts/checkpatch.pl`, `MAINTAINERS`, the two-week merge window, `-rc` releases, and stable and long-term branches (6.18 is the newest long-term branch at the time of writing). The Raspberry Pi kernel follows them with its own board-support patch stack, the position OMH will be in. `git bisect` finds a regression among $N$ commits in about $log_2 N$ builds, and the fix's `Fixes:` tag names the culprit. A small patch stack on one long-term branch keeps this work bounded.

== Reading

- Love, _Linux Kernel Development_, 3rd ed., quickly, in the first week: the details are from 2.6.34 but the structure is current.
- Bootlin's "Linux kernel and driver development" slides on build, debugging and concurrency.
- 0xAX, _Linux Insides_: the booting and interrupts chapters, for the x86 entry path.
- In `Documentation/`: `core-api/`, the EEVDF and cgroup v2 pages, `admin-guide/mm/`, `RCU/whatisRCU.rst`, `memory-barriers.txt`, `trace/ftrace.rst`, the KASAN and KCSAN pages in `dev-tools/`, the guide to verifying and bisecting regressions in `admin-guide/`, and `process/submitting-patches.rst`.
- McKenney, _Is Parallel Programming Hard, And, If So, What Can You Do About It?_: deferred processing (RCU) and memory ordering.
- Gregg, _BPF Performance Tools_: chapters 1 to 5 and 9 (disk I/O).
- LWN.net's kernel index on EEVDF, the multi-generational LRU, io_uring, blk-mq, `sched_ext` and RCU. Subscribe; it is the trade journal.

== Labs

Use the newest long-term branch on the server and the Raspberry Pi tree's default branch on the Pi, cross-compiling the Pi's kernels on the server (`ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`, `bcm2712_defconfig`). The server's SOL console is usually `ttyS1`; the Pi's is `ttyAMA10` on its debug header, or GPIO 14 and 15 with `enable_uart=1`.

#lab([Build, boot, break and dump], time: [1 weekend], kit: [The server, the Pi 5 with a USB-to-serial adapter, QEMU.])[
+ Build the long-term kernel from `defconfig` with `CONFIG_DEBUG_INFO_DWARF5` and `CONFIG_GDB_SCRIPTS`, timing the build. Boot it in QEMU with a BusyBox initramfs, `-append "console=ttyS0 nokaslr"` and `-s -S`; in `gdb vmlinux` run `lx-symbols`, break on `vfs_open`, take a backtrace and print `$lx_current().comm`.
+ Boot it on the server with `console=ttyS1,115200`. Enable kdump (`crashkernel=`, `kdump-tools`), crash the machine with `echo c > /proc/sysrq-trigger`, and find the panicking task's backtrace with `crash`.
+ Build the Pi tree on the server and on the Pi, timing both. Name the new image with `kernel=` in a copy of `config.txt` called `tryboot.txt` and boot it with `sudo reboot '0 tryboot'`, which falls back to `config.txt` after a hang. Check that `getconf PAGESIZE` prints 16384.

#done-when(
  [Your kernels boot in QEMU under GDB, on the server over SOL and on the Pi over serial.],
  [One crash dump is analysed with `crash` down to the panicking task's backtrace.],
)
#evidence([The three build times; the GDB session; the `crash` output.])
] <lab-linux-build>

#lab([A tracing tour], time: [1 weekend])[
+ On the server, trace one `echo hi > /dev/ttyS1` with `function_graph` and `set_graph_function` set to `ksys_write`, and annotate each layer of the graph, as in the write-path figure; then trace `serial8250_tx_chars` to catch the interrupt that drains the buffer.
+ On the Pi, trace a read of the TMP117’s `in_temp_raw` from `iio_read_channel_info` through `tmp117_read_raw` and the I#super[2]C core to `i2c_dw_xfer` and its completion interrupt; the DesignWare controller sits in RP1, across PCIe. Enable `CONFIG_FUNCTION_GRAPH_TRACER` if it is missing.
+ With `bpftrace`, histogram the time from `block:block_rq_issue` to `block:block_rq_complete` under `fio` 4 KiB random reads at queue depths 1, 8 and 32, on the NV3 beside your Lab 4.1.5 table and then on the P4510.
+ Run `perf record -g` under `fio` and under `iperf3` across the X520 (ports joined by a DAC, one in its own network namespace), and explain three top kernel symbols. Count context switches, migrations, page faults and cache misses with `perf stat` on a kernel build, with and without `taskset`.
+ Record `sched_switch` and `sched_wakeup` with `trace-cmd` during `cyclictest`, and find the worst latency and its cause in KernelShark.

#done-when(
  [The annotated write path from the server and TMP117 path from the Pi are in the notebook.],
  [The histograms sit beside your Lab 4.1.5 numbers, and the KernelShark finding is explained.],
)
#evidence([Trimmed, annotated traces; the histograms; `perf` output with your explanations.])
] <lab-linux-trace>

#lab([Modules, from hello to a character device under the sanitisers], time: [2 weekends])[
+ Write a `hello.ko` that uses `module_param`, `MODULE_LICENSE` and `pr_info`; load it, read its parameters under `/sys/module/hello/` and decode the taint mask in `/proc/sys/kernel/tainted`. Add a procfs file and a sysfs attribute for a read-write counter.
+ Write a character device (`alloc_chrdev_region`, `cdev`, and `file_operations` with `open`, `read`, `write`, `unlocked_ioctl` and `poll`) with per-open data, a kernel thread filling a ring buffer, `poll` waking readers through a wait queue, and a rate `ioctl` numbered with `_IOW` and `_IOR` in a uAPI header.
+ Make it SMP-safe with a spinlock, then make the readers lockless with `smp_load_acquire` and `smp_store_release`. Stress it with many readers and writers on the server and on the Pi, whose weaker ordering (Lab 2.4.3) exposes barriers that x86 forgives.
+ Build one kernel with KASAN and lockdep and one with KCSAN and lockdep. Plant a use-after-free on close, a lock-order inversion and an unlocked counter update; read each tool's report, then fix all three.

#done-when(
  [The stress test runs clean under both debug kernels and on the Pi.],
  [The notebook holds the KASAN, KCSAN and lockdep reports from the planted bugs.],
)
#evidence([The module, uAPI header and stress test; the three reports.])
] <lab-linux-modules>

#lab([RCU in your module], time: [1 weekend])[
+ Add an RCU-protected list of subscribers that readers walk with `list_for_each_entry_rcu` inside `rcu_read_lock` and writers change under a spinlock, freeing entries with `kfree_rcu`.
+ Stress it from user space, adding and removing subscribers while readers iterate, and confirm with `perf` that readers take no lock.
+ Swap RCU for a reader-writer lock, and plot reader throughput for both at 1, 4 and 16 readers on the server and at 1 and 4 on the Pi.
+ Read the RCU requirements in `Documentation/RCU/Design/` and the header comment of `kernel/rcu/tree.c` until you can explain why `synchronize_rcu` can take milliseconds.

#done-when(
  [The plot shows RCU readers scaling where reader-writer-lock readers do not.],
  [You can explain a grace period in one paragraph.],
)
#evidence([The plot and its raw numbers; the paragraph.])
] <lab-linux-rcu>

#lab([Scheduler and memory experiments], time: [1 weekend])[
+ Isolate four server cores with `isolcpus`, `nohz_full` and `rcu_nocbs`, move IRQ affinities off them, and compare the maximum `cyclictest` latency there and on a busy core.
+ Pointer-chase 8 GiB with transparent huge pages set to `always`, `madvise` and `never`, counting `dTLB-load-misses` with `perf stat`. Repeat over 2 GiB on the Pi, where a huge page is 32 MiB.
+ Run the benchmark under a `memory.max` of half its footprint and watch `memory.stat`, reclaim and the OOM kill; then use `memory.high` and watch throttling.
+ Compare `numactl --cpunodebind=0 --membind=1` with local placement for memory bandwidth, and read `numastat`.
+ Give two kernel builds cgroup v2 CPU weights of 100 and 900 and measure their wall times.

#done-when(
  [The latency, TLB, cgroup and NUMA measurements are in the notebook, each with an explanation.],
)
#evidence([The `cyclictest` histograms; the measurement tables.])
] <lab-linux-sched>

#lab([Bisect a change, then a regression on hardware], time: [1 weekend], kit: [The server, QEMU, `virtme-ng`.])[
+ Write a `git bisect run` script that builds with `vng --build` (with `CONFIG_SCHED_DEBUG` set once through `vng --kconfig --configitem`), boots with `vng --user root`, lists `/sys/kernel/debug/sched/` after mounting debugfs, and exits 0 (good), 1 (bad) or 125 (skip).
+ Between v6.5 and v6.6 the fair class became EEVDF and the CFS tunable `latency_ns` left that directory. Bisect for its removal, timing each step. Confirm the commit with `git log -S '"latency_ns"' v6.5..v6.6` on `kernel/sched/debug.c`, and explain why bisection is still needed when no string names a change.
+ Script a branch of 40 commits from your long-term tree plus one, at a random position recorded in a file you leave unopened, that adds `udelay(200)` to `nvme_queue_rq`. Bisect it on the server: build, install and `kexec` into each kernel to skip POST, then compare 10 seconds of `fio` 4 KiB random reads at queue depth 1 on the NV3 with a threshold. Under Secure Boot, sign each image with your db key and use `kexec -s`.

#done-when(
  [`git bisect run` finds the commit that removed `latency_ns`, matching `git log -S`.],
  [The hardware bisection finds the planted commit, confirmed against the recorded position.],
)
#evidence([Both `git bisect log` outputs; the scripts; the time per step.])
] <lab-linux-bisect>

#lab([The node kernel and the patch process], time: [2 weekends], kit: [The server, the Pi 5, your Lab 2.7.3 Secure Boot keys and Lab 2.7.5 FIT key.])[
+ Configure the server from `defconfig` plus `make localmodconfig`, and the Pi from `bcm2712_defconfig` plus `localmodconfig` with `ARCH=arm64` and `LSMOD=` naming the Pi's saved `lsmod` output. Trim both toward a headless node for Chapters 4.4 and 4.5 (keep KVM, VFIO, NVMe, the NICs and the TPM; drop sound, graphics and wireless), keep each as a `merge_config.sh` fragment, and justify ten options added and ten removed. The Pi's fragment also serves Board B, whose Compute Module 5 has the same BCM2712.
+ Harden both: set `CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY` and `CONFIG_MODULE_SIG_FORCE` with your own signing key, add the options above and IMA for your Lab 2.7.4 verifier, and drop `/dev/mem`. Decide whether the arm64 node keeps 16 KiB pages, and justify every `kernel-hardening-checker -c` failure you accept.
+ On the server, boot under Secure Boot a unified kernel image built with `ukify` and signed with your db key; on the Pi, boot a FIT signed with your Lab 2.7.5 key through U-Boot. On both, check that `/sys/kernel/security/lockdown` shows `[integrity]` and that `insmod` refuses an unsigned module.
+ Pick a driver and fix one legitimate warning from `scripts/checkpatch.pl`, a documentation error or a missing `static`. Write the message with a rationale and `Signed-off-by:`, run `git format-patch` and `scripts/get_maintainer.pl`, and read in `Documentation/process/` how it would be merged. Sending it is encouraged.
+ Write OMH's one-page kernel policy: the branch per architecture, the patch stack, signing and fleet rollout of kernels and modules, CVE handling, and who bisects a regression.

#done-when(
  [Both node kernels boot signed, in integrity lockdown, and refuse unsigned modules.],
  [Fragments, change logs and the hardening report are committed for Chapter 4.7’s image.],
  [The patch is formatted and the policy is committed.],
)
#evidence([Fragments and change logs; the checker output; the refusals; the patch; the policy.])
] <lab-linux-node>

== Problem set

+ List each layer, and its key function or structure, from a cold `read(2)` on ext4 over NVMe to the doorbell.
+ Why can RCU readers never block a writer, what breaks if one sleeps under `rcu_read_lock()`, and what does SRCU change?
+ Map blk-mq's software and hardware contexts onto NVMe queue pairs and MSI-X vectors for 56 logical CPUs and a drive offering 32 I/O queue pairs. Where is the mapping one to one, and where is it not?
+ A process `mmap`s a 1 GiB file and touches every page. Describe the fault path, page-cache lookups, readahead, and major against minor faults. Count the faults with 4 KiB and with 16 KiB pages, without fault-around and with the default 64 KiB `fault_around_bytes`. What does `MAP_POPULATE` change?
+ What does taint mean for a bug report, for kdump analysis and for a support contract? How would you take an OMH driver upstream, and what would you ship meanwhile?
+ Give a concrete deadlock for each wrong choice among `spin_lock`, `spin_lock_bh` and `spin_lock_irqsave`.
+ Explain what `nohz_full` does to a core, what still interrupts it, and why a pinned vCPU thread benefits. With a 250 Hz tick costing 2 µs, how much time per second does it return to each isolated core?
+ A memory cgroup at `memory.max` runs out. Walk what reclaim tries before the OOM killer, and explain why `memory.high` behaves better on a multi-tenant node.
+ Bisecting 2,900 commits: how many steps, and how long at 6 minutes per build and 4 per boot and test, with and without the 3 minutes of POST that `kexec` saves? What if a step will not build?

== Deliverables and stretch

*Deliverables.* The node-kernel fragments and change logs; the RCU module with its uAPI header, stress test and sanitiser reports; the Lab 4.2.2 and 4.2.5 traces and tables; both bisection logs; the patch and policy.

*Stretch.* A libbpf program exporting per-queue NVMe latency from the driver's tracepoints, a Signals prototype. An upstream fix backported to your long-term branch, resolving the conflict by hand. A `sched_ext` scheduler, written or adapted from `tools/sched_ext/`, that pins chosen tasks to isolated cores.

#checklist(
  [*Lab 4.2.1:* kernels under GDB in QEMU, on the server and on the Pi; a crash dump analysed.],
  [*Lab 4.2.2:* both paths annotated; histograms beside Lab 4.1.5; the KernelShark finding.],
  [*Lab 4.2.3:* the module clean under both debug kernels and on the Pi; the three reports.],
  [*Lab 4.2.4:* RCU readers scaling where reader-writer-lock readers do not.],
  [*Lab 4.2.5:* latency, TLB, cgroup and NUMA measurements explained.],
  [*Lab 4.2.6:* the EEVDF commit and the planted regression found by bisection.],
  [*Lab 4.2.7:* both node kernels signed and locked down; patch and policy committed.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: the `write(2)` and NVMe paths, RCU, lock variants, taint and lockdown.],
)
