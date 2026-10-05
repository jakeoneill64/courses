#import "../lib/template.typ": *

= Capstone: Module Zero <ch-capstone>

#chapter-meta(
  weeks: [6 weeks at least; 8 is realistic],
  builds: [Module Zero: the x86 server and Board B under Board A, with the Pi as a third voter, powering on through Redfish, booting measured, attesting to one another, forming a quorum, running a tenant's VM on your VMM with its volume erasure-coded across all three nodes, surviving a pulled node, and taking a rolling firmware update while the tenant works. Recorded in one take.],
  needs: [Everything: the lab server, Boards A and B, the Pi 5, the TL-SG108E, a laptop on the management VLAN, your VMM, stripe store, transport, verifier, node kernels and Board A firmware, a camera and a screen recorder.],
)

#why[
  The course has produced parts; Module Zero is the assembly. Two engineering-sample nodes of different architectures, the x86 server and the arm64 Board B, power on, attest their firmware, form a quorum, accept a tenant, run its VM on your hypervisor, store its data erasure-coded across the rack, survive a node being pulled, take a rolling firmware update without the tenant noticing, and show all of it through the interface a customer would use. The software must not care which architecture it runs on. When the demonstration runs from a cold rack with no keyboard attached, every claim on the OMH hardware page has a small, honest implementation behind it, and the recording is the first thing you show an investor, a customer or a hire.
]

#note(title: [No skip test])[If you have done the Handbook and Units 1 to 4 you are ready. If you have not, the capstone will show you which chapter you skipped.]

== The demonstration

Write this down first and build toward it. Each step is a done-when criterion, and the acceptance checklist below turns each one into a check you tick from a cold start.

+ *Cold start.* Every node is off and Board A has standby power. From a laptop on the management VLAN, a Redfish `ComputerSystem.Reset` to Board A, served by its own firmware over lwIP, raises Board B's power-enable line and waits for power-good; a second call to the iDRAC powers the server, and the Pi starts with its supply. Board B boots through verified U-Boot and a signed FIT, the server through Secure Boot with your keys, both measured into their TPMs.
+ *Attest and join.* Each node boots the OMH node image, attests with a fresh nonce, and receives its credentials and disk key only on a passing quote. The nodes find one another on the management VLAN with no configuration and form a quorum with the Pi. The control plane shows every node joined within a time you record.
+ *A tenant arrives.* A tenant is created as a key pair and a policy, and calls the Compute API you designed in Chapter 4.4 to create an instance with a Lab 4.5.6 volume whose key is unwrapped from your Modulus stand-in and never written to disk. The instance boots where the scheduler puts it, attaches its volume over NVMe-oF, and the tenant logs in over the tenant VLAN.
+ *Data is safe.* The tenant writes a known dataset and you pull the network cable, or the power, from a node that is not running the instance. The tenant's I/O continues, the control plane shows the degraded state and the repair plan, and after you reconnect, repair completes and every checksum verifies.
+ *A rolling update.* You release new firmware for Board A and a new host image. The Lab 4.6.3 rollout drains each node, or live-migrates its instances with the migration you built in Chapter 4.4, then updates, reboots, attests against the new reference values and readmits it before moving on. The tenant's instance stays reachable throughout. A deliberately bad image then halts the rollout and rolls back.
+ *Observe.* One dashboard fed by the management interface shows each node's temperatures and fan speeds, power from the INA228s and the server's power supplies, per-volume IOPS and latency, per-instance CPU and attestation state, and `curl` reaches the Redfish subset from your Lab 4.6.1 specification.
+ *Recorded.* One take with a camera on the rack and a screen capture, narrated, under twenty minutes, with the cable pull on camera.

#fig("/figures/u4-capstone-coldstart.svg", caption: [The cold start, from the first Redfish call to Board B's admission. The time between the first message and the last is the boot-to-joined figure your specification guessed.], width: 100%)

== Architecture

