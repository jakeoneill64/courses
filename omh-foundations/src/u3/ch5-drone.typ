#import "../lib/template.typ": *

= The drone: integration, test and flight <ch-drone>

#chapter-meta(
  weeks: [5 weeks],
  builds: [A 450 mm quadcopter that flies on your firmware: DShot motor output over µDMA, a CRSF receiver parser with failsafe, a flight-software core with an arming state machine, a mixer, a flight logger and telemetry, tested in software-in-the-loop simulation; an assembled airframe with your Boards P and F, the 868 MHz telemetry radio and the 60 GHz radar altimeter; rig-tuned rate and angle loops; tethered then free hover; altitude hold fusing radar and barometer; a written flight-test report.],
  needs: [Everything from Chapters 3.1 to 3.4: the Tarot frame, four SunnySky motors and CloudPhoenix ESCs, props, the 3S pack and charger, Boards P and F on an MSP-EXP432E401Y, the RP1 receiver and Pocket transmitter, the BMP581, the LIS3MDL on a mast, a CC1312R LaunchPad on the drone and one on the ground with the Pi, the IWRL6432BOOST, the one-axis rig, a tether line and a 10 kg anchor, safety glasses, a logic analyser.],
)

#why[
  Integration is where the course's separate skills meet a deadline and a physical consequence. A server module and a drone fail the same way: subsystems that each passed their tests interact through timing, power, vibration, electromagnetic interference and software states nobody drew. The habits this chapter forces (a written system architecture, interface contracts, a simulator before hardware, a test plan with exit criteria, logs good enough to explain every anomaly, and a report) are what make Module Zero's integration in Chapter 4.7 possible, and what a customer's acceptance test of an OMH rack will demand.
]

#skip-test(
  rule: [If all five are easy, do Labs 3.5.3, 3.5.6 and 3.5.7.],
  [Encode DShot600 throttle 1,046 with no telemetry request: give the 16 bits, including the checksum, and the frame's duration.],
  [A CRSF channels frame packs sixteen 11-bit channels into 22 bytes. Write the expression that extracts channel 3 from the payload bytes.],
  [List the conditions your firmware must check before it arms, and the events that must disarm it, with a time limit for each.],
  [The radar reports 2.10 m to the ground with the drone pitched 12°. What is the height, and what error does a 2° attitude error add?],
  [Your rate loop runs at 1 kHz. Budget the time for the IMU read, estimator, controllers, mixer and DShot set-up, and say what happens if the budget overruns once a second.],
)

== Core ideas

*The system.* The flight controller is an MSP-EXP432E401Y carrying Board F; Board P supplies it and measures the battery. Four ESCs take DShot from four timer outputs. The RP1 receiver sends CRSF over a UART. The CC1312R LaunchPad on the drone forwards telemetry frames from another UART to the ground. The IWRL6432BOOST, facing down, reports range over a third. The magnetometer sits on a mast at the height Lab 3.1.6 chose. Write this as an architecture document before you assemble anything: every interface with its protocol, rate, voltage level and owner.

#fig("/figures/u3-drone-system.svg", caption: [The drone as a system. Every arrow is an interface with a protocol, a rate and a failure mode, and each one appears in the architecture document you write in Lab 3.5.3.])

*DShot.* A digital ESC protocol: each frame is 16 bits, an 11-bit throttle (0 disarmed, 1 to 47 commands, 48 to 2,047 throttle), one telemetry-request bit, and a 4-bit checksum, the XOR of the three nibbles of the first 12 bits. Each bit is a pulse in a fixed period, high for 75 % of it for a one and 37.5 % for a zero. At DShot600 the bit period is 1.67 µs and a frame takes 26.7 µs. Because it is digital it needs no calibration, has a checksum, and carries commands such as spin direction and beeps. Generating it in software would cost the CPU every microsecond; a timer in PWM mode whose compare value µDMA reloads once per bit costs nothing per bit. Bidirectional DShot inverts the line and lets the ESC answer with motor speed, which the best flight controllers use to place notch filters.

#fig("/figures/u3-dshot.svg", caption: [One DShot600 frame. The timer's period is the bit time; µDMA writes the next compare value at each period's start, so the CPU writes sixteen words and walks away.])

*The control link.* ExpressLRS sends stick positions over 2.4 GHz at a packet rate you choose (50 to 1,000 Hz), and the RP1 delivers them as CRSF at 420,000 baud: a frame of an address byte, a length, a type, a payload and a CRC-8 with polynomial 0xD5 over the type and payload. The channels frame carries sixteen 11-bit channels, with 172 to 1,811 representing 988 to 2,012 µs. Link statistics frames report signal strength and link quality. When the link fails the receiver stops sending channel frames, so failsafe is a timeout in your code, not a message.

