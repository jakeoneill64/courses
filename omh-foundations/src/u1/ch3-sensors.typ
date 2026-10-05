#import "../lib/template.typ": *

= Sensors with TI silicon <ch-sensors>

#chapter-meta(
  weeks: [2.5 weeks],
  builds: [Library-free drivers for five TI sensors; a temperature and humidity metrology rig checked against a salt reference; a calibrated power monitor; a magnetic angle sensor; an optical time-of-flight rangefinder; a written error budget for the drone's battery-current measurement.],
  needs: [Raspberry Pi 5, logic analyser, Qwiic cables, the TMP117, humidity, INA228 and TMAG5273 breakouts, the Pololu OPT3101 module, the multimeter's K-type thermocouple.],
)

#why[
  A baseboard management controller is mostly a sensor hub: inlet and component temperatures, rail voltages, currents and power, fan speeds, intrusion and position switches. A drone is the same hub with an IMU attached. Every one of these readings arrives as a register on a bus, with an accuracy the datasheet states under conditions your board may not meet. This chapter teaches you to read a sensor datasheet critically, write the driver from the register map, and say how wrong the number on the screen can be.
]

#skip-test(
  rule: [If all five are easy, do Labs 1.3.3 and 1.3.6 only.],
  [A temperature sensor quotes ±0.1 °C accuracy and 7.8 m°C resolution. Explain the difference and give one way the reading can still be 1 °C wrong on your board.],
  [Write the I#super[2]C transaction (start, address, R/W, register pointer, repeated start, data, ACK and NACK) that reads a 16-bit register from a device at address 0x48.],
  [Compute the shunt calibration value for an INA228 with a 1 mΩ shunt and a maximum current of 40 A.],
  [Why can a 3D Hall-effect position sensor not serve as a drone's compass?],
  [An optical time-of-flight sensor modulates its light at 10 MHz and measures a phase shift of 0.6 rad. How far away is the target, and what is the largest distance it can report without ambiguity?],
)

== Core ideas

*A sensor is a transfer function plus errors.* The datasheet gives the ideal relationship between the physical quantity and the output code, then the deviations: offset, gain error, nonlinearity, hysteresis, noise, drift with temperature and time, and response time. *Resolution* is the smallest change the output can show; *precision* (repeatability) is how much repeated readings scatter; *accuracy* is how close the reading is to the truth. A 16-bit sensor can be precise to a millikelvin and inaccurate by a whole kelvin. Datasheets give "typical" values (half of parts are worse) and "maximum" values (guaranteed, usually over a stated range of temperature and supply). Design to the maximums.

*Errors combine.* Independent random errors add as the root of the sum of squares; correlated and systematic errors add linearly. An error budget lists every term with its source and its magnitude in the measurement's units, then totals them both ways. The largest term is the only one worth spending money on.

*Calibration removes what is repeatable.* A one-point calibration removes offset; two points remove offset and gain; more points expose nonlinearity. Calibration cannot remove noise, hysteresis or drift that has not happened yet, and every calibration is only as good as its reference.

*The bus.* Most of the sensors in this course speak I#super[2]C: an open-drain clock and data line with pull-ups (Chapter 1.1), 7-bit addresses, a write of a register pointer followed by a repeated start and a read. Devices may stretch the clock, NACK a bad address, or hang the bus mid-byte if a master resets halfway through a transaction; a robust driver detects a stuck data line and clocks it free. SPI is faster and simpler: chip select, clock, and data in each direction, in one of four clock modes. On Linux, `/dev/i2c-1` and `/dev/spidev0.0` expose the buses to userspace, and `i2cdetect`, `i2ctransfer` and `spi-pipe` let you talk to a part before you write any code.

#fig("/figures/u1-i2c-read.svg", caption: [Reading a 16-bit register over I#super[2]C: write the register pointer, repeated start, read two bytes, NACK the last. Lab 1.3.1 asks you to find every one of these features in a logic-analyser capture.])

*Temperature: silicon bandgap sensors.* A transistor's base-emitter voltage falls by about 2 mV per kelvin; the difference between two transistors at different current densities is proportional to absolute temperature. TI's TMP117 digitises that difference to 7.8125 m°C per LSB and is trimmed and tested to ±0.1 °C from −20 to +50 °C. The sensor measures its own die. On your board the die sits between the air you care about and the copper you do not, so placement, airflow and the sensor's own dissipation (self-heating) decide the real accuracy. A first-order thermal model, a time constant $tau$ and an offset from self-heating, describes most of what you will see.

*Humidity: capacitive polymer sensors.* A thin polymer absorbs water and changes the capacitance of an interdigitated electrode. TI's HDC3022 pairs that with a temperature sensor behind a PTFE filter, because relative humidity is meaningless without the temperature it was measured at. Its errors are offset after exposure to high humidity or contaminants, slow response, and condensation; an on-chip heater drives off moisture. Saturated salt solutions give laboratory-grade references for free: sodium chloride holds the air above it at about 75 % RH over a wide temperature range.

*Light: photodiodes with a shaped response.* TI's OPT4048 filters four photodiodes to the CIE X, Y and Z colour-matching responses and a wide channel, auto-ranges over many decades, and reports each channel as an exponent and mantissa. Its errors are angular response, infrared leakage and the window you put in front of it. Linux has no driver for it, so Chapter 4.3 has you write one.

*Magnetic: the Hall effect.* A current through a semiconductor in a magnetic field develops a transverse voltage proportional to the field. TI's TMAG5273 measures all three axes over ±40 or ±80 millitesla (the A1 variant) and computes the angle of a magnet in hardware. Earth's field is 25 to 65 microtesla. The A1’s resolution of 1.2 µT per count would see it, but its noise (22 µT RMS on X and Y even with 32× averaging) and its offset (±300 µT typical) are larger than the field itself, so a Hall sensor measures magnets and positions. Compasses use magnetoresistive parts, which Chapter 3.1 adds to the drone.

*Current and power: shunts and Kelvin connections.* A current through a small resistor develops a small voltage; a precise differential ADC measures it. TI's INA228 measures the shunt voltage (±163.84 mV or ±40.96 mV range) with a 20-bit delta-sigma converter, measures the bus voltage up to 85 V, multiplies them, and accumulates energy and charge in 40-bit registers. Its accuracy is limited by the shunt more often than by the chip: the shunt's tolerance, its temperature coefficient, the voltage drop in the copper between the shunt and the sense pins (which Kelvin, or four-wire, connections remove), and its self-heating at high current. The power the shunt wastes, $I^2 R$, sets how small it must be; the INA228’s offset sets how small it can be.

#fig("/figures/u1-shunt.svg", caption: [Measuring battery current with an INA228. The sense lines leave the shunt's pads directly (Kelvin connection) so the copper carrying 60 A does not add its drop to the 30 mV you are measuring.], width: 94%)

*Distance: time of flight.* Distance is half the round trip times the propagation speed. Ultrasonic sensors such as TI's PGA460 time an acoustic echo, so their answer depends on the speed of sound, which varies by about 0.6 m/s per kelvin. Optical sensors such as TI's OPT3101 modulate an infrared LED and measure the phase $phi$ of the returned light: $d = c phi \/ (4 pi f_"mod")$, unambiguous up to $c \/ (2 f_"mod")$. Their errors come from ambient light, the target's reflectivity, multipath and crosstalk inside the module, which is why they need calibration. Millimetre-wave radar (Chapter 3.3) measures the same round trip as a frequency.

*Inertial sensors, previewed.* MEMS accelerometers and gyroscopes are the drone's most important sensors and TI does not make them; Chapter 3.1 uses ST's LSM6DSOX. Everything in this chapter applies to them: noise density, bias and its temperature drift, scale-factor error, and calibration.

== Reading

- The datasheets for TMP117, HDC3022 (or the SHT45 if you bought it), INA228, TMAG5273 and OPT3101. Read each one completely before its lab: the electrical characteristics table, the typical performance graphs, the register map and the application section.
- NXP, UM10204 _I#super[2]C-bus specification and user manual_ (free), sections 3 (timing and electrical) and 3.1.16 (bus clear).
- Fraden, _Handbook of Modern Sensors_, 5th ed., chapters 2 (transfer functions), 3 (characteristics) and the chapters for temperature, humidity, magnetic and distance sensing.
- One TI application note on shunt-based current-sensing error analysis (search ti.com for "current sense amplifier error analysis") and the INA228 datasheet's application section on shunt selection.
- Linux `Documentation/i2c/dev-interface.rst` for the userspace I#super[2]C interface.

== Labs

All labs run on the Raspberry Pi 5 in Python 3 with `smbus2` and `spidev` only. No sensor library from the vendor or from Adafruit: you write each driver from the register map, and only afterwards compare it with someone else's.

#lab([Bus bring-up and a driver from the datasheet], goal: [see a register read on the wire and write a correct driver.], time: [4 h], kit: [Pi 5, TMP117 breakout, Qwiic cables, logic analyser.])[
+ Enable I#super[2]C on the Pi, connect the TMP117, and find it with `i2cdetect -y 1`. Read the device ID register (0x0F) with `i2ctransfer` and confirm it reads 0x0117.
+ Capture the transaction with the logic analyser and annotate start, address, ACK, register pointer, repeated start, data and NACK.
+ Write `tmp117.py`: read temperature (two's complement, 7.8125 m°C per LSB), set conversion cycle and averaging, start one-shot conversions, and set the high and low alert limits.
+ Wire the ALERT pin to a Pi GPIO and use `gpiomon` (or `gpiod` in Python) to log an event when you warm the sensor between your fingers past the high limit.
+ Unplug the sensor in the middle of a read loop and make your driver report a clear error and recover when it is reconnected.

#done-when(
  [The annotated capture shows every element of the transaction in the figure above.],
  [Your driver's readings match `i2ctransfer` decoded by hand for at least three temperatures.],
  [The alert reaches the GPIO and is logged with a timestamp.],
  [Unplugging and reconnecting does not crash the program or hang the bus.],
)
#evidence([Annotated capture; driver source with docstrings citing datasheet sections; log of the alert event.])
] <lab-tmp117>

#lab([Temperature and humidity metrology], goal: [measure accuracy, self-heating, response time and a humidity reference.], time: [6 h], kit: [TMP117 and humidity breakouts, the multimeter's thermocouple, a sealed jar or food container, table salt, a small dish.])[
+ Write a driver for your humidity sensor (`hdc3022.py`, or `sht45.py` for the alternative), including the CRC-8 check on every word the device returns. Reject readings whose CRC fails and count them.
+ Place the TMP117, the humidity sensor and the thermocouple bead together in still air for 30 minutes. Log all three every 10 s and compute the differences and their scatter.
+ Self-heating: run the TMP117 in continuous conversion with no averaging, then in one-shot mode once a minute. Compare the steady readings.
+ Response time: move the sensor pair from room air into a warm airflow (a desk fan blowing over a warm, not hot, surface) and back. Fit a first-order response to each step and report $tau$ for each sensor.
+ Humidity reference: make a slurry of salt and a little water in a dish inside a sealed container with the humidity sensor. Log for 12 hours. The equilibrium should be about 75 % RH. Report the offset and how long equilibrium took.
+ Run the sensor's heater for 10 s and log the effect on both its readings.

#done-when(
  [The three temperature readings agree within the sum of their stated accuracies, or the notebook explains the disagreement.],
  [Self-heating is quantified in millikelvin and the two time constants are fitted from data.],
  [The salt test gives the humidity sensor's offset at 75 % RH with the equilibrium curve plotted.],
)
#evidence([Logs as CSV; plots of the drift, step responses and salt test; the fitted parameters.])
] <lab-metrology>

