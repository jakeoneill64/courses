# Module 13: Storage and network data paths

**Part IV · 2 weeks · Needs: the server with both NVMe drives and the 82599 NICs, the Pi as a second node on the lab VLAN, your Lab 12.2 VMM. Can follow Module 11 directly.**

## Why this module (and what it buys OMH)

Storage, Blocks, Tables, Queues and Relational are all the same product underneath: bytes
arrive on a NIC, get transformed, land on NVMe, and are copied to other modules so that a
failed drive or a failed module loses nothing. The spec sheet promises erasure coding
across hot-swap bays, replacement without downtime, and encryption with keys in Modulus.
Whether those promises cost one CPU core per drive or eight is decided by the data path:
how many times a byte is copied, how many context switches it crosses, and whether the
erasure code runs at memory bandwidth or at a tenth of it. This module measures every
layer between a tenant's write and durable, replicated flash, and builds the two
primitives that Storage and Blocks share: a fast local NVMe path and a fast path between
modules.

## Skip test

1. A 4 KiB `pwrite` with `O_DIRECT` on an NVMe drive: list every copy, every context switch
   and every interrupt from the syscall to completion, then repeat for io_uring with
   `IORING_SETUP_SQPOLL` and `IOPOLL`, then for SPDK.
2. Reed-Solomon over GF(2^8) with 4 data and 2 parity shards: how many bytes of source are
   read to encode one stripe, how many to repair one lost shard, and why does a systematic
   code matter for the read path?
3. NVMe over Fabrics on TCP versus RDMA: what does each do on the initiator's CPU per I/O,
   and what does the target do?
4. Why does a userspace network stack (DPDK, XDP) beat the kernel for small packets, and
   what does it give up?
5. An enterprise NVMe drive advertises power-loss protection. What exactly is protected,
   what is not, and what does a consumer drive do with your `fsync`?

If all five are easy, do Labs 13.2, 13.4 and 13.5.

## Core ideas

**The storage path in Linux.** `write(2)` on a buffered file dirties page cache; writeback
later issues bios; the filesystem's allocator and journal decide layout and ordering;
blk-mq queues the request on a per-CPU software queue, dispatches to a hardware queue
mapped to an NVMe submission queue, and the driver writes the doorbell. `O_DIRECT` skips
the page cache but not the filesystem or the block layer. `fsync` forces the journal and
issues a flush (or relies on FUA). Each layer adds latency in the tens of microseconds
range on a drive whose media latency is about 10 microseconds, which is why the data path
matters more for NVMe than it ever did for disks.

**Asynchronous I/O.** libaio was never fully asynchronous for buffered files. io_uring
provides a submission ring and a completion ring shared with the kernel, with options to
skip the syscall (`SQPOLL`: a kernel thread watches the ring), skip the interrupt
(`IOPOLL`: completions are polled), pre-register buffers and file descriptors, and chain
operations. It is the kernel's answer to SPDK and, for many workloads, close enough.

**Polling versus interrupts.** An interrupt costs a few microseconds of wakeup and context
switch; at queue depth 1 that doubles a fast drive's latency. Polling burns a core to
remove it. Hybrid polling sleeps for a fraction of the expected completion time. The
trade-off is CPU cost against latency, and Blocks will have to pick a point per volume
tier.

**SPDK and userspace drivers.** SPDK takes the NVMe drive from the kernel with VFIO, maps
its BARs into the process, and runs a lock-free, poll-mode driver on a dedicated core
with hugepage-backed buffers pinned for DMA. No interrupts, no syscalls, no copies: a
million 4 KiB IOPS per core. Its `bdev` layer stacks virtual block devices (RAID, crypto,
compression, logical volumes) above the driver, and its NVMe-oF target and vhost-user
target export them. The cost is a dedicated core per polling thread and losing the
kernel's tooling.

