#import "../lib/template.typ": *

= Electricity, components and measurement <ch-electricity>

#chapter-meta(
  weeks: [2 weeks],
  builds: [An LED circuit and a loaded divider explained by Thevenin; a fitted RC time constant; a characterised MOSFET switch with and without a flyback diode; a decoupling failure captured on the oscilloscope.],
  needs: [Bench kit (multimeter, oscilloscope, bench supply, breadboards, passives, discrete semiconductors, SN74HC04N and SN74HC14N, 12 V PWM fan).],
)

#why[
  Everything above this layer is an abstraction that leaks. A rack module is a power tree (a 12 V or 48 V bus feeding dozens of point-of-load rails), a thermal budget (every watt in is a watt of heat out) and a forest of decoupling capacitors that keep rails quiet while PCIe lanes switch at gigahertz. A quadcopter is the same problem with a battery instead of a bus and 60 A of motor current instead of a PSU. You will not design every converter yourself, but you will specify, review and debug them, and that needs the intuition this chapter builds.
]

#skip-test(
  rule: [If all five are easy, do Labs 1.1.3 and 1.1.4 only.],
  [A 3.3 V rail with 10 µF of decoupling sees a 2 A load step lasting 1 µs. How far does the rail dip, ignoring ESR and inductance? What if there is also 5 nH of trace inductance between the capacitor and the load?],
  [Why does an LED need a series resistor, while a resistor does not need a series LED?],
  [Explain, in terms of charge, why an I#super[2]C bus with a 10 kΩ pull-up cannot run at 400 kHz with 300 pF of bus capacitance.],
  [What does a 10× oscilloscope probe actually do, and why does grounding it at the wrong place show ringing that is not there?],
  [A MOSFET switches an inductive load off. Where does the stored energy go if there is no flyback diode?],
)

== Core ideas

*Voltage is energy per unit charge; current is charge per unit time.* Power is their product, $P = V I$. Every hardware design conversation returns to this: $P$ is the heat you must remove and $I$ is what your connectors, traces and wires must carry.

*Kirchhoff's laws are the real laws; Ohm's law is a material property.* The currents into a node sum to zero and the voltages around a loop sum to zero, because charge and energy are conserved. Resistors obey $V = I R$; diodes and transistors do not. Thevenin's theorem collapses any linear network seen from two terminals into one source $V_"th"$ behind one resistance $R_"th"$. That single number, $R_"th"$, answers the question every power and sensing design asks: how stiff is this node?

*A divider is a signal, not a supply.* Its output sags as soon as you draw current, in proportion to its Thevenin resistance (the two resistors in parallel). Sensing uses dividers; power uses regulators.

#fig("/figures/u1-thevenin.svg", caption: [A divider and its Thevenin equivalent. Loading the output with $R_L$ forms a second divider with $R_"th"$, which is why a 10 kΩ divider collapses under a 1 kΩ load.], width: 92%)

*Capacitors store charge and resist changes of voltage.* $I = C dif V \/ dif t$. An RC network has the time constant $tau = R C$; a step covers 63.2 % of its final value after one $tau$ and 99.3 % after five. Decoupling works because a capacitor next to a load is a local reservoir that supplies fast current before the distant regulator can respond. Its usefulness at high frequency is limited by its own series inductance (ESL) and resistance (ESR), which is why boards use many small capacitors close to the pins rather than one large one far away.

*Inductors store current and resist changes of current.* $V = L dif I \/ dif t$. Every wire and trace has inductance, roughly 1 nH per millimetre for a thin trace over a plane. A fast current step through a long return path produces a voltage spike (ground bounce); switching off an inductive load produces a spike large enough to destroy the switch unless something gives the current somewhere to go.

*Diodes conduct exponentially.* A small rise in forward voltage produces a large rise in current, so a diode or LED across a fixed voltage with no series resistor draws whatever the source will give. Rules of thumb: 0.6 to 0.7 V for silicon, 0.2 to 0.4 V for Schottky, 1.8 to 3.2 V for LEDs depending on colour. Schottky diodes are what you reach for in power paths for their low drop and fast recovery.

*A MOSFET is a voltage-controlled switch.* Above the threshold $V_"GS(th)"$ a channel forms; the on-resistance $R_"DS(on)"$ sets conduction loss $I^2 R$. The gate is a capacitor, so switching it takes charge and time, and during the transition the device is neither on nor off and dissipates heavily. Switching loss scales with frequency; conduction loss does not. A "logic-level" MOSFET is fully on at 3.3 or 5 V of gate drive; many are not. Read the $R_"DS(on)"$ against $V_"GS"$ curve, never the headline number.

*Open-drain outputs and pull-ups let many devices share a wire.* Any device may pull low; a resistor pulls high when nobody does. The rise time is the pull-up resistance times the bus capacitance, and it caps the bus speed. I#super[2]C, SMBus, PMBus, interrupt and reset lines on every board you will build work this way.

