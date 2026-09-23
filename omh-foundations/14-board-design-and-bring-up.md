# Module 14: Board design and bring-up

**Part V · 4 weeks plus fab lead time · Needs: the Board tier (scope, bench supply, soldering, microscope), KiCad, your Module 7 firmware and Module 3 RTL. Board A can start as soon as Module 7 is done.**

## Why this module (and what it buys OMH)

OMH sells hardware. Until now the course has run on other people's boards; from here on
the mistakes are yours to pay for at fab. Two boards, designed, reviewed, fabricated,
assembled and brought up: Board A is a management controller in the shape of a DC-SCM
card, the thing that becomes Module Zero's BMC; Board B is a Compute Module carrier, a
PCIe host board with an M.2 NVMe slot and a TPM that lets a compute-on-module run your
Module 8 boot chain on hardware whose every trace you placed. Neither is a product. Both
teach the loop that a hardware company lives inside: specify, schematic, layout, review,
fab, assemble, bring up, find the mistake, respin. The lead time of that loop, six to
twelve weeks per turn at a contract manufacturer, is the constraint that shapes every
schedule and cost model in Module 15.

## Skip test

1. A 3.3 V rail feeds an FPGA drawing 400 mA with 50 mV of allowable ripple and a
   switching regulator at 1 MHz. Size the output capacitance and choose the ESR, then say
   why a 0402 100 nF ceramic goes next to every power pin anyway.
2. What is the characteristic impedance of a 5 mil trace on a 4-layer board with a 7 mil
   prepreg to the reference plane, and how far can a 33 MHz SPI clock travel before you
   must care?
3. A PCIe Gen3 lane pair leaves a connector, crosses a via, and reaches an M.2 slot. List
   the layout rules you must meet and the two you can bend.
4. Your new board draws 1.2 A at power-on instead of 200 mA. Give the first five things you
   do, in order, before touching the firmware.
5. What does a design-for-manufacture review at a contract manufacturer check, and which
   three of your choices most affect the assembled unit cost at a hundred pieces?

If all five are easy, do the Board B labs and the design review only.

## Core ideas

**A board is a power supply with signals attached.** Start every design from the power
tree: input, protection, each rail with its current, sequencing and tolerance, and the
regulators that produce it. Switching regulators are efficient and noisy; linear
regulators are quiet and hot. Every rail needs bulk capacitance at the regulator and
decoupling at every load pin, sized as in Module 1 Lab 1.4. Power sequencing matters for
anything with multiple rails (FPGAs, SoCs): the datasheet says the order and the
tolerance, and a sequencer or a chain of enable pins enforces it. Inrush, brownout,
reverse polarity and hot-plug are the failure modes you protect against; a current-limited
bench supply is how you survive the first power-on.

**Schematic capture as specification.** A schematic is a document first. One sheet per
function (power, MCU, FPGA, connectors), named nets, reference designators that group by
function, and a note wherever a value came from a calculation. Every part gets a symbol
that matches the datasheet's pin table, verified pin by pin, and a footprint verified
against the mechanical drawing with a printed 1:1 paper overlay of the layout before fab.
The electrical rules check catches unconnected pins and driver conflicts. Design rules you
can state in words (every enable has a pull-down; every I2C bus has pull-ups and a test
point) become a checklist you run before every review.

**Component selection and the supply chain.** The part you want is out of stock. Choose
parts with second sources, multiple package options and a lifecycle status of Active. A
bill of materials with manufacturer part numbers, distributor part numbers, alternates,
and quantity breaks is a deliverable, not an afterthought. Cost drivers: connectors and
anything with a brand on it (FPGAs, SoCs, memory) dominate; passives are noise. Prefer
what JLCPCB or your assembler stocks for anything you do not care about.

**Stack-up and impedance.** A 4-layer board (signal, ground, power, signal) with a thin
prepreg between the outer signal layers and the planes gives controlled-impedance traces
and a solid return path. Trace width and spacing to the reference plane set impedance;
your fab publishes a stack-up and a calculator. 50 Ω single-ended and 90 or 100 Ω
differential are the targets for almost everything. Six layers when you need two signal
layers with a plane adjacent to each, which PCIe wants.