**Erasure coding.** Replication costs 3× for two-failure tolerance; a (k, m) Reed-Solomon
code costs (k+m)/k. Encode: multiply the data shards by a k×m Cauchy or Vandermonde
matrix over GF(2^8). Repair: invert a k×k submatrix from any k surviving shards. Reads of
undamaged data touch only the data shards if the code is systematic. Implementation speed
lives in the GF multiply: log tables are slow; the split-table technique with `pshufb`
(SSSE3) or `vpshufb` (AVX2) and `vgf2p8mulb` (GFNI) reach memory bandwidth. Intel ISA-L
and the Klauspost `reedsolomon` library are the references. Erasure coding turns one
write into k+m writes and one lost drive into k reads plus a matrix multiply, and the
repair bandwidth is what decides how many drives a module can lose per hour before data
is at risk.

**Consistency across modules.** A stripe written to six drives on three modules is only
durable if a failure at any instant leaves a recoverable state. Write-ahead intent
records, two-phase commit on the stripe, or append-only stripes with a versioned index
avoid the "partially updated parity" problem. Above the stripes sits a placement and
membership layer: a consensus group (Raft) holds the map of which module owns which
stripe, and clients learn placement from it. Module 16 assembles this; here you build
the stripe and the replication transport.

**NVMe over Fabrics.** The NVMe command set over a network: RDMA (RoCE or InfiniBand),
TCP or Fibre Channel. The target exposes namespaces; the initiator's `nvme-fabrics` driver
presents them as local NVMe devices. NVMe/TCP costs the initiator a copy and a kernel
TCP stack per I/O but needs no special NICs; RDMA delivers a remote 4 KiB read in about
10 microseconds with near-zero CPU. Blocks' volumes are NVMe-oF namespaces served from a
storage module to a compute module; the tier choice is the transport choice.

**NVMe reservations and fencing.** Persistent Reservations (the NVMe Reservation Register,
Acquire and Release commands, with a host ID per initiator) let one host fence others
off a namespace. This is the mechanism behind Blocks' multi-attach fencing: without it,
two compute sleds writing the same volume after a network partition corrupt it. Test it
against a target that implements it and against one that ignores it.

**The network path.** A frame arrives, the NIC DMAs it into a ring buffer, raises an
interrupt (moderated), NAPI polls the ring, builds an `sk_buff`, runs it through
netfilter and the IP and TCP stacks, and copies the payload to the socket buffer on
`recv`. Around 60 to 100 microseconds and a few thousand cycles per packet with all the
features on. Bypasses: XDP runs an eBPF program at the driver before `sk_buff` allocation
(drop, redirect, or pass), AF_XDP hands raw frames to userspace through a ring, DPDK takes
the NIC entirely into userspace with a poll-mode driver, and RDMA lets the NIC write into
application memory with no CPU at all. Offloads (checksum, segmentation, receive-side
scaling, flow steering, TLS) move work to the NIC; SmartNICs and DPUs move whole stacks.
Every OMH module has a NIC in its data path; the choice of stack per module is a capacity
question.

**Copies, cores and capacity.** Memory bandwidth on a two-socket server is a few hundred
GB/s; a copy costs twice its size in bandwidth. Zero-copy is the discipline of arranging
that the NIC DMAs into the buffer the erasure coder reads and the NVMe drive DMAs from
the buffer the coder writes. Count copies in every design; each one is a fraction of a
core at 25 Gbit/s and a whole core at 100.

**Encryption in the path.** AES-XTS at rest, per volume or per object, with keys unwrapped
from Modulus into memory and never to disk. AES-GCM in flight for NVMe/TCP with TLS or for
your own replication protocol. AES-NI encrypts at several GB/s per core; the cost is
where it lands in the pipeline and whether the drive's self-encryption (OPAL, TCG) is
trusted instead. A design decision for Module 15: keys per tenant in software, or keys
per drive in hardware, or both.

**Durability engineering.** Power-loss protection in the drive means acknowledged writes
survive; without it, the drive's volatile cache lies to you. `fsync` cost is the price of
telling the truth. Checksums on every block (CRC32C or xxHash), verified on read, catch
silent corruption that RAID and erasure codes do not detect on their own. Scrubbing reads
everything periodically. Write amplification, flash endurance (TBW, DWPD), over-provisioning
and the garbage collection stall are the physics beneath the drive's SMART page.

## Reading

- NVMe Base Specification: ch. 3 (queues and doorbells, the memory-based transport),
  ch. 5 (admin commands: Identify, Get Log Page for SMART), ch. 7 (reservations), ch. 8
  (I/O command set). NVMe over Fabrics specification: ch. 1 to 3, and the TCP transport
  binding.
