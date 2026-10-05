#import "../lib/template.typ": *

= Power conversion and batteries <ch-power>

#chapter-meta(
  weeks: [2.5 weeks],
  builds: [Measured efficiency, ripple and transient response of a TI buck converter; demonstrated inrush control, short-circuit protection and reverse-polarity protection; a characterised three-cell lithium-polymer pack; two power trees with chosen TI parts that become Board P and Board A in Unit 3.],
  needs: [Bench supply, oscilloscope, DC electronic load, INA228 breakout, LM317 in TO-220, the TI buck, eFuse and ideal-diode EVMs, the drone's 3S 5000 mAh LiPo with its balance charger, LiPo bag and cell checker, the multimeter's thermocouple.],
)

#why[
  OMH's modules take a 12 V bus and turn it into a dozen rails, one of which feeds a CPU at 0.9 V and 100 A. The drone takes a battery whose voltage falls by a quarter over a flight and sags by more under load. In both, the power system decides efficiency, heat, noise, what happens when something is plugged in live or wired backwards, and how long the thing runs. This chapter turns Chapter 1.1’s intuition into converters, protection and batteries you have measured.
]

#skip-test(
  rule: [If all five are easy, do Labs 1.4.4 and 1.4.5 only.],
  [A synchronous buck converts 12 V to 3.3 V at 2 A, switching at 500 kHz with a 4.7 µH inductor. What is the duty cycle and the inductor's peak-to-peak ripple current, and what output capacitance keeps the ripple under 10 mV ignoring ESR?],
  [Why does a buck converter's efficiency fall at light load, and what do "PFM" and "skip mode" do about it?],
  [A 470 µF bulk capacitor is hot-plugged onto a 12 V bus. Estimate the inrush current with 50 mΩ of total path resistance, and say how an eFuse with a dV/dt control limits it.],
  [Why does an ideal-diode controller with an N-channel MOSFET waste less power than a Schottky diode at 10 A?],
  [A 3S 5000 mAh pack reads 12.4 V at rest and 11.5 V at 30 A. What is its internal resistance, and how much of a 15-minute hover's energy is lost inside it at a steady 12 A?],
)

== Core ideas

*Start from the power tree.* Draw the source, each conversion stage, each rail with its voltage, maximum current, tolerance and noise requirement, and each load. Sum the currents upward through the efficiencies. The tree tells you the input current, the heat in each converter, which rails need sequencing, and where you need telemetry. Unit 3 designs two boards from the trees you draw in Lab 1.4.5.

#fig("/figures/u1-power-trees.svg", caption: [The two power trees this course builds toward: the drone's (a three-cell pack feeding the ESCs directly and a 5 V converter for the electronics) and a rack module's (a 12 V bus feeding point-of-load converters). Both have an input protection stage and current telemetry.])

*Linear regulators.* A linear regulator is a transistor whose resistance a feedback loop adjusts to hold the output. The dropped voltage times the load current is heat, so efficiency is at best $V_"out" \/ V_"in"$. Linear regulators are quiet, simple and fast; they reject input ripple (PSRR, falling with frequency); a low-dropout (LDO) part works with as little as 100 to 300 mV of headroom. They suit small currents and noise-sensitive rails such as PLLs, references and ADCs, and they are the second stage after a switcher wherever noise matters.

*The buck converter.* Two switches alternately connect an inductor to the input and to ground; the inductor and output capacitor average the result. In continuous conduction the duty cycle is $D approx V_"out" \/ V_"in"$, and the inductor's ripple current and the output ripple are

$ Delta I_L = ((V_"in" - V_"out") D) / (L f_"sw"), quad Delta V_"out" approx (Delta I_L) / (8 f_"sw" C_"out") + Delta I_L dot "ESR". $

Designers choose $L$ for a ripple of 20 to 40 % of the full-load current. Losses come from conduction ($I^2 R$ in the switches and the inductor's winding resistance), switching (the overlap of voltage and current at each edge, proportional to $f_"sw"$), gate drive ($Q_g V_"GS" f_"sw"$) and quiescent current. At light load the fixed losses dominate, so modern controllers drop into pulse-frequency or skip modes, trading ripple for efficiency.

#fig("/figures/u1-buck.svg", caption: [A synchronous buck converter and its waveforms. The switch node swings between $V_"in"$ and ground at the duty cycle; the inductor current ramps up and down around the load current; the output ripple is what the capacitor fails to absorb.])

*Control and stability.* A feedback loop compares the divided output with a reference and sets the duty cycle. Peak-current-mode control, the most common, senses the inductor current each cycle, which makes the inductor behave like a current source and simplifies compensation. The loop's crossover frequency (typically a tenth of $f_"sw"$ or less) and phase margin (45° to 60°) decide how the output recovers from a load step: too little margin rings, too little bandwidth sags. Most TI converters are internally compensated for a range of output capacitance; stepping outside that range is the commonest way to make a stable design oscillate.

*Layout is part of the circuit.* The loop from the input capacitor through the high-side switch and back through the low-side switch carries current that changes in nanoseconds; its area is an antenna and its inductance makes voltage spikes. Keep it tiny. Keep the switch node small (it is the noisiest copper on the board) and the feedback trace away from it. Every TI converter datasheet has a layout example; copy it exactly on your first board.

*Boost and buck-boost.* A boost puts the inductor on the input side and raises the voltage; a buck-boost can do either, which a single-cell battery system needs as its voltage falls through the output. TI's BQ25798 is a buck-boost battery charger for one to four cells.

*Protection.* Faults you must design for:
- *Reverse polarity.* A series diode wastes $V_F times I$; a P-channel MOSFET in the return or supply path is better; an ideal-diode controller such as TI's LM74700 drives an N-channel MOSFET so that it conducts like a diode with millivolts of drop and turns off in microseconds when current reverses.
- *Inrush and hot plug.* Charging bulk capacitance through milliohms draws hundreds of amps for microseconds; connectors arc and the upstream bus dips. A hot-swap controller or an eFuse such as TI's TPS25947 ramps the output at a controlled $dif V \/ dif t$, limits current, and latches off or retries on a fault. Every OMH module's 12 V input needs one, because modules are inserted into live racks.
- *Overvoltage and transients.* A transient-voltage suppressor (TVS) diode clamps short spikes; an overvoltage cut-off disconnects sustained ones.
- *Undervoltage.* Lockout (UVLO) keeps a converter off until its input is valid; for a battery, a low-voltage cut-off protects the cells.

*Lithium-polymer cells.* A lithium-ion cell's open-circuit voltage runs from about 3.0 V empty to 4.20 V full, nominally 3.7 V. Capacity in ampere-hours times nominal voltage is energy in watt-hours; the C-rate expresses current relative to capacity (1C from a 3 Ah cell is 3 A). Each cell has an internal resistance of a few milliohms to tens of milliohms that rises with age and cold, so voltage sags under load and the pack warms. The voltage-against-charge curve is flat through the middle, which makes voltage a poor fuel gauge under load. Packs put cells in series (3S is three cells, 11.1 V nominal) and sometimes in parallel; series cells drift apart and must be balanced while charging.

#fig("/figures/u1-lipo.svg", caption: [A model of a three-cell pack discharging at 1C and 5C. Internal resistance shifts the whole curve down; the usable energy before the 3.5 V per cell cut-off shrinks at high current.])

*Gauging and protection.* Coulomb counting integrates current (the INA228’s charge accumulator does it in hardware) but drifts without an anchor. Voltage at rest anchors it. TI's fuel gauges combine both with a model of the cell's impedance. A battery management system watches every cell for over- and under-voltage, over-current and temperature, and opens a switch when any limit is crossed. A hobby drone pack has none of this; your flight controller must do the minimum (voltage cut-off and current logging) itself.

*Handling.* Charge at 1C or less, constant current then constant voltage to no more than 4.20 V per cell, always with balancing, never hot, never below about 5 °C and never unattended. Do not discharge below about 3.0 V per cell; set cut-offs at 3.3 to 3.5 V per cell. Store at 3.6 to 3.8 V per cell in a fire-resistant container. Retire any pack that is swollen, hot or crash-damaged: isolate it, discharge it through a resistive load, never short it, and take it to a battery recycling point.

== Reading

- Horowitz and Hill, _The Art of Electronics_, 3rd ed., chapter 9 (voltage regulation and power conversion), sections 9.1 to 9.7.
- Erickson and Maksimović, _Fundamentals of Power Electronics_, 3rd ed., chapters 1 to 3 (steady-state converter analysis) and chapter 9 sections 9.1 to 9.4 (control loops), as deep as you want to go.
- The datasheets and EVM user's guides for your buck converter, the TPS25947 and the LM74700, including their layout sections.
- TI, _Power Supply Design Seminar_ papers on buck converter fundamentals and on loop compensation (free on ti.com; search "power supply design seminar").
- Battery University (batteryuniversity.com), articles BU-205 (lithium types), BU-409 (charging lithium-ion), BU-501a (discharge characteristics) and BU-802 (capacity loss).

== Labs

#lab([Linear versus switching], goal: [see where the watts go.], time: [3 h], kit: [LM317 in TO-220 with its two resistors, the TI buck EVM, bench supply, DC load, thermocouple meter.])[
+ Set an LM317 for 5.0 V from 12 V. Load it to 300 mA with the DC load. Measure input and output power, the regulator's case temperature after five minutes with no heatsink, and its dropout as you lower the input.
+ Configure the TI buck EVM for 5 V (or use its fixed output) from 12 V and repeat at 300 mA and at 1 A.
+ Compute each efficiency and compare the measured temperature rise with $P theta_"JA"$ from the datasheets.
+ Scope both outputs with the spring ground tip and record ripple and noise at the same scale.

#done-when(
  [An efficiency table at both currents agrees with the textbook expectation ($V_"out" \/ V_"in"$ for the linear) within 3 points.],
  [Measured temperature rises are within 30 % of the $theta_"JA"$ prediction, or the discrepancy is explained.],
)
#evidence([Efficiency table; thermocouple readings; two ripple captures.])
] <lab-linear-switching>

#lab([Inside a buck converter], goal: [measure duty cycle, ripple, efficiency and transient response against the equations.], time: [6 h], kit: [TI buck EVM, bench supply, DC load, INA228, the MOSFET load-step switch from Lab 1.1.3 with a power resistor.])[
+ Probe the switch node with a short ground spring at 12 V in and half load. Measure frequency and duty cycle. Sweep the input from 8 to 16 V and plot duty cycle against $V_"out" \/ V_"in"$.
+ From the switch-node waveform and the inductor value in the EVM's bill of materials, compute $Delta I_L$. Measure the output ripple and compare with the formula, with and without an extra 22 µF ceramic.
+ Measure efficiency from 10 mA to the EVM's maximum current in at least eight steps, using the bench supply's readings for input power and the INA228 for output power. Mark where the converter changes mode.
+ Build a load step from 10 % to 90 % of full load with the MOSFET switch and a power resistor, driven at 100 Hz. Capture the output's undershoot, overshoot and settling time.
+ Read the EVM's layout and label the hot loop on a photograph.

#done-when(
  [Duty cycle tracks $V_"out" \/ V_"in"$ within 5 % and the mode change at light load is identified on the efficiency plot.],
  [Computed and measured output ripple agree within a factor of two, with the remaining difference explained (ESR, ESL, probing).],
  [The transient capture gives undershoot in millivolts and settling time in microseconds, compared with the datasheet's load-transient figure.],
)
#evidence([Duty-cycle plot; ripple captures; efficiency curve; transient capture; annotated EVM photo.])
] <lab-buck>

