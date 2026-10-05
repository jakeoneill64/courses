#import "../lib/template.typ": *

= Storage and network data paths <ch-datapath>

#chapter-meta(
  weeks: [2.5 weeks],
  builds: [Every layer between a write and the flash measured, with a power-cut test of acknowledged writes; SPDK and a vhost-user disk for your VMM; a Reed-Solomon stripe store at memory bandwidth; NVMe over Fabrics with reservation fencing; four network receive paths compared at line rate; a replication transport; a Blocks prototype that survives losing a node.],
  needs: [The lab server with the Intel P4510 and the sacrificial Kingston NV3, the X520-DA2 with a DAC between its ports, the Pi 5 with its NVMe drive, your Chapter 4.4 VMM, `fio`, liburing, SPDK, DPDK and ISA-L.],
)

#why[
  Storage, Blocks, Tables, Queues and Relational are the same product underneath: bytes arrive on a NIC, are transformed, land on NVMe and are copied to other modules so that a failed drive or module loses nothing. OMH's specification sheet promises erasure coding across hot-swap bays, drive replacement without downtime and encryption with keys in Modulus. Whether they cost one core per drive or eight is decided by the data path: the copies per byte, the interrupts per I/O and the speed of the erasure code. This chapter measures every layer between a tenant's write and replicated flash, and builds the two primitives Storage and Blocks share: a fast local NVMe path and a fast path between modules.
]

#skip-test(
  rule: [If all five are easy, do Labs 4.5.2, 4.5.4 and 4.5.5.],
  [A 4 KiB `pwrite` with `O_DIRECT` to an NVMe drive: list every copy, mode switch and interrupt to completion. Repeat for `io_uring` with `SQPOLL` and `IOPOLL`, then for SPDK.],
  [Reed-Solomon over GF($2^8$) with four data and two parity shards: how many bytes are read to encode a stripe and to repair one shard, and why does a systematic code matter for reads?],
  [NVMe over Fabrics on TCP and on RDMA: what does each cost the initiator's CPU per I/O?],
  [Why does DPDK or AF\_XDP beat the kernel at 64-byte packets, and what does it give up?],
  [An enterprise drive advertises power-loss protection. What exactly is protected, and what does a consumer drive do with your `fsync`?],
)

== Core ideas

*The storage path in Linux.* A buffered `write` copies into the page cache and returns. Writeback later builds bios, the filesystem decides layout and order, and blk-mq moves each request from a per-CPU software queue to a hardware queue mapped to an NVMe submission queue. The driver writes a 64-byte command and rings the doorbell; the controller fetches it, moves the data by DMA and posts a completion, usually with an MSI-X interrupt. `O_DIRECT` skips only the page cache. `fsync` forces the journal and sends a Flush, or relies on FUA writes. Each layer costs microseconds: noise against a disk, a large share of an NVMe drive's tens of microseconds. The generic device `/dev/ng0n1` with `io_uring` passthrough keeps the driver and skips the block layer.

#fig("/figures/u4-datapath-stack.svg", caption: [Four ways from a 4 KiB write to flash. Labs 4.5.1 and 4.5.2 measure what each removed layer is worth.], width: 100%)

*Asynchronous I/O and polling.* libaio is asynchronous only with `O_DIRECT`. `io_uring` shares submission and completion rings with the kernel. With `SQPOLL` a kernel thread watches the submission ring, so a busy application makes no system calls; with `IOPOLL` completions are polled from the driver, which needs NVMe poll queues (`nvme.poll_queues`). Registered buffers skip per-I/O pinning, and linked requests order a write before its flush. An interrupt and wake-up cost several microseconds, much of a fast drive's latency at queue depth 1. Polling removes them and spends a core (hybrid polling sleeps through part of the wait first), and Blocks picks a point on that curve per volume tier.

*SPDK.* SPDK takes the drive from the kernel through VFIO, maps its BARs into the process and runs a lock-free poll-mode driver on a dedicated core with pinned hugepage buffers. With no interrupts, system calls or copies, one core completes a million or more 4 KiB I/Os per second. Its bdev layer stacks RAID, encryption and logical volumes, and its NVMe-oF and vhost-user targets export them. The price is a core that always spins, and no kernel tooling.