*Real sources have internal resistance.* A USB port, a bench supply, a lithium-polymer pack and a server PSU are all Thevenin sources. The droop under a steady load and the dip under a step tell you their effective source impedance. A drone battery's internal resistance decides how far its voltage sags when four motors spin up at once.

*Measurement changes the circuit.* A multimeter reports averages and lies about anything fast. An oscilloscope probe adds 10 pF or more of capacitance, and its 15 cm ground lead is an inductor that rings with that capacitance near 100 MHz. A 10× probe divides the signal by ten and presents ten times the impedance of a 1× probe. Ground at the nearest ground to your signal with the shortest lead you have, using the spring tip for fast edges.

*Heat.* Every component has a thermal resistance from junction to ambient, $theta_"JA"$ in kelvin per watt. Temperature rise is $P theta_"JA"$: a 2 W part with $theta_"JA" = 60$ K/W runs 120 K above ambient and fails. Copper pours, thermal vias, heatsinks and airflow reduce $theta_"JA"$. Rack modules are thermal designs first, and so are motor drivers.

#fig("/figures/u1-decoupling.svg", caption: [Why decoupling capacitors go next to the pins. Left: the loop a load-step current takes. Right: the impedance of one 10 µF ceramic and of ten 1 µF ceramics, each with realistic ESL and ESR. Above its self-resonant frequency a capacitor is an inductor.])

== Reading

- Horowitz and Hill, _The Art of Electronics_, 3rd ed.: chapter 1 (all), sections 3.1 to 3.5 (FETs as switches).
- Scherz and Monk, _Practical Electronics for Inventors_, chapters 2 to 4, for a gentler first pass if AoE is too dense.
- One decoupling-placement application note from TI or Analog Devices (search either site for "decoupling capacitor placement"). Read it once now and again before your first layout.
- Falstad circuit simulator: reproduce every lab in simulation before building it, and keep the simulation link in your notebook.

== Labs

#lab([Divider, LED and the meaning of stiffness], goal: [feel the difference between a signal and a supply.], time: [3 h])[
+ Compute the series resistor for a red LED at 10 mA from 5 V, using the forward voltage from its datasheet. Build it on the breadboard from the bench supply. Measure the voltage across the LED and across the resistor; compute the actual current; compare with your prediction.
+ Build a 2:1 divider from two 10 kΩ resistors on 5 V. Predict, then measure, the output unloaded, with a 10 kΩ load and with a 1 kΩ load.
+ Repeat with two 100 Ω resistors. Compute how much power the divider itself wastes in each case.
+ Measure the bench supply's output impedance: record its voltage at no load and at 500 mA into a power resistor, with the current limit set to 1 A. Repeat at a USB port with a USB load tester or a resistor on a breakout.

#done-when(
  [Predicted and measured values agree within resistor tolerance (5 %) for every divider case.],
  [The 1 kΩ case is explained in the notebook with a drawn Thevenin equivalent and a one-line calculation.],
  [The bench supply's and the USB port's effective source resistances are computed from your two measurements each.],
)
#evidence([A table of predicted and measured values with the percentage error per row.], [Photographs of the breadboard and the meter for the LED case.])
] <lab-divider>

#lab([RC charging and a threshold crossing], goal: [own $tau = R C$ and the oscilloscope's single-shot trigger.], time: [3 h])[
+ Build an RC network (10 kΩ, 10 µF) driven by a push button from 5 V, with a 100 kΩ discharge resistor across the capacitor. Capture the charge curve on the oscilloscope in single-shot mode, triggered on the rising edge.
+ Fit $tau$ from the capture using the cursors at 63.2 % and by fitting the exponential to exported data in Python. Compare with $R C$ and explain any discrepancy (electrolytic capacitors are often −20 %/+80 %).
+ Predict the time to cross 2.0 V, a common logic-high threshold, and measure it.
+ Change $R$ to 1 kΩ and repeat. Then capture the discharge curve and fit it.

#done-when(
  [Your fitted $tau$ is within 20 % of $R C$ and the notebook explains the error with the capacitor's tolerance and the meter's measurement of $C$.],
  [The measured 2.0 V crossing time is within 10 % of your prediction from the fitted $tau$.],
)
#evidence([Scope captures of charge and discharge, the exported CSV and the Python fit.])
] <lab-rc>

#lab([The MOSFET as a switch], goal: [understand conduction loss, switching loss and the inductive kick.], time: [4 h])[
+ Drive a 12 V fan from a 2N7000 and then from a TI CSD18534KCS (low-side switch, source to ground), with the gate driven by an NE555P astable at about 1 kHz. Measure $V_"DS"$ while on and compute $R_"DS(on)"$ and the conduction loss for each transistor.
+ Add a 10 kΩ resistor in series with the gate. Capture gate and drain voltages together. Measure the transition time and estimate the switching energy as the area under $V_"DS" times I_D$ during the transition.
+ Capture the drain at turn-off without a flyback diode, then with a 1N5819 across the fan. Measure the peak voltage in each case and explain it with $V = L dif I \/ dif t$.