**Signal integrity.** A trace is a transmission line when its length exceeds about a sixth
of the signal's rise-time distance, which for modern logic with 1 ns edges is a few
centimetres regardless of clock rate. Terminate series or parallel, match impedance,
avoid stubs, keep the return path under the trace, and change reference planes only with
a stitching capacitor or via nearby. Differential pairs: matched length within a fraction
of the bit period (PCIe Gen3: about 5 mil intra-pair), consistent spacing, symmetric
vias, no split under the pair. Crosstalk falls with spacing; three times the trace width
is the usual rule. Timing budget for a source-synchronous bus (SPI at 50 MHz, SDRAM): the
Module 2 setup and hold analysis with trace delay (about 150 ps per inch) added.

**Power integrity and EMC.** The power distribution network is an impedance versus
frequency curve; the target impedance is the ripple budget divided by the transient
current. Bulk electrolytics cover kilohertz, ceramics megahertz, the plane pair above
that. Every current loop is an antenna: keep loops small, keep return paths adjacent,
filter what leaves the board, and give the enclosure a way to ground. Module 15 covers
the regulatory tests; here you design so that they pass, which is mostly the same
discipline as signal integrity.

**Layout.** Place power first, then the critical signals (clocks, high-speed pairs, the
analogue reference), then the rest. Route the critical nets by hand; let the autorouter
do nothing. Ground pours with stitching vias. Thermal relief on pads that must be soldered
by hand; solid connections where current flows. Test points on every rail, every reset,
every enable, and every bus you will debug. Fiducials for the pick-and-place. Silkscreen
that says what a connector is and which pin is 1. Mounting holes where the enclosure
wants them, with a keep-out. DRC clean against the fab's capabilities before you export.

**Fabrication and assembly.** Gerbers, drill files, pick-and-place, a BOM in the assembler's
format, and a stencil. Design for manufacture: component orientation consistent, no parts
under other parts, room for the nozzle, no 0201 unless you must, tented vias where the
stencil will sit. Design for test: a test-point pattern a fixture can probe, a way to
program and reset without hands. Panelisation for volume. Impedance control and controlled
stack-up cost extra; order them for Board B.

**Bring-up.** A procedure, written before the boards arrive: visual inspection under the
microscope for bridges, tombstones and missing parts; continuity between rails and
ground with nothing powered; power on with the bench supply current-limited to a
fraction of the expected draw, one rail at a time if you can; check each rail's voltage
and ripple on the scope; then the clock; then the reset; then attach the debugger and
read the chip's ID register; then and only then run code. Every failure gets a written
root cause, a fix, and an entry in the errata that the respin must address. Two boards
of five is normal on a first run.

**Mechanical and thermal.** The board lives in an enclosure with a fan curve you control
from Module 11. Where the hot parts are decides the airflow; a thermal camera or a
thermocouple on the regulator tells you whether the copper is enough. Connector
placement, board-to-board mating, standoff heights and the sled form factor (Open Rack v3
and Yosemite v3 give you numbers for a real rack) constrain the outline. A 3D export from
KiCad into FreeCAD, and a printed or laser-cut mock enclosure, catch collisions for a
tenth of the cost of a respin.

**Standards to borrow.** OCP DC-SCM 2.0 defines a management card (BMC, root of trust, TPM,
boot flash, a connector to the host) that any host board accepts; designing Board A in
its shape means Module Zero can later use a commercial DC-SCM or offer its own. The M.2
and U.2 specifications give you an NVMe slot that just works. The Raspberry Pi Compute
Module 5 and its I/O board design files give you a fully documented carrier for a Linux
SoC with PCIe; Board B stands on them.

## Reading

- Horowitz and Hill, *The Art of Electronics*, 3rd ed.: ch. 9 (voltage regulation and
  power conversion), ch. 12 (logic interfacing), appendix H (transmission lines).
- Johnson and Graham, *High-Speed Digital Design*: ch. 1 to 6 (fundamentals, transmission
  lines, ground planes, terminations, vias), ch. 8 (power systems), ch. 12 (clock
  distribution).
- Bogatin, *Signal and Power Integrity, Simplified*, 3rd ed.: ch. 1 to 8 for the
  intuition, ch. 13 (PDN) before the Board A power design.
- Ott, *Electromagnetic Compatibility Engineering*: ch. 3 (grounding), ch. 10 (digital
  circuit grounding), ch. 11 (PCB layout), ch. 12 (mixed-signal).
- OCP DC-SCM 2.0 specification (the management card form factor and connector), OCP
  Open Rack v3 and Yosemite v3 (sled mechanicals) for the outline decisions.
