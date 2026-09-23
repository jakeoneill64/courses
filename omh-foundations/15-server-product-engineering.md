# Module 15: Server product engineering

**Part V · 2 weeks · Needs: everything you have built, the notebook, a spreadsheet. Reading and writing, not soldering.**

## Why this module (and what it buys OMH)

A working prototype is not a product. A product is a prototype plus the documents that let
someone else build it, test it, ship it legally, support it, and price it, and the
decisions that make those documents consistent. Module Zero, the first OMH module, needs a
specification that says what it is; a threat model that says what it must never do; a
firmware update architecture that lets you fix it in the field without bricking a rack; a
manufacturing test plan that turns a pallet of boards into working units; a compliance
plan that keeps it legal to sell; and a cost model that tells you whether the company
lives. This module writes all six from the evidence in your notebook, and the writing will
send you back to earlier modules for numbers you did not record.

## Skip test

1. What must a device do to carry a CE mark for sale in the EU and an FCC Part 15 Class A
   declaration in the US, and which tests does a server usually fail first?
2. Define a root of trust for update, a root of trust for measurement and a root of trust
   for reporting, and say which component of Module Zero provides each.
3. A firmware update reaches 40 of 100 modules in a rack before a bug halts the rollout.
   Describe the state the rack must be in, and the mechanism that put it there.
4. Give the bill of materials, contract manufacturing, logistics, warranty reserve and
   support cost structure of a 1U server as percentages of unit cost, and say what gross
   margin a hardware company needs to survive.
5. What is a failure mode and effects analysis, and what would the top three rows of one
   for Module Zero say?

If all five are easy, write the six documents and skip the reading.

## Core ideas

**A product specification is a contract with the future.** It states what the module
does, for whom, at what performance and reliability, under what conditions, with what
interfaces, and what it explicitly does not do. Every later document points back at it.
Good specifications are short, numeric and testable: "sustains 2 GB/s of erasure-coded
writes at 8 W per TB with two drives failed" rather than "high performance". They name
the standards they adopt (Redfish, NVMe-oF, DC-SCM, Open Rack) so that a customer knows
what they are getting and an engineer knows what to build.

**Threat modelling.** Enumerate assets (tenant data, keys in Modulus, firmware integrity,
availability), adversaries (a tenant, a neighbour in the rack, a person with physical
access, a supply-chain interposer, a compromised update server, an insider at OMH), and
the trust boundaries the earlier modules built: the hypervisor between tenants, the IOMMU
between devices and memory, the BMC between the management network and the host, measured
boot between firmware versions, the TPM between the module and its secrets. STRIDE per
boundary produces the threat list; each threat gets a mitigation, an accepted risk or a
gap. The gaps are your roadmap. The document must be honest about what a prototype BMC
running your firmware cannot yet claim.

**Hardware roots of trust.** A root of trust is the component whose correct behaviour is
assumed rather than verified. Module Zero has several: the CPU's boot ROM (verifies the
first firmware), the TPM (measures and reports), the BMC's boot ROM (verifies the BMC
firmware), and whatever holds the device identity (the ATECC608 on Board A, the TPM's
endorsement key on Board B). Caliptra is OCP's open silicon root of trust; understanding
it tells you what a mature design puts in hardware. Platform Firmware Resiliency (NIST
SP 800-193) names the three properties: protection, detection and recovery, and Module
Zero should be able to state which of its firmware components have each.

**Firmware update architecture.** Every programmable component in Module Zero holds an
image that will need replacing: host UEFI or U-Boot, the BMC, the FPGA bitstream, drive
firmware, NIC firmware, the TPM's own firmware, the ATECC configuration. Each needs a
signed image format, a verification path anchored in a root of trust, an A/B or recovery
scheme, anti-rollback, a way to deliver it (Redfish `UpdateService`, PLDM over MCTP for
components behind the BMC, `fwupd` for the host), and a policy for ordering and
dependencies. Across a rack, updates roll one module at a time, each module drained,
updated, attested and readmitted before the next; a failure halts the rollout with the
rack in a known mixed state that the control plane can reason about. The Uptane
framework (automotive) is the best-documented design for multi-component signed updates.

**Reliability engineering.** Mean time between failures per component from vendor data
and field experience, rolled up into a module MTBF; the annualised failure rate of drives
(Backblaze publishes theirs); redundancy where the arithmetic demands it (PSUs, fans,
boot flash), erasure coding where it does not. Failure mode and effects analysis: for each
component, how it fails, what the effect is, how it is detected, what the mitigation is,
ranked by severity times probability times detectability. Environmental limits: inlet
temperature (ASHRAE A2 is 10 to 35 °C), humidity, altitude, vibration and shock in
transit. Burn-in and thermal cycling find infant mortality before the customer does.

