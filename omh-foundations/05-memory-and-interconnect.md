# Module 5: Memory and interconnect

**Part II · 3 weeks · Needs: FPGA with SDRAM, the server with a PCIe NIC, workstation for C++ experiments.**

## Why this module (and what it buys OMH)

The OMH spec sheet says "Fabric: Ethernet · CXL" and promises erasure coding across hot-swap
bays. Both claims live in this module. CXL is a coherent memory protocol over PCIe; the drive
bays are PCIe endpoints; the erasure-coding budget is bounded by memory bandwidth and the
number of times data crosses the interconnect. An IOMMU is what lets Compute hand a NIC to a
tenant VM safely. ECC memory is what makes a storage appliance trustworthy. You need to speak
this layer with vendors as a peer, and that means knowing what a page walk, a TLP and a
MESI transition cost.

## Skip test

1. A 32 KiB, 4-way set-associative cache with 64-byte lines on a 32-bit address: how many
   bits of index, tag and offset?
2. Walk a Sv39 virtual address through three levels of page table. How many memory accesses
   does a TLB miss cost, and why do huge pages help?
3. Two cores each write to different variables that share a cache line. Describe what MESI
   does per write, and why this is slow.
4. Write the x86 TSO store-buffer litmus test and say which outcomes are allowed. Now say
   which C++ `memory_order` prevents the surprising one.
5. A PCIe device wants to raise an interrupt and DMA 4 KiB into host memory. Describe the
   TLPs involved and where the IOMMU intervenes.

If all five are easy, do Labs 5.1 and 5.4 only.

## Core ideas