*Arming and failsafe.* Most drone accidents happen on the ground: a motor that spins when someone is holding the frame. An arming state machine makes the dangerous transitions explicit. It refuses to arm unless the arm switch moves from off to on with throttle low, the attitude is level, the IMU is calibrated, the battery is above its threshold and the link is healthy. It disarms on the switch, on loss of link beyond a timeout, on an attitude beyond any flyable angle, and on a critical battery. Each transition is logged with its reason. In this course a lost link disarms: the drone never flies higher than a fall it can survive, so a controlled descent is a stretch goal, not a requirement.

#fig("/figures/u3-arming.svg", caption: [The arming state machine. Every arrow is a test case in Lab 3.5.3’s simulator, and the guarded transitions into ARMED are the ones that prevent injuries.])

*The control core.* The IMU's data-ready interrupt at 1.66 kHz starts the fast path: read the IMU by µDMA, update the attitude estimate, run the rate controllers, mix, and start the DShot transfer. The angle loop runs at 500 Hz, altitude at 50 Hz, telemetry at 10 Hz and the logger at 500 Hz from lower-priority contexts. The mixer turns collective thrust and roll, pitch and yaw demands into four motor commands; when one saturates, it must keep attitude control and give up altitude, never the reverse.

#fig("/figures/u3-mixer.svg", caption: [Motor numbering, rotation directions and the mixer for the course's X configuration. Diagonal motors spin the same way so their torques cancel; yaw comes from speeding up one diagonal and slowing the other.], width: 88%)

*Simulation before flight.* The same control code, compiled for your workstation, runs against a six-degree-of-freedom rigid-body model with the motor lag and thrust curve from Lab 3.1.1, sensor noise and bias from Labs 3.1.4 and 3.1.6, and the loop delays you measured. Software-in-the-loop testing finds sign errors, mixer mistakes, arming bugs and saturation behaviour at no risk. It does not prove the drone flies, but every bug it finds is one you do not find with a propeller.

*Altitude.* Three sensors measure height badly in different ways. The barometer reads pressure altitude with about 10 cm of noise, drifts with weather and temperature, and sees prop wash. The radar measures range to the ground to centimetres, but range is height only when level ($h = r cos theta cos phi$ over flat ground), and it drops out over water and at steep angles. The accelerometer, rotated to the earth frame with gravity removed, gives vertical acceleration with no delay but drifts within seconds when integrated. A three-state Kalman filter (height, vertical velocity and barometer bias) fuses them: the accelerometer drives the prediction, the radar and barometer correct it, and the bias state lets the barometer track the radar while the radar is valid and coast when it is not.

#fig("/figures/u3-alt-fusion.svg", caption: [Altitude fusion on a simulated hover with a radar dropout from 6 to 8 s. The fused estimate follows the radar while it is valid and coasts on the barometer, with its learned bias, during the dropout.])

*Testing like an aircraft.* Each test has a card: the objective, the configuration, the procedure, the abort criteria and the data to collect. Tests climb a ladder from software to hardware: simulation, props-off bench, the one-axis rig, a tether, free hover at low height, then the manoeuvre. You climb one rung at a time and step down when an anomaly is unexplained. The flight logger records enough to explain any anomaly afterwards: sensor data, estimates, setpoints, controller terms, motor outputs, battery and link state, and every state transition.

== Reading

- Your own Chapter 3.1 and 3.2 deliverables, and the TI SLAU723A chapters on general-purpose timers (PWM mode and the GPTMDMAEV register) and µDMA.
- The DShot and bidirectional DShot descriptions in the Betaflight wiki and source (`src/main/drivers/dshot.c`), read after you have written your own.
- The TBS CRSF protocol specification, and the ExpressLRS documentation on packet rates, telemetry ratio and failsafe.
- Beard and McLain, _Small Unmanned Aircraft_, chapters 3 to 5 (the equations of motion you simulate); or Mahony, Kumar and Corke, "Multirotor Aerial Vehicles" (IEEE Robotics and Automation Magazine, 2012).
- Simon, _Optimal State Estimation_, chapter 5 (the discrete Kalman filter), for the altitude filter.
- The PX4 or ArduPilot documentation on pre-flight checks, arming checks and log analysis, as examples of how mature projects structure them.

== Labs

#safety[Propellers come off for every bench test, every firmware flash and every wiring change; they go on only for a rig, tether or flight test with a written test card. Wear safety glasses and keep everyone else at least 5 m away during powered tests. Test the kill switch before every flight. Fly over grass in an open space with no one underneath. Charge, store and retire the pack by the Chapter 1.4 rules, and land at 3.5 V per cell.]