**Manufacturing.** Contract manufacturers assemble boards and integrate systems; you
provide the design package, the BOM, the test procedures and the acceptance criteria.
Design for manufacture reviews are Module 14's checklist scaled up; design for test means
every board has a fixture that programs, tests and provisions it in minutes. Provisioning
is where identity is born: the fixture generates or injects the device key, records the
public part and the serial number in your manufacturing database, and installs the
first firmware. Serialisation, labelling, traceability from a module in the field back to
the lot of every board inside it. Yield, first-pass yield and the cost of rework decide
whether the price in the cost model is real.

**Manufacturing test.** In-circuit test or flying probe for opens and shorts; functional
test on a fixture running a self-test firmware that exercises every interface and reads
every sensor against limits; system test with the real firmware, attestation to a factory
verifier, and a burn-in under load with temperature logging; final inspection and
packaging. Each stage has a procedure, a pass and fail criterion, a data record and a
yield target. The self-test firmware is a product in itself and is best written by the
same people who wrote the drivers.

**Compliance.** Safety (IEC 62368-1 for ICT equipment, tested by a nationally recognised
laboratory such as UL, TÜV or Intertek), electromagnetic compatibility (FCC Part 15
Class A in the US, EN 55032 and EN 55035 in the EU, both with emissions and immunity),
the EU's CE marking with a Declaration of Conformity referencing the EMC Directive, the
Low Voltage Directive and the Radio Equipment Directive if there is any radio, RoHS and
REACH for materials, WEEE for disposal, energy-efficiency labelling where required, and
export control classification (ECCN) for anything with cryptography. Pre-compliance
testing in your own lab with a spectrum analyser and near-field probes finds most
emissions problems before the expensive chamber time. Budget weeks and tens of thousands
of dollars per product for the first round.

**Cost model.** Bill of materials cost at volume with price breaks and the exchange rate;
assembly and test labour; yield loss and rework; logistics inbound and outbound; tariffs
and duties; warranty reserve as a percentage of revenue; support cost per unit per year;
and the capital tied up in inventory between paying suppliers and being paid. Gross
margin is price minus all of that. Hardware companies that survive run 35 to 60 per cent
gross margin with a services or software line on top; the AWS-class services OMH sells on
the hardware are that line. The model must also cover the non-recurring costs: fab
respins, compliance, tooling, and the year you have just spent.

**Operations and support.** A module in a customer's rack must report health to OMH (with
the customer's consent and without tenant data), accept remote diagnosis, and be
replaceable by the customer with a shipped spare and no OMH engineer present. Field
replaceable units, spares stocking, return merchandise authorisation flow, failure
analysis on returns, and the feedback loop into design. Service level agreements define
what you owe when a module fails; the FMEA and the redundancy design define whether you
can afford to offer them.

**Documentation as product.** Installation guide, safety notices, the supported operations
list for each service API, the Redfish schema you implement, the firmware release notes,
the security advisories process (a PSIRT with a disclosure policy and a contact), the
end-of-life policy. Customers of on-premises hardware read documentation; it is a large
part of what they are buying.

## Reading

- NIST SP 800-193, *Platform Firmware Resiliency Guidelines*: all of it, short.
- IETF RFC 9334, *Remote Attestation Procedures Architecture*: reread with Module Zero as
  the attester and the rack quorum as the relying party.
- OCP Caliptra specification: ch. 1 to 3 (what a silicon root of trust does).
- Uptane Standard for the Design and Implementation: the multi-repository, multi-role
  signed update model. Adapt, do not adopt.
- DMTF PLDM for Firmware Update (DSP0267) and MCTP base (DSP0236): how components behind
  the BMC receive images.
- Shostack, *Threat Modeling: Designing for Security*: ch. 1 to 5 (STRIDE and the process),
  ch. 7 (processing threats).
- Arthur and Challener, *A Practical Guide to TPM 2.0*: ch. 9 (hierarchies), ch. 12
  (attestation), ch. 22 (platform security).
- OCP Yosemite v3 and DC-SCM 2.0 specifications for what a shipping design specifies, and
  the Open Compute Project's hardware management module specification for the operational
  interfaces.
- IEC 62368-1 overview articles from a test laboratory, and the FCC's Part 15 Subpart B
  text; Ott, *Electromagnetic Compatibility Engineering*, ch. 18 (measurements and
  pre-compliance).
- Backblaze drive statistics (any recent quarter) and Schroeder and Gibson, "Disk
  Failures in the Real World", FAST 2007, for realistic failure rates.
- A public teardown cost analysis of a server or a Nitro card (TechInsights or similar)
  for the shape of a BOM.
- Ben Einstein's "Hardware by the Numbers" essays and the Bolt hardware startup guides,
  for the cost and cash-flow model of a hardware company.

## Labs

