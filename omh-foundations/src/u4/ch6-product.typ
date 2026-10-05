#import "../lib/template.typ": *

= Product engineering <ch-product>

#chapter-meta(
  weeks: [2 weeks],
  builds: [Module Zero's specification, threat model, firmware update architecture (exercised on real hardware), manufacturing and test plan (with Board A's self-test and provisioning run), compliance plan (with a pre-compliance scan) and cost model.],
  needs: [Your notebook, a spreadsheet, Boards A and B, the lab server, your Lab 2.7.4 verifier, the tinySA Ultra with the Tekbox near-field probes, a spare SparkFun ATECC608A breakout.],
)

#why[
  A product is a prototype plus the documents that let someone else build it, test it, sell it legally, support it and price it, and the decisions that keep those documents consistent. Module Zero needs a specification, a threat model, an update architecture that fixes it in the field without bricking a rack, a test plan that turns boards into working units, a compliance plan that keeps it legal to sell, and a cost model that says whether the company survives. This chapter writes all six from your notebook. Some of it is already law: since 11 September 2026 the EU has required manufacturers to give a 24-hour early warning of any actively exploited vulnerability in their products.
]

#skip-test(
  rule: [If all five are easy, skip the reading and go straight to the labs.],
  [What must Module Zero meet to be sold in Great Britain, the EU and the US, and which test does a server usually fail first?],
  [Define roots of trust for update, measurement and reporting, and name the component of Module Zero that provides each.],
  [An update reaches 40 of 100 modules before a bug halts the rollout. What state must the rack be in, and what put it there?],
  [Give a 1U server's cost structure (materials, assembly, logistics, warranty, support) as shares of unit cost, and the gross margin a hardware company needs.],
  [What is a failure mode and effects analysis, and what would the top three rows of one for Module Zero say?],
)

== Core ideas

*A specification is a contract with the future.* It states what the module does, for whom, at what performance and reliability, through which interfaces, and what it does not do; every later document points back at it. Good specifications are short, numeric and testable ("sustains 2 GB/s of erasure-coded writes at 8 W per TB with two drives failed" in place of "high performance") and name the standards they adopt: Redfish, NVMe-oF, DC-SCM, Open Rack.

*Threat modelling.* List the assets (tenant data, keys in Modulus, firmware integrity, availability) and the adversaries (a tenant, a rack neighbour, someone with physical access, a supply-chain interposer, a compromised update server, an insider). The trust boundaries are those earlier chapters built: the hypervisor between tenants (Chapter 4.4), the IOMMU between devices and memory, the BMC between the management network and the host, measured boot between firmware versions (Chapter 2.7), and the TPM around the module's secrets. STRIDE at each boundary (spoofing, tampering, repudiation, information disclosure, denial of service, elevation of privilege) yields the threats. Each gets a mitigation, an accepted risk or a gap, and the gaps are the roadmap.

#fig("/figures/u4-product-threat.svg", caption: [Module Zero's data flows and trust boundaries. Lab 4.6.2 applies STRIDE at each numbered boundary.], width: 100%)

*Roots of trust.* A root of trust is assumed correct because nothing beneath it can check it. TCG names roots for measurement, storage and reporting; NIST SP 800-193 adds update, detection and recovery, and asks of each firmware component whether it is protected, checked and recoverable. In Module Zero a CPU's boot ROM verifies the first firmware only where signed boot is fused and enabled; the server's TPM and Board B's SLB 9672 measure, store and report; your Lab 2.6.6 bootloader, in write-protected flash, verifies Board A's firmware; identity lives in Board A's ATECC608 and Board B's TPM endorsement key. OCP's Caliptra shows what a mature design puts in silicon.

