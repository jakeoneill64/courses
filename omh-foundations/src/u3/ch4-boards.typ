#import "../lib/template.typ": *

= Board design and bring-up <ch-boards>

#chapter-meta(
  weeks: [6 weeks, plus two fabrication lead times of 2 to 3 weeks each],
  builds: [Four printed circuit boards, specified, designed in KiCad, reviewed, fabricated, assembled and brought up: Board P, the drone's power module; Board F, the flight-controller BoosterPack; Board A, a BMC-lite management controller built on the MSP432E401Y chip; and Board B, a Compute Module 5 carrier with NVMe and a TPM. An errata list and a respin decision for each.],
  needs: [KiCad 9 or later, the bench kit (supply, scope, multimeter, microscope, hot-air station, thermal camera if you have one), the Raspberry Pi Debug Probe, the USB-to-serial adapters, your firmware from Chapters 2.6 and 3.1, your boot chain from Chapter 2.7, an account with a PCB fabricator that also assembles (JLCPCB is assumed below), the CM5 module and a spare NVMe drive for Board B.],
)

#why[
  OMH sells hardware. Until now the course has run on other people's boards; from here the mistakes are yours to pay for at fabrication. Four boards teach the loop a hardware company lives inside: specify, draw the schematic, lay out, review, fabricate, assemble, bring up, find the mistake, respin. Two are drone boards, small enough to finish quickly and unforgiving of power and layout errors. Two are server boards: Board A is the management controller that becomes Module Zero's BMC, and Board B is a PCIe host board whose every trace you placed. The lead time of the loop, weeks per turn even at a fast fabricator and months at a contract manufacturer, is the constraint that shapes every schedule and cost model in Chapter 4.6.
]

#skip-test(
  rule: [If all five are easy, do Labs 3.4.5, 3.4.7 and the design review only.],
  [A 3.3 V rail feeds a load drawing 400 mA with 50 mV of allowable ripple from a buck switching at 1 MHz. Size the output capacitance and its ESR, then say why a 100 nF ceramic still goes next to every power pin.],
  [What is the characteristic impedance of a 0.2 mm trace over a 0.2 mm prepreg to the reference plane on a typical four-layer board, and how long can a 25 MHz SPI clock with 1 ns edges run before you treat it as a transmission line?],
  [A PCIe Gen 3 lane pair leaves a connector, changes layer through a via and reaches an M.2 slot. List the layout rules you must meet and the two you can bend.],
  [Your new board draws 1.2 A at power-on instead of 200 mA. Give the first five things you do, in order, before touching firmware.],
  [What does a design-for-manufacture review check, and which three of your choices most affect the assembled cost at a hundred pieces?],
)

== Core ideas

*A board is a power supply with signals attached.* Start every design from the power tree you drew in Lab 1.4.5: input, protection, each rail with its current, sequencing and tolerance, and the regulator that produces it. Switching regulators are efficient and noisy; linear regulators are quiet and hot. Every rail needs bulk capacitance at the regulator and decoupling at each load pin. Multi-rail parts state a power-up order in their datasheets, and a sequencer or a chain of enable pins enforces it. Inrush, brownout, reverse polarity and hot plug are the failure modes you protect against, and a current-limited bench supply is how you survive the first power-on.

#fig("/figures/u3-boards.svg", caption: [The four boards and their connections. P and F fly; A and B become Module Zero's first node in Chapter 4.7.])

*The four boards.*