**SRAM versus DRAM.** SRAM (Module 2's 6T cell) is fast, large and static; it is caches.
DRAM stores a bit as charge on a capacitor read through one transistor; it is dense and
cheap and must be refreshed every 64 ms because the charge leaks. Reading destroys the row,
so a row is copied into a row buffer (sense amplifiers), served from there, and written back.

**DRAM organisation.** Channels, DIMMs, ranks, chips, banks, rows, columns. A row hit is
fast; a row miss pays precharge and activate. Timing parameters (tRCD, tCAS, tRP, tRAS) are
in DRAM clocks and are what a memory controller schedules around. DDR transfers on both
clock edges; DDR4 and DDR5 add bank groups, higher speeds and, in DDR5, on-die ECC. A
controller must "train" the interface at boot to align signals, which is why memory
initialisation is the slowest and most fragile part of firmware.

**ECC.** Single-error-correct, double-error-detect Hamming codes over 64 bits with 8 check
bits; chipkill or SDDC to survive a whole chip failing. Servers use it because at scale
memory errors happen daily, and a storage appliance that silently corrupts is worse than one
that fails.

**The hierarchy and locality.** Registers, L1, L2, L3, DRAM, NVMe, network: each level
about an order of magnitude slower and bigger. Programs exhibit temporal and spatial
locality, which is the entire justification for caches.

**Cache organisation.** Lines (64 bytes almost everywhere), sets, ways. Direct-mapped is
one way; fully associative is one set. Tag, index, offset bits. Write-through versus
write-back; write-allocate versus no-write-allocate; replacement (LRU, pseudo-LRU, random).
Misses are compulsory, capacity or conflict. Average memory access time
AMAT = hit time + miss rate × miss penalty. Prefetchers guess the next line.

**Coherence.** Multiple caches holding one line must agree. Snooping protocols broadcast;
directory protocols track owners. MESI states (Modified, Exclusive, Shared, Invalid) and
MOESI with Owned. A write to a Shared line invalidates every other copy, so two cores
writing to different words in one line ping-pong the line: false sharing. Coherence is
about a single location; consistency is about ordering across locations.

**Consistency and your C++ atomics.** Sequential consistency is what programmers assume;
hardware provides weaker models. x86 is TSO: stores may be delayed in a store buffer past
later loads, and nothing else is reordered. ARM and RISC-V (RVWMO) are weaker: loads and
stores reorder freely unless fenced. C++ `memory_order_acquire`/`release` map to cheap
instructions on x86 and to explicit barriers or load-acquire/store-release instructions on
ARM. Litmus tests (store buffering, message passing, load buffering) are how you reason
about what a model allows.

**Virtual memory.** Pages (4 KiB default), page tables (multi-level radix trees indexed by
virtual address bits), page table entries (physical page number plus permission, valid,
dirty, accessed bits). The TLB caches translations; a miss walks the table, costing one
memory access per level (three for Sv39, four for x86-64). Huge pages (2 MiB, 1 GiB) cut
walks and TLB pressure. Address space identifiers let the TLB hold entries from several
processes. Page-table walks are themselves cached.

**The IOMMU.** The same idea for devices: a DMA address from a device is translated through
I/O page tables, so a device can only touch memory its owner mapped for it. Intel VT-d, AMD
IOMMU, ARM SMMU, RISC-V IOMMU. Without it, PCIe passthrough to a VM is unsafe. With it,
VFIO becomes possible and a buggy NIC cannot scribble on the kernel.

**On-chip interconnect.** Wishbone and AXI (Module 3) between a few blocks; crossbars and
networks-on-chip when there are many. Bandwidth = width × clock; contention and arbitration
add latency. Little's law relates throughput, latency and outstanding requests:
concurrency = throughput × latency. A CPU with 10 outstanding misses at 100 ns each sustains
one line per 10 ns, which bounds memory bandwidth per core.

**PCIe.** Point-to-point serial lanes (x1 to x16), a layered protocol: physical (128b/130b
encoding at Gen3, PAM4 at Gen6), data link (ACK/NAK, flow control credits), transaction
(TLPs: memory read/write, configuration, message). Devices are enumerated by walking
buses, discovering functions via configuration space (vendor/device ID, class, BARs,
capabilities). Base Address Registers tell the host how much MMIO a device needs; firmware
or the OS assigns addresses. Interrupts arrive as message-signalled writes (MSI, MSI-X with
per-vector addresses) rather than wires. DMA is the device issuing memory TLPs itself as a
bus master. Efficiency depends on maximum payload size versus header overhead. Advanced
Error Reporting, hot-plug, power states and Access Control Services are the parts a server
platform must handle and a laptop can ignore.

**CXL.** Compute Express Link reuses the PCIe physical layer to carry three protocols:
CXL.io (PCIe as usual), CXL.cache (a device caches host memory coherently), CXL.mem (the
host uses device memory as if it were its own). Type 1 devices are accelerators that cache;
Type 3 devices are memory expanders and pools; Type 2 do both. CXL 2.0 adds switches and
pooling; 3.x adds fabrics and shared memory. For OMH, CXL means memory that can be attached,
pooled and moved between modules, and a coherent path for accelerators, and it is the reason
the spec sheet names it.

**NUMA.** Multiple sockets or chiplets each with local memory. Remote accesses are slower.
Placement of threads and their memory matters, and a hypervisor must expose or hide topology
deliberately.

**NVMe, previewed.** Submission and completion queues in host memory, doorbell registers in
a BAR, commands that carry physical addresses, completions signalled by MSI-X. It is a
PCIe protocol that assumes everything in this module. Module 9 makes you write the driver.

## Reading

- Patterson and Hennessy, CO&D RISC-V ed., ch. 5 (memory hierarchy, all of it).
- Drepper, *What Every Programmer Should Know About Memory*, parts 2 to 6.
- Nagarajan, Sorin, Hill, Wood, *A Primer on Memory Consistency and Cache Coherence*,
  2nd ed., ch. 1 to 4 and 6 to 8. Free from Morgan and Claypool.
- Hennessy and Patterson, CA:AQA, ch. 2 and Appendix B (memory hierarchy design).
- Jackson and Budruk, *PCI Express Technology 3.0*: ch. 1 to 6 (architecture, TLPs,
  configuration), ch. 8 to 10 (address spaces, BARs, enumeration), ch. 17 (interrupts).
- CXL Consortium, CXL 3.1 specification, ch. 1 and 2 (overview and architecture);
  any recent CXL primer article from a memory vendor.
- JEDEC DDR4 SDRAM standard, sections 2 to 4 for the organisation and state diagram.
- Intel VT-d specification, ch. 1 to 3.

## Labs

### Lab 5.1: Caches on your CPU

1. Add a direct-mapped instruction cache and a write-back data cache (4 KiB each, 32-byte
   lines) between your pipeline and the memory bus. Loads and stores to the peripheral
   address range must bypass the cache: implement an uncached region and make `fence`
   and `fence.i` real (drain the write buffer, invalidate the I-cache).
2. Simulate a memory-bound benchmark (array sum with large stride, pointer chase, matrix
   multiply) with a memory model that has a configurable latency (e.g. 20 cycles).
   Instrument hit and miss counters as CSRs. Record CPI and miss rate.
3. Change to 2-way set-associative with pseudo-LRU. Repeat. Change line size to 64 bytes.
   Repeat.
4. Add a next-line prefetcher for the I-cache. Repeat.

Done when: riscv-tests still pass with caches on, and your notebook has a table of CPI and
miss rate across at least four configurations with an explanation of each change.

### Lab 5.2: External SDRAM

1. Read the datasheet for the ULX3S's SDRAM chip: state diagram, initialisation sequence,
   timing parameters. Write down the init sequence and the read and write command
   timings before looking at any controller code.
2. Integrate an open controller (LiteDRAM, or a simple SDRAM controller from the ULX3S
   examples) behind your cache. Run a program from SDRAM. Then, if time permits, write
   your own simple controller: init, refresh timer, single-word read and write with row
   open/close, no bank interleaving.
3. In simulation with a behavioural SDRAM model, count row hits versus misses for a
   sequential and a strided access pattern. Relate to your cache line size.

Done when: your C runs from SDRAM on the FPGA and you can explain the init sequence and
what a refresh cycle costs in bandwidth.

### Lab 5.3: Memory experiments on a real machine (C++)

On your workstation and on the server:

1. Stride benchmark: touch one byte every S bytes across a large array; plot time per
   access against S. Read off the line size and the page size from the knees.
2. Working-set benchmark: random access within an array of size N; plot against N. Read
   off L1, L2, L3 sizes. Compare to `lscpu`.
3. False sharing: two threads incrementing adjacent `std::atomic<int>` versus ones padded to
   separate lines. Measure with `perf stat -e cache-misses,instructions,cycles`.
4. TLB: pointer-chase over 4 GiB with 4 KiB pages versus 2 MiB huge pages
   (`madvise(MADV_HUGEPAGE)` or hugetlbfs). Measure with `perf stat -e dTLB-load-misses`.
5. Store-buffer litmus test: two threads, x86, no fences, run a million times, count the
   "both read zero" outcome. Add `std::atomic_thread_fence(std::memory_order_seq_cst)` and
   repeat. If you have access to an ARM machine (the Pi), repeat the message-passing test
   with relaxed atomics and observe reordering that x86 never shows.
6. NUMA (server only): `numactl --membind` remote versus local for a bandwidth benchmark;
   record the ratio.

Done when: your plots show the line size, page size and three cache levels, and the litmus
test demonstrates TSO on x86 and weaker ordering on ARM.

### Lab 5.4: PCIe by hand

On the server, with the NIC installed:

1. `lspci -vvv -s <nic>`: read the whole output slowly. Identify vendor and device ID,
   class code, each BAR with its size and type, the capability list, the MSI-X capability
   with its table BAR and offset, the PCIe capability with link speed and width, and the AER
   capability.
2. Now do it without `lspci`. Use `setpci` (or read `/sys/bus/pci/devices/<bdf>/config`) to
   dump the raw 256 bytes of standard configuration space and decode every field yourself
   from the PCI spec's header layout. Walk the capability linked list by hand to find
   MSI-X. Decode the BAR sizes by the write-all-ones method (read the spec for why, and do
   it only with the driver unbound).
3. Unbind the kernel driver (`echo <bdf> > /sys/bus/pci/drivers/ixgbe/unbind`). Write a C
   program that `mmap`s `resource0` from sysfs and reads harmless registers (the 82599
   datasheet lists device status and ID registers). Print them. You have talked to a PCIe
   device with no driver.
4. Rebind the driver. Read `/proc/interrupts` for the NIC's MSI-X vectors and their CPU
   affinity. Generate traffic and watch counts move.
5. Find the IOMMU groups (`/sys/kernel/iommu_groups/`). Explain why the NIC is (or is not)
   alone in its group and what that means for passthrough.

Done when: your notebook has a hand-decoded configuration space with every field labelled,
and your program's register reads match `lspci`'s.

### Lab 5.5: A page-table walker (optional here, required in Module 6)

Add a Sv32 page-table walker and a small fully-associative TLB to your CPU's data and
instruction paths, gated by a `satp`-like CSR. Test with a program that builds a page table
in RAM, enables translation, and verifies that a load through a mapped page works and a
load through an unmapped page reports a fault (fault handling itself arrives in Module 6).
Skip this now if you are behind; Module 6 needs it.

## Problem set

1. A 64 KiB, 8-way, 64-byte-line cache with 48-bit physical addresses: index, tag and
   offset widths, and total tag storage in bits.
2. AMAT with L1 hit 1 ns at 95%, L2 hit 4 ns at 80% of L1 misses, memory 80 ns. Now add an
   L3 at 12 ns hitting 60% of L2 misses.
3. A DDR4-3200 channel is 64 bits wide. Peak bandwidth in GB/s? With 8 channels? Why does
   measured bandwidth reach perhaps 80% of that and single-core bandwidth far less (use
   Little's law with 10 outstanding misses at 90 ns)?
4. Refresh: 8,192 rows every 64 ms, each refresh command taking 350 ns. What fraction of
   time is the bank unavailable? What happens at 16 Gbit densities?
5. Construct the SECDED code for 8 data bits: how many check bits, and show it corrects one
   flipped bit and detects two.
6. Walk virtual address 0x0000_003F_C000_1234 through Sv39 with `satp` pointing to
   0x8000_0000: give the byte offset into each level's table.
7. PCIe Gen4 x4: raw lane rate 16 GT/s. Compute usable bandwidth after 128b/130b encoding,
   then after TLP overhead with a 256-byte maximum payload and 20 bytes of header and
   framing per TLP. Compare with an NVMe drive advertising 7,000 MB/s.
8. Give the MESI state of a line in cores A and B after: A reads, B reads, A writes,
   B reads, B writes, A reads. Count bus transactions.
9. Explain why the store-buffer litmus test can print 0,0 on x86 and why the
   message-passing test cannot. Then say what changes on RISC-V RVWMO.
10. A CXL Type 3 memory expander adds 512 GiB at about 250 ns latency versus 90 ns for
    local DRAM. For a key-value store with a 5% miss rate to the far tier, what is the
    effective access time? For which OMH module does that trade make sense?

## Deliverables

- Cached CPU passing tests, running from SDRAM, with the configuration table.
- C++ measurement programs and plots from Lab 5.3.
- The hand-decoded PCIe configuration space and the userspace register-read program.

## Stretch

- Implement a two-core version of your CPU with a snooping MSI protocol on a shared bus
  and run a spin-lock test. This is a serious project; even a partial attempt teaches
  more about coherence than any reading.
- Write a `perf`-driven script that estimates the cost of a page-table walk on the
  server by comparing 4 KiB and 1 GiB pages.
- Read the CXL.mem transaction chapter and draw the request/response flow for a host
  read from a Type 3 device.

## Next

Module 6 adds privilege. Your CPU gets trap handling, a timer interrupt and the beginnings
of an MMU, and you learn the x86 and ARM equivalents on QEMU and the real server.