*Firmware update architecture.* Every programmable part will need a new image: the server's UEFI, Board B's CM5 bootloader EEPROM and U-Boot, Board A's bootloader and application, and drive, NIC and TPM firmware. A locked ATECC608 configuration never changes. Each image needs a signed format, verification from a root of trust, A/B slots or recovery, anti-rollback, a delivery path (Redfish `UpdateService`, PLDM over MCTP behind the BMC, `fwupd` on the host) and a place in a dependency order. A rack updates one module at a time, each drained, updated, attested against the release's reference values and readmitted; a failure halts the rollout in a known mixed state. The Uptane standard is the best-documented design for signed multi-component updates; borrow its roles and metadata.

#fig("/figures/u4-product-rollout.svg", caption: [The per-module update sequence, and what a halted rollout leaves behind.], width: 100%)

*Reliability.* Failure rates of parts in series add, and the annualised failure rate follows from the MTBF:
$ lambda_"module" = sum_i lambda_i, quad "AFR" = 1 - e^(-8760 slash "MTBF") $
so a 1,000,000-hour MTBF fails 0.87 % of units a year. Field data such as Backblaze's drive statistics beats datasheets, and redundancy goes where the arithmetic demands it. A failure mode and effects analysis lists how each part fails, the effect, its detection and its mitigation, ranked by severity times occurrence times detectability. ASHRAE class A2 allows 10 to 35 °C at the inlet; add humidity, altitude and transit shock. Burn-in finds infant mortality before a customer does.

*Manufacturing and test.* A contract manufacturer builds from your design package, BOM and test procedures, and design for test gives each board a fixture that programs, tests and provisions it in minutes. Provisioning is where identity is born: the ATECC608 generates its private key internally, and the fixture records the public key and serial, installs the first firmware and enrols the identity in the fleet verifier. Flying probe finds opens and shorts before power, functional test runs self-test firmware against limits, and system test runs the real firmware, attests to a factory verifier and burns in. First-pass yield decides whether the cost model's price is real.

#fig("/figures/u4-product-manufacturing.svg", caption: [From bare board to enrolled module. Every station writes to the manufacturing database.], width: 100%)

*Product compliance.* Module Zero is IT equipment with no radio. In Great Britain and the EU it needs safety to IEC 62368-1 (the fourth edition, 2023, is current; check which edition is harmonised and designated before testing) under the Low Voltage Directive and the UK Electrical Equipment (Safety) Regulations 2016, and EMC under Directive 2014/30/EU and the UK EMC Regulations 2016, tested to EN 55032 for emissions and EN 55035 for immunity. Great Britain accepts the UKCA or CE mark indefinitely, so one technical file serves both. RoHS limits ten substances to 0.1 % of each homogeneous material (cadmium 0.01 %), with files kept for ten years. REACH makes you declare any substance of very high concern above 0.1 % by weight and, in the EU, notify it to ECHA's SCIP database. UK WEEE producers register yearly (through a compliance scheme above five tonnes a year), mark the crossed-out wheeled bin and keep records for four years. The EU's server ecodesign regulation, 2019/424, requires secure data deletion and firmware and security updates until eight years after a model's last unit is placed on the market, unless an exclusion applies. In the US, FCC Part 15 Subpart B Class A applies, by Supplier's Declaration of Conformity or certification, and the cryptography needs an export classification (ECCN 5A002, or 5A992 as mass-market). Radiated emissions fails most often; a bench near-field scan finds most problems first.

*Security regulation.* The EU Cyber Resilience Act, Regulation (EU) 2024/2847, entered into force on 10 December 2024. Since 11 September 2026 manufacturers must report actively exploited vulnerabilities and severe incidents through ENISA's single reporting platform: an early warning within 24 hours, a notification within 72, and a final report 14 days after a fix for a vulnerability or a month after notification for an incident. From 11 December 2027 the whole Act applies, with conformity assessment, CE marking and updates for a declared support period. Radio equipment has had cybersecurity rules since 1 August 2025 under Delegated Regulation (EU) 2022/30, with EN 18031-1 to -3 listed, with restrictions, as its standards; Delegated Regulation (EU) 2026/339 repeals 2022/30 from 11 December 2027, when the CRA takes over. Module Zero has no radio, so it is outside 2022/30, which in the UK applies only in Northern Ireland. Great Britain has PSTI, in force since 29 April 2024 for consumer connectable products, which bans universal default and guessable passwords and requires a published way to report security issues, with response times, and a published minimum update period. Whether a module sold only to businesses is covered needs legal advice; the three requirements cost little.