- *Board P*, the drone's power module, on two layers with 2 oz copper: XT60 in and out on a 60 A path, a 0.5 mΩ four-terminal shunt read by an INA228, a TPS62933 buck making 5 V at 3 A for the electronics, reverse-polarity protection and a TVS on that low-current branch only, two USB-A sockets that supply 5 V to the radio and radar LaunchPads, and a JST-GH connector to Board F carrying 5 V, I#super[2]C and the INA228’s alert.
- *Board F*, the flight-controller BoosterPack for the MSP-EXP432E401Y, on four layers: the LSM6DSOX and BMP581 as chips, a W25Q128JV SPI flash for the flight logger, four ESC outputs with series resistors and ESD protection, UART connectors for the receiver, the telemetry radio and the radar, an I#super[2]C connector to the magnetometer mast, a 3.3 V regulator, a buzzer, LEDs and test points. The LaunchPad takes its power from the BoosterPack header when its JP1 jumper is in the left position, and in that position the board must also be given 3.3 V with the J101 3V3 jumper removed (TI SLAU748B section 2.1.6.4); Board F's regulator provides it.
- *Board A*, the BMC-lite, on four layers: the MSP432E401Y in its 128-pin package with the crystal and Ethernet magnetics from the LaunchPad's reference design, a 12 V input through a TPS25947 eFuse to a 3.3 V buck, an INA228 on the input, two TMP117s at the board's edges, two 4-pin fan headers with PWM and tachometer, an ATECC608 for identity, an RJ45 MagJack, a 10-pin Cortex debug header for the Debug Probe, status LEDs, and a host connector carrying UART, I#super[2]C, power-good, reset, power-enable and presence. Outline: a 100 × 80 mm rectangle, or OCP's DC-SCM 2.0 card if you dare.
- *Board B*, the Compute Module 5 carrier, on four or six layers with controlled impedance: the CM5’s two connectors, an M.2 M-key slot for NVMe on the CM5’s PCIe lane, an SPI TPM (Infineon SLB 9672), Gigabit Ethernet to a MagJack, 12 V input through an eFuse to the CM5’s 5 V supply, USB for a keyboard, and the management connector to Board A.

*Schematic capture as specification.* A schematic is a document first. One sheet per function, named nets, reference designators grouped by function, and a note wherever a value came from a calculation. Every symbol is checked pin by pin against the datasheet's pin table, and every footprint against its mechanical drawing, with a 1:1 paper print of the layout before ordering. The electrical rules check catches unconnected pins and driver conflicts. Rules you can say in words (every enable has a defined default; every I#super[2]C bus has pull-ups and a test point) become the checklist at the end of this chapter.

*Component selection and the supply chain.* The part you want is out of stock; Units 1 to 3 made that obvious. Choose active parts with second sources and more than one package, check stock at two distributors, and prefer the assembler's basic library for anything you do not care about. A bill of materials with manufacturer and distributor part numbers, alternates and price breaks is a deliverable. Connectors and anything with a brand on it dominate the cost; passives are noise.

*Stack-up and impedance.* A four-layer board (signal, ground, power, signal) with thin prepreg between each outer layer and its plane gives controlled-impedance traces and a solid return path. Width and height above the plane set impedance; your fabricator publishes its stack-up and a calculator. Targets: 50 Ω single-ended, 90 Ω differential for USB and PCIe, 100 Ω for Ethernet. Six layers when you need two signal layers each with an adjacent plane.

#fig("/figures/u3-stackup.svg", caption: [A four-layer stack-up and the microstrip that sits on it. Impedance depends on the trace width $w$ against its height $h$ above the plane, which is why a stack-up is chosen before the layout starts.])

*Signal integrity.* A trace is a transmission line when it is longer than about a sixth of the distance an edge travels during its rise time, which for 1 ns edges is a few centimetres whatever the clock rate (Chapter 1.5). Terminate, match impedance, avoid stubs, keep the return path under the trace, and change reference plane only with a stitching via or capacitor nearby. Differential pairs need matched lengths within a fraction of the bit period (about 0.13 mm for PCIe Gen 3), constant spacing, symmetric vias and no plane split beneath them. A source-synchronous bus's timing budget is Chapter 2.1’s setup-and-hold analysis with trace delay (about 6 ps per millimetre) added.