Decide these in the first week and write each as a short design note in the labs repository: the decision, the alternatives, and the lab that produced the evidence.

*Node image.* A Buildroot or Debian-based image holding the node kernels from Chapter 4.2, your VMM, the stripe store and the node agent, and nothing else, built for x86-64 and arm64 from one tree. The differences are the boot path and the kernel's platform code. Build it reproducibly: when two builds are identical, the reference values for the image's measurements can be computed from the build and published with the release, before any node boots it.

*Identity and attestation.* Each node's identity is its TPM endorsement-key certificate, enrolled by the Lab 4.6.4 procedure; Board A's is its ATECC608 key. The Lab 2.7.4 verifier becomes a quorum service: each node checks its peers' quotes against the signed reference values of the current release, and a node whose quote fails is refused. The Modulus stand-in is a key store sealed to each node's PCRs and replicated through the quorum, unwrapping volume keys for the VMM on request.

*Membership and consensus.* A Raft group holds the cluster state: nodes and their attestation status, tenants and policies, instances and placement, volumes and stripe maps, the firmware inventory and the active rollout. Implement Raft in C++ from the Chapter 4.5 reading, or take a library and write down why. Two voters cannot keep a quorum through a partition, so the Pi is the third voter and the third storage failure domain; record the trade-off.

#fig("/figures/u4-capstone-arch.svg", caption: [Module Zero on the bench: three nodes on three VLANs, with Board A on Board B's host connector and on the management VLAN through its own port. Every stripe keeps two shards on each node.], width: 100%)

*Discovery and join.* Nodes announce themselves on the management VLAN with mDNS or a multicast beacon carrying their attestation evidence. The first node bootstraps the quorum alone; each later node is admitted when its quote verifies. There is no installation step, which is the site's zero-touch claim.

*Compute.* Your Chapter 4.4 VMM, or the Firecracker or Cloud Hypervisor decision you made there, behind the API you designed, one process per instance under the Chapter 4.4 tenant hardening, with the arm64 port on Board B. A simple scheduler places instances. Each instance gets virtio-net on a per-tenant VLAN and a virtio-blk or vhost-user attachment to its volume.

*Blocks.* The Lab 4.5.6 stripe store, one process per node, with stripe maps in the Raft state, per-volume encryption keyed from the Modulus stand-in, NVMe reservations for fencing and snapshots as index copies. Place each (4, 2) stripe with two shards on each of the three nodes, so that any one node can disappear; a node holding more than $m$ shards of a stripe turns its own loss into an outage. Repair starts when the quorum marks a node unhealthy, and scrub runs continuously at low priority.

*Management.* The server's iDRAC serves its vendor Redfish. Board A's firmware serves the Redfish subset directly over lwIP on its own Ethernet port: the service root, a `ComputerSystem` for Board B whose `Reset` action drives power-enable and reset, a `Chassis` with the TMP117, INA228 and fan sensors, a `Manager` for Board A itself and an `UpdateService` for its firmware. Serve it over TLS with the private key generated inside the ATECC608, and record the RAM high-water mark, because lwIP, TLS and JSON buffers share 256 KB. The control plane aggregates both behind one Redfish endpoint for the rack, the site's "one endpoint" claim, and adds OMH's resources: tenants, instances, volumes, attestation and rollouts. If you respun Board A with the ECP5 and your Chapter 2.2 register-map peripheral (Chapter 3.4’s stretch), that peripheral becomes the backplane controller, driving presence and identify LEDs over SPI as in Lab 2.6.3.

*Networks.* Three VLANs on the TL-SG108E: management (Board A, the iDRAC, node agents, the control plane), storage (NVMe-oF and replication) and tenant (instance traffic), configured on each node from its join response. The switch has no SFP+ ports, so every cross-node path runs at 1 Gbit/s, about 117 MB/s of payload; measure cores per GB/s on the server's DAC loop and treat 117 MB/s as the ceiling for every cross-node number.

