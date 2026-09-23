# Module 16: Capstone: Module Zero

**Part V · 6 weeks or more · Needs: everything. The server, Board B with Board A, the Pi as a third node if you want a real quorum, the managed switch, your VMM, your stripe store, your verifier, your BMC firmware.**

## Why this module (and what it buys OMH)

The course has produced parts. Module Zero is the assembly: two engineering-sample nodes
of different hardware (the x86 server and the ARM Board B, which is the point: the
software must not care) that power on, attest their firmware to each other, form a
quorum, accept a tenant, run the tenant's VM on your hypervisor, store the tenant's data
erasure-coded across both nodes, survive a node being pulled, take a rolling firmware
update without the tenant noticing, and show all of it through the management interface a
customer would use. When the demo runs from a cold rack with no keyboard attached, every
claim on the OMH hardware page has a small, honest implementation behind it, and the
recording is the first thing you show an investor, a customer or a hire.

## Skip test

There is none. If you have done Modules 0 to 15, you are ready; if you have not, the
capstone will tell you which one you skipped.

## The demonstration

Write this down first and build toward it. Every step is a "done when".

1. **Cold start.** Both nodes are powered off. Board A (the BMC) is powered. From a
   laptop on the management VLAN, a Redfish call to Board A powers on Board B; a Redfish
   call to the server's BMC powers on the server. Both boot through your Module 8 chain:
   Secure Boot with your keys on the server, verified U-Boot and a signed FIT on Board B,
   measured into their TPMs.
2. **Attest and join.** Each node netboots or boots from local disk into the OMH node image,
   attests to the verifier with a fresh nonce, and receives its credentials and its disk
   encryption key only on a passing quote. The nodes discover each other on the lab VLAN
   with no configuration, exchange attestation evidence, and form a two-node quorum (or
   three, with the Pi). The control plane shows both as joined within a time you record.
3. **A tenant arrives.** Through Witness-shaped identity (a key pair and a policy), a tenant
   is created. The tenant calls the Compute API from Lab 12.5 to create an instance with a
   Blocks volume from Lab 13.6. The volume's key is unwrapped from your Modulus stand-in
   (the TPM-sealed key store) and never written to disk. The instance boots on whichever
   node the scheduler picks, attaches the volume over NVMe-oF, and the tenant logs in over
   the tenant VLAN.
4. **Data is safe.** The tenant writes a known dataset. You pull the network cable (or the
   power) from the other node. The tenant's I/O continues. The control plane shows the
   degraded state and the repair plan. Reconnect; repair completes; the checksums verify.
5. **A rolling update.** Release a new firmware version for the BMC (Board A) and a new host
   image. The rollout from Lab 15.3 drains the node without the tenant's instance (or
   migrates the instance with Lab 12.6), updates, reboots, attests against the new
   reference values, readmits, then moves to the second node. The tenant's instance is
   reachable throughout. Then release a deliberately bad image and show the halt and the
   rollback.
6. **Observe.** Signals-shaped telemetry: per-node temperatures, fan speeds, power from the
   INA226 and the PMBus PSU, per-volume IOPS and latency from the stripe store, per-instance
   CPU from the VMM, and the attestation state, all in one dashboard fed by the management
   interface, with the Redfish subset from Lab 15.1 available to `curl`.
7. **Recorded.** One take, one camera on the rack and one screen capture, narrated, under
   twenty minutes, with the cable pull on camera.

## Architecture

Decide these in the first week and write them as a set of short design notes in the labs
repo. Each note records the decision, the alternatives, and the lab that produced the
evidence.

**Node image.** A Buildroot or Debian-based image with your kernel configuration from
Lab 10.5 (trimmed, signed, hardened), your VMM, your stripe store, the node agent, and
nothing else. The same image, built for x86-64 and arm64 from one tree; the differences
are the boot path and the kernel's platform code. Rebuilding it reproducibly is part of
the firmware update story.

**Identity and attestation.** Each node's identity is its TPM's endorsement key certificate
(or the ATECC's on the BMC), enrolled at provisioning by the Lab 15.4 procedure. The
verifier from Lab 8.4 becomes a service in the quorum rather than a machine outside it:
each node verifies its peers' quotes against the release's reference values, and a node
whose quote fails is refused. Reference values per release are published with the release
and signed. The Modulus stand-in is a key store sealed to each node's PCRs, replicated
through the quorum, unwrapping volume keys for the VMM on request.

**Membership and consensus.** A Raft group (your own implementation in C++ from the
Module 13 reading, or an existing library if you decide the time is better spent
elsewhere; write down why) holds the cluster state: nodes and their attestation status,
tenants and their policies, instances and their placement, volumes and their stripe maps,
the firmware inventory and the active rollout. Two nodes cannot hold a quorum through a
partition; the Pi as a third voter, or a witness-only member, makes the cable-pull step
honest. State the trade-off you chose.

**Discovery and join.** Nodes announce themselves on the management VLAN (mDNS or a
multicast beacon with the attestation evidence). A new node is admitted by the existing
quorum after its quote verifies; the first node bootstraps the quorum alone. There is no
installation step, which is the site's zero-touch claim.

**Compute.** Your Lab 12.2 VMM (or the Firecracker or Cloud Hypervisor decision from Lab
12.5) behind the API you designed, run per instance under the Lab 12.6 tenant hardening.
Placement is a simple scheduler in the control plane. Instances get a virtio-net into a
per-tenant VLAN and a virtio-blk or NVMe-oF attachment to a Blocks volume.

**Blocks.** The Lab 13.6 stripe store, one process per node, with the stripe map in the
Raft state, encryption per volume with keys from the Modulus stand-in, NVMe reservations
for fencing, snapshots as index copies. Repair runs when the quorum marks a node
unhealthy; scrub runs continuously at low priority.

**Management.** OpenBMC on the server's BMC if you replaced the vendor firmware (a
stretch), or the vendor Redfish; your Board A firmware exposing a Redfish subset over its
Ethernet (F446) or through a proxy on Board B over the UART link (F411). The control
plane aggregates both behind one Redfish endpoint for the rack, per the site's "one
endpoint" claim, and adds the OMH-specific resources: tenants, instances, volumes,
attestation, rollouts.