*Power integrity and EMC.* The power distribution network is an impedance against frequency; its target is the allowed ripple divided by the transient current. Bulk capacitors cover kilohertz, ceramics megahertz, and the plane pair above that. Every current loop is an antenna: keep loops small and returns adjacent, filter what leaves the board, and give the enclosure a ground. On Board P the loop that matters carries 60 A; on Board A it is the buck's switching loop; on Board B it is the PCIe and Ethernet pairs.

*Layout.* Place power first, then the critical signals (clocks, high-speed pairs, the IMU and the shunt's Kelvin traces), then the rest. Route the critical nets by hand. Pour ground with stitching vias. Thermal reliefs on pads you solder by hand; solid connections where current flows. Test points on every rail, reset, enable and bus. Fiducials for assembly. Silkscreen that names every connector and marks pin 1. Mounting holes with keep-outs. A design-rule check against your fabricator's capabilities before export.

*Fabrication and assembly.* Gerbers, drill files, a pick-and-place file and a BOM in the assembler's format. Design for manufacture: consistent orientation, nothing under other parts, no 0201 unless you must, tented vias under the stencil. Design for test: probe points a fixture can reach, and a way to program and reset without hands. Controlled impedance and a custom stack-up cost extra; order them for Board B.

*Bring-up.* A procedure written before the boards arrive. Inspect under the microscope for bridges, tombstones and missing parts; check every rail to ground with nothing powered; power on with the bench supply limited to a fraction of the expected current, one rail at a time if you can; check each rail's voltage and ripple, then the clock, then reset; attach the debugger and read the chip's ID; only then run code. Every failure gets a root cause, a fix, and an entry in the errata the respin must address.

#fig("/figures/u3-bringup.svg", caption: [The bring-up procedure as a sequence of gates. You do not pass a gate until its measurement is in the notebook, and a failure sends you to the microscope, never to the firmware.])

*Mechanical and thermal.* Board F's IMU sits near the frame's centre of rotation, on foam, away from the ESC wiring. Board P's shunt and XT60 pads dissipate watts; a thermal camera or thermocouple shows whether the copper is enough. Board A lives in an enclosure with the fan curve you control; Board B's outline is set by the CM5, the M.2 drive and the connectors. A 3D export from KiCad catches collisions for a tenth of the cost of a respin.

*Standards to borrow.* OCP's DC-SCM 2.0 defines a management card that any host board accepts; designing Board A in its shape lets Module Zero later use a commercial card or offer its own. The M.2 and PCIe CEM specifications give you a slot that just works. Raspberry Pi publishes the CM5 IO Board's KiCad files; Board B starts from them.

== Reading

- Horowitz and Hill, _The Art of Electronics_, 3rd ed., chapter 9 (regulation and power conversion), chapter 12 (logic interfacing) and appendix H (transmission lines).
- Bogatin, _Signal and Power Integrity, Simplified_, 3rd ed., chapters 1 to 8, then chapter 13 (the PDN) before Board A's power design.
- Johnson and Graham, _High-Speed Digital Design_, chapters 1 to 6, 8 and 12.
- Ott, _Electromagnetic Compatibility Engineering_, chapters 3, 10, 11 and 12.
- TI SLAU748B and the MSP-EXP432E401Y design files: schematic, layout and BOM, the reference for Board A's MCU, crystal and Ethernet; TI's application note on the MSP432E4 Ethernet PHY layout.
- The datasheets of every regulator you place, each with its layout guidelines section; the TPS62933, TPS25947 and INA228 datasheets at minimum.
- OCP DC-SCM 2.0 (management card form factor and connector); the PCI Express CEM specification chapter 4 and the M.2 specification's PCIe section, for Board B.
- Raspberry Pi's _Compute Module 5 Datasheet_ and the CM5 IO Board design files.
- Your fabricator's capabilities page, stack-up table and DFM guide, before layout.

== Labs

The boards go to fabrication in two batches so the lead times overlap with work: P and F together, then A and B. The design review checklist at the end of the chapter is mandatory for each board before ordering.

#lab([Specify four boards], goal: [decide what each board is for and how you will know it works, before drawing anything.], time: [6 h])[
+ Write one page per board: purpose; interfaces with pinouts; the power budget per rail; outline and mounting; the main parts and why; the bring-up plan; and what "working" means as measurable criteria.
+ For Board F, map every signal to an MSP432E401Y pin using the LaunchPad user's guide's BoosterPack tables, with no pin used twice: SSI for the IMU and the flash, four timer capture/compare pins for the ESCs, three UARTs, two I#super[2]C buses, an ADC input for the battery divider, and GPIOs for the buzzer and LEDs.
+ For Board A, map the same functions plus Ethernet, the fans and the host connector, and confirm in the MSP432E401Y datasheet that each function exists on the pin you chose in the 128-pin package.

#done-when(
  [Four specifications exist, each with a pin map checked against the datasheet, and every main part is in stock at two distributors.],
)
#evidence([The four pages; the pin maps; stock screenshots.])
] <lab-board-spec>

