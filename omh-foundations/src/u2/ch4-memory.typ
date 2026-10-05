#import "../lib/template.typ": *

= Memory and interconnect <ch-memory>

#chapter-meta(
  weeks: [3 weeks],
  builds: [Caches on your CPU with measured miss rates; your CPU running from external SDRAM; C++ experiments that reveal a real machine's cache sizes, line size, page size and memory model; a PCIe device's configuration space decoded by hand and its registers read with no driver.],
  needs: [ULX3S with its SDRAM, the lab server with a PCIe NIC, the workstation, the Raspberry Pi 5 for an Arm comparison.],
)

#why[
  OMH's specification promises Ethernet and CXL fabrics and erasure coding across hot-swap bays. Both claims live here. CXL is a coherent memory protocol over PCIe; the drive bays are PCIe endpoints; the erasure-coding budget is bounded by memory bandwidth and by how many times data crosses the interconnect. An IOMMU is what lets Compute hand a NIC to a tenant VM safely; ECC memory is what makes a storage appliance trustworthy. To talk to vendors as a peer you must know what a page walk, a TLP and a MESI transition cost.
]

#skip-test(
  rule: [If all five are easy, do Labs 2.4.1 and 2.4.4 only.],
  [A 32 KiB, 4-way set-associative cache with 64-byte lines on a 32-bit address: how many bits of index, tag and offset?],
  [Walk a Sv39 virtual address through three levels of page table. How many memory accesses does a TLB miss cost, and why do huge pages help?],
  [Two cores each write a different variable in the same cache line. What does MESI do on each write, and why is it slow?],
  [Write the x86 store-buffer litmus test and say which outcomes are allowed. Which C++ `memory_order` forbids the surprising one?],
  [A PCIe device raises an interrupt and DMAs 4 KiB into host memory. Describe the TLPs involved and where the IOMMU intervenes.],
)

== Core ideas

*SRAM and DRAM.* SRAM (Chapter 2.1’s 6T cell) is fast and static; it is caches. DRAM stores a bit as charge on a capacitor behind one transistor; it is dense and cheap and must be refreshed every 64 ms because the charge leaks. Reading destroys a row, so the row is copied into the sense amplifiers (the row buffer), served from there, and written back.

*DRAM organisation.* Channels, DIMMs, ranks, chips, banks, rows and columns. A row hit is fast; a row miss pays precharge and activate. Timing parameters (tRCD, tCAS, tRP, tRAS) are counted in DRAM clocks and are what a memory controller schedules around. DDR transfers on both edges; DDR4 and DDR5 add bank groups and speed, and DDR5 adds on-die ECC. The controller must train the interface at boot to align signals, which is why memory initialisation is the slowest and most fragile part of firmware.

*ECC.* Single-error-correct, double-error-detect Hamming codes cover 64 data bits with 8 check bits; chipkill or SDDC survives a whole chip failing. Servers use it because at scale memory errors happen daily, and a storage appliance that silently corrupts is worse than one that fails.

*The hierarchy and locality.* Registers, L1, L2, L3, DRAM, NVMe, network: each level about an order of magnitude slower and larger. Programs show temporal and spatial locality, which is the whole justification for caches.

*Cache organisation.* Lines (64 bytes almost everywhere), sets and ways. Direct-mapped has one way; fully associative has one set. An address splits into tag, index and offset. Write-through or write-back; write-allocate or not; replacement by LRU, pseudo-LRU or random. Misses are compulsory, capacity or conflict. Average memory access time is hit time plus miss rate times miss penalty. Prefetchers guess the next line.

#fig("/figures/u2-cache.svg", caption: [A 4-way set-associative cache. The index selects a set, the four tags are compared in parallel, and the offset selects bytes within the hitting line.])

*Coherence.* Several caches holding one line must agree. Snooping protocols broadcast; directory protocols track owners. MESI (Modified, Exclusive, Shared, Invalid) and MOESI with Owned. A write to a Shared line invalidates every other copy, so two cores writing different words of one line ping-pong it: false sharing. Coherence concerns one location; consistency concerns ordering across locations.