- PCI Express Card Electromechanical specification, ch. 4 (electrical) and the M.2
  specification's PCIe section, for Board B's routing rules.
- Raspberry Pi Compute Module 5 datasheet and the CM5 IO Board design files (KiCad),
  and the ASPEED AST2600 or Nuvoton NPCM8XX datasheets as the reference for what a real
  BMC SoC needs around it.
- Your fab's capabilities page, stack-up table and DFM guide. Read them before layout.
- Texas Instruments and Analog Devices application notes on regulator layout (each part
  you pick has one) and Murata's capacitor impedance tool for the PDN.
- Bolton, *PCB Design for Real-World EMI Control* (Archambeault), ch. 4 to 7, if EMC
  worries you (it should).

## Labs

### Lab 14.1: Specify both boards

Two one-page specifications, written before any schematic. Each states the purpose, the
interfaces with pinouts, the power budget per rail, the mechanical outline, the parts you
have chosen and why, the bring-up plan, and what "working" means.

**Board A: BMC-lite management controller.** An STM32F4 (the F411 from Module 7, or the
F446 for Ethernet) with: 12 V input through a buck to 5 V and 3.3 V with a current sense
(INA226); two I2C buses with a PCA9548 mux and headers to a BME280, an EMC2101 fan
controller and a PMBus connector; one SPI bus to the ULX3S header (later, an on-board
ECP5 in the respin) and to a LetsTrust-style SPI TPM footprint; an ATECC608 for device
identity; two 4-pin fan headers with PWM and tachometer; a host-side UART and a debug
UART; power-good, reset and presence GPIOs to a host connector; a 10-pin SWD header;
status LEDs; and the DC-SCM 2.0 card outline if you dare, a 100 × 80 mm rectangle if you
do not.

**Board B: Compute Module carrier.** A Raspberry Pi Compute Module 5 (or CM4 with a PCIe
switch if you want Gen2 and more lanes): the CM5 connectors; a PCIe Gen2 x1 (CM5: Gen3
capable) to an M.2 M-key slot for the NVMe drive; an SPI TPM 2.0 (Infineon SLB9670 or
9672); a management connector to Board A carrying UART, I2C, power-good, reset and
presence; 12 V input with the CM5's 5 V regulator and an inrush limiter; Gigabit Ethernet
through the CM5's PHY and a MagJack; USB for a keyboard; a status LED driven from the
BMC; and mounting holes for a sled mock-up.

Done when: both specifications are reviewed against the checklist in this module and the
parts are in stock at two distributors.

### Lab 14.2: Board A schematic, layout and design review

1. KiCad project with one sheet per function. Draw the power tree first and simulate the
   buck regulator's output filter in ngspice for ripple under a 500 mA step. Every
   decoupling capacitor placed per the datasheets you read in Module 7. Pull-ups on I2C
   sized from bus capacitance and speed. Series terminations on SPI clock. ESD protection on
   every connector that leaves the board.
2. Custom symbols and footprints for anything not in the library, each checked against the
   datasheet pin table and mechanical drawing. Print the layout 1:1 and place real parts on
   the paper.
3. 4-layer layout with your fab's stack-up: power and ground planes, SPI and I2C routed
   by hand with the return path under them, the regulator's switching loop tight, test
   points on every rail, reset, enable and bus, fiducials, silkscreen. DRC against the
   fab's rules. A 3D view checked for collisions with connectors and the Nucleo-style
   headers you may keep for debugging.
4. Design review: write the review yourself using the checklist below, then get one
   outside review (a friend, a forum such as EEVblog or r/PrintedCircuitBoard, or a paid
   hour from a contractor). Fix what they find. Record every finding, even the ones you
   reject, with your reason.
5. Export Gerbers, drills, BOM in JLCPCB or PCBWay format, pick-and-place. Order five,
   assembled, with a stencil. Log the lead time and cost per board in the notebook; this
   feeds Module 15's cost model.

Done when: the order is placed and the design review document has no open findings.

### Lab 14.3: Board B schematic, layout and design review

Start while Board A is at fab.

1. Start from the CM5 IO Board design files. Strip what you do not need; add the M.2 slot,
   the TPM, the management connector and the inrush limiter. Understand every net you keep.