#lab([Power metrology with the INA228], goal: [measure current, voltage, power and energy, and know the error.], time: [4 h], kit: [INA228 breakout, the 12 V fan, bench supply, multimeter, power resistors.])[
+ Write `ina228.py`: compute CURRENT_LSB and SHUNT_CAL for the breakout's shunt and a 2 A maximum, configure conversion time and averaging, and read shunt voltage, bus voltage, current, power, energy and charge.
+ Put the fan and then a 5 Ω power resistor in series with the shunt. Compare the INA228’s current and voltage with the multimeter at five operating points.
+ Accumulate energy for ten minutes while the fan runs at three PWM duties (reuse Lab 1.1.3’s switch). Compare with power × time from your own sampling.
+ Configure the shunt-overcurrent alert and show it firing on the Pi GPIO when you stall the fan by hand (gently, with a gloved finger on the hub).
+ Measure the shunt's actual resistance with the four-wire method (a known current from the bench supply and the multimeter across the shunt pads) and recompute your calibration.

#done-when(
  [Current agrees with the multimeter within 1 % at every point above 100 mA, after calibrating with the measured shunt value.],
  [The energy accumulator and your integrated power agree within 2 %.],
  [The overcurrent alert fires within one conversion period of the stall.],
)
#evidence([Calibration arithmetic; comparison table; energy plot; alert log.])
] <lab-ina228>