#lab([Board P: the drone's power module], goal: [design a board where layout decides whether it works.], time: [10 h], kit: [KiCad, your Lab 1.4.5 drone power tree, the Lab 1.3.6 error budget.])[
+ Schematic: the 60 A path with the shunt in the positive lead, sized from your error budget; the INA228 with its Kelvin sense traces and address straps; the TPS62933 at 5 V and 3 A designed from its datasheet (inductor, capacitors, feedback divider, soft start); reverse-polarity protection and a TVS on the 5 V branch only; the USB-A sockets (power pins only); the connector to Board F.
+ Simulate the buck's output filter in ngspice for ripple under a 1 A load step.
+ Layout on two layers with 2 oz copper: the high-current path as wide pours with the XT60 pads sized for the wire, the shunt's sense traces leaving its sense pads as a pair, and the buck's input loop as small as the datasheet's layout guide shows.
+ Estimate the copper's temperature rise at 60 A for 10 s with an IPC-2152 calculator and widen what needs it.

#done-when(
  [The board passes the design review checklist with no open findings and is ordered with Board F.],
)
#evidence([Schematic and layout PDFs; the buck design arithmetic and simulation; the temperature-rise estimate; the review record.])
] <lab-board-p>

#lab([Board F: the flight-controller BoosterPack], goal: [put the drone's sensors and connectors on a board you designed.], time: [2 weekends], kit: [KiCad, the Lab 3.4.1 pin map, the LaunchPad's BoosterPack mechanical drawing.])[
+ Schematic: the LSM6DSOX and BMP581 with decoupling as their datasheets show; the W25Q128JV; ESC outputs through 100 Ω series resistors and a TI ESD array; the UART, I#super[2]C and power connectors (JST-GH); a 3.3 V regulator sized for the LaunchPad's MCU domain plus your sensors; a buzzer on a MOSFET; LEDs; test points on every bus.
+ Layout on four layers in the BoosterPack outline, with the headers on the LaunchPad's 0.1 inch grid. Place the IMU at the board's centre, away from the ESC traces and the regulator, with its axes printed on the silkscreen.
+ Print the layout 1:1, push the LaunchPad's headers through the paper, and check alignment.
+ Order P and F from a fabricator with assembly of the fine-pitch parts; hand-solder the connectors yourself.

#done-when(
  [The board passes the checklist, the paper fit check is photographed, and P and F are ordered.],
)
#evidence([Schematic and layout; the fit-check photograph; the BOM with cost per board; the order confirmation with lead time and cost, which feed Chapter 4.6’s cost model.])
] <lab-board-f>