*Erasure coding.* Three-way replication survives two failures at three times the capacity; a $(k, m)$ Reed-Solomon code survives any $m$ lost shards at $(k + m) slash k$. Encoding multiplies the data by a generator matrix over GF($2^8$), where addition is XOR. A systematic generator stacks the identity on an $m times k$ matrix $C$, so data shards are stored as they are and healthy reads touch only them. With a Cauchy matrix, $c_(i j) = 1 slash (x_i + y_j)$, every square submatrix is invertible, so any $k$ survivors rebuild the stripe: take their rows, invert, multiply. The field multiply sets the speed: nibble lookups with `vpshufb` handle 32 bytes per instruction on AVX2 and reach memory bandwidth. ISA-L uses the polynomial 0x11D while GFNI's `gf2p8mulb` is fixed to the AES polynomial 0x11B, so fast libraries use `gf2p8affineqb` with an 8 × 8 bit matrix per coefficient. Each write becomes $k + m$ writes and each lost drive $k$ reads per stripe; that repair bandwidth sets how many drives a module can lose per hour before data is at risk.

#fig("/figures/u4-datapath-erasure.svg", caption: [A (4, 2) stripe. Identity rows keep data shards readable as stored; Cauchy rows make any four survivors enough. Lab 4.5.6’s failure domains are two drives and the Pi; Chapter 4.7 makes each a node.], width: 100%)

*Consistency across modules.* A stripe spread over three modules is durable only if a crash at any instant leaves a recoverable state. Updating in place risks the write hole, where data and parity disagree after a crash; intent logs, two-phase commit per stripe, or append-only stripes under a versioned index avoid it, and the last makes snapshots nearly free. A Raft group above the stripes holds placement, which Chapter 4.7 builds.

*NVMe over Fabrics.* The NVMe command set over RDMA, TCP or Fibre Channel: a target exports namespaces and the initiator presents them as local drives. NVMe/TCP needs no special NIC and costs the initiator a TCP stack and a copy per I/O. RDMA places data straight into registered memory and adds under 10 µs to a remote read for almost no CPU. The X520 has no RDMA engine, so the labs use soft-RoCE (`rdma_rxe`), which runs the protocol on the CPU: it teaches the verbs and says nothing about hardware latency. NVMe/TCP can run over TLS 1.3 with the handshake in user space (`tlshd`). Blocks serves volumes as NVMe-oF namespaces, so a volume tier is a transport choice.

*Reservations and fencing.* Hosts register keys under their host identifiers, and one holder acquires a reservation such as Write Exclusive. Reservation Acquire with Preempt, or Preempt and Abort, removes another host's registration, and that host's next write fails with a reservation conflict. This is Blocks' multi-attach fence: without it, two sleds writing one volume after a partition corrupt it. Linux's kernel target supports reservations when a namespace's `resv_enable` is set, and so does SPDK; on a target without them nothing stops the second writer.

*The network path.* The NIC DMAs a frame into a receive ring and raises a moderated interrupt. NAPI polls the ring, the driver builds an `sk_buff`, GRO merges segments, netfilter, IP and TCP run, and `recv` copies the payload out, at a few thousand cycles per packet. XDP runs eBPF in the driver before any `sk_buff` exists and returns drop, transmit, pass or redirect. AF\_XDP redirects frames to a user-space socket whose UMEM the driver fills directly, and `ixgbe` supports its zero-copy mode. DPDK polls the NIC from user space through `vfio-pci`; RDMA writes into application memory with no CPU. Offloads (checksum, segmentation, RSS, kTLS) and DPUs move work into the NIC. A 64-byte frame occupies 84 bytes of wire time, so 10 Gbit/s line rate is $10^10 slash (84 times 8) approx 14.88$ million packets per second: 67 ns per packet, about 175 cycles at 2.6 GHz.

#fig("/figures/u4-datapath-network.svg", caption: [The receive path and its exits, each measured per core in Lab 4.5.5.], width: 100%)

*Copies, cores and capacity.* The lab server's eight DDR4-2400 channels peak near 150 GB/s, and a copy costs twice its size. Zero copy means the NIC DMAs into the buffer the encoder reads and the drive DMAs from the one it writes; each copy avoided saves part of a core at 25 Gbit/s and a whole core at 100.

*Encryption in the path.* AES-XTS at rest, with keys unwrapped from Modulus into memory only, and AES-GCM in flight. AES-NI runs at several GB/s per core, so the decision is placement, or trusting the drive's TCG Opal instead.

