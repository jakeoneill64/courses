# Module 10: Linux kernel internals

**Part IV · 3 weeks · Needs: kernel source tree, QEMU, the server, the NVMe drive, `fio`, `bpftrace`, `trace-cmd`.**

## Why this module (and what it buys OMH)

Every OMH module ships a Linux kernel that you configure, harden, patch, sign and update
for years. Compute needs the scheduler's isolation features and the memory manager's huge
page and NUMA behaviour. Storage and Blocks live in the block layer and the NVMe driver.
Clusters is namespaces and cgroups. Signals is `perf`, ftrace and eBPF turned into a
product. Your own kernel from Module 9 gave you the map; this module is about the
territory: reading a very large codebase efficiently, tracing it live, and writing code
that runs inside it without breaking it.

## Skip test

1. Trace `write(2)` on a tty from the syscall entry to the UART driver, naming the
   subsystems crossed.
2. What does RCU guarantee to readers, what does it require of writers, and why is it
   everywhere in the networking and VFS code?
3. Describe blk-mq's queue model and why it matches NVMe better than the old single-queue
   block layer.
4. A page fault on a file-backed `mmap` region: what does the kernel consult, in what
   order, and when does it touch the disk?
5. A vendor's out-of-tree module taints the kernel. What does that mean technically, and
   what are the consequences for OMH shipping one?

If all five are easy, do Labs 10.2, 10.3 and 10.5.

## Core ideas

**Finding your way.** `arch/x86/` (entry code, paging, APIC), `kernel/` (scheduler, time,
locking, RCU, tracing), `mm/`, `fs/`, `block/`, `drivers/`, `net/`, `include/linux/`,
`Documentation/`. `cscope` or `clangd` with a generated `compile_commands.json`; `git
log -S` and `git blame` to learn why; LWN's kernel index to learn what changed and when.
Configuration through Kconfig (`make menuconfig`, `localmodconfig`, `tinyconfig`); the
build through Kbuild; the result a `bzImage`, modules and an optional initramfs.

**Processes and threads.** `task_struct` is both; a thread is a task sharing `mm`, files
and signal handlers via `clone` flags. `fork` copies with CoW; `execve` loads a binary
through `binfmt` handlers. Namespaces (pid, net, mnt, user, and others) virtualise the
view of global resources; cgroups (v2) account and limit CPU, memory, I/O per hierarchy.
Containers are these two plus a filesystem; that is all Clusters' nodes are running.

**Scheduling.** Scheduling classes in priority order: stop, deadline, real-time, fair
(EEVDF since 6.6, CFS before), idle. Per-CPU run queues; load balancing across scheduling
domains built from the topology; `nice`, weights, and virtual runtime. Isolation for
latency-critical work: `isolcpus`, `nohz_full`, `rcu_nocbs`, IRQ affinity, cpusets. Compute
will pin vCPU threads and this is the toolbox.

**Memory.** Zones and nodes; the buddy allocator (`alloc_pages`); SLUB for objects
(`kmalloc`, `kmem_cache`); `vmalloc` for virtually contiguous; the page cache as the unifying
abstraction for file data; `mmap` and VMAs; the fault path (`handle_mm_fault`); reclaim with
the multi-generational LRU; swap; transparent huge pages; NUMA policies; memory cgroups and
the OOM killer. `/proc/meminfo`, `/proc/vmstat` and `smem` literacy is a professional skill.

**VFS and the block layer.** `super_block`, `inode`, `dentry`, `file`, and their operations
tables; the dcache; page cache integration through `address_space`. Below the filesystem:
`bio` structures carrying segments, submitted through blk-mq to per-CPU software queues and
per-hardware-queue dispatch, with I/O schedulers (none, mq-deadline, bfq) and the
device-mapper for stacking (dm-crypt is "encrypted at rest"). io_uring is an asynchronous
syscall interface whose ring design mirrors NVMe's.

**Interrupts and deferred work.** Hard IRQ handlers run with the line masked and must be
short. Softirqs (networking, block, timers, RCU) run on return from interrupt or in
`ksoftirqd`. Tasklets are dying; workqueues run in process context and can sleep; threaded
IRQs move handlers into kernel threads. NAPI is the networking stack's polling hybrid.
`/proc/interrupts` and `/proc/softirqs` tell you where the time went.