#lab([Board A: a BMC-lite on the MSP432E401Y], goal: [design the management controller Module Zero will run on.], time: [3 weekends], kit: [KiCad, the LaunchPad's design files, your Chapter 2.6 firmware.])[
+ Start from TI's LaunchPad schematic for the MCU, its crystals, the Ethernet PHY's connections and the reset and debug circuitry. Understand every net you keep and cite the reason in a note.
+ Add the 12 V input with the TPS25947 eFuse and a 3.3 V buck, the INA228 on the input, the TMP117s, the two fan headers with tachometer pull-ups and PWM at 25 kHz, the ATECC608, the host connector, the debug header and LEDs. Put ESD protection on every connector that leaves the board.
+ Simulate the buck's output in ngspice for ripple under a 500 mA step, and design the 3.3 V PDN to a target impedance (problem 1).
+ Layout on four layers: Ethernet pairs at 100 Ω differential from the PHY pins to the MagJack with no vias, the crystal close and guarded, the buck's switching loop tight, SPI and I#super[2]C routed over solid ground.
+ Review, including one outside review (a colleague, or a forum such as r/PrintedCircuitBoard), and order five assembled.

#done-when(
  [The review record has no open findings, including those from the outside reviewer, and the order is placed.],
)
#evidence([Schematic with notes; layout; the PDN design; the review record; the order with cost and lead time.])
] <lab-board-a>

#lab([Board B: a Compute Module 5 carrier], goal: [route PCIe and Gigabit Ethernet on a board you own.], time: [3 weekends], kit: [KiCad, the CM5 IO Board design files, the CM5 datasheet.])[
+ Strip the CM5 IO Board design to what you need. Add the M.2 M-key slot, the SPI TPM, the management connector to Board A, and the 12 V input with an eFuse and the 5 V supply the CM5 datasheet specifies.
+ Route PCIe: 90 Ω differential, matched within 0.13 mm in each pair, AC-coupling capacitors where the specification puts them, the reference clock pair with the same care, `PERST#` and `CLKREQ#` defined. Keep within the CM5 datasheet's length guidance.
+ Choose four or six layers so every high-speed pair has an adjacent plane. Order the fabricator's controlled-impedance stack-up and confirm your widths with its calculator.
+ Review with the high-speed additions to the checklist, and order five with the CM5 connectors and M.2 slot assembled.

#done-when(
  [The order is placed, the fabricator's impedance report matches your targets, and the review has no open findings.],
)
#evidence([Schematic; layout; stack-up and impedance calculations; the review record.])
] <lab-board-b>

#lab([Bring-up of Boards P and F], goal: [turn two bare boards into the drone's power and sensor core.], time: [2 weekends], kit: [Both boards, the bench supply, electronic load, scope, microscope, Debug Probe, a LaunchPad, the 3S pack, thermal camera or thermocouple.])[
+ Inspect every joint under the microscope and photograph anything doubtful. Check each rail to ground and each connector pin to its net with nothing powered.
+ Board P on the bench supply at 12 V limited to 100 mA with no load: check 5 V, then load it to 3 A with the electronic load and measure efficiency, ripple and a load step. Then 15 A through the main path from the pack into the electronic load for 60 s (the load's 200 W rating is the limit at this voltage): measure the shunt's and the pads' temperatures and the INA228’s reading against the load's. The 60 A bursts are checked in Chapter 3.5’s flight logs.
+ Board F on the LaunchPad with JP1 moved to the BoosterPack position and the 3V3 jumper on J101 removed, powered first from the bench supply through Board F's power connector. Read the IMU's and barometer's ID registers, the flash's JEDEC ID and the INA228 over the cable from Board P.
+ Port your Chapter 3.1 IMU and estimator code to Board F's pins and compare its noise with the breakout's. Write and read back the whole flash.
+ Record errata: every deviation, workaround (a cut trace, a wire, a swapped part) and what the respin changes.

#done-when(
  [Board P delivers 5 V at 3 A within its ripple specification and carries 15 A for 60 s within your temperature estimate, with the INA228 within 1 % of the load.],
  [Board F's sensors and flash work on the LaunchPad from Board P's power, and its IMU noise is no worse than the breakout's.],
)
#evidence([Bring-up notebook with photographs, captures and thermal readings; the errata lists.])
] <lab-bringup-pf>