**Networks.** Three VLANs on the managed switch: management (BMCs, node agents, the
control plane), storage (NVMe-oF and replication), tenant (instance traffic). The node
image configures them from the join response.

**Telemetry.** Node agents publish sensor and performance data into a time series; a
small dashboard renders it. This is Signals in miniature; keep it small.

## Weekly plan

Six weeks is the minimum; eight is realistic. Each week ends with a recorded partial demo.

**Week 1: Node image and join.** Build the image for both architectures. Both nodes boot
it through the Module 8 chain and attest to a verifier running on the server. Write the
design notes. Demo: two nodes attest and appear in a list.

**Week 2: Quorum and identity.** Raft (or the library) holding node state; discovery and
admission; the verifier inside the quorum; the Modulus stand-in with sealed keys. Demo: a
node is refused after a kernel command-line change, admitted after the reference values
are updated.

**Week 3: Compute.** The VMM API deployed per node; the scheduler; tenant VLANs; an instance
boots on each node from a local image. Demo: a tenant creates an instance through the API
and logs in.

**Week 4: Blocks.** The stripe store across both nodes with keys from the store, NVMe-oF
attachment, an instance booting from a volume, the cable pull and the repair. Demo: the
cable pull with `fio` running in the guest.

**Week 5: Updates and management.** The rollout state machine driving a BMC update on Board
A and a host image update on both nodes; the rack Redfish endpoint; the dashboard. Demo:
a rolling update during tenant I/O, then a rollback.

**Week 6: Integration and recording.** The full demonstration end to end, from cold, five
times. Fix what breaks. Record it. Write the retrospective.

## Acceptance criteria

Module Zero is done when every line holds on a cold start with no keyboard attached to
either node.

- Both nodes power on through Redfish and boot with Secure Boot or verified boot enabled
  and your keys enrolled.
- Both nodes attest with a nonce, and a node with modified firmware or kernel is refused.
- The quorum forms without configuration and the control plane lists both nodes with
  their attestation state and firmware versions.
- A tenant creates an instance with a volume through the API and reaches it over the
  tenant VLAN; the volume's key is unwrapped from the sealed store and appears in no file.
- Pulling one node during tenant writes causes no I/O errors in the guest; repair
  completes and a full read verifies every checksum.
- A rolling update of the BMC and host images completes with the tenant's instance
  reachable throughout, and a bad image halts and rolls back.
- The dashboard shows live sensors, power, per-volume and per-instance metrics for both
  nodes, and `curl` against the rack's Redfish endpoint returns Systems, Chassis, Managers
  and the OMH resources.
- The recording exists, is under twenty minutes, and shows the cable pull.
- The retrospective is written.

## Measurements to record

These are the numbers the Module 15 specification guessed. Record each with its method.

- Cold power-on to both nodes joined, in seconds, and the breakdown: firmware, boot,
  attestation, admission.
- Instance create-to-login time, and boot time inside the VMM.
- Volume throughput and latency from the guest at queue depths 1 and 32, healthy and
  degraded, and repair throughput after the cable pull.
- Cores consumed per GB/s of erasure-coded writes, and the memory bandwidth used.
- Rolling update duration per node and total, and the tenant's observed latency during it.
- Idle and loaded power per node from the INA226 and the PMBus PSU; thermal steady state
  at the lab's inlet temperature.
- Attestation cost: quote generation and verification time, and the size of the evidence.

## Retrospective

Two to four pages, written in the week after the recording.

1. What each claim on the OMH hardware page now rests on, and how far each is from
   something a customer could rely on. Be specific about the distance.
2. The three hardest problems and what each taught you about the product.
3. What you would build differently, in hardware and in software, knowing what you know.
4. The roadmap from Module Zero to a saleable module: the gaps from the threat model, the
   respin from Module 14, the measurements still missing, the compliance plan's timeline,
   and the cost model's inputs that are still guesses.
5. Who you need to hire first, and what in this course they should already know.

## Stretch

- Replace the server's vendor BMC firmware with OpenBMC and your Lab 8.7 D-Bus daemon,
  so both nodes run management firmware you built.
- Run the whole demonstration with the Pi as a third node and a real network partition,
  and show the minority side fencing itself off the volumes.
- Add live migration (Lab 12.6) to the rolling update so no instance is drained, and
  measure the tenant's downtime.
- Implement the Storage front end from the Module 13 stretch on the stripe store and
  demonstrate an S3 client writing and reading an object through the rack.
- Present the recording and the retrospective to three people who build hardware for a
  living, and record their objections. That list is the start of OMH's second year.

## After the course

The labs repo is now a prototype of the company. The notebook is its engineering blog.
The six documents from Module 15 are its first business plan. The retrospective is its
roadmap. Keep working the loop that Module 14 taught: specify, build, review, fabricate,
bring up, find the mistake, respin. That is the whole job.