#fig("/figures/u4-product-compliance.svg", caption: [UK and EU dates that bear on Module Zero. CRA reporting applies now, the rest of the Act from December 2027.], width: 100%)

*Cost model.* Unit cost is the BOM at volume, with price breaks and exchange rates, plus labour, yield loss, logistics and duties, a warranty reserve, support, compliance upkeep and the cash tied up in inventory; gross margin is price minus all of it. Hardware companies that last run 35 to 60 % gross margin with services on top, which for OMH are the AWS-class services. Respins, compliance tests, tooling and this year are non-recurring costs.

*Operations and documentation.* A module in a customer's rack reports health without tenant data and is replaced from a shipped spare without an OMH engineer; the FMEA says which service levels you can afford. Guides, the Redfish schema, release notes and the disclosure policy are much of what an on-premises customer buys.

== Reading

- NIST SP 800-193, all of it; RFC 9334 again, with Module Zero as attester and the quorum as relying party.
- OCP Caliptra's overview and boot flow; the Uptane Standard's roles and metadata; DMTF DSP0267 (PLDM for Firmware Update) and DSP0236 (MCTP).
- Shostack, _Threat Modeling_, chapters 1 to 5 and 7; Arthur and Challener, _A Practical Guide to TPM 2.0_, chapters 9, 12 and 22; OCP Yosemite v3 and DC-SCM 2.0.
- Regulation (EU) 2024/2847, Articles 13 and 14 and Annex I; the Commission's CRA reporting page; GOV.UK's PSTI and UKCA guidance.
- Ott, _Electromagnetic Compatibility Engineering_, chapter 18 (pre-compliance); FCC Part 15 Subpart B.
- Backblaze's drive statistics; Schroeder and Gibson, FAST 2007, on real disk failure rates; Ben Einstein's "Hardware by the Numbers".

== Labs

Each lab is a document written from your notebook. Mark every number you had to guess: those are the measurements you still owe, and Chapter 4.7 collects them.

#lab([The Module Zero specification], goal: [say what Module Zero is, in numbers you can test.], time: [8 h])[
+ Write a page of positioning: who buys Module Zero and what they stop doing. Map each claim on the OMH site to the mechanism in this course that delivers it.
+ Fix the configuration: sled envelope (Yosemite v3, Open Rack v3 or your own), compute, memory, drives (M.2, U.2 or E1.S), NICs, Board A's successor, the TPM, power input and fans.
+ Define the interfaces: management (Board A's Redfish subset, console, join protocol), data (Ethernet, NVMe-oF) and the service APIs.
+ Set numeric targets, each with its measurement: storage throughput and latency (Lab 4.5.6), VMs per module (Chapter 4.4), boot to joined (Lab 2.7.6), power, noise, inlet range, MTBF and the security-update period you will publish.
+ List what Module Zero does not do, and why.

#done-when(
  [Every claim on the OMH hardware page maps to a specification line and a mechanism, or is marked unsupported; every target names its measurement and says whether it was measured or guessed.],
)
#evidence([The specification; the claim-to-mechanism table.])
] <lab-pe-spec>

#lab([The threat model], goal: [know what Module Zero must never do, and what stops it.], time: [8 h])[
+ Draw the full data-flow diagram, extending Figure 4.6.1 with Modulus and every network, and mark each trust boundary.
+ Apply STRIDE at each boundary and produce the threat table.
+ Record for each threat the mitigation you built (chapter and lab), one designed but not built, or an accepted risk with its reason. Cross-tenant memory reads, for example, meet Chapter 4.4’s EPT isolation, core scheduling and side-channel mitigations, with a residual risk accepted for future speculative-execution bugs.
+ Physical attack: say what the TPM and encryption at rest protect, what an SPI flash interposer defeats, and what a Caliptra-class root of trust would add.
+ Supply chain: a board returns from the manufacturer with modified BMC firmware. Say what detects it, and when.