#lab([Bring-up of Boards A and B], goal: [make your management controller run your BMC firmware and control your host board.], time: [3 weekends], kit: [Both boards, a 12 V supply, the Debug Probe, the CM5, an NVMe drive, the managed switch, the server.])[
+ Board A: inspection and continuity, then 12 V limited to 100 mA. Check the eFuse's inrush and the 3.3 V rail. Connect the Debug Probe, read the MCU's ID with OpenOCD and flash a blink.
+ Port the Chapter 2.6 firmware set: UART console, sensors, fans with tachometers, the INA228, the watchdog and the signed A/B bootloader. Bring up Ethernet with a link and a ping.
+ Board B without the CM5: rails and inrush on the scope. With the CM5: boot from eMMC with a serial console on the management connector, then check the Ethernet link. `lspci` must show the NVMe drive; if it does not, check `dmesg` for link training, then `PERST#` and the reference clock on the scope, then force Gen 1 to separate a signal-integrity problem from a logic one.
+ Bring up the TPM: `/dev/tpm0` with your Chapter 2.7 device-tree overlay, `tpm2_pcrread`, and the measured-boot chain from Lab 2.7.4 with your U-Boot measuring the kernel.
+ Connect A to B. Board A controls B's power and reset, reads its presence, forwards its console and runs a fan from B's temperature. Power-cycle B from A's console.
+ Boot B through your Lab 2.7.6 zero-touch path: netboot, install, attest, join.

#done-when(
  [Board A runs the Chapter 2.6 firmware set, updates itself over UART, and answers ping over its own Ethernet.],
  [Board B boots Linux from NVMe through your U-Boot with the TPM measuring the chain, under Board A's power control, and your attestation verifier admits it.],
)
#evidence([Bring-up notebooks; captures; the errata lists.])
] <lab-bringup-ab>

#lab([The respin decision], goal: [decide like a hardware company: with errata, costs and lead times.], time: [4 h])[
+ Consolidate the four errata lists. Classify each item: must fix (the board does not work without a workaround), should fix (works, but is not manufacturable or reliable), could fix.
+ For each board, decide what a respin changes and estimate the cost and lead time for five more.
+ Respin any board with a must-fix item that blocks Chapter 3.5 or 4.7. Write the decision as a page with the numbers behind it.

#done-when(
  [The decision is written with costs, lead times and the reason for each choice.],
)
#evidence([The consolidated errata and the decision page.])
] <lab-respin>

== The design review checklist

Run this on every board before ordering, and add to it after every bring-up.