#safety[The turn-off spike without a diode can exceed the 2N7000’s 60 V rating. Keep the run short, use the CSD18534KCS for this step and switch the supply off between changes.]

#done-when(
  [Your notebook says which transistor is logic-level at 5 V of gate drive and shows the $R_"DS(on)"$ curve from its datasheet that proves it.],
  [Two captures show the turn-off spike with and without the diode, with peak voltages labelled.],
  [Conduction and switching losses are computed for both transistors at 1 kHz and extrapolated to 100 kHz.],
)
#evidence([Scope captures with both channels labelled; the loss calculation.])
] <lab-mosfet>

#fig("/figures/u1-mosfet.svg", caption: [Low-side switch for an inductive load. Without the flyback diode the drain voltage at turn-off is whatever $L dif I \/ dif t$ demands; with it, the current circulates through the diode and decays.], width: 96%)

#lab([Decoupling failure, seen], goal: [see why the capacitors are there.], time: [3 h])[
+ Build a fast square-wave source from an SN74HC14N (Schmitt inverter oscillator) driving a few hundred picofarads, powered through a pair of 50 cm breadboard wires from the bench supply. Fit no decoupling.
+ Probe the supply at the IC's power pin with the spring ground tip. Record the peak-to-peak noise.
+ Add a 100 nF ceramic directly across the IC's supply pins and record again. Then add a 10 µF electrolytic at the supply end of the long wires and record.
+ Move the 100 nF capacitor to the far end of the wires and record. Explain the difference in terms of the inductance between the capacitor and the pin.

#done-when(
  [Three captures show the rail noise falling as decoupling is added, each with its peak-to-peak value.],
  [One capture shows that a capacitor 50 cm away barely helps, and the notebook estimates the inductance of the wires from the ringing frequency.],
)
#evidence([Four captures at the same vertical scale; your inductance estimate.])
] <lab-decoupling>

== Problem set

+ Derive the RC step response from $I = C dif V \/ dif t$ and Ohm's law. Show where 63.2 % comes from.
+ A load steps by 3 A in 50 ns on a 1.0 V rail that may dip at most 30 mV. Ignoring inductance, how much decoupling capacitance is needed? Now add 2 nH between the capacitor and the load and compute the inductive dip alone. What does this tell you about where the capacitors go?
+ An I#super[2]C bus has 250 pF of capacitance and needs a rise time (30 % to 70 %) under 300 ns for Fast-mode. What is the largest pull-up allowed? What is the smallest, given a 3 mA sink limit at 3.3 V?
+ A power MOSFET with $R_"DS(on)" = 25$ mΩ switches 10 A at 100 kHz with 50 ns transitions between 12 V and 0 V. Estimate conduction and switching loss. Which dominates, and what happens at 1 MHz?
+ A server's 12 V rail has 4,700 µF of bulk capacitance. A hot-swapped drive draws 4 A for 2 ms while its regulators start. How far does the rail dip if the PSU cannot respond in that time? Why do hot-swap controllers exist?
+ A 3S lithium-polymer pack reads 12.4 V at rest and 11.2 V while four motors draw 40 A. What is its internal resistance, how much power is lost inside the pack, and what does that do to the pack's temperature over a five-minute flight?
+ Explain why an SN74HC output driving a 1 m cable rings, and what a 33 Ω series resistor at the source does.
+ A USB port is specified at 5 V with up to 500 mA and up to 0.35 V of droop. What is its effective source resistance? What is the largest load step it can handle with a dip under 100 mV, given 10 µF at the load?

== Deliverables and stretch

*Deliverables.* The notebook with predictions, measurements and captures for all four labs, and a one-page "power and decoupling" cheat sheet in your own words. You will reuse the cheat sheet in every board design review in Unit 3.

*Stretch.* Simulate Lab 1.1.4 in ngspice with a capacitor model that includes ESL and ESR, and plot impedance against frequency for one 10 µF capacitor against ten 1 µF capacitors. Build a current-limited hot-swap circuit with a P-channel MOSFET, a sense resistor and a comparator, and capture the controlled inrush.

#checklist(
  intro: [Tick each line and date it. Do not start Chapter 1.2 until every line holds.],
  [*Lab 1.1.1:* divider table complete with errors under 5 %; Thevenin drawing for the 1 kΩ case; two source resistances computed.],
  [*Lab 1.1.2:* fitted $tau$ within 20 % of $R C$ for both resistor values, with the Python fit committed to the labs repository.],
  [*Lab 1.1.3:* logic-level verdict for both MOSFETs with the datasheet curve; turn-off captures with and without the diode.],
  [*Lab 1.1.4:* four rail-noise captures at one scale; the far-capacitor case explained with an inductance estimate.],
  [*Problem set:* all eight answered in writing with units, and each numeric answer checked by a second method or a simulation.],
  [*Cheat sheet* written and committed.],
  [*You can explain*, without notes: Thevenin equivalence, why $tau = R C$ gives 63 %, why switching loss scales with frequency, and why a decoupling capacitor's position matters more than its value.],
)