#lab([Magnetic angle with the TMAG5273], goal: [measure an angle without contact, and prove the compass limit.], time: [3 h], kit: [TMAG5273 breakout, a diametrically magnetised disc magnet, a protractor or printed angle scale, the 12 V fan or a hobby servo.])[
+ Write `tmag5273.py`: enable X, Y and Z, set the range, read the three axes in millitesla and the on-chip angle result.
+ Fix the magnet to a shaft above the sensor. Rotate it in 15° steps against the printed scale. Plot the sensor's angle against the true angle and fit the error.
+ Move the magnet 2 mm further away and repeat. Explain the change in field magnitude and in angle error.
+ Remove all magnets and log the field for a minute while you rotate the board. Compute the noise and compare it with Earth's field.

#done-when(
  [The angle error is under 2° RMS at the nominal spacing.],
  [The notebook shows numerically why the sensor cannot be a compass.],
)
#evidence([Angle-error plot at two spacings; noise log.])
] <lab-tmag>

#lab([Optical time of flight with the OPT3101], goal: [measure distance by phase and see what calibration fixes.], time: [5 h], kit: [Pololu OPT3101 three-channel module (headers not fitted; solder them), tape measure, a white card and a black card as targets, a desk lamp.])[
+ Wire the module to the Pi's I#super[2]C bus at 3.3 V and find it at 0x58. Read the OPT3101 datasheet's register map and its initialisation and calibration sections. Pololu's Arduino library shows one working start-up sequence: port it to Python, and cite the datasheet section behind every register you write.
+ Read distance, amplitude and ambient level from the centre channel against the white card at ten distances from 10 cm to 1 m. Plot error against distance.
+ Repeat with the black card, then with the lamp shining at the sensor. Explain the changes in amplitude, noise and error.
+ Apply a phase-offset correction from one measured distance and repeat the sweep. Report what the correction fixed and what it did not.