- Plank, "A Tutorial on Reed-Solomon Coding for Fault-Tolerance in RAID-like Systems",
  1997, and its 2005 correction note. Then Plank et al., "Screaming Fast Galois Field
  Arithmetic Using Intel SIMD Instructions", FAST 2013.
- Intel ISA-L source: `erasure_code/` for the reference implementations and the AVX2 and
  GFNI kernels. Klauspost `reedsolomon` for a readable production library.
- Axboe, "Efficient IO with io_uring" (the original design document) and the `liburing`
  man pages. `Documentation/block/` in the kernel tree.
- SPDK documentation: NVMe driver, bdev layer, NVMe-oF target, vhost-user target.
- DPDK Programmer's Guide: ch. on the poll-mode driver, mbufs and rings. The Linux XDP
  paper: Høiland-Jørgensen et al., "The eXpress Data Path", CoNEXT 2018.
- Ongaro and Ousterhout, "In Search of an Understandable Consensus Algorithm" (Raft),
  2014. Read now; implement in Module 16.
- Ghemawat, Gobioff, Leung, "The Google File System", 2003, and Weil et al., "Ceph: A
  Scalable, High-Performance Distributed File System", 2006, for two placement designs.
- Pillai et al., "All File Systems Are Not Created Equal", OSDI 2014, on what `fsync`
  actually guarantees per filesystem.

## Labs

### Lab 13.1: Measure the local storage path

On the server with the sacrificial drive, `fio` and your own C++ harness.

1. `fio` matrix: engines `psync`, `libaio`, `io_uring` (with and without `sqthread_poll`
   and `hipri`), block sizes 4 KiB and 128 KiB, queue depths 1, 8, 32, 128, random read and
   random write, `direct=1`. Record IOPS, bandwidth, and p50, p99 and p99.9 latency. Then
   repeat with a filesystem (ext4 and XFS) instead of the raw device, and with `fsync` per
   write.
2. Explain each row's difference from the previous one in a sentence. Little's law from
   Module 5 should predict throughput from latency and depth; where it does not, find the
   bottleneck with `perf top` and `bpftrace` on the block tracepoints.
3. Write your own io_uring harness in C++ with `liburing`: registered buffers and files,
   `IOPOLL`, a fixed pool of in-flight requests, and a per-request latency histogram
   (HdrHistogram or your own log-linear buckets). Match `fio`'s best numbers.
4. Enterprise drive versus consumer drive: repeat the `fsync` rows on both. Pull the
   power on the consumer drive mid-write (a USB-to-NVMe enclosure you can unplug, or a
   PCIe slot power switch if you have one) with a program that writes sequenced,
   checksummed blocks and `fsync`s each; on reboot, find the last acknowledged block that
   is missing. Repeat on the enterprise drive.

Done when: the matrix is in your notebook with an explanation per row, your harness
matches `fio`, and you have demonstrated (or failed to demonstrate) lost acknowledged
writes on the consumer drive.

### Lab 13.2: SPDK on your drive, and a vhost-user disk for your VMM

1. Build SPDK. Bind the sacrificial drive to `vfio-pci` (`scripts/setup.sh`). Run
   `examples/nvme/perf` and `bdevperf` and add the numbers to the Lab 13.1 matrix. Explain
   the gap from your best io_uring result: syscalls, interrupts, copies, and the dedicated
   core.
2. Write an SPDK application: open the NVMe controller, create one queue pair, submit
   reads from a hugepage buffer, poll completions. Your Module 9 NVMe driver was this
   without the framework; compare line by line.
3. Stack a `crypto` bdev (AES-XTS) and a `raid` or `lvol` bdev over the drive; measure the
   cost of encryption per core.
4. Run SPDK's vhost-user-blk target and connect your Lab 12.2 VMM to it: implement the
   vhost-user protocol on the VMM side (feature negotiation, memory regions, virtqueue
   addresses, call and kick eventfds). The guest's virtio-blk now goes to SPDK with no
   host kernel in the path. `fio` inside the guest; compare with your file-backed
   virtio-blk.

Done when: a guest in your VMM does I/O through vhost-user to SPDK at within 20% of the
host's SPDK throughput, and the per-layer cost table is complete.