Each lab is a document. Write in your own words, with numbers from your notebook, and
mark every number you had to guess. The guesses are the list of measurements you still
owe.

### Lab 15.1: The Module Zero product specification

1. One page of positioning: who buys Module Zero, what they run on it, and what they stop
   doing because of it. Draw on the OMH site's fleet and managed-service claims, and state
   for each which mechanism from the course delivers it.
2. Configuration: the sled form factor (a Yosemite v3 or Open Rack v3 envelope, or your
   own), the compute-on-module or CPU, memory, the drive bay count and form factor (M.2,
   U.2 or E1.S), the NICs, the management controller (Board A's successor), the TPM and
   root of trust, the power input and the fan arrangement.
3. Interfaces: management (Redfish subset you implement, serial console, the join
   protocol), data (Ethernet, NVMe-oF), and the service APIs each module type exposes.
4. Numeric targets with the measurement that verifies each: storage throughput and
   latency per Module 13, VMs per module per Module 12, boot-to-joined time per Module 8,
   power at idle and full load, acoustic level, inlet temperature range, MTBF.
5. Explicit exclusions: what Module Zero does not do (multi-rack, cold storage, GPUs,
   whatever you decide) and why.

Done when: every claim on the OMH hardware page maps to a line in this specification and
a mechanism in your labs repo, or is marked as not yet supported.

### Lab 15.2: The threat model

1. A data-flow diagram of Module Zero: tenant VM, hypervisor, host kernel, BMC, TPM,
   drives, NICs, management network, tenant network, the control plane, the update
   server, Modulus. Mark every trust boundary.
2. Assets and adversaries as in the core ideas. For each boundary, STRIDE: spoofing,
   tampering, repudiation, information disclosure, denial of service, elevation of
   privilege. Produce the threat table.
3. For each threat: the mitigation you have built (name the module and lab), the
   mitigation you have designed but not built, or the accepted risk with a justification.
   Be specific: "a tenant reads another tenant's memory" is mitigated by EPT (Lab 12.4),
   core scheduling (Lab 12.6) and the microcode mitigations you enabled, with an accepted
   residual risk from future speculative-execution bugs.
4. Physical attacks: a person with the module in their hands. What does the TPM protect,
   what does encryption at rest protect, what does a hardware interposer on the SPI bus
   defeat, and what would a Caliptra-class root of trust add?
5. Supply chain: a board comes back from the contract manufacturer with a modified BMC
   flash. What detects it, and when?

Done when: the threat table has no row without a mitigation or an explicit acceptance, and
the top ten gaps are ranked as a roadmap.

### Lab 15.3: The firmware update architecture

1. Inventory every programmable component in Module Zero with its current update path,
   image format, signing status and recovery path. Include the drives and NICs.
2. Design the signed image format and key hierarchy: an offline root, per-component
   signing keys, key rotation, revocation, and where each public key lives (the BMC ROM,
   the host's db, the FPGA's bitstream verifier). Reuse your Lab 7.6 header where it fits.
3. Design the per-module update sequence: stage the images, verify, write inactive slots,
   commit in dependency order, reboot, attest, compare the new PCR set to the release's
   reference values, confirm or roll back. Define the states and the transitions as a
   state machine.
4. Design the rack rollout: drain, update, readmit, one module at a time, with the
   control plane holding the rack's firmware inventory. Define what halts a rollout, what
   state the rack is in when halted, and how an operator resumes or reverts.
5. Implement the per-module sequence on the lab server or Board B: `fwupd` or your own
   agent for the host image, Redfish `UpdateService` on OpenBMC (Lab 8.7) or your Board A
   protocol for the BMC, and your Module 8 verifier as the gate. Update, attest, readmit;
   then update with a deliberately broken image and show the rollback and the halt.

Done when: the architecture is written, and a real module rolls forward and rolls back
under it with the verifier as the gate.

### Lab 15.4: The manufacturing and test plan

1. Process flow from bare boards to a packed module: board assembly, in-circuit test,
   functional test, provisioning, system integration, burn-in, final test, packaging.
   Name the fixture or station at each step and what it records.
2. Functional test specification for Board A and Board B: every interface exercised, every
   sensor read against limits, the pass and fail criteria, the time budget per unit.
   Write the self-test firmware for Board A (the Module 7 code, extended with a test mode
   reachable from the fixture) and run it on your five boards; record first-pass yield.
3. Provisioning specification: device identity generation in the ATECC608 or TPM, the
   manufacturing database schema (serial, keys, lot, test results, firmware versions), the
   labels, and how a module's identity is enrolled in the fleet's verifier before it ships.
   Implement it on Board A with your Lab 8.4 verifier as the database.
4. Burn-in: load profile, duration, temperature, what is logged, and the failure
   criteria. Run a 24-hour burn-in on Board B with `stress-ng` and `fio` and log it.
5. Traceability: from a module serial in the field to the boards, the lots, the test
   records and the firmware. A one-page procedure and a schema.

Done when: the plan is written, the self-test runs on Board A with a recorded yield, and a
board can be provisioned and enrolled by the procedure alone.

### Lab 15.5: The compliance plan

1. List every regulation and standard Module Zero must meet for sale in the EU and the US
   (add your other target markets), with the test or declaration each requires, a
   laboratory that performs it, an estimated cost and duration, and the design features
   that address it.
2. Safety: walk IEC 62368-1's energy-source classification for Module Zero (mains, the 12
   or 48 V bus, hot surfaces, fans, batteries if any) and list the safeguards required.