#done-when(
  [Distance error after your one-point correction is under 3 cm from 10 cm to 1 m on the white card.],
  [The effects of target reflectivity and ambient light are quantified and explained.],
)
#evidence([Driver source with a datasheet citation per register; error plots before and after correction; the three-condition comparison.])
] <lab-tof>

#lab([An error budget for the drone's battery current], goal: [quantify a real measurement before building it.], time: [3 h, paper and Python])[
The drone in Chapter 3.5 draws about 12 A in hover and up to 60 A at full throttle from a three-cell pack, through a 0.5 mΩ shunt measured by an INA228.
+ List every error term: shunt tolerance and temperature coefficient (assume the shunt warms by 40 K at full current), INA228 offset and gain error from the datasheet's maximums, ADC noise at your chosen conversion time and averaging, copper drop if the Kelvin connection is imperfect, and the effect of a 1 kHz ripple on the reading.
+ Express each in milliamps at 1 A, 12 A and 60 A. Total them both as root sum of squares and linearly.
+ Decide the shunt power rating, the ADC range setting and the averaging you would use, and say which single term dominates at 1 A and at 60 A.
+ Verify the low-current end on the bench: the breakout's own shunt at 100 mA and 1 A.

#done-when(
  [The budget table has every term with its source and the two totals at three currents.],
  [The design choices are justified by the dominant terms.],
)
#evidence([The budget as a table and as a Python script; the bench check.])
] <lab-budget>