#lab([DShot over µDMA], goal: [drive four ESCs with a protocol you implemented, at zero CPU cost per bit.], time: [8 h], kit: [Flight-controller LaunchPad with Board F, logic analyser, one ESC and motor without a propeller, the 3S pack.])[
+ Choose four timer capture/compare pins from your Board F pin map. Configure each half-timer in PWM mode with a period of 200 cycles at 120 MHz (1.67 µs). Establish from the TRM which timer event can request µDMA once per period in PWM mode, set it in GPTMDMAEV, and confirm on the logic analyser with a GPIO toggled in the transfer-complete interrupt.
+ Encode frames with the checksum, fill a buffer of compare values, and let µDMA send each frame. Add a reset gap between frames and send all four motors' frames in parallel.
+ Write a decoder for the logic analyser's exported samples that checks timing and checksum for every frame, and run it on 10,000 frames.
+ With the ESC on the pack and the motor bare: arm with zero throttle, send the beep and spin-direction commands as their specification requires, and ramp throttle from 48 to 300 and back.
+ Measure the CPU time per update and the latency from your throttle write to the first edge.

#done-when(
  [Ten thousand frames decode with correct timing and checksum, and the motor arms, beeps, reverses and ramps under your commands.],
  [CPU time per update and the write-to-edge latency are measured.],
)
#evidence([Source; the decoder; captures; the timing measurements.])
] <lab-dshot>

#lab([The receiver link], goal: [turn stick movements into trustworthy setpoints, and notice instantly when they stop.], time: [6 h], kit: [RP1 receiver, Pocket transmitter, flight-controller LaunchPad, logic analyser.])[
+ Update the receiver to the transmitter's ExpressLRS major version and bind it. Connect it to the UART on Board F for the receiver at 420,000 baud.
+ Write the parser as a byte-at-a-time state machine fed from the UART's µDMA ring buffer: sync, length check, CRC-8 over type and payload, channel unpacking, link statistics. Count every kind of error.
+ Test it on your workstation against recorded byte streams with injected corruption: truncated frames, wrong lengths, bad CRCs, noise between frames.
+ Implement failsafe: no valid channels frame for 100 ms is a lost link. Switch the transmitter off and measure the time to detection on the analyser.
+ Measure the time from a channels frame's last byte to the change in DShot output.

#done-when(
  [The parser passes every corruption test, and loss of link is detected within 120 ms on ten trials.],
  [Frame-to-output latency is measured and stated against the packet rate.],
)
#evidence([Parser source and tests; captures of failsafe detection and latency.])
] <lab-crsf>

#lab([Flight software and simulation], goal: [build the flight core and break it in simulation before it can break anything else.], time: [2 weekends], kit: [Workstation, the flight-controller LaunchPad with Board F.])[
+ Write the architecture document: interfaces, rates, priorities, the timing budget of the 1.66 kHz path, and the failure response for every sensor and link.
+ Implement the core: the interrupt-driven fast path; the arming state machine with every guard and disarm reason logged; the mixer with saturation handling that preserves attitude; parameters in EEPROM with a version and CRC; the flight logger writing 500 Hz records to Board F's flash; telemetry frames to the radio bridge from Lab 3.2.4.
+ Build the same code for the workstation against a six-degree-of-freedom simulator with your measured motor model, sensor noise and delays. Write test cases for every arming guard, every disarm path, link loss, a stuck IMU, motor saturation during a roll, and a battery sag.
+ Fly simulated hovers and steps. Compare the simulated roll-rate loop with your Lab 3.1.7 rig data.

#done-when(
  [Every test case passes in simulation, and the fast path's measured execution time on the MCU is under 50 % of its period.],
  [The logger records a full simulated flight and a script replays it into plots.],
)
#evidence([The architecture document; source; the test report; replay plots.])
] <lab-flight-sw>