#lab([Protection: inrush, short circuit and reverse polarity], goal: [watch protection work, and fail without it.], time: [4 h], kit: [TPS25947 eFuse EVM, LM74700 ideal-diode EVM, a 1,000 µF low-ESR capacitor, a 0.1 Ω current-sense resistor, a 1N5819 Schottky diode.])[
+ Without the eFuse, hot-plug the 1,000 µF capacitor (through the 0.1 Ω sense resistor) onto the 12 V supply set to a 3 A limit. Capture the inrush current from the voltage across the sense resistor.
+ Repeat through the eFuse EVM. Set its current limit and dV/dt capacitor per the user's guide for a 20 ms ramp. Capture the ramp and the current.
+ Short the eFuse output through a 0.1 Ω resistor and capture the response. Note whether it latches or retries and how long it takes to act.
+ Through the LM74700 EVM, reverse the input polarity (current-limited) and show no reverse current flows. Then measure its forward drop at 2 A and compare with the 1N5819’s.

#done-when(
  [Captures show the inrush peak without protection, the controlled ramp with it, and the short-circuit response with its timing.],
  [The reverse-polarity test is captured and the forward-drop comparison is expressed in watts at 2 A and extrapolated to 20 A.],
)
#evidence([Four captures with current scales; the power comparison.])
] <lab-protection>