*Durability.* Power-loss protection keeps a drive alive long enough to save its write cache. A drive without it reports a volatile write cache and may hold acknowledged data in DRAM until a Flush, and one that acknowledges a Flush early is found only by cutting its power. Per-block checksums (CRC32C, xxHash) verified on read catch silent corruption that erasure codes cannot see, and a scrubber finds it before a second failure makes it permanent. Endurance sits beneath: the NV3 500 GB is rated for 160 TB written, which at a write amplification of 3 allows about 49 GB of host writes a day for three years.

== Reading

- NVMe Base Specification 2.x on queues, Identify Controller, the SMART log, reservations and Fabrics; the NVM Command Set and NVMe/TCP Transport specifications.
- Plank's 1997 Reed-Solomon tutorial with its 2005 correction; Plank, Greenan and Miller, "Screaming Fast Galois Field Arithmetic", FAST 2013; ISA-L's `erasure_code/`.
- Axboe, "Efficient IO with io_uring"; the liburing man pages; kernel `blk-mq.rst` and `ublk.rst`.
- SPDK's NVMe, bdev, NVMe-oF and vhost pages; the DPDK guide on poll-mode drivers and mbufs; "The eXpress Data Path", CoNEXT 2018; kernel `af_xdp.rst`.
- The Raft paper (Ongaro and Ousterhout, 2014) for Chapter 4.7; the GFS and Ceph papers for placement.
- Pillai et al., "All File Systems Are Not Created Equal", OSDI 2014, on what `fsync` guarantees.

== Labs

Every lab but Lab 4.5.3 destroys data on the NV3: keep the operating system on another disk, and save each drive's `nvme smart-log` first.

#lab([Measure the local storage path], goal: [what each layer costs, and whether each drive keeps its promises.], time: [1 weekend], kit: [The server, both drives, the Pi.])[
+ Boot with `nvme.poll_queues=4`. Record `nvme id-ctrl` for both drives, including VWC, and predict their behaviour under `fsync`.
+ Run `fio` with `direct=1` on the raw NV3: `psync`, `libaio`, `io_uring` (plain, `sqthread_poll`, then `hipri` with `fixedbufs`) and `io_uring_cmd` on `/dev/ng1n1`, at 4 KiB and 128 KiB, depths 1 to 128, random read and write. Record IOPS, bandwidth and p50 to p99.9 latency. Repeat on ext4, on XFS, with `fsync=1`, and on the P4510.
+ Explain each row against the last. Where Little's law (Chapter 2.4) fails, find the bottleneck with `perf` and `bpftrace` on the block tracepoints.
+ Write a C++ liburing harness with registered buffers, `IOPOLL`, a fixed pool of in-flight requests and a latency histogram, and match `fio`'s best rows.
+ Cut the power. Write sequenced, CRC-checked 4 KiB blocks with `fdatasync`, send each acknowledged sequence number by UDP to the Pi, and cut the server mid-run from the Pi with a Redfish `ForceOff` to the iDRAC (Lab 2.7.7). Count acknowledged blocks lost. Make five cuts per drive, then five without `fdatasync`.

#safety[`ForceOff` cuts power to the whole host. Keep only the boot disk mounted read-write, and nothing on the server that you need.]

#done-when(
  [The matrix has a sentence per row, and your harness is within 10 % of `fio`'s best IOPS at depth 32.],
  [Twenty power cuts are logged with the acknowledged blocks lost per drive and mode.],
)
#evidence([`fio` output; the harness; the power-cut log with each drive's VWC field.])
] <lab-dp-local>

#lab([SPDK, and a vhost-user disk for your VMM], goal: [take the kernel out of the storage path.], time: [1 weekend])[
+ Build SPDK, bind the NV3 with `scripts/setup.sh`, run `spdk_nvme_perf` and `bdevperf`, and explain the gap to your best `io_uring` row, with CPU per I/O from `perf stat`.
+ Write an SPDK application that attaches the controller, allocates a queue pair, reads into `spdk_dma_zmalloc` memory and polls for completions. Compare it with your Chapter 4.1 NVMe driver.
+ Stack a crypto bdev (`AES_XTS`, key from `accel_crypto_key_create`) and a logical volume store, and measure encryption's cost per core.
+ Create a controller in SPDK's `vhost` target and implement the vhost-user front end in your Chapter 4.4 VMM: shared hugepage memory, `VHOST_USER_SET_MEM_TABLE` with descriptors passed over the socket, the vring messages, and eventfds bound to `KVM_IOEVENTFD` and `KVM_IRQFD`. Compare guest `fio` with your file-backed virtio-blk.

