# Module 1: Electricity and components

**Part I · 2 weeks · Needs: Core tier kit. A scope makes this module far better.**

## Why this module (and what it buys OMH)

Everything above this layer is an abstraction that leaks. A rack module is a power tree
(48 V or 12 V bus to dozens of point-of-load rails), a thermal budget (every watt in is a
watt of heat out), and a forest of decoupling capacitors keeping supply rails quiet
while PCIe lanes switch at gigahertz. Hot-swap bays need controlled inrush. Drive
failures often start as power events. You will not design the buck converters on an OMH
board, but you will review them, debug them and specify them, and that requires the
intuition this module builds.

## Skip test

Answer cold, in writing.

1. A 3.3 V rail with 10 µF of decoupling sees a 2 A load step lasting 1 µs. How far does
   the rail dip, ignoring ESR and inductance? What if there is also 5 nH of trace
   inductance between the capacitor and the load?
2. Why does an LED need a series resistor but a resistor does not need a series LED?
3. A linear regulator drops 12 V to 3.3 V at 1.5 A. Where does the energy go, how much
   per second, and roughly what temperature rise does that imply for a TO-220 with no
   heatsink?
4. Explain, in terms of charge, why an I2C bus with a 10 kΩ pull-up cannot run at
   400 kHz with 300 pF of bus capacitance.
5. What does a 10× scope probe actually do, and why does grounding the probe at the
   wrong place show you ringing that is not there?

If all five are easy, do Labs 1.4 and 1.5 only.

## Core ideas

**Voltage is energy per unit charge; current is charge per unit time.** Power is their
product. Every design conversation in hardware eventually returns to this: P = VI is the
heat you must remove and the current your connectors and traces must carry.

**Ohm's law is a material property, not a law of nature.** Resistors obey it; diodes and
transistors do not. Kirchhoff's laws (currents into a node sum to zero; voltages around
a loop sum to zero) are the actual laws, and they follow from conservation of charge and
energy. Thevenin equivalence lets you collapse any linear network into one source and
one resistor, which is how you reason about "how stiff is this rail".

**A voltage divider is a signal, not a supply.** Its output sags as soon as you draw
current, in proportion to its Thevenin resistance. This is why sensing uses dividers
and power uses regulators.

**Capacitors store charge and resist voltage change.** I = C·dV/dt. The RC time
constant τ = RC is when a step has covered 63%. Decoupling works because a capacitor
near the load is a local charge reservoir that supplies fast current demand before the
distant supply can respond. Its usefulness at high frequency is limited by its own
series inductance (ESL) and resistance (ESR), which is why boards use many small caps
close to pins rather than one big one far away.