**Concurrency.** Spinlocks (and `spin_lock_irqsave` when interrupt handlers share the data),
mutexes (sleep), rwlocks and rw semaphores, seqlocks (readers retry), per-CPU variables
(avoid sharing), atomics, and RCU. RCU: readers mark a section with `rcu_read_lock()` and
pay nothing; writers publish a new version with `rcu_assign_pointer` and free the old one
only after every pre-existing reader has finished (`synchronize_rcu` or `call_rcu`). It
converts read-mostly locking into pointer publication. `Documentation/memory-barriers.txt`
is the memory model; `smp_load_acquire`/`smp_store_release` are what you usually want.
Lockdep validates lock ordering at runtime; KCSAN finds data races; KASAN finds
use-after-free and out-of-bounds.

**Time.** Clocksources (TSC, HPET, ARM generic timer), clockevents, hrtimers, tickless
idle, `ktime_get`, jiffies for coarse work. Timekeeping is subtle; do not invent your own.

**Syscalls and entry.** `entry_64.S`, the syscall table, `SYSCALL_DEFINE`, `copy_from_user`
with access checks and SMAP, the vDSO for `gettimeofday` without entering the kernel,
`ptrace` and `seccomp` hooks on the path.

**The device model.** `kobject`, `kset`, sysfs as its filesystem view; `bus_type`, `device`,
`device_driver`, and the matching and probing that connects them; `udev` in userspace
reacting to `uevent`s. Module 11 lives here.

**Modules.** Loadable objects linked against the running kernel's exported symbols
(`EXPORT_SYMBOL`, `EXPORT_SYMBOL_GPL`), with parameters, init and exit, version magic,
optional signing enforced by lockdown or Secure Boot. An out-of-tree module taints the
kernel, which upstream and distributions use to decline bug reports; a proprietary one
taints it differently. A vendor shipping a module must rebuild it for every kernel update
or use DKMS-style automation, and must sign it if the boot chain enforces signatures.

**Observability.** `printk` and its levels; `dynamic_debug`; ftrace (`function_graph`,
tracepoints, `trace-cmd`, `perf trace`); kprobes and uprobes; eBPF via `bpftrace` and libbpf
for programmable tracing without rebooting; `perf` for counters and sampling; kgdb and
kdb; kdump and the `crash` utility for post-mortem. Signals is a product built from these.

**Security.** Linux Security Modules (SELinux, AppArmor, Landlock), the Integrity
Measurement Architecture (extends file hashes into the TPM, Module 8), lockdown mode
(restricts root from modifying the running kernel when Secure Boot is on), seccomp
filters, kernel hardening options (`CONFIG_HARDENED_USERCOPY`, `CONFIG_RANDOMIZE_BASE`,
stack protectors, `CONFIG_INIT_ON_ALLOC_DEFAULT_ON`). A storage appliance's kernel
configuration is a security decision.

**The process.** Mailing lists, `git format-patch`, `scripts/checkpatch.pl`,
`MAINTAINERS`, the merge window, `-rc` releases, stable and long-term branches, and how a
distribution or a vendor picks a kernel and backports fixes. OMH will track an LTS branch
and carry a small patch stack; knowing the process is how you keep that stack small.

## Reading

- Love, *Linux Kernel Development*, 3rd ed.: all chapters. The details are from 2.6.34;
  the structure is current. Read it fast in the first week.
- Bootlin, "Linux kernel and driver development" training slides: sections on kernel
  sources, configuration and build, kernel debugging, and concurrency. Free and current.
- 0xAX, *Linux Insides* (free): the booting and interrupts chapters for the x86 entry path
  in real code.
- `Documentation/`: `core-api/` (memory allocation, workqueue, RCU concepts),
  `scheduler/`, `admin-guide/mm/`, `locking/`, `RCU/whatisRCU.rst`,
  `memory-barriers.txt`, `trace/ftrace.rst`, `dev-tools/kasan.rst`,
  `process/submitting-patches.rst`, `process/coding-style.rst`.