== Problem set

+ The TMP117 is trimmed to ±0.1 °C maximum from −20 to +50 °C. List four reasons your reading of the air in a rack module could still be 2 °C wrong, and the design choice that addresses each.
+ Derive the RMS noise in °C of the average of 64 TMP117 conversions if one conversion has 7.8 m°C RMS noise, and say why the real improvement is less.
+ Write the bus-clear procedure for an I#super[2]C slave holding SDA low, and explain why it works.
+ Compute SHUNT_CAL for an INA228 with a 0.5 mΩ shunt, a 60 A maximum and the ±40.96 mV range. What is the current LSB? What full-scale current can the range represent before it saturates?
+ A 1 mΩ shunt carries 30 A. What power does it dissipate, and what is its temperature rise in an 0.5 K/W mounting? With a temperature coefficient of 50 ppm/K, what error does that cause?
+ The speed of sound in air is about $331.3 + 0.606 T$ m/s with $T$ in °C. An uncorrected ultrasonic altimeter calibrated at 20 °C reads 10.00 m on a winter morning at −5 °C. What is the true altitude? Why does an optical time-of-flight sensor not have this error, and what error does it have instead?
+ A Hall sensor has 0.2 mT RMS noise. How many readings must be averaged to resolve Earth's horizontal field of 20 µT with a signal-to-noise ratio of 10, and why is that still not a usable compass?
+ Your humidity sensor reads 79 % above saturated sodium chloride at 25 °C. Write the one-point correction and state what it cannot correct.

== Deliverables and stretch

*Deliverables.* A `sensors/` package in the labs repository with five drivers, each with a docstring per function citing the datasheet section it implements and a test that runs against a recorded bus trace. The metrology logs and plots. The error budget as a document and a script.

*Stretch.* Port `tmp117.py` to C on the Pi using the `i2c-dev` ioctl interface directly, and measure the time per read against Python. Write a driver for the OPT4048 colour sensor (Adafruit 6335) and convert its XYZ output to a correlated colour temperature; Chapter 4.3 turns it into a kernel driver.

#checklist(
  [*Lab 1.3.1:* annotated I#super[2]C capture; TMP117 driver verified against hand-decoded reads; alert on GPIO; hot-unplug recovery.],
  [*Lab 1.3.2:* three-way temperature comparison, self-heating, two fitted time constants and the 12-hour salt test.],
  [*Lab 1.3.3:* INA228 within 1 % of the multimeter after shunt calibration; energy within 2 %; overcurrent alert demonstrated.],
  [*Lab 1.3.4:* angle error under 2° RMS; compass limit shown with numbers.],
  [*Lab 1.3.5:* time-of-flight error under 3 cm after correction; reflectivity and ambient light quantified.],
  [*Lab 1.3.6:* error budget at three currents with design choices justified.],
  [*Problem set:* all eight answered with units.],
  [*You can explain*, without notes: accuracy versus precision versus resolution, how to combine errors, why Kelvin connections matter, and how phase becomes distance in a time-of-flight sensor.],
)