**Inductors store current and resist current change.** V = L·dI/dt. Every wire and trace
has inductance, roughly 1 nH per millimetre for a thin trace over a plane. This is why
a fast current step through a long ground return produces a voltage spike ("ground
bounce") and why decoupling caps must be physically close to the pins they serve.

**Diodes conduct exponentially.** A tiny increase in forward voltage produces a large
increase in current, so a diode (or LED) across a fixed voltage without a series
resistor draws unbounded current. The forward drop (0.7 V silicon, 0.3 V Schottky,
2 to 3 V for LEDs) is a useful rule of thumb, and Schottky diodes are what you reach for
in power paths because of the lower drop and fast recovery.

**A MOSFET is a voltage-controlled switch.** Gate voltage above threshold (V_GS(th))
forms a channel; on-resistance R_DS(on) sets conduction loss (I²R). The gate is a
capacitor, so switching it takes charge and time, and during the transition the device
is neither on nor off and dissipates heavily. Switching loss scales with frequency;
conduction loss does not. "Logic-level" MOSFETs turn fully on at 3.3 V or 5 V; many do
not. Read the datasheet's R_DS(on) versus V_GS curve, not the headline number.

**Open-drain outputs and pull-ups let many devices share a wire.** Any device can pull
low; the resistor pulls high when nobody does. The rise time is the pull-up's RC with
the bus capacitance, which caps the bus speed. I2C, interrupt lines, reset lines and
SMBus on servers all work this way.

**Regulators: linear versus switching.** A linear regulator is a variable resistor in
series with the load; the dropped voltage times the current is pure heat, and
efficiency is V_out/V_in. A switching regulator moves energy in packets through an
inductor and capacitor, so efficiency can exceed 90%, at the cost of noise, complexity
and layout sensitivity. A server has both: bucks for the heavy rails, LDOs for quiet
analog and PLL supplies.

**Real sources have internal resistance.** A USB port, a bench supply, a battery and a
server PSU are all Thevenin sources. Voltage droop under load and the size of the
transient dip tell you the effective source impedance.

**Measurement changes the circuit.** A multimeter measures averages, so it lies about
anything fast. A scope probe adds capacitance (10 pF or more), and its ground lead is an
inductor; a 10× probe divides the signal and presents higher impedance. Ground at the
nearest ground to your signal, and use the shortest possible lead for fast edges.

**Heat.** Every component has a thermal resistance from junction to ambient (θJA, in
K/W). Temperature rise is P × θJA. A 2 W part with θJA of 60 K/W runs 120 K above
ambient and dies. Copper pours, thermal vias, heatsinks and airflow reduce θJA. Rack
modules are thermal designs first.

## Reading

- Horowitz and Hill, *The Art of Electronics*, 3rd ed., ch. 1 (all), ch. 3 sections
  3.1 to 3.5 (FETs as switches), ch. 9 sections 9.1 to 9.3 and 9.6 (regulators).
- Scherz and Monk, *Practical Electronics for Inventors*, ch. 2 to 4 for a gentler pass
  if AoE is too dense on first reading.
- Falstad circuit simulator: reproduce every lab in simulation before building it.
- Any TI or Analog Devices application note on decoupling capacitor placement, for
  example TI SLVA 1176 "Basics of power supply decoupling".

## Labs

### Lab 1.1: Divider, LED, and the meaning of stiffness

Goal: feel the difference between a signal and a supply.

1. Compute the series resistor for a red LED at 10 mA from 5 V. Build it. Measure the
   voltage across the LED and the resistor; compute the actual current; compare.
2. Build a 2:1 divider from two 10 kΩ resistors on 5 V. Measure the output unloaded, then
   with a 10 kΩ load, then 1 kΩ. Predict each before measuring.
3. Repeat with 100 Ω resistors. Note how much current the divider itself wastes.

Done when: predicted and measured values agree within resistor tolerance, and your
notebook explains the 1 kΩ case with a Thevenin equivalent.

### Lab 1.2: RC charging and a threshold crossing

Goal: own τ = RC.

1. Build an RC (10 kΩ, 10 µF) driven by a pushbutton from 5 V. Capture the charge curve
   on the scope in single-shot mode (or sample it with a Pico ADC if no scope yet).
2. Fit τ from the capture. Compare to the computed value; explain any discrepancy with
   electrolytic capacitor tolerance.
3. Predict the time to cross 2.0 V (a common logic-high threshold). Measure it.
4. Change R to 1 kΩ and repeat. Then measure the discharge curve.

Done when: fitted τ is within 20% of computed and you can explain why it is off.

### Lab 1.3: MOSFET as a switch

Goal: understand switching and conduction loss.

1. Drive a 12 V fan from a 2N7000 (then an IRLZ44N) with a 3.3 V or 5 V gate signal from
   a 555 astable at about 1 kHz. Measure V_DS when on for each; compute R_DS(on) and
   conduction loss.
2. Add a 10 kΩ resistor in series with the gate. Scope the gate voltage and the drain
   voltage together. Measure the transition time. Estimate switching loss as the area
   under the V·I curve during the transition.
3. Put a flyback diode across the fan and scope the drain at turn-off with and without
   it. Explain the spike from V = L·dI/dt.

Done when: you can say which MOSFET is logic-level and why, and your notebook has the
turn-off spike with and without the diode.

### Lab 1.4: Decoupling failure, seen

Goal: see why the caps are there.

1. Build a ring oscillator or a fast square-wave source from a 74HC04 or 74HC14 driving
   a few hundred pF of load, powered from a long pair of breadboard wires to the bench
   supply. Do not add any decoupling.
2. Scope the supply rail at the IC's power pin with the shortest possible ground lead.
   Record the peak-to-peak noise.
3. Add a 100 nF ceramic directly across the IC's supply pins. Record again. Then add a
   10 µF electrolytic at the supply end of the long wires. Record.
4. Move the 100 nF to the far end of the wires. Record. Explain the difference in terms
   of the inductance between the capacitor and the pin.

Done when: you have three captures showing the rail noise falling, and one showing that
a far-away capacitor barely helps.

### Lab 1.5: Regulators and where the heat goes

Goal: compare linear and switching regulation with numbers.

1. Build a crude linear regulator: Zener reference plus an NPN pass transistor. Load it
   to 200 mA. Measure V_in, V_out, I; compute dissipation in the transistor; feel it.
2. Measure an AMS1117-3.3 LDO module and an MP1584 buck module from 12 V to 3.3 V at
   0.5 A. For each, measure input power and output power; compute efficiency; use a
   thermocouple or your finger to compare heat.
3. Scope the buck's output ripple and switching node. Identify the switching frequency.
   Add a 10 µF ceramic at the output and re-measure ripple.
4. Sketch the power tree for a hypothetical rack module: 12 V bus into a 5 V buck, a
   3.3 V buck, a 1.8 V LDO, a 0.9 V core buck at 20 A. Estimate the loss at each stage
   and the total heat at 80% efficiency versus 92%.

Done when: your notebook has an efficiency table for the three regulators and the
power-tree sketch with loss estimates.

## Problem set

1. Derive the RC step response from I = C·dV/dt and Ohm's law. Show where 63% comes from.
2. A 5 V to 3.3 V LDO at 1 A: dissipation, efficiency, and the temperature rise in a
   SOT-223 package with θJA = 55 K/W. Is it viable without a heatsink or copper pour?
3. A load steps by 3 A in 50 ns on a 1.0 V rail that may dip at most 30 mV. Ignoring
   inductance, how much decoupling capacitance is needed? Now add 2 nH between the
   capacitor and the load and compute the inductive dip alone. What does this tell you
   about where the capacitors go?
4. An I2C bus has 250 pF of capacitance and needs a rise time (30% to 70%) under 300 ns
   for Fast-mode. What is the largest pull-up resistor allowed? What is the smallest,
   given a 3 mA sink limit at 3.3 V?
5. An IRLZ44N with R_DS(on) = 25 mΩ switches 10 A at 100 kHz with 50 ns transitions
   between 12 V and 0 V. Estimate conduction loss and switching loss. Which dominates,
   and what happens at 1 MHz?
6. A server's 12 V rail has 4,700 µF of bulk capacitance. A hot-swapped drive draws
   4 A for 2 ms as it spins up its regulators. How far does the rail dip if the PSU
   cannot respond within that time? Why do hot-swap controllers exist?
7. Explain why a 74HC output driving a 1 m cable rings, and what a 33 Ω series resistor
   at the source does.
8. A USB port is specified at 5 V with up to 500 mA and up to 0.35 V of droop. What is
   its effective source resistance? What is the largest load step it can handle with a
   dip under 100 mV, given 10 µF at the load?

## Deliverables

- Notebook with predictions, measurements and captures for all five labs.
- A one-page "power and decoupling" cheat sheet in your own words. You will reuse it in
  Module 14's design review.

## Stretch

- Simulate Lab 1.4 in ngspice with a realistic capacitor model (C, ESL, ESR) and show
  the impedance-versus-frequency curve for one 10 µF cap versus ten 1 µF caps.
- Build a current-limited hot-swap circuit with a P-MOSFET, a sense resistor and a
  comparator, and show the controlled inrush on the scope.

## Next

Module 2 turns voltages into bits. The noise margins you meet there are the reason this
module cared about rail quality.