2. PCIe routing: 90 Ω differential, length-matched within 5 mil intra-pair, minimal vias
   with ground return vias next to any layer change, AC coupling capacitors where the
   specification requires them on the transmitter side, the reference clock pair with the
   same care, `PERST#` and `CLKREQ#` with pull-ups. Read the CM5's PCIe guidance for the
   maximum trace length at Gen2 and Gen3 and stay under it.
3. Six layers if you need two routing layers with adjacent planes for the PCIe and the
   Ethernet; four if you can route both on one outer layer over a solid ground.
4. Impedance-controlled stack-up ordered from the fab; the fab's calculator confirms your
   widths. Ethernet magnetics and the MagJack per the PHY's application note.
5. Design review as for Board A, with the added checklist for high-speed pairs. Order five
   with the CM5 connectors and M.2 slot assembled, the rest by hand if cheaper.

Done when: the order is placed, the impedance report from the fab matches your targets,
and the review has no open findings.

### Lab 14.4: Board A bring-up

When the boards arrive:

1. Inspection under the microscope, every joint, with photos of anything odd. Continuity
   test: every rail to ground (should be open), every rail to its regulator output, every
   connector pin to its net.
2. Power on with the bench supply at 12 V limited to 100 mA, no MCU firmware yet. Read each
   rail's voltage and scope its ripple. Check the current draw against your budget. If the
   limit trips, find the short with the thermal camera or by touch before raising it.
3. SWD: OpenOCD connects, reads the F4's `IDCODE`. Flash the Module 7 blink. Then the
   Module 7 UART, I2C sensor, EMC2101 fan and INA226 code, adapted to your pin assignments.
   Each peripheral verified with the logic analyser as in Module 7.
4. The bootloader from Lab 7.6 with A/B slots; update over UART; power-loss test. This
   board is now a BMC-lite: fans, sensors, power monitoring, a serial console, a signed
   firmware update path.
5. Errata: every deviation from the specification, every workaround (a cut trace, a wire, a
   component swap), and what the respin changes. Take the board's thermal image under load.

Done when: Board A runs the Module 7 firmware set, updates itself over UART, and the
errata list is written with a respin plan.

### Lab 14.5: Board B bring-up and the boot chain on your hardware

1. Inspection and continuity as before; particular care with the M.2 slot and the CM5
   connectors under the microscope.
2. Power on without the CM5 fitted; rails and inrush on the scope. Then with the CM5: it
   boots from eMMC or from your Module 8 U-Boot over the serial console on the management
   connector. Ethernet link. `lspci` shows the NVMe drive; if it does not, `dmesg` for
   link training failures, then the scope on `PERST#` and the reference clock, then the
   eye of the transmit pair if your scope reaches (it will not at Gen3; reason from the
   link status registers of Lab 5.4 instead). Retrain at Gen1 with a device-tree change to
   isolate a signal-integrity problem from a logic one.
3. TPM: the SPI TPM appears as `/dev/tpm0` with the device-tree node you wrote in
   Module 8; `tpm2_pcrread` works; the Module 8 measured boot and attestation labs run on
   this board with your U-Boot measuring the kernel into a PCR.
4. Connect Board A to Board B through the management connector. Board A's firmware
   controls Board B's power and reset, reads its presence pin, and forwards its console.
   Power-cycle Board B from Board A's serial console. Read Board B's temperature over the
   I2C link and run the fan from it.
5. Boot your Module 8 zero-touch path on Board B: netboot, install, attest to your
   verifier, join. Module Zero's first node exists.

Done when: Board B boots Linux from the NVMe drive through your U-Boot with the TPM
measuring the chain, Board A controls Board B's power, and the attestation from Lab 8.4
admits it.

### Lab 14.6: The respin decision

1. Consolidate both errata lists. Classify each item: must fix (board does not work
   without a workaround), should fix (works, but not manufacturable or reliable), could fix
   (cosmetic or convenience).
2. Decide what a respin of each board would change: fixes, plus the deferred features
   (the on-board ECP5 for Board A, a second M.2 or a U.2 connector for Board B, a real
   DC-SCM connector). Estimate the cost and lead time for five more of each.
3. Respin Board A if its must-fix list is non-empty; otherwise put the money toward
   Module 16's second node. Write the decision as a page.

Done when: the decision is written with the numbers behind it.

## Design review checklist

Run this on every board before ordering. Add to it after every bring-up.