- McKenney, *Is Parallel Programming Hard, And, If So, What Can You Do About It?*
  (free): ch. 9 (deferred processing: RCU) and ch. 15 (memory ordering).
- Gregg, *BPF Performance Tools*, ch. 1 to 5 and 9 (disks).
- LWN.net: the kernel index for scheduler (EEVDF), MGLRU, io_uring, blk-mq, and RCU
  articles by Jonathan Corbet. Subscribe; it is the trade journal.

## Labs

### Lab 10.1: Build, boot, break, dump

1. Clone the current LTS branch. Start from `make defconfig`, then `make localmodconfig` on
   the server, then trim by hand toward what a headless storage node needs. Record each
   removal and why. Build with `make -j`. Note build time.
2. Build a minimal initramfs (busybox static, an `init` script). Boot in QEMU with
   `-kernel -initrd -append "console=ttyS0" -s -S`, attach `gdb vmlinux`, break on
   `do_sys_openat2`, `bt`, inspect `current`.
3. Boot your kernel on the server via a GRUB entry with serial console over SOL. Enable
   kdump (`crashkernel=`), trigger a crash with `echo c > /proc/sysrq-trigger`, and open
   the dump with `crash`. Find the panicking task and backtrace.
4. Sign the kernel and modules with your Module 8 keys and boot with Secure Boot on;
   confirm lockdown mode is active and an unsigned module is refused.

Done when: your trimmed kernel boots on QEMU and the server under Secure Boot, and you have
analysed one crash dump.

### Lab 10.2: A tracing tour

1. ftrace `function_graph` filtered to the `write` syscall: `echo 1 > tracing_on` around a
   single `echo hi > /dev/ttyS0`. Read the whole graph from `__x64_sys_write` through VFS,
   the tty layer, the line discipline, to the serial driver. Annotate it in your notebook.
2. `bpftrace`: histogram of `blk_account_io_done` latency (or the `block:block_rq_complete`
   tracepoint) while `fio` runs 4 KiB random reads on the NVMe drive at queue depths 1, 8,
   32. Compare with Module 9's numbers from your own driver.
3. `perf record -g` under `fio` and a network load; `perf report`; find the top kernel
   symbols; explain three of them.
4. `perf stat -e` for context switches, migrations, page faults, cache misses on a
   compile job with and without `taskset` pinning.
5. `trace-cmd record -e sched_switch` during `cyclictest`; open in KernelShark; find the
   worst latency and what preempted you.

Done when: the annotated write path, the three latency histograms and the KernelShark
finding are in your notebook.

### Lab 10.3: Modules, from hello to a char device under KASAN

1. `hello.ko` with `module_param`, `MODULE_LICENSE`, `pr_info`. Load, unload, read
   `dmesg`, inspect `/sys/module/hello/parameters`.
2. A `procfs` file and a `sysfs` attribute exposing a counter you can read and write.
3. A character device (`alloc_chrdev_region`, `cdev`, a `struct file_operations` with
   `open`, `read`, `write`, `unlocked_ioctl`, `poll`), a per-open private data structure,
   a kernel thread producing data into a ring buffer, `poll` waking readers via a wait
   queue, an `ioctl` to change the rate. Define the `ioctl` numbers properly in a uAPI
   header with `_IOW`/`_IOR`.
4. Make it SMP-safe with a spinlock, then convert the reader side to lockless with
   `smp_load_acquire`/`smp_store_release`. Run a multi-reader multi-writer stress test.
5. Build a KASAN + lockdep + KCSAN kernel. Introduce a use-after-free on close and a lock
   ordering inversion. Watch each tool report it with a readable backtrace. Fix both.

Done when: the stress test runs clean under KASAN, lockdep and KCSAN, and your notebook has
the reports from the deliberately broken versions.

### Lab 10.4: Scheduler and memory experiments on the server

1. `isolcpus`, `nohz_full` and `rcu_nocbs` for four cores; move IRQ affinities off them;
   run `cyclictest` pinned there versus on a busy core. Record max latency for each.
2. THP: a pointer-chasing benchmark over 8 GiB with `always`, `madvise`, `never`; measure
   with `perf stat -e dTLB-load-misses`.
