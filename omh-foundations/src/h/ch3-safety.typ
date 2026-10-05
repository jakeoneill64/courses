#import "../lib/template.typ": *

= Safety on the bench <h-safety>

Nothing in this course works at dangerous voltages on purpose. The hazards are stored energy (lithium-polymer packs and capacitors), heat (soldering irons, hot air and hot components), spinning propellers, and the mains equipment on the bench. The rules below apply to every chapter; individual labs add their own.

== Mains and the bench

- The only things plugged into the mains are bought, closed instruments and chargers: the bench supply, the electronic load, the oscilloscope, the generator, the soldering station, the charger, the computers. Never open one, and never build anything that connects to the mains.
- Use sockets protected by a residual-current device, and keep liquids off the bench.
- Set the bench supply's voltage and current limit before you connect anything, with the output off. For a first power-on, limit the current to a fraction of what you expect the circuit to draw.
- Check polarity with the multimeter before connecting any supply to a board. Most of the TI EVMs survive a reversed supply; most of your boards will not.
- Large capacitors hold their charge after power is removed. Discharge them through a resistor and confirm with the meter before you touch the circuit.

== Static

Work on the anti-static mat with the wrist strap connected, and keep boards in their bags when not in use. The radar, the synthesiser and the radio boards are the most sensitive in the kit, and an ESD failure can be partial: a board that still works, slightly worse, which ruins a measurement without telling you.

== Soldering, rework and chemicals

- A soldering tip runs at 300 to 400 °C and a hot-air nozzle at up to 500 °C. Return the iron to its stand every time you put it down, keep the hot-air handle in its cradle so it switches off, and let parts cool before you touch them.
- Hot air melts plastic connectors and lifts nearby parts; shield them with Kapton tape and practise on a scrap board first.
- Flux fumes irritate the lungs: work with a window open or a fume extractor drawing the plume away from your face.
- Leaded solder is easier to learn on and is used in this course for that reason. Wash your hands after soldering, do not eat at the bench, and keep it away from children. Anything OMH ships will use lead-free solder (Chapter 4.6).
- Isopropyl alcohol is flammable. Keep it closed and away from the iron and hot air.
- Wear safety glasses when you clip leads: offcuts fly.

== Lithium-polymer packs

The drone's 3S pack stores about 55 Wh and can deliver over 100 A into a short circuit. It is the most dangerous object in the kit. The British Model Flying Association's battery booklet is the basis for these rules.

- *Charging.* Use the balance charger in balance mode, constant current then constant voltage, to no more than 4.20 V per cell, at 1C (5 A for the 5,000 mAh pack) unless the maker allows more. Charge inside the LiPo bag on a non-flammable surface, never when the pack is hot or below 5 °C, and never unattended, while you sleep, or in an escape route.
- *Discharging.* Never go below 2.8 V per cell. Set every cut-off at 3.0 to 3.3 V per cell under load; this course lands the drone at 3.5 V per cell.
- *Storage.* Store at 3.6 to 3.8 V per cell (about 60 % charge), at 10 to 25 °C, in a vented metal box or the LiPo bag, never above 45 °C or in direct sunlight. The charger's storage mode does this.
- *Damage.* A pack that is puffed, hot, dented or crash-damaged is finished. Stop, disconnect, and move it to the fire-safe container outdoors if you can do so safely. Do not open it. Once it is cool and stable, discharge it slowly through a resistive load (never by shorting the leads), tape the connectors, label it, and take it to a household waste recycling centre.
- *Fire.* A lithium fire cannot be put out with a small extinguisher. Get out, close the door, and call the fire service.
- *Shipping.* Couriers restrict lithium batteries; check that the seller delivers them to your address before you order.

== Propellers and the test ladder

- Propellers come off for every bench test, firmware flash and wiring change, and go on only for a stand, rig, tether or flight test with a written test card.
- Wear safety glasses for every powered motor test, stand outside the plane of the propellers, and keep other people at least 5 m away.
- Check the kill switch disarms before every test, and test failsafe with propellers off.
- Climb the test ladder one rung at a time (simulation, bench, rig, tether, hover), and step back down when anything is unexplained. Chapter 3.5 describes the ladder in full.
- Fly in an open space over grass with nobody underneath.

== RF and microwave

The transmitters in this course are low power: 25 mW at most at 868 MHz and a few milliwatts at 60 GHz. The risk is to the instruments. Fit the 30 dB attenuator directly on a transmitter's output before connecting anything else, compute the level at the instrument before you connect it, and keep the tinySA below 0 dBm. Never connect a transmitter to the network analyser.

== The server

A 2U server weighs 20 to 30 kg: lift it with someone else or put it straight onto rails. It is loud and draws a few hundred watts; give it airflow, keep its lid on when running (the fans rely on it), and run it where the noise will not stop you working.