- Power: every rail's current budget summed and within the regulator's rating with margin;
  input protection; sequencing meets every datasheet; bulk and decoupling per pin; test
  point per rail; a way to measure current per rail (a jumper or a sense resistor).
- Resets and enables: defined at power-on by a pull resistor, never floating; reset
  supervisor or RC where the datasheet requires; reset reachable from the debugger.
- Clocks: crystal load capacitors from the crystal's specification; short traces; ground
  guard; no other signals under.
- Buses: I2C pull-ups sized; addresses unique per bus (check every part's address pins);
  SPI chip selects unique with pull-ups; UART levels match (3.3 V versus 5 V versus RS-232).
- High-speed: impedance, length match, via count, reference plane continuity, AC coupling,
  keep-outs, and the maximum length from the source's guidance.
- Connectors: pin 1 marked; mating part number in the BOM; mechanical keep-out; ESD on
  anything external; current rating per contact.
- Debug: SWD or JTAG header; console UART header; LED on power-good and on a GPIO; test
  points on every net you would want to scope, including the ones you think you will not.
- Mechanical: outline, holes, standoff height, connector overhang, 3D collision check,
  1:1 paper print with real parts placed on it.
- Manufacturing: footprints checked against datasheets; part orientation consistent;
  fiducials; stencil apertures; no unnecessary 0201 or fine-pitch; every BOM line has a
  manufacturer part number, a distributor part number and an alternate; parts in stock.
- Documentation: schematic notes for every calculated value; net names; revision and date
  on silkscreen; a bring-up procedure written before the boards ship.

## Problem set

1. Design the PDN for Board A's 3.3 V rail: transient current, ripple budget, target
   impedance, and a capacitor set (values, count, package) whose combined impedance stays
   below target from 1 kHz to 100 MHz. Show the curve.
2. The SPI bus from Board A's MCU to the FPGA header is 12 cm long at 25 MHz with 1 ns
   edges. Is it a transmission line? Compute the round-trip delay, decide on termination,
   and compute the setup margin using the Module 2 method with trace delay included.
3. Board B's PCIe pair crosses from the top layer to the bottom through two vias. Explain
   what the return current does at each via, what you add to help it, and the discontinuity
   a via adds in picoseconds.
4. Your 12 V input sees a 30 V transient for 100 µs when the bench supply is switched on.
   Choose a protection scheme and the parts.
5. Estimate the assembled cost of Board A at 5, 100 and 1,000 units, splitting fab,
   assembly, connectors, silicon and passives. Which decision in your design has the
   biggest effect on the 1,000-unit price?
6. Board A's first unit draws 800 mA at 12 V with nothing running. Give an ordered
   diagnostic procedure and the three most likely causes.
7. A part in your BOM goes end-of-life six months after your first production run. What
   in your design and process determines whether that is a one-week or a six-month problem?
8. Compare designing Board A in the DC-SCM 2.0 form factor against a custom outline, for
   Module Zero: what does the standard buy, what does it cost, and what would a customer
   with an existing fleet think?
9. Plan a thermal test for Board B in a sled mock-up at 35 °C inlet: what you measure,
   where the thermocouples go, and what result means the fan curve from Module 11 must
   change.

## Deliverables

- Two specifications, two KiCad projects, two design review documents with all findings,
  two ordered BOMs with costs and lead times.
- Bring-up notebooks with photographs, scope captures, current measurements and errata.
- A working Board A running the Module 7 firmware set with the A/B bootloader.
- A working Board B booting the Module 8 chain from NVMe with TPM measurement, controlled
  by Board A.
- The respin decision page.

## Stretch

- Respin Board A with an on-board ECP5-25 and the Module 3 register-map peripheral, so the
  FPGA is on the management board as Module 3 promised.
- Design a sled mechanical for Board A and Board B together in the Yosemite v3 or Open Rack
  v3 envelope in FreeCAD; 3D-print or laser-cut a mock-up; fit-check the connectors.
- Build a bed-of-nails or pogo-pin test fixture for Board A that programs the bootloader
  and runs a self-test; time a unit through it. This is Module 15's manufacturing test in
  miniature.
- Run a pre-compliance radiated emissions scan with a TinySA or an SDR and a near-field
  probe you wind yourself; find the loudest loop and fix it.

## Next

Module 15 turns the prototype into a plan: what Module Zero is, what it must never do, how
it is built and tested in quantity, what it costs, and which laws it must satisfy before
a customer racks it.