#lab([Characterise the drone battery], goal: [measure what the drone will actually get from its pack.], time: [5 h plus charging], kit: [Overlander 5000 mAh 3S pack, SkyRC S65 charger, LiPo bag, cell checker, Siglent SDL1020X-E electronic load, INA228 with the Bourns 1 mΩ shunt, TMP117, multimeter.])[
#safety[Charge and discharge inside the LiPo bag on a non-flammable surface, attended, with the charger's balance lead connected. Stop at 3.5 V per cell. If a cell swells or warms abnormally, stop and follow the handling rules above.]
+ Charge the pack fully with balancing. Measure each cell's resting voltage at the balance connector.
+ Measure internal resistance: apply 2 A, then step to 10 A for two seconds, and compute $Delta V \/ Delta I$ for the pack and, from the balance connector, for each cell.
+ Discharge at a constant 0.5C until any cell reaches 3.5 V, logging pack voltage, current, energy and pack temperature (TMP117 taped to the pack) every second. Recharge, then repeat at 2C.
+ Plot both discharge curves against delivered watt-hours. Compute the usable energy to the cut-off at each rate.
+ Return the pack to storage voltage (3.8 V per cell) and record it.

#done-when(
  [Pack and per-cell internal resistances are measured and the weakest cell identified.],
  [Two discharge curves are plotted with usable watt-hours and temperature rise at each rate.],
  [The notebook states the energy you will budget for flight, with its margin.],
)
#evidence([Cell table; discharge logs and plots; storage-voltage record.])
] <lab-battery>