#checklist(title: [Design review], intro: [A board is not ordered until every line is ticked or has a written exception.],
  [*Power:* every rail's budget summed and within its regulator's rating with margin; input protection; sequencing meets every datasheet; bulk and per-pin decoupling; a test point per rail; a way to measure each rail's current.],
  [*Resets and enables:* defined at power-on by a resistor, never floating; a supervisor or RC where a datasheet requires it; reset reachable from the debugger.],
  [*Clocks:* crystal load capacitors computed from the crystal's specification; short traces; ground guard; nothing routed underneath.],
  [*Buses:* I#super[2]C pull-ups sized for the bus capacitance; addresses unique on each bus; SPI chip selects pulled inactive; UART voltage levels match at both ends.],
  [*High-speed:* impedance, length match, via count, reference-plane continuity, AC coupling, keep-outs, and the source's maximum length.],
  [*Connectors:* pin 1 marked; mating part in the BOM; mechanical keep-out; ESD on everything external; current rating per contact.],
  [*Debug:* SWD or JTAG header; console UART; an LED on power-good and on a GPIO; test points on every net you might scope.],
  [*Mechanical:* outline, holes, standoff height, connector overhang, a 3D collision check, and a 1:1 paper print with real parts placed on it.],
  [*Manufacturing:* footprints checked against datasheets; consistent orientation; fiducials; stencil apertures; every BOM line with a manufacturer number, a distributor number and an alternate; parts in stock.],
  [*Documentation:* a note for every calculated value; net names; revision and date on the silkscreen; the bring-up procedure written before the boards ship.],
)

== Problem set

+ Design the PDN for Board A's 3.3 V rail: transient current, ripple budget, target impedance, and a capacitor set whose combined impedance stays below the target from 1 kHz to 100 MHz. Show the curve.
+ Board P's shunt is 0.5 mΩ. At 60 A, what power does it dissipate? If the copper between the shunt's current pads and its sense pads adds 50 µΩ that the Kelvin connection fails to exclude, what error does it cause?
+ The SPI bus from Board F's MCU to the flash is 40 mm long at 30 MHz with 1 ns edges. Is it a transmission line? Decide on termination and compute the setup margin with trace delay included.
+ Board B's PCIe pair changes from the top layer to the bottom through two vias. Explain what the return current does at each via, what you add to help it, and estimate the discontinuity a via adds in picoseconds.
+ Board A's 12 V input sees a 30 V transient for 100 µs when the bench supply is switched on. Choose a protection scheme and its parts.
+ Estimate the assembled cost of Board A at 5, 100 and 1,000 units, split into fabrication, assembly, connectors, silicon and passives. Which design decision most affects the 1,000-unit price?
+ Board A's first unit draws 800 mA at 12 V with nothing running. Give an ordered diagnostic procedure and the three most likely causes.
+ A part in your BOM goes end-of-life six months after your first production run. What in your design and process decides whether that is a one-week or a six-month problem?
+ Compare designing Board A in the DC-SCM 2.0 form factor with a custom outline, for Module Zero: what does the standard buy, what does it cost, and what would a customer with an existing fleet think?

== Deliverables and stretch

*Deliverables.* Four specifications, four KiCad projects, four review records, four ordered BOMs with costs and lead times; bring-up notebooks with photographs, captures and errata; working Boards P and F feeding the drone; Board A running your BMC firmware; Board B booting your chain from NVMe under Board A's control; the respin decision.

*Stretch.* Respin Board A with an ECP5 FPGA and the Chapter 2.2 register-map peripheral on board. Design a sled for Boards A and B in the Open Rack v3 or Yosemite v3 envelope in FreeCAD and print a mock-up. Build a pogo-pin test fixture for Board A that programs the bootloader and runs a self-test, and time a unit through it: Chapter 4.6’s manufacturing test in miniature. Scan Board A for radiated emissions with the Tekbox near-field probes and the tinySA, find the loudest loop and fix it.

#checklist(
  [*Lab 3.4.1:* four specifications with checked pin maps; parts in stock at two distributors.],
  [*Lab 3.4.2:* Board P reviewed and ordered, with the buck design and the temperature estimate.],
  [*Lab 3.4.3:* Board F reviewed, fit-checked on paper and ordered.],
  [*Lab 3.4.4:* Board A reviewed with an outside reviewer and ordered.],
  [*Lab 3.4.5:* Board B ordered with a matching impedance report.],
  [*Lab 3.4.6:* Board P at 3 A and 15 A within specification; Board F's sensors and flash working on the LaunchPad.],
  [*Lab 3.4.7:* Board A running your BMC firmware over its own Ethernet; Board B booting the measured chain from NVMe under A's control.],
  [*Lab 3.4.8:* the respin decision written with numbers.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: why a board starts from its power tree, what sets a trace's impedance, how a return current behaves at a via, what you check before applying power to a new board, and what decides whether to respin.],
)