#done-when(
  [No row lacks a mitigation or an explicit acceptance, and the top ten gaps are ranked as a roadmap.],
)
#evidence([The diagram; the threat table; the ranked gaps.])
] <lab-pe-threat>

#lab([The firmware update architecture], goal: [update a module in the field and survive a bad release.], time: [1 weekend], kit: [Boards A and B, the server, your Lab 2.7.4 verifier.])[
+ Inventory every programmable part with its update path, format, signing and recovery, including the drives (`nvme fw-download`, `nvme fw-commit`) and the X520.
+ Design the image format and key hierarchy: an offline root, per-component keys, rotation, revocation, and where each public key lives (Board A's bootloader, the Secure Boot db, U-Boot's FIT key). Reuse your Lab 2.6.6 header where it fits.
+ Write the per-module sequence and the rack rollout as state machines: what halts a rollout, the halted state, and how an operator resumes or reverts.
+ Implement it. Board A takes its image through its own Redfish `UpdateService` over lwIP into the inactive slot of your Lab 2.6.6 bootloader, Board B's host image goes through `fwupd` or your own agent, and the verifier is the gate. Update, attest and readmit, then release a broken image and show the rollback and halt.
+ Map it onto the update duties of the CRA, PSTI and ecodesign 2019/424, and list the gaps.

#done-when(
  [A real module rolls forward and back under the written architecture, with the verifier as the gate and the control plane reporting the halt.],
)
#evidence([The state machines; the update, rollback and halt logs.])
] <lab-pe-update>

#lab([The manufacturing and test plan], goal: [tested, identified units by procedure alone.], time: [1 weekend and a 24 h burn-in], kit: [Every Board A you built, Board B, the Debug Probe, the spare ATECC608A breakout.])[
+ Write the process flow from bare board to packed module, naming each station and what it records.
+ Specify functional test for Boards A and B with limits and a time budget. Write Board A's self-test as a test mode of your Chapter 2.6 firmware, entered over the debug UART: the INA228, the TMP117s against each other, both fan tachometers, the ATECC608, an Ethernet ping and the host connector through a loopback plug. Run it on every Board A and record first-pass yield.
+ Specify provisioning (a key generated inside the ATECC608, per-unit Redfish credentials with no default password, the database schema, the label, enrolment before shipping) and implement it with your Lab 2.7.4 verifier as the database.
+ Burn Board B in for 24 hours under `stress-ng` and `fio`, logging temperatures and power through Board A against written criteria.
+ Write the traceability procedure from a module serial to its boards, lots and test records.

#safety[Locking the ATECC608’s configuration and data zones is permanent. Rehearse provisioning on the spare breakout before you lock a Board A.]

#done-when(
  [The self-test has run on every Board A with yield recorded, one board is provisioned and enrolled by the procedure alone, and the burn-in log is complete.],
)
#evidence([The plan; the self-test firmware; the yield record; the burn-in log.])
] <lab-pe-mfg>

#lab([The compliance plan], goal: [every mark, declaration and report, with cost and time.], time: [8 h and a bench scan], kit: [Boards A and B, the tinySA Ultra, the near-field probes.])[
+ List every requirement for sale in Great Britain, the EU and the US with its test or declaration, a laboratory, cost, duration and the design features that address it.
+ Safety: walk IEC 62368-1’s energy-source classification for Module Zero (mains in the power supply, the 12 V bus, hot surfaces, fans, any battery) and list the safeguards each needs.
+ EMC: name the likely sources (regulators, PCIe, Ethernet, any FPGA clock) and the Chapter 3.4 layout measures against each. Scan Boards A and B with the near-field probes and the tinySA, and attribute the five loudest frequencies.
+ Materials: supplier RoHS and REACH declarations, SCIP notification, WEEE registration and marking, and what leaded prototype solder changes.
+ Security and export: map PSTI and the CRA's reporting duty onto your design and processes, write the 24-hour and 72-hour reporting runbook, and classify Module Zero for export.

