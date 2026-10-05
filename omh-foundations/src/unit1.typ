#import "lib/template.typ": *
#show: course-doc.with(unit: "1", title: "Circuits, Sensors and Signals", short: "Circuits, Sensors and Signals",
  subtitle: "From electrons to measured, digitised and transmitted signals",
  chapters: ("Electricity, components and measurement", "The analogue signal chain", "Sensors with TI silicon", "Power conversion and batteries", "Signals on wires and RF fundamentals"))
#contents()

#about-unit(unit: "1",
  intro: [Unit 1 turns a software engineer into someone who can measure. It starts with Ohm's law and a meter and ends with link budgets checked against an SDR, by way of op-amps, filters and converters, five TI sensors driven from their register maps, a buck converter taken apart with a scope, and the drone's battery characterised to the watt-hour. Every later unit stands on these measurements: the thrust stand, the radio link, the boards and the BMC all reuse what you build here.],
  rows: (
    ([1.1], [A measured divider, RC charge, MOSFET switch and a decoupling failure you can see], [2]),
    ([1.2], [Op-amp stages, a filter with a Bode plot, a characterised ADC, a load cell on a 24-bit converter], [2]),
    ([1.3], [Library-free drivers and metrology for TI sensors; an error budget for the drone's current], [2.5]),
    ([1.4], [Converter, protection and battery measurements; the drone and rack power trees], [2.5]),
    ([1.5], [Reflections, S-parameters, a tuned antenna, an FM receiver, link budgets], [2.5]),
  ),
  before: [Work through the Handbook's setup checklist for the bench, the workstation and the Pi. The rest of the setup can wait for Unit 2.],
)

#include "u1/ch1-electricity.typ"
#include "u1/ch2-analogue.typ"
#include "u1/ch3-sensors.typ"
#include "u1/ch4-power.typ"
#include "u1/ch5-rf.typ"

#signoff(unit: "1",
  chapters: ("Electricity, components and measurement", "The analogue signal chain", "Sensors with TI silicon", "Power conversion and batteries", "Signals on wires and RF fundamentals"),
  review: (
    [At a whiteboard, trace the drone's battery-current measurement from the shunt to a number in software: every component, every term of your Lab 1.3.6 error budget, and which term dominates at hover and at full throttle.],
    [Explain from your Lab 1.1.4 captures why a decoupling capacitor belongs next to the pin, and predict what changes if every edge becomes ten times faster.],
    [For the ADS1115 and the ADS1220, state the resolution, the measured noise-free bits and the anti-alias filter you would need for a 1 kHz signal, from your own data.],
    [Draw the buck converter's switching loop and account for every loss in your measured efficiency curve.],
    [Close the 868 MHz link budget at 1 km from memory, and say what the fade margin must cover.],
  ),
)