#done-when([A guest reaches within 20 % of host SPDK throughput at 4 KiB random read, depth 32, and the cost table includes CPU per I/O and AES-XTS per core.])
#evidence([The SPDK rows; a vhost-user message trace of one guest boot.])
] <lab-dp-spdk>

#lab([Reed-Solomon in C++ at memory bandwidth], goal: [a code fast enough that the network sets the limit.], time: [1 weekend])[
+ Implement GF($2^8$) with 0x11D, tested against a slow carry-less reference; a Cauchy generator; a systematic encoder; and a Gaussian-elimination decoder tested on every combination of $m$ lost shards for (4, 2) and (10, 4).
+ Vectorise with nibble tables and `_mm256_shuffle_epi8`. Benchmark (10, 4) encode and repair with 1 MiB shards on one core against ISA-L's `ec_encode_data`, then read ISA-L's AVX2 kernel and close the gap. The E5-26xx v4 lacks GFNI; on a workstation that has it, add a `gf2p8affineqb` kernel.
+ Build a stripe store: each shard in its own file behind a header (stripe ID, shard index, version, CRC32C), a reader that rebuilds from any $k$ and verifies, and a scrubber.
+ Write 10 GiB as (4, 2) across both drives, delete two shard files, read back and time the repair. Flip a byte in one shard and show the checksum catching it.

#done-when([The encoder is within a factor of two of ISA-L and passes every loss pattern; the store returns every byte after two lost shards and a silent corruption.])
#evidence([The benchmark table; the failure-test log.])
] <lab-dp-rs>

#lab([NVMe over Fabrics between two nodes], goal: [serve a volume across the network, and fence a host.], time: [1 weekend], kit: [The server, the Pi, the X520 and its DAC.])[
+ Export an NV3 partition with `nvmet-tcp` through `/sys/kernel/config/nvmet`. From the Pi, `nvme connect` and run `fio` over 1 Gbit/s.
+ For 10 Gbit/s, put the X520’s second port in a network namespace and connect from it with `ip netns exec`; the host driver opens its sockets in the caller's namespace, so traffic crosses the DAC. Rerun `fio` and trace the target's TCP send path with `bpftrace`.
+ Serve the namespace from SPDK's `nvmf_tgt` and compare CPU per I/O. Build `rdma_rxe` into both kernels, run `rdma link add rxe0 type rxe netdev <port>`, connect with `-t rdma` and compare depth-1 latency with TCP.
+ Fence. Register and acquire Write Exclusive from the Pi with `nvme resv-register` and `nvme resv-acquire`; show the server's initiator gets a reservation conflict; preempt the Pi from the server. Repeat on SPDK and with `resv_enable` unset, and write the fencing protocol for a partitioned sled on one page.
+ Reverse the roles and boot a guest in your VMM from the Pi's drive.

#done-when(
  [A guest boots from a remote volume, and reservations fence the second host wherever the target implements them.],
  [The transport table gives depth-1 latency and CPU per I/O for kernel TCP at 1 and 10 Gbit/s, SPDK and soft-RoCE.],
)
#evidence([The target scripts; the reservation transcript; the fencing page.])
] <lab-dp-nvmeof>

#lab([The network path: kernel, XDP, AF\_XDP and DPDK], goal: [the cost per packet at each exit, and the replication transport.], time: [1 weekend], kit: [The X520’s ports joined by the DAC, one in a network namespace; the Pi.])[
+ Baseline with `iperf3`, then 64-byte frames from `pktgen` (`samples/pktgen`): packets per second and CPU per packet against 14.88 Mpps, with `ethtool -S` and `perf top`.
+ XDP: drop one UDP port with `ip link set dev <port> xdpdrv object drop.o section xdp`, then reflect frames with `XDP_TX` and compare with a user-space `recvmmsg` echo.
+ AF\_XDP: bind a UMEM and its rings with libxdp's `xsk` API and `XDP_ZEROCOPY` to one queue, steer the flow there with `ethtool -N`, and echo.
+ DPDK: bind both ports to `vfio-pci`, generate with `dpdk-testpmd` in `txonly` mode on one, and forward with your own `rte_eth_rx_burst` loop on the other, as two processes with separate `--file-prefix` values. Aim for line rate on one core.
+ Build Chapter 4.7’s replication transport: CRC32C-checked frames over TCP with `io_uring` and `IORING_OP_SEND_ZC`. Measure GB/s per core at 1 MiB across the DAC and to the Pi.