### Lab 13.3: Reed-Solomon, in C++, at memory bandwidth

1. Implement GF(2^8) arithmetic with the AES polynomial (0x11d): tables for multiply and
   inverse, tests against a slow reference. Build a Cauchy matrix generator and a
   systematic (k, m) encoder and decoder with Gaussian elimination for the inverse.
   Property tests: encode, delete any m shards, decode, compare.
2. Make it fast: the split-table `pshufb` technique with AVX2 (`_mm256_shuffle_epi8`),
   then GFNI (`_mm512_gf2p8affine_epi64_epi8` or `vgf2p8mulb`) if the server supports it.
   Benchmark (10, 4) with 1 MiB shards; report GB/s per core encode and single-shard
   repair. Target ISA-L's numbers within a factor of two; then read ISA-L's kernel and
   close the gap.
3. Wire it into a stripe writer: data arrives as a stream, is cut into stripes, encoded,
   and each shard written to a different drive or file with a header (stripe ID, shard
   index, version, CRC32C over the shard). A reader reconstructs from any k shards and
   verifies checksums. A scrubber walks all stripes and reports.
4. Failure test: write 10 GiB across six files on two drives, delete two files, read
   everything back, measure repair throughput. Then corrupt a byte in one shard silently
   and confirm the checksum catches it and repair proceeds from the other shards.

Done when: your encoder is within 2× of ISA-L, and the stripe store survives two lost
shards and one silently corrupted one.

### Lab 13.4: NVMe over Fabrics between two nodes

The server as target, the Pi (with its NVMe) as initiator, or the reverse.

1. Kernel target: `nvmet` with the TCP transport, exporting a namespace backed by a
   partition on the sacrificial drive (`configfs` under `/sys/kernel/config/nvmet`).
   Initiator: `nvme discover` and `nvme connect`. `fio` across the link; compare to local.
   Where does the time go? `bpftrace` the TCP send path on the target.
2. SPDK target: the same namespace via `nvmf_tgt` with the TCP transport, polled. Compare
   CPU per IOPS with the kernel target under `perf stat`.
3. If you have two 82599s and a DAC: bring up RoCE (or use the ConnectX if that is what you
   bought). `nvme connect -t rdma`. Compare latency at queue depth 1 with TCP.
4. Reservations: from the initiator, `nvme resv-register`, `resv-acquire` with a write-
   exclusive type, then attempt a write from a second host ID (a second connection with a
   different `--hostnqn` and host ID) and confirm it is refused with a reservation
   conflict. This is the Blocks multi-attach fence; write the fencing protocol for a
   partitioned compute sled as a page.
5. Attach the remote namespace as a passthrough or virtio-blk disk to a guest in your VMM.
   A tenant VM on one module now boots from a volume on another. Measure the whole path.

Done when: a guest boots from a remote NVMe-oF volume, reservations fence a second
initiator, and the transport comparison table is done.

### Lab 13.5: The network path: kernel, XDP, AF_XDP, DPDK

On the server with the second 82599 port and a DAC to the first (or to the Pi's NIC, or a
second machine), so you control both ends.

1. Baseline: `iperf3` TCP and UDP, then a small-packet test with `pktgen` or `trafgen`
   at 64-byte frames. Record packets per second and CPU per packet. Read
   `/proc/interrupts`, `ethtool -S`, and `perf top` while it runs.
2. XDP: an eBPF program that drops frames matching a UDP port and passes everything else,
   loaded with `ip link set xdp`. Measure drop rate in packets per second. Then an XDP
   program that rewrites MACs and `XDP_TX`s the frame back: a reflector. Compare with a
   userspace UDP echo.
3. AF_XDP: a C program that binds a UMEM and rings to a queue, receives frames, echoes
   them. Zero-copy mode if the driver supports it. Packets per second and CPU.
4. DPDK: bind the port to `vfio-pci`, run `testpmd` in forwarding mode, then write a
   forwarding application with `rte_eth_rx_burst` and `rte_eth_tx_burst`. Line rate at
   64 bytes on one core is the goal.