*Telemetry.* Node agents publish sensor and performance data into a time series, and a small dashboard renders it: Signals in miniature, kept small.

== Weekly plan

Six weeks is the minimum and eight is realistic. Each week is a lab that ends in a recorded partial demonstration.

#lab([Week 1: node image and join], goal: [one image, two architectures, both attested.], time: [1 week])[
+ Build the node image for x86-64 and arm64 from one tree with the Chapter 4.2 node kernels. Build it twice and compare the hashes.
+ Boot the server through Secure Boot with your keys (Lab 2.7.3) and Board B through verified U-Boot, a signed FIT and U-Boot's measured boot into the SLB 9672 (Labs 2.7.5 and 3.4.7).
+ Run the Lab 2.7.4 verifier on the server and attest both nodes to it.
+ Write the design notes.

#done-when([Both nodes attest and appear in a list, and two builds of the image are identical.])
#evidence([The design notes; the image hashes; the week's recording.])
] <lab-cap-image>

#lab([Week 2: quorum and identity], goal: [admission decided by attestation inside the quorum.], time: [1 week])[
+ Bring up Raft, yours or a library's, holding node state, with the Pi as third voter.
+ Implement discovery and admission: a beacon on the management VLAN, a nonce, a quote, and a Raft entry that admits the node.
+ Move the verifier into the quorum, with reference values signed per release.
+ Build the Modulus stand-in: a key store sealed to each node's PCRs and replicated through Raft.

#done-when([A node is refused after a change to its kernel command line and admitted once the reference values are updated.])
#evidence([The admission log for both cases; the Raft log; the week's recording.])
] <lab-cap-quorum>

#lab([Week 3: compute], goal: [a tenant's instance on either architecture.], time: [1 week])[
+ Deploy your VMM and its API on both nodes, and write the scheduler.
+ Configure tenant VLANs from the join response.
+ Boot an instance on each node from a local image.

#done-when([A tenant creates an instance through the API and logs in over the tenant VLAN, on each node in turn.])
#evidence([The API transcript; the week's recording.])
] <lab-cap-compute>

#lab([Week 4: Blocks], goal: [tenant volumes that survive a lost node.], time: [1 week])[
+ Run the stripe store on all three nodes with stripe maps in Raft and keys from the Modulus stand-in.
+ Attach volumes over NVMe-oF and boot an instance from one.
+ Run `fio` in the guest and pull a node's cable; reconnect, repair and scrub.

#done-when([The guest sees no I/O errors through the cable pull, and repair completes with every checksum verified.])
#evidence([The guest `fio` log across the pull; the repair and scrub logs; the week's recording.])
] <lab-cap-blocks>

#lab([Week 5: updates and management], goal: [a rolling update under load, seen through one endpoint.], time: [1 week])[
+ Drive Board A's firmware update and both host image updates from the Lab 4.6.3 state machine.
+ Build the rack Redfish endpoint that aggregates Board A and the iDRAC and adds OMH's resources, and check it with DMTF's Redfish Service Validator.
+ Build the dashboard.

#done-when([A rolling update completes during tenant I/O, a bad image rolls back, and the rack endpoint passes the validator for every resource it implements.])
#evidence([The rollout log; the validator report; the week's recording.])
] <lab-cap-update>

#lab([Week 6: integration and recording], goal: [the whole demonstration, from cold, on camera.], time: [1 week])[
+ Run the full demonstration from cold five times, and fix what breaks each time.
+ Record it.
+ Write the retrospective.

#done-when([Five consecutive cold runs pass every step, and the recording and the retrospective exist.])
#evidence([The run log; the recording; the retrospective.])
] <lab-cap-record>

== Acceptance criteria