#done-when([The four paths are compared per core at 64 bytes and at 1 MiB, and the transport moves shards to the Pi with every checksum verified.])
#evidence([The programs; the comparison table.])
] <lab-dp-net>

#lab([A Blocks prototype], goal: [one volume a guest boots from, which survives a lost node.], time: [2 weekends])[
+ Build a volume of 1 MiB stripes coded (4, 2), with two shards each on the P4510, the NV3 and the Pi's drive, the last through your transport. Writes append new stripe versions under an offset index, and a compactor reclaims old ones.
+ Expose it with `ublk` (ublksrv's library, or your own `io_uring` loop on `/dev/ublkc0`) and boot a guest in your VMM from `/dev/ublkb0`.
+ Run `fio` in the guest, then pull the Pi's cable mid-write: I/O continues on four shards, and the store repairs when the cable returns.
+ Snapshot by copying the copy-on-write index, and boot a second guest from a clone.
+ Measure cores per GB/s of erasure-coded writes, and memory bandwidth with `pcm-memory`.

#done-when(
  [The guest sees no I/O errors when the Pi disappears mid-write; repair completes and a scrub verifies every checksum.],
  [A clone boots a second guest, and cores per GB/s is recorded as the first line of Chapter 4.6’s cost model.],
)
#evidence([The cable-pull script; guest results, healthy and degraded.])
] <lab-dp-blocks>

== Problem set

+ Compute overhead, repair reads and failures tolerated for 3× replication, (4, 2), (10, 4) and (17, 3). Which suits a six-bay module, and which a rack of ten?
+ A stripe write to three modules stops when one loses power after four of six shards are written. Give two designs that keep the volume consistent and their write-path costs.
+ From Lab 4.5.3, how many cores does encoding 10 GB/s of (10, 4) take, and how much memory bandwidth with one copy in and one out? Where does the 150 GB/s server hit its ceiling, and what removes the copies?
+ `io_uring` with `SQPOLL` and `IOPOLL` still costs something per I/O. List what, and estimate each cost in nanoseconds.
+ Why does the NVMe/TCP initiator copy each read completion, and how does RDMA avoid it? What must the RDMA NIC know about the buffers, and who tells it?
+ A consumer drive acknowledges flushes it has not completed. Design a test that proves it in one power cycle, and say what Blocks must do on such drives.
+ Two sleds attach one Blocks volume; sled A loses the control plane and keeps its path to the storage module. Walk the fencing protocol and name the NVMe command and action that stop A's writes.
+ Should Lab 4.5.6 encrypt in the guest, the VMM, the stripe store before encoding, each shard, or the drive? Compare key custody, repair, deduplication and CPU.
+ A bit flips silently in a shard. Trace its detection on read and on scrub, and what parity without a checksum would do.

== Deliverables and stretch

*Deliverables.* The explained measurement matrix; the power-cut log; the Reed-Solomon library and benchmarks; the stripe store, transport and Blocks prototype with a cable-pull script; the fencing page and the encryption decision.

*Stretch.* Make the stripe store an SPDK bdev module and compare cores per GB/s. Add local reconstruction codes (Huang et al., USENIX ATC 2012) and measure repair traffic. Build Storage's skeleton, an S3 subset (PUT, GET, multipart upload, range reads, ETags), on the stripe store. Move the transport to RDMA verbs on soft-RoCE.

#checklist(
  [*Lab 4.5.1:* the matrix explained; the harness within 10 % of `fio`; twenty power cuts logged.],
  [*Lab 4.5.2:* SPDK rows and application; a vhost-user guest within 20 % of host SPDK.],
  [*Lab 4.5.3:* encoder within 2× of ISA-L; the stripe store survives two lost shards and a silent corruption.],
  [*Lab 4.5.4:* a guest boots from a remote volume; reservations fence a second host; the transport table.],
  [*Lab 4.5.5:* four receive paths compared per core; the transport verified end to end.],
  [*Lab 4.5.6:* a guest survives losing the Pi mid-write; a snapshot boots; cores per GB/s recorded.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: the copies, mode switches and interrupts in a 4 KiB write on each path, how a Cauchy matrix lets any $k$ shards rebuild a stripe, what a reservation conflict proves, and why only a power cut exposes a lying drive.],
)