#lab([Two power trees], goal: [specify the power systems you will build in Unit 3.], time: [5 h, paper and TI's parametric search])[
+ *Drone.* From the 3S pack: the four ESCs directly; 5 V at 3 A for the flight-controller LaunchPad, the radar, the telemetry radio and the receiver; 3.3 V for sensors. Add input protection, a current shunt with the INA228, and a battery-voltage divider for an ADC. Choose a TI buck for the 5 V rail, justify it with an efficiency estimate at 1 A, and draw the tree.
+ *Rack module.* From a 12 V bus: an eFuse at the input; 5 V at 4 A; 3.3 V at 6 A; a 1.8 V LDO at 0.5 A; and a 0.9 V core rail at 20 A. Choose TI parts for each stage, estimate losses at 85 % and 92 % converter efficiency, and total the heat.
+ For each tree state the power-up sequence, the telemetry points, and what fault each protection stage handles.

#done-when(
  [Both trees are drawn with part numbers, currents, efficiencies and losses at every node.],
  [Each choice cites the datasheet figure (efficiency curve, current limit, dropout) that justifies it.],
)
#evidence([The two trees as diagrams in the repository, with a parts table.])
] <lab-power-trees>

== Problem set

+ Derive the buck's duty cycle from volt-second balance on the inductor. Show why it is independent of load in continuous conduction and what changes in discontinuous conduction.
+ A buck converts 12 V to 1.0 V at 20 A at 400 kHz. Compute the duty cycle and explain why such a low duty cycle is hard. How do multiphase converters help?
+ An LDO with 60 dB of PSRR at 1 kHz and 20 dB at 1 MHz follows a buck with 20 mV of ripple at 1 MHz. What ripple reaches the output? What would you add?
+ Size the dV/dt ramp of an eFuse so that charging 2,200 µF draws no more than 1 A, and compute the energy the eFuse dissipates during the ramp from 0 to 12 V.
+ A three-cell pack with 6 mΩ per cell feeds four motors drawing 3 A each in hover and 15 A each at full throttle. Compute the voltage sag, the power lost in the pack, and the efficiency of delivery to the ESCs in both cases.
+ Explain why a pack's resting voltage after a flight overstates its charge if measured immediately, and how a gauge corrects for it.
+ Your drone's 5 V rail must ride through a 200 ms dip of the battery to 10 V when the motors spin up. Is a buck from the battery enough, or does the rail need a hold-up capacitor? Size it.
+ A rack module's 12 V eFuse trips at 20 A. The module draws 14 A in steady state and 26 A for 5 ms while its drives spin up. Propose two designs that avoid nuisance trips.

== Deliverables and stretch

*Deliverables.* The buck converter measurements as a report with plots; the protection captures; the battery characterisation with the flight-energy budget; the two power trees, which Chapter 3.4 turns into Board P and Board A.

*Stretch.* Measure the buck's loop gain by injecting a signal across a 10 Ω resistor in the feedback path with the function generator, and estimate crossover and phase margin. Read a TI fuel-gauge datasheet (for example BQ34Z100-R2) and design how the drone would use it.

#checklist(
  [*Lab 1.4.1:* efficiency and temperature table for the LM317 and the buck at two currents.],
  [*Lab 1.4.2:* duty-cycle sweep, ripple comparison, efficiency curve with the mode change marked, and a load-step capture.],
  [*Lab 1.4.3:* inrush with and without the eFuse, short-circuit response, reverse polarity, and the ideal-diode power comparison.],
  [*Lab 1.4.4:* per-cell resistance, two discharge curves, usable energy, and the pack left at storage voltage.],
  [*Lab 1.4.5:* both power trees with parts, losses, sequencing and telemetry points, committed.],
  [*Problem set:* all eight answered with units.],
  [*You can explain*, without notes: volt-second balance, where a buck's losses come from, why hot-plug needs an eFuse, and why a LiPo's voltage is a poor gauge under load.],
)