#fig("/figures/u2-mesi.svg", caption: [MESI from one cache's point of view. Left, the cache's own reads and writes; right, other caches' requests, seen on the bus or from the directory, which force write-backs and invalidations. Read hits leave the state unchanged.])

*Consistency and your C++ atomics.* Sequential consistency is what programmers assume; hardware provides weaker models. x86 is TSO: stores may wait in a store buffer behind later loads, and nothing else reorders. Arm and RISC-V (RVWMO) are weaker: loads and stores reorder freely unless fenced. C++ acquire and release map to cheap instructions on x86 and to barriers or load-acquire and store-release instructions on Arm. Litmus tests (store buffering, message passing, load buffering) are how you reason about what a model allows.

*Virtual memory.* Pages (4 KiB by default), multi-level page tables indexed by virtual-address bits, and entries holding a physical page number with valid, permission, accessed and dirty bits. The TLB caches translations; a miss walks the table at one memory access per level (three for Sv39, four for x86-64). Huge pages (2 MiB, 1 GiB) cut walks and TLB pressure. Address-space identifiers let the TLB hold several processes' entries.

#fig("/figures/u2-sv39.svg", caption: [A Sv39 page walk. Three 9-bit fields index three levels of 512-entry tables starting from the root in `satp`; the final entry's physical page number joins the 12-bit offset.])

*The IOMMU.* The same idea for devices: a device's DMA address is translated through I/O page tables, so a device can touch only memory its owner mapped for it. Intel VT-d, AMD-Vi, Arm SMMU and the RISC-V IOMMU. Without it, PCIe passthrough to a VM is unsafe; with it, VFIO becomes possible and a buggy NIC cannot scribble on the kernel.

*On-chip interconnect.* Wishbone and AXI between a few blocks; crossbars and networks-on-chip between many. Bandwidth is width times clock; contention and arbitration add latency. Little's law relates them: concurrency = throughput × latency. A core with 10 outstanding misses at 100 ns each sustains one line per 10 ns, which bounds its memory bandwidth.

*PCIe.* Point-to-point serial lanes (×1 to ×16) and a layered protocol: physical (128b/130b encoding at Gen3, PAM4 at Gen6), data link (ACK/NAK and flow-control credits) and transaction (TLPs: memory read and write, configuration, message). Devices are enumerated by walking buses and reading configuration space: vendor and device ID, class, BARs and capabilities. BARs say how much MMIO a device needs; firmware or the OS assigns addresses. Interrupts are message-signalled writes (MSI, MSI-X with per-vector addresses). DMA is the device issuing memory TLPs itself. Advanced Error Reporting, hot-plug, power states and Access Control Services are what a server must handle and a laptop can ignore.

#fig("/figures/u2-pcie.svg", caption: [A device's DMA write and MSI-X interrupt as TLPs. Both pass through the root complex, where the IOMMU translates the DMA address and remaps the interrupt.])

*CXL.* Compute Express Link reuses PCIe's physical layer for three protocols: CXL.io (PCIe as usual), CXL.cache (a device caches host memory coherently) and CXL.mem (the host uses device memory as its own). Type 1 devices are caching accelerators, Type 3 are memory expanders and pools, Type 2 do both. CXL 2.0 adds switches and pooling; 3.x adds fabrics and shared memory. For OMH it means memory attached, pooled and moved between modules, and a coherent path for accelerators.

*NUMA.* Several sockets or chiplets, each with local memory; remote access is slower. Thread and memory placement matter, and a hypervisor must expose or hide topology deliberately.

*NVMe, previewed.* Submission and completion queues in host memory, doorbells in a BAR, commands carrying physical addresses, completions signalled by MSI-X. It assumes everything above. Chapter 4.1 makes you write the driver.

== Reading