#checklist(title: [Done when, from cold], intro: [Module Zero is done when every line holds on a cold start with no keyboard attached to any node.],
  [Both nodes power on through Redfish, Board B through Board A and the server through its iDRAC, and boot with Secure Boot or verified boot and your keys enrolled.],
  [Every node attests with a fresh nonce, and a node with modified firmware or kernel is refused.],
  [The quorum forms without configuration, and the control plane lists every node with its attestation state and firmware versions.],
  [A tenant creates an instance with a volume through the API and reaches it over the tenant VLAN; the volume's key is unwrapped from the sealed store and appears in no file.],
  [Pulling any one node during tenant writes causes no I/O error in the guest, and after repair a full read verifies every checksum.],
  [A rolling update of Board A and both host images completes with the tenant's instance reachable throughout, and a bad image halts and rolls back.],
  [The dashboard shows live sensors, INA228 power and per-volume and per-instance metrics for every node; `curl` against the rack endpoint returns Systems, Chassis, Managers and the OMH resources, and Board A answers Redfish on its own Ethernet.],
  [*Labs 4.7.1 to 4.7.6:* six weekly demonstrations recorded.],
  [The recording exists, is under twenty minutes and shows the cable pull, and the retrospective is written.],
)

== Measurements to record

#tbl(columns: (1fr, 1fr), header: ([Measurement], [Method]),
  [Cold power-on to every node joined, split into firmware, boot, attestation and admission], [Timestamps from the first Redfish call, the consoles and the Raft log],
  [Instance create to login, and boot time inside the VMM], [API timestamps and the guest console],
  [Volume throughput and latency at queue depths 1 and 32, healthy and degraded; repair throughput], [`fio` in the guest; the stripe store's repair log],
  [Cores per GB/s of erasure-coded writes, and the memory bandwidth used], [`perf stat` and `pcm-memory`, as in Lab 4.5.6],
  [Rolling update duration per node and in total; the tenant's latency during it], [Rollout timestamps; a latency probe in the guest],
  [Idle and loaded power per node; thermal steady state at the lab's inlet temperature], [The INA228s on Boards A and B; the iDRAC's power and temperature readings; the TMP117s],
  [Attestation cost: quote generation and verification time, and evidence size], [Timers in the agent and the verifier],
  [Board A's RAM high-water mark and Redfish response time], [A stack and heap watermark; `curl -w` timings],
)

These are the numbers your Lab 4.6.1 specification guessed. Record each with its method, and replace the guess in the specification and the cost model.

== Retrospective

Two to four pages, written in the week after the recording.

+ What each claim on the OMH hardware page now rests on, and how far each is from something a customer could rely on. Be specific about the distance.
+ The three hardest problems, and what each taught you about the product.
+ What you would build differently, in hardware and in software, knowing what you know now.
+ The road from Module Zero to a saleable module: the threat model's gaps, the respin from Lab 3.4.8, the measurements still missing, the compliance plan's timeline and the cost model's remaining guesses.
+ Who you need to hire first, and what in this course they should already know.

== Deliverables and stretch

*Deliverables.* The recording; the design notes; the six weekly demonstrations; the measurements with their methods; the retrospective; the labs repository tagged at the recorded release.

*Stretch.* Replace the server's vendor BMC firmware with OpenBMC if OpenBMC supports your server's BMC (check the openbmc repository's machine list before you flash anything), so every node runs management firmware you built. Run the demonstration with a real network partition and show the minority side fenced off the volumes by NVMe reservations. Add live migration to every step of the rolling update so no instance is drained, and measure the tenant's downtime. Put the S3 front end from Chapter 4.5’s stretch on the stripe store and write and read an object through the rack. Present the recording and the retrospective to three people who build hardware for a living, and record their objections: that list starts OMH's second year.

== After the course

The labs repository is now a prototype of the company, and the notebook is its engineering blog. The six documents from Chapter 4.6 are its first business plan, and the retrospective is its roadmap. Keep working the loop Chapter 3.4 taught: specify, build, review, fabricate, bring up, find the mistake, respin.