#lab([Assembly], goal: [build an airframe that is balanced, quiet in vibration and wired so you can debug it.], time: [8 h], kit: [Frame, motors, ESCs, Boards P and F with the LaunchPad, receiver, both radios, radar, magnetometer mast, standoffs, foam tape, cable ties, 14 AWG wire, XT60 connectors, heat-shrink, the scale from the thrust stand.])[
+ Mount motors and ESCs, solder the ESC power leads to the frame's power board and Board P between battery and frame. Mount the flight controller on foam at the frame's centre, the receiver antennas at 90° to each other away from carbon and wiring, the telemetry radio where Lab 3.2.5 put it, the radar facing down with nothing in its field of view, and the magnetometer on its mast.
+ For the radar and the telemetry radio, read each board's schematic to see how its application UART reaches the debugger and the BoosterPack headers. On the CC1312R LaunchPad, remove the RXD and TXD jumpers so the flight controller owns the UART. On the IWRL6432BOOST, set the switches the user's guide gives for routing the UART to the headers; if the debugger's transmit line cannot be isolated, decide how the radar gets its configuration and write the decision down.
+ With propellers off: check every motor's number and direction against the mixer figure, correct directions with DShot commands, and check the radio, radar and telemetry from the bench.
+ Weigh the drone and balance it: the centre of gravity within 5 mm of the frame's centre in both axes, adjusted by moving the pack.
+ Tethered to the rig with propellers on, run the motors to hover throttle and log the IMU at full rate. Compare the vibration spectrum with Lab 3.1.5’s and fix anything new (a loose prop, an unbalanced motor, a stiff mount).

#done-when(
  [Motor order, direction, centre of gravity and every sensor are verified with propellers off, and the vibration spectrum at hover throttle is no worse than on the thrust stand.],
)
#evidence([Photographs; the wiring diagram; the weight and balance record; the vibration spectra.])
] <lab-assembly>

#lab([Rig tuning], goal: [tune the real airframe's loops where a mistake costs nothing.], time: [6 h], kit: [The drone, the one-axis rig from Lab 3.1.7 adapted to the full frame, safety glasses, the transmitter.])[
+ Mount the drone on the rig for roll. Bring up the rate loop with low gains, then raise them while logging step responses from the transmitter's stick. Stop at the first sign of oscillation and back off by a third.
+ Close the angle loop and log steps and a hand-push disturbance. Compare with the simulation and update the model where it was wrong.
+ Remount for pitch and repeat. If you bought the three-axis rig, tune yaw on it; otherwise tune yaw in the first hover with conservative gains.

#done-when(
  [Roll and pitch angle steps of 15° settle within 0.5 s with under 20 % overshoot on the rig, and the logged responses match the updated simulation in rise time within 30 %.],
)
#evidence([The logged step responses with the simulation overlaid; the final gains and the reasoning for them.])
] <lab-rig-tuning>

#lab([First hover], goal: [fly, safely and on purpose.], time: [1 day outdoors], kit: [The drone, a fully charged pack, the transmitter, a 1.5 m tether line tied to a 10 kg anchor, safety glasses, the test cards, a phone camera on a tripod.])[
+ Write the test cards: tethered hover, free hover at 1 m, gentle translation. Each has its objective, procedure, abort criteria and data to collect.
+ Pre-flight: propellers tight and correctly oriented, pack voltage per cell, centre of gravity, arming refused with throttle up, kill switch disarms, and failsafe disarms within 0.5 s of switching the transmitter off (propellers off for these last checks).
+ Tethered hover: tie the anchor line to the frame's centre so the drone cannot rise above 1.5 m or travel more than 1.5 m. Hover for 60 s in angle mode with manual throttle. Land and read the log before anything else.
+ Free hover at 1 m for 60 s, then gentle translations in each direction. Land at 3.5 V per cell.
+ From the logs, plot attitude error, motor outputs, current and vibration, and explain any anomaly before the next flight.

#done-when(
  [A 60 s free hover holds attitude within ±5° with no motor saturating for more than 100 ms, recorded on video and in the log.],
  [Every anomaly in the logs is explained in the notebook.],
)
#evidence([The test cards with results; the video; log plots and the anomaly notes.])
] <lab-hover>

#lab([Altitude hold with radar and barometer], goal: [make the drone hold a height by itself, from sensors you characterised.], time: [8 h plus a day outdoors], kit: [The drone with the radar and barometer, tape measure, a pole marked at 1, 2 and 3 m.])[
+ Port your Lab 3.3.5 parser to the flight controller and run the radar at your altimeter configuration. Read the BMP581 at 50 Hz under a foam cover.
+ Implement the three-state Kalman filter with tilt compensation of the radar range and gating of radar outliers. Hold the drone by hand at measured heights from 0.3 to 3 m, tilted and level, and compare the estimate with the tape.
+ Implement altitude hold: a height loop commanding vertical velocity, a velocity loop commanding collective thrust with hover-throttle feedforward from your thrust model and battery voltage.
+ Fly holds at 1, 2 and 3 m beside the pole, steps between them, and passes over grass and concrete. Cover the radar for 2 s in flight to force a dropout.