3. Memory cgroup: run the same benchmark under a `memory.max` of half its footprint; watch
   `memory.stat`, reclaim, and the OOM kill. Then set `memory.high` and observe throttling
   instead.
4. NUMA: `numactl --cpunodebind=0 --membind=1` versus local for a memory-bandwidth
   benchmark; read `numastat`.
5. cpusets and a cgroup v2 hierarchy with CPU weights: two competing compile jobs at
   weights 100 and 900; measure wall time.

Done when: your notebook has the latency, TLB, cgroup and NUMA measurements with an
explanation for each result.

### Lab 10.5: RCU in your module

1. Add an RCU-protected list of "subscribers" to your char device: readers walk it with
   `list_for_each_entry_rcu` under `rcu_read_lock`; writers add and remove under a
   spinlock and free with `kfree_rcu`.
2. Write a userspace stress test that adds and removes subscribers at high rate while
   readers iterate. Confirm no crash; confirm with `perf` that readers take no lock.
3. Replace RCU with a plain rwlock and measure reader throughput at 1, 4, 16 concurrent
   readers. Plot both.
4. Read `kernel/rcu/tree.c`'s header comment and `Documentation/RCU/Design/Requirements/`
   until you can explain grace periods and why `synchronize_rcu` can take milliseconds.

Done when: the plot shows RCU readers scaling where rwlock readers do not, and you can
explain a grace period in one paragraph.

### Lab 10.6: The patch process

1. Run `scripts/checkpatch.pl` on a driver you find interesting. Fix one legitimate
   warning, or find a documentation typo, or a missing `static`. Write a proper commit
   message with a `Fixes:` or a rationale, `Signed-off-by`, and `git format-patch`.
2. Run `scripts/get_maintainer.pl` on it. Read `Documentation/process/` on how the patch
   would be reviewed and merged. Sending it is optional and encouraged.
3. Write a one-page policy for OMH: which kernel line to track, how patches are carried,
   how kernels are signed and updated on modules, how a CVE is handled.

Done when: the patch is formatted and the policy page is committed.

## Problem set

1. From `read(2)` on a file in ext4 on an NVMe drive with a cold cache to the NVMe
   doorbell write: list every layer and the key function or structure at each.
2. Why can RCU readers never block a writer, and what would break if a reader slept inside
   `rcu_read_lock`? What does `SRCU` change?
3. Compare blk-mq's software and hardware queues with NVMe's submission queues and MSI-X
   vectors. Where is the one-to-one mapping and where is it not?
4. A process `mmap`s a 1 GiB file and touches every page. Describe the fault path, the
   page cache lookups, readahead, and what "major fault" versus "minor fault" means. How
   does `MAP_POPULATE` change this?
5. What does kernel taint mean for a bug report, for `kdump` analysis and for your
   customers' support contracts? How would you ship an OMH-specific driver upstream over
   time, and what would you do in the meantime?
6. Design a kernel configuration for a Storage module: list ten options you enable, ten
   you disable, and the hardening options you require. Justify each in one line.
7. `spin_lock_irqsave` versus `spin_lock` versus `spin_lock_bh`: give a concrete deadlock
   for each wrong choice.
8. Explain what `nohz_full` does to a core, what still interrupts it, and why a pinned
   vCPU thread benefits.
9. A memory cgroup at `memory.max` runs out. Walk what reclaim tries before the OOM killer,
   and why `memory.high` produces better behaviour for a multi-tenant node.

## Deliverables

- A trimmed, signed kernel config for a headless storage node, with a change log.
- Your char device module with RCU, uAPI header, stress test, and the sanitizer reports.
- Annotated traces and measurement tables from Labs 10.2 and 10.4.
- The formatted patch and the OMH kernel policy page.

## Stretch

- Write an eBPF program with libbpf that attaches to the NVMe driver's tracepoints and
  exports per-queue latency to userspace; this is a Signals prototype.
- Backport a small upstream fix onto your LTS branch, resolving the conflict by hand.
- Implement a tiny scheduling class (or use `sched_ext`) that pins a set of tasks to
  isolated cores and measure.

## Next

Module 11 is drivers: the device model, real buses, real hardware, and the interfaces OMH
will use to talk to drive bays, fans, PSUs and NICs.