#done-when(
  [The plan has a costed line per requirement with its design feature, the scan's loudest frequencies are attributed, and the runbook has been rehearsed against a mock vulnerability inside 24 hours.],
)
#evidence([The compliance table; the scan; the runbook and the walk-through notes.])
] <lab-pe-compliance>

#lab([The cost model], goal: [find out whether the company lives.], time: [8 h])[
+ Build the BOM at 10, 100 and 1,000 units from your Chapter 3.4 BOMs with distributor price breaks and estimates for drives, NICs and assembly, marking every guess.
+ Add labour from Lab 4.6.4’s time budgets at a contract manufacturer's hourly rate, and yield loss from your first-pass yield.
+ Add logistics, tariffs, the warranty reserve from the FMEA, support and compliance upkeep, then the non-recurring costs: respins, Lab 4.6.5’s testing, tooling and the engineering year.
+ Set the price from the margin you need, and compare three years of Module Zero with the equivalent AWS services for one typical customer: the number the OMH pitch depends on.
+ Model the cash flow, and how many units you can build before revenue.

#done-when(
  [Every input is labelled measured, quoted or guessed, and a one-page summary states the unit price, the margin and the cash needed for the first 100 units.],
)
#evidence([The spreadsheet; the summary page.])
] <lab-pe-cost>

== Problem set

+ Module Zero's BMC signing key leaks. Walk revocation and recovery across 1,000 modules, naming what in your architecture makes it possible.
+ Can tenant data be recovered from a returned failed drive? Answer for your Chapter 4.5 encryption placement, and show how you meet ecodesign 2019/424’s secure-deletion requirement.
+ A fan failure at 35 °C inlet throttles the module in four minutes. Design detection, mitigation, notification and the SLA. With two 70,000 h MTBF fans per module, how many fail a year across 100 modules?
+ Compare an OMH management board with a commercial DC-SCM card on cost, time, control and the threat model.
+ A run of 100 yields 78 % at first pass; rework at £40 a unit saves 80 % of failures, and the rest are scrapped at a £600 BOM. Find the yield cost per good unit and the Chapter 3.4 decisions to revisit.
+ List Module Zero's Redfish resources and actions, justifying each omission against customers' tooling.
+ A tenant says another read their VM's memory. What can Module Zero prove, and what not?
+ Map the CRA onto your update architecture and PSIRT, and use Annexes III and IV to classify a module that ships a hypervisor and a boot manager. What follows for its conformity assessment?
+ The model shows 28 % gross margin at 100 units. Name three levers that lift it above 45 %, and their cost in time or risk.

== Deliverables and stretch

*Deliverables.* The six documents; Board A's self-test and provisioning, exercised; a recorded update and rollback; the ranked guesses that become Chapter 4.7’s measurement plan.

*Stretch.* Write the PSIRT policy and disclosure page, with a mailbox, a PGP key and a `security.txt` (RFC 9116). Model a ten-customer fleet's support cost over three years, and make the manufacturing database a service.

#checklist(
  [*Lab 4.6.1:* every site claim mapped to a mechanism or marked unsupported.],
  [*Lab 4.6.2:* every threat mitigated or accepted; the top ten gaps ranked.],
  [*Lab 4.6.3:* a real module rolled forward and back with the verifier as the gate.],
  [*Lab 4.6.4:* self-test yield recorded; a board provisioned by procedure; burn-in logged.],
  [*Lab 4.6.5:* a costed line per requirement; the scan attributed; the reporting runbook rehearsed.],
  [*Lab 4.6.6:* unit price, margin and cash for 100 units, with every input labelled.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: what each of Module Zero's roots of trust assumes, the state a halted rollout leaves, which marks and reports it needs, and where the margin goes.],
)