#done-when(
  [Hand-held estimates are within 5 cm of the tape when level and within 10 cm at 15° of tilt.],
  [In flight the drone holds each height within ±15 cm for 30 s and survives the forced dropout with under 30 cm of excursion.],
)
#evidence([Filter design and tuning; hand-held comparison table; flight logs with height estimates, setpoints and the dropout.])
] <lab-alt-hold>

#lab([Telemetry and the flight report], goal: [operate the drone from the ground and report on it like an engineer.], time: [1 day plus writing], kit: [The drone, the ground station (CC1312R LaunchPad and the Pi), a fully charged pack.])[
+ Fly a scripted mission with altitude hold: climb to 2 m, hold 60 s, step to 3 m, hold 60 s, descend and land, with live telemetry on the Pi showing attitude, height, battery and link quality.
+ Fly a hover to the 3.5 V per cell landing threshold and record flight time and energy used. Compare hover power and flight time with your Lab 3.1.1 and Lab 1.4.4 predictions.
+ Write the flight-test report: configuration, test cards and results, plots from the log, measured against predicted performance, every anomaly with its cause, and the changes you would make.

#done-when(
  [The mission flies on telemetry with packet loss under 2 % at the flying distances used.],
  [Measured hover power is within 15 % of your prediction, or the report explains the difference.],
  [The report is written and another engineer could repeat your tests from it.],
)
#evidence([Telemetry logs; the flight log; the report.])
] <lab-flight-report>

== Problem set

+ Encode DShot600 throttle 1,046 without telemetry and verify your checksum. What is the highest frame rate with a 2 µs gap between frames, and how does that compare with your rate loop?
+ The receiver runs at 250 packets per second. What is the worst-case delay from a stick movement to a new channels frame at the UART, and to DShot output with your measured latencies?
+ From your thrust model, compute the hover throttle at 12.6 V and 10.5 V for the drone's measured mass, and the feedforward you would use.
+ A roll demand needs motor 1 at 110 % while collective is 70 %. Give two mixer strategies, compute the four outputs for each, and say which keeps the drone level.
+ Your altitude filter uses accelerometer noise 0.3 m/s² and radar noise 2 cm at 50 Hz. Estimate the steady-state uncertainty in height and the delay the filter adds.
+ The radar reads 3.00 m with roll 10° and pitch −8°. Compute the height over flat ground and the error from a 2° error in each angle.
+ The link fails at 3 m and your firmware disarms 0.5 s later. Estimate the impact speed and energy. At what height would you rather descend under control than disarm?
+ The 1.66 kHz fast path spends 35 µs reading the IMU by DMA, 60 µs in the estimator, 15 µs in the controllers, 5 µs in the mixer and 8 µs starting DShot. What is its utilisation, and what is left for the 500 Hz logger if it needs 120 µs per record?
+ The drone hovers at 135 W with an all-up mass of 1.25 kg. Using 80 % of the pack's 55 Wh, estimate the hover time. What reduces it in practice?

== Deliverables and stretch

*Deliverables.* The architecture document; the flight firmware with its simulator and tests; the assembled, balanced and documented drone; the tuning logs; video and logs of the hover and altitude-hold flights; the flight-test report.

*Stretch.* Bidirectional DShot with rpm-tracking notch filters, and the vibration spectra before and after. A controlled descent on link loss using the altitude estimate. Position logging and position hold with the Matek GNSS module. A second telemetry ground station on the BeaglePlay. Replace one CloudPhoenix with your Lab 3.1.3 FOC firmware on a small custom ESC board.

#checklist(
  [*Lab 3.5.1:* DShot to four ESCs over µDMA; 10,000 frames decoded; commands and ramp demonstrated.],
  [*Lab 3.5.2:* CRSF parser passing corruption tests; failsafe within 120 ms; latency measured.],
  [*Lab 3.5.3:* architecture written; every simulation test passing; fast path under 50 % of its period.],
  [*Lab 3.5.4:* assembled, balanced, wired and verified with propellers off; vibration checked.],
  [*Lab 3.5.5:* roll and pitch tuned on the rig within the step-response criteria.],
  [*Lab 3.5.6:* 60 s free hover within ±5°, on video and in the log, with anomalies explained.],
  [*Lab 3.5.7:* altitude hold within ±15 cm at three heights, surviving a radar dropout.],
  [*Lab 3.5.8:* telemetry mission flown; flight time against prediction; the report written.],
  [*Problem set:* all nine answered with units.],
  [*You can explain*, without notes: what each subsystem on the drone does and how it fails, why arming is a state machine, what DShot and CRSF put on the wire, how the altitude filter blends three sensors, and how you climbed the test ladder.],
)