- Patterson and Hennessy, CO&D RISC-V edition, chapter 5 (all).
- Drepper, _What Every Programmer Should Know About Memory_, parts 2 to 6.
- Nagarajan, Sorin, Hill and Wood, _A Primer on Memory Consistency and Cache Coherence_, 2nd ed., chapters 1 to 4 and 6 to 8 (free).
- Hennessy and Patterson, CA:AQA, chapter 2 and appendix B.
- Jackson and Budruk, _PCI Express Technology 3.0_: chapters 1 to 6, 8 to 10 and 17.
- CXL 3.1 specification, chapters 1 and 2; JEDEC DDR4 standard sections 2 to 4; Intel VT-d specification chapters 1 to 3.

== Labs

#lab([Caches on your CPU], time: [2 weekends])[
+ Add a direct-mapped instruction cache and a write-back data cache (4 KiB each, 32-byte lines). Peripheral addresses bypass the cache; make `fence` and `fence.i` real (drain the write buffer, invalidate the I-cache).
+ Simulate memory-bound benchmarks (large-stride array sum, pointer chase, matrix multiply) with a memory model of configurable latency. Expose hit and miss counters as CSRs; record CPI and miss rate.
+ Change to 2-way with pseudo-LRU, then to 64-byte lines, then add a next-line I-cache prefetcher, measuring each.

#done-when(
  [riscv-tests still pass with caches on, and a table of CPI and miss rate across at least four configurations explains each change.],
)
#evidence([The configuration table and the benchmark sources.])
] <lab-caches>

#lab([External SDRAM], time: [1 weekend])[
+ Read the datasheet of the ULX3S's SDRAM: state diagram, initialisation sequence and timings. Write the init sequence and command timings down before looking at any controller.
+ Integrate an open controller (LiteDRAM or a ULX3S example) behind your cache and run a program from SDRAM. If time allows, write your own simple controller: init, refresh timer, single-word read and write with row open and close.
+ With a behavioural SDRAM model, count row hits and misses for sequential and strided access, and relate them to your line size.

#done-when(
  [C runs from SDRAM on the FPGA and you can explain the init sequence and what refresh costs in bandwidth.],
)
#evidence([The written init sequence; the row-hit counts.])
] <lab-sdram>

#lab([Memory experiments on a real machine], time: [1 weekend], kit: [Workstation, lab server, Raspberry Pi 5.])[
+ Stride benchmark: touch one byte every S bytes across a large array; plot time per access against S and read off the line and page sizes.
+ Working-set benchmark: random access within N bytes; plot against N and read off L1, L2 and L3. Compare with `lscpu`.
+ False sharing: two threads incrementing adjacent `std::atomic<int>`s against padded ones, measured with `perf stat -e cache-misses,instructions,cycles`.
+ TLB: pointer-chase 4 GiB with 4 KiB pages against 2 MiB huge pages; measure `dTLB-load-misses`.
+ Store-buffer litmus test: two threads on x86, no fences, a million runs, count "both read zero"; add a sequentially consistent fence and repeat. On the Pi, run the message-passing test with relaxed atomics and observe reordering x86 never shows.
+ On the server, `numactl --membind` remote against local for a bandwidth benchmark; record the ratio.

#done-when(
  [Plots show the line size, page size and three cache levels, and the litmus tests demonstrate TSO on x86 and weaker ordering on Arm.],
)
#evidence([C++ sources, plots and the litmus counts.])
] <lab-memory-experiments>

#lab([PCIe by hand], time: [1 weekend], kit: [Lab server with the NIC installed.])[
+ Read `lspci -vvv -s <nic>` slowly: vendor and device ID, class, each BAR's size and type, the capability list, MSI-X with its table BAR and offset, link speed and width, and AER.
+ Without `lspci`, dump the 256-byte standard configuration space from sysfs and decode every field from the PCI specification's header layout. Walk the capability list to MSI-X. Determine BAR sizes by the write-all-ones method, with the driver unbound.
+ Unbind the driver, `mmap` `resource0` from sysfs in a C program and read harmless registers (the 82599 datasheet lists device status and ID registers). You have talked to a PCIe device with no driver.
+ Rebind, read `/proc/interrupts` for the MSI-X vectors and their affinity, and watch counts move under traffic.
+ Find the IOMMU groups and explain why the NIC is or is not alone in its group, and what that means for passthrough.