5. Build the replication transport for Module 16 on the best fit: a length-prefixed,
   checksummed frame protocol over TCP (kernel) first, with `io_uring` for the socket I/O
   and zero-copy send (`MSG_ZEROCOPY`); measure GB/s per core at 1 MiB messages. Note what
   you would gain by moving it to RDMA or AF_XDP and at what cost.

Done when: the four stacks are compared on packets per second per core at 64 bytes and
GB/s per core at 1 MiB, and the replication transport moves shards between the server and
the Pi with checksums verified.

### Lab 13.6: A Blocks prototype

Assemble the pieces into one program per node:

1. A volume is a sequence of 1 MiB stripes, each erasure-coded (4, 2) across six shard
   files spread over the server's two drives and the Pi's drive over your Lab 13.5
   transport. Writes are append-only into new stripe versions with an index that maps
   volume offsets to stripe versions; a background compactor reclaims old versions.
2. Expose the volume as an NVMe-oF namespace with SPDK's `bdev` API (a custom bdev module
   that calls your stripe store) or, simpler, as a `ublk` or NBD device on the server.
3. Attach it to a guest in your VMM. Run `fio` inside the guest; report throughput and
   latency versus a plain local disk. Pull the Pi's network cable mid-write: the guest's
   I/O continues (4 shards remain), the store marks the missing shards, and reconnects and
   repairs when the cable returns.
4. Snapshot: the index is copy-on-write, so a snapshot is a copy of the index; clone a new
   volume from it and boot a second guest.

Done when: a guest runs on an erasure-coded volume spanning two nodes, survives a node
disappearing during writes, and a snapshot boots a second guest. Record the cores per
GB/s figure; it is the first line of Module 15's cost model.

## Problem set

1. Compute the storage overhead, repair reads per lost drive, and simultaneous-failure
   tolerance for 3× replication, (4, 2), (10, 4) and (17, 3). Which suits a six-bay module?
   A rack of ten?
2. A stripe write to six drives on three modules is interrupted by power loss on one
   module after four shards are written. Describe two designs that leave the volume
   consistent and what each costs on the write path.
3. Derive the CPU cost in cores of encoding 10 GB/s with your Lab 13.3 numbers, then the
   memory bandwidth consumed including one copy in and one out. Where does a two-socket
   server hit its ceiling, and what removes the copies?
4. io_uring with `SQPOLL` and `IOPOLL` still costs something per I/O. What?
5. Explain why NVMe/TCP's initiator needs a copy per read completion in the kernel stack
   and how RDMA avoids it. What does the RDMA NIC need to know about the buffers?
6. A consumer drive lies about `fsync`. Design a test that proves it in one power cycle,
   and explain what Blocks would have to do to be durable on such drives.
7. Two compute sleds attach the same Blocks volume. Sled A loses network contact with the
   control plane but not with the storage module. Walk the fencing protocol step by step
   and name the exact NVMe command that stops A's writes.
8. Where should encryption happen in the Lab 13.6 path: in the guest, in the VMM, in the
   stripe store before encoding, per shard after encoding, or in the drive? Give the
   trade-offs for key custody, repair, deduplication and CPU.
9. A silent bit flip occurs in a shard on disk. Trace how it is detected on read, on
   scrub, and what would happen with parity alone and no checksum.

## Deliverables

- The measurement matrix from Labs 13.1, 13.2, 13.4 and 13.5 with a written explanation
  per row.
- Your Reed-Solomon library with benchmarks and property tests.
- The stripe store, the replication transport and the Blocks prototype, in your labs repo
  with a demo script that runs the cable-pull test.
- The fencing protocol page and the encryption placement decision.

## Stretch

- Implement the stripe store as an SPDK bdev module and run the whole node data path with
  zero kernel involvement; compare cores per GB/s.
- Add local reconstruction codes (Huang et al., "Erasure Coding in Windows Azure Storage",
  2012) and measure repair traffic against plain Reed-Solomon.
- Build the object store front end: an S3 PUT and GET subset over HTTP (multipart upload,
  range reads, ETags) on the stripe store. This is Storage's skeleton.
- Move the replication transport to RDMA verbs and measure.

## Next

Part V. Module 14 designs and builds the two boards, the management controller and the
Compute Module carrier, that turn the lab server into a prototype of the product you have
been writing software for.