3. EMC: identify the likely emission sources (switching regulators, PCIe, Ethernet, the
   FPGA clock) and the design measures from Module 14 that address them. Run a
   pre-compliance near-field scan on Board A and Board B with the TinySA or SDR from the
   Module 14 stretch, or borrow time on a spectrum analyser; record the loudest frequencies
   and their sources.
4. Materials and disposal: RoHS and REACH declarations you need from suppliers, the WEEE
   registration, and what changes if you use leaded solder in prototypes.
5. Cryptography and export: classify Module Zero (ECCN 5A002 or the mass-market exception)
   and state the filings.

Done when: the plan has a line per requirement with cost, time and the responsible design
feature, and the pre-compliance scan is in the notebook.

### Lab 15.6: The cost model

1. BOM for Module Zero at 10, 100 and 1,000 units from your Module 14 BOMs scaled up, with
   distributor pricing at each break for the silicon and connectors, and an estimate for
   the CM, drives and NICs. Mark every guessed price.
2. Assembly, test and provisioning labour per unit from your Lab 15.4 time budgets and a
   contract manufacturer's hourly rate. Yield loss from your first-pass yield.
3. Logistics, tariffs, warranty reserve (from the FMEA's failure rates and the spares
   policy), and support cost per unit per year.
4. Non-recurring: fab respins, compliance from Lab 15.5, tooling, and the engineering year.
5. Price: the gross margin needed, the resulting unit price, and a comparison against the
   three-year cost of the equivalent AWS services for a representative customer, which is
   the number the OMH pitch depends on. Then the cash-flow model: when you pay suppliers,
   when the customer pays you, and how many units you can afford to build before revenue.

Done when: the model is a spreadsheet with every input labelled measured, quoted or
guessed, and a one-page summary states the unit price, the margin and the cash needed for
the first 100 units.

## Problem set

1. Module Zero's BMC firmware is signed with a key that leaks. Walk the revocation and
   recovery across a fleet of 1,000 modules, and name what in your architecture makes it
   possible or impossible.
2. A customer's compliance team asks whether tenant data can be recovered from a returned
   failed drive. Answer for the encryption placement you chose in Module 13.
3. The FMEA says a fan failure at 35 °C inlet leads to thermal throttling within four
   minutes. Design the detection, the mitigation and the customer notification, and say
   what the SLA can promise.
4. Compare an OMH-designed management board against buying a commercial DC-SCM card for
   Module Zero: cost, time, control, and what the threat model says.
5. Your first production run of 100 has a 78 per cent first-pass yield at functional test.
   Which of your Module 14 design decisions do you look at first, and what does the yield
   do to the unit cost?
6. Write the Redfish subset Module Zero implements as a list of resources and actions, and
   justify each omission against what a customer's existing tooling will call.
7. A tenant claims their VM's memory was read by another tenant. What evidence can Module
   Zero produce, from what logs and measurements, and what can it not prove?
8. The EU's Cyber Resilience Act requires vulnerability handling and security updates for
   the product's support period. Map its obligations onto your update architecture and
   your PSIRT process, and identify the gaps.
9. Your cost model shows 28 per cent gross margin at 100 units. Name three levers that
   move it above 45 and what each costs in time or risk.

## Deliverables

- Six documents: specification, threat model, firmware update architecture, manufacturing
  and test plan, compliance plan, cost model with summary.
- The Board A self-test firmware and the provisioning procedure, exercised.
- The rack rollout state machine and the recorded forward and rollback update on a real
  module.
- A ranked list of every measurement you guessed, which is Module 16's measurement plan.

## Stretch

- Write the PSIRT policy, the security advisory template and the coordinated disclosure
  page, and set up the mailbox and the PGP key.
- Model three years of a ten-customer fleet: failures per the FMEA, spares shipped,
  support hours, firmware releases, and the support cost per module per year that
  results.
- Prototype the manufacturing database and the fixture software as a small service, with
  Board A's self-test posting results to it.

## Next

Module 16 builds Module Zero: two nodes that attest, join, hold a quorum, run tenant VMs
and replicate their data, demonstrated end to end and recorded.