#done-when(
  [The notebook has a hand-decoded configuration space with every field labelled, and your program's register reads match `lspci`.],
)
#evidence([The annotated hex dump; the C program and its output.])
] <lab-pcie-hand>

#lab([A page-table walker], time: [1 weekend])[
Add a Sv32 page-table walker and a small fully associative TLB to your CPU's instruction and data paths, gated by a `satp`-like CSR. Test with a program that builds a page table, enables translation, and checks that a load through a mapped page works and one through an unmapped page reports a fault. Fault handling arrives in Chapter 2.5; skip this lab now if you are behind, because 2.5 needs it.

#done-when(
  [Translated loads work and an unmapped access raises a fault signal in simulation.],
)
] <lab-ptw>

== Problem set

+ A 64 KiB, 8-way, 64-byte-line cache with 48-bit physical addresses: index, tag and offset widths, and total tag storage.
+ AMAT with L1 hits of 1 ns at 95 %, L2 hits of 4 ns on 80 % of L1 misses, and 80 ns memory. Then add an L3 at 12 ns hitting 60 % of L2 misses.
+ A DDR4-3200 channel is 64 bits wide. Peak bandwidth? With 8 channels? Why does measured bandwidth reach perhaps 80 % and a single core far less (Little's law with 10 outstanding misses at 90 ns)?
+ Refresh: 8,192 rows every 64 ms at 350 ns per refresh command. What fraction of time is the bank unavailable, and what happens at 16 Gbit densities?
+ Construct the SECDED code for 8 data bits and show it corrects one flipped bit and detects two.
+ Walk virtual address 0x0000_003F_C000_1234 through Sv39 with `satp` pointing at 0x8000_0000, giving the byte offset into each level's table.
+ PCIe Gen4 ×4 runs at 16 GT/s per lane. Compute usable bandwidth after 128b/130b, then after TLP overhead with 256-byte payloads and 20 bytes of header and framing. Compare with a drive advertising 7,000 MB/s.
+ Give the MESI state of a line in cores A and B after: A reads, B reads, A writes, B reads, B writes, A reads. Count bus transactions.
+ Explain why the store-buffer test can print 0,0 on x86 and the message-passing test cannot, then what changes on RISC-V RVWMO.
+ A CXL Type 3 expander adds 512 GiB at 250 ns against 90 ns local. For a key-value store with 5 % of accesses going to the far tier, what is the effective access time, and which OMH module does that trade suit?

== Deliverables and stretch

*Deliverables.* The cached CPU passing tests and running from SDRAM, with the configuration table; the C++ measurement programs and plots; the hand-decoded configuration space and the register-reading program.

*Stretch.* A two-core version of your CPU with snooping MSI coherence on a shared bus and a spin-lock test. A `perf` script estimating the cost of a page walk on the server by comparing 4 KiB and 1 GiB pages. Draw the CXL.mem request and response flow for a host read from a Type 3 device.

#checklist(
  [*Lab 2.4.1:* caches with fences working; four-configuration table explained.],
  [*Lab 2.4.2:* C runs from SDRAM; init sequence and refresh cost written down.],
  [*Lab 2.4.3:* plots revealing line, page and cache sizes; litmus results on x86 and Arm; the NUMA ratio.],
  [*Lab 2.4.4:* configuration space decoded by hand; driver-less register reads matching `lspci`.],
  [*Lab 2.4.5:* the page-table walker, here or before Chapter 2.5.],
  [*Problem set:* all ten answered.],
  [*You can explain*, without notes: tag, index and offset; MESI and false sharing; TSO versus RVWMO; a page walk; what a TLP is and where the IOMMU sits.],
)
