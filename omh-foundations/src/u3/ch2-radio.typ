#import "../lib/template.typ": *

= Radio links <ch-radio>

#chapter-meta(
  weeks: [3 weeks],
  builds: [Two CC1312R LaunchPads reworked for conducted measurement; a packet radio written directly on TI's RF driver; a measured packet-error waterfall at two data rates, with the test set-up's leakage floor quantified; the drone's telemetry protocol with a duty-cycle budget, a UART bridge and a ground station; a field range test against your Chapter 1.5 link budget; a software demodulator that decodes your own packets from an SDR capture.],
  needs: [Two LAUNCHXL-CC1312R1, the Linx 868 MHz antennas, the tinySA Ultra, the RTL-SDR, the Mini-Circuits attenuators (10, 20 and three 30 dB), SMA cables and adapters, a die-cast aluminium box with an SMA bulkhead and a USB power bank, the microscope and hot-air station, the Raspberry Pi 5, the Windows PC with SmartRF Studio 7, Code Composer Studio with the SimpleLink Low Power F2 SDK.],
)

#why[
  A drone without telemetry is flown blind, and a fleet of server modules without a management network cannot be operated. Both depend on links whose loss rate, latency and capacity were designed and then measured. This chapter goes below every protocol stack to the packet on the air: what decides how far it reaches, how often it is lost, how long it occupies the channel, and how you prove each number on a bench. The habits carry over directly to OMH's management and data networks, where "the link drops packets sometimes" is the start of an investigation, not an answer.
]

#skip-test(
  rule: [If all five are easy, do Labs 3.2.3 and 3.2.4 only.],
  [A packet has a 4-byte preamble, a 4-byte sync word, a length byte, 32 bytes of payload and a 2-byte CRC. What is its airtime at 50 kbit/s, and how many can you send per hour within a 1 % duty cycle?],
  [What is the modulation index of 2-GFSK at 50 kbit/s with 25 kHz deviation, and what does the Gaussian filter change about the spectrum?],
  [Two radios each have a ±20 ppm crystal. What is the worst-case frequency offset at 868 MHz, and why does it matter for a receiver with an 87 kHz filter?],
  [Why does a packet-error-rate curve fall from 100 % to 1 % over only a few decibels?],
  [You need to test a receiver at −110 dBm with a transmitter whose lowest setting is −20 dBm. What attenuation do you need, and what else will spoil the measurement?],
)

== Core ideas

*Modulation for low-power links.* The CC1312R, like most sub-gigahertz radios, transmits frequency-shift keying: the carrier moves up by the deviation $Delta f$ for a one and down for a zero. The modulation index $h = 2 Delta f \/ R_b$ relates deviation to bit rate; $h = 1$ (25 kHz at 50 kbit/s) is a common, robust choice. A Gaussian filter on the bit stream before modulation (GFSK) rounds the frequency transitions and narrows the spectrum at the cost of some intersymbol interference. Narrower filters and lower rates buy sensitivity: Chapter 1.5’s $-174 + 10 log_10 B + "NF" + "SNR"_"min"$ applies directly, and TI's long-range mode trades a twentieth of the bit rate for about 10 dB. ExpressLRS on the 2.4 GHz control link uses LoRa chirp spread spectrum or FLRC on Semtech radios; the ideas are the same.

#fig("/figures/u3-gfsk.svg", caption: [2-GFSK: the bit stream, its Gaussian-filtered frequency, and what an FM discriminator recovers from a noisy capture. Lab 3.2.6 implements the bottom panel.])

*A packet on the air.* A preamble of alternating bits lets the receiver settle its gain, estimate the frequency offset and lock its bit clock. A sync word marks the start of the frame; the receiver correlates against it and accepts a match within a set number of bit errors, which trades missed packets against false detections. Then a length field, the payload and a CRC. Whitening XORs the data with a pseudo-random sequence so long runs of identical bits do not upset the receiver's clock recovery. The CC1312R's radio core does all of this in hardware; you choose the parameters.

#fig("/figures/u3-packet.svg", caption: [The packet format Lab 3.2.2 defines, with the airtime of each field at 50 kbit/s. The preamble and sync word are overhead you pay on every packet, which is why tiny packets waste airtime.])

*The CC1312R.* An Arm Cortex-M4F application processor at 48 MHz runs your code. A separate radio core, a Cortex-M0 running TI's firmware, runs the modem and the packet engine. You talk to it by posting radio operation commands (set-up, frequency synthesiser, transmit, receive) through TI's RF driver; each command has a trigger, a start time on the 4 MHz radio timer, and a status the driver reports back. SysConfig generates the register settings for a chosen physical layer. The F2 SDK's EasyLink and TI 15.4-Stack sit on top; this chapter does not use them, because a drone's telemetry needs latency and duty-cycle control they hide.

*Errors and the waterfall.* For noncoherent binary FSK in white noise the bit error rate is $P_b = 1/2 e^(-E_b \/ 2 N_0)$, and a packet of $N$ bits survives with probability $(1 - P_b)^N$. Because $P_b$ falls exponentially with signal-to-noise ratio, the packet error rate drops from near 100 % to 1 % over a few decibels: the waterfall. Sensitivity is the received power at an agreed error rate and packet length. TI's measurement on this LaunchPad gives −110.5 dBm for 1 % bit error rate with 3-byte packets at 50 kbit/s, and −120.7 dBm in long-range mode (TI SWRA588A). Your measurement will use longer packets and so land slightly higher; the difference is calculable.

*Frequency error.* Each radio's synthesiser is derived from a crystal; 20 ppm at 868 MHz is 17 kHz, and the two ends can be wrong in opposite directions. The receiver's channel filter must pass the signal plus the offset, and the demodulator must tolerate it. TCXOs, factory trimming and the receiver's offset estimate in the preamble are the remedies. Temperature moves crystals: a drone climbing on a cold day changes its frequency.

*Propagation beyond free space.* Chapter 1.5’s link budget assumed free space. Over the ground a reflected ray adds to the direct ray with a phase that depends on the heights and distance, producing nulls; buildings and bodies add shadowing; and a vertical dipole has a null straight up, so the link can fail directly above the ground station. Polarisation mismatch between a tilted drone antenna and a vertical ground antenna costs more. A fade margin of 15 to 20 dB, antenna placement, and diversity (two antennas, pick the better) are the answers.

*Duty cycle as a design input.* The 868 MHz short-range band is divided into sub-bands, each with a power limit and a maximum fraction of time a transmitter may occupy it, measured over an hour. Every product radio is designed to them, so your telemetry design starts from the table below. A 1 % duty cycle is 36 s of transmission per hour; at 50 kbit/s that is an average of 500 bit/s. Listen-before-talk with adaptive frequency agility is the alternative to a duty-cycle limit in some sub-bands.

#tbl(columns: (auto, auto, 1fr), header: ([Sub-band], [Maximum power], [Duty cycle]),
  [863.0–865.0 MHz], [25 mW ERP], [0.1 %],
  [868.0–868.6 MHz], [25 mW ERP], [1 %, or listen-before-talk with frequency agility],
  [868.7–869.2 MHz], [25 mW ERP], [0.1 %],
  [869.40–869.65 MHz], [500 mW ERP], [10 %],
  [869.7–870.0 MHz], [5 mW ERP, or 25 mW ERP], [none at 5 mW; 1 % at 25 mW],
)

ERP is referenced to a half-wave dipole: ERP = EIRP − 2.15 dB. The CC1312R's maximum of +14 dBm (25 mW) into the Linx antenna fits every row; the 869.40–869.65 MHz sub-band's 10 % allowance is what makes a useful telemetry rate possible.

*Protocol design.* Telemetry is a stream where only the latest value matters: no acknowledgements, a sequence number to count losses, and fields packed in fixed point to the resolution the ground needs. Commands are the opposite: they must arrive exactly once, so they carry a sequence number, are acknowledged, retried with a timeout, and made idempotent so a duplicate does no harm. Between the flight controller and the radio LaunchPad, a UART carries frames delimited by consistent-overhead byte stuffing (COBS) with a CRC, so a lost byte costs one frame and the receiver resynchronises at the next delimiter. The radio firmware enforces the duty-cycle budget itself with a token bucket, so no bug upstream can exceed it.

*Measuring radios conducted.* Over the air, multipath and the room decide the answer. Conducted measurement connects the transmitter's RF port through calibrated attenuators to the receiver's, so the received level is known to a decibel. The pitfall is leakage: a board radiates from its traces and cables, and if that path delivers more signal than the attenuators do, you are measuring your bench. You defend with a shielded box around the transmitter, a battery inside the box so no cable leaves it except the coaxial one, distance to the receiver, and a measured leakage floor.

#fig("/figures/u3-conducted.svg", caption: [The conducted packet-error test of Lab 3.2.3. The dashed path is leakage; the test is valid only where the conducted level exceeds it by 10 dB or more, which you measure by terminating the chain.])

*Seeing your own signal.* An SDR delivers complex baseband samples; the phase difference between consecutive samples is the instantaneous frequency, so an FM discriminator is one line of NumPy. Symbol timing, sync-word correlation, de-whitening and a CRC check turn that frequency trace back into your bytes. Decoding your own packets proves you understand every layer, and the same tools find the interferer that a spectrum analyser only shows as a bump.

== Reading

- TI SWRA588A, _SimpleLink CC1312R LaunchPad for 868 MHz/915 MHz Bands_: the measured performance tables and section 5 on the RF design, including the SMA option.
- TI's CC13x2 Technical Reference Manual (SWCU185), the chapters on the radio, its command interface and the proprietary-mode packet format; the CC1312R datasheet's RF characteristics tables.
- The SimpleLink Low Power F2 SDK's RF driver API documentation and the `rfPacketTx`, `rfPacketRx` and `rfPacketErrorRate` examples.
- Proakis and Salehi, _Communication Systems Engineering_, the sections on FSK and noncoherent detection; or Sklar, _Digital Communications_, chapter 4.
- Cheshire and Baker, "Consistent Overhead Byte Stuffing" (IEEE/ACM ToN, 1999).
- Rappaport, _Wireless Communications_, chapter 4 (the two-ray model and link budgets).
- The tinySA Ultra's user guide sections on power measurement, the generator and maximum input.

== Labs

#safety[A transmitter connected straight to an instrument can destroy it. Fit the 30 dB attenuator directly on the transmitter's SMA connector before anything else, every time, and write the expected level at the instrument in the notebook before you connect it. The tinySA's limit is 0 dBm for normal use.]

#lab([Bring-up and the SMA rework], goal: [get both radios working and make their RF ports measurable.], time: [6 h], kit: [Two LAUNCHXL-CC1312R1, microscope, hot-air station, tweezers, flux, the tinySA with the 30 dB attenuator, the Windows PC with SmartRF Studio 7, CCS with the F2 SDK.])[
+ Build TI's `rfPacketTx` and `rfPacketRx` examples for the LaunchPad and flash one to each board. Confirm reception with the LEDs.
+ Read section 5.3 of SWRA588A: the RF path goes to the PCB antenna through C36, and moving that capacitor to the C37 pads routes it to SMA connector J7. Under the microscope, move it on both boards. Photograph before and after, and check with the multimeter that the capacitor's new pads are not shorted to ground.
+ With SmartRF Studio 7 driving one board in continuous-wave mode at 868.0 MHz, measure output power at J7 through the 30 dB attenuator for each power setting from the lowest to +14 dBm. Measure the second and third harmonics and the carrier frequency error.
+ Repeat the +14 dBm and frequency measurements on the second board.

#done-when(
  [Both boards transmit through J7, and the power table agrees with the settings within ±1.5 dB after attenuator and cable loss.],
  [Harmonics and frequency error are measured for both boards.],
)
#evidence([Rework photographs; the power table; harmonic and frequency captures.])
] <lab-radio-bringup>

#lab([A packet radio below the stack], goal: [own every byte and microsecond of your link.], time: [8 h], kit: [Both LaunchPads with Linx antennas fitted, oscilloscope.])[
+ Write your own transmitter and receiver applications using only TI's RF driver and a SysConfig-generated 2-GFSK physical layer at 50 kbit/s with 25 kHz deviation. Define your packet: a 16-bit sequence number and a 30-byte payload, with whitening and the radio core's CRC.
+ Set a GPIO when you post the transmit command and clear it in the command-done callback. Compare the measured airtime with your calculation from the packet format, and measure the time from posting to the start of transmission.
+ On the receiver, count sequence gaps and CRC failures and read the RSSI of every packet; print statistics once a second over the back-channel UART.
+ Measure the receive-to-transmit turnaround: the receiver answers each packet, and you time the gap on the scope with both GPIOs.

#done-when(
  [Measured airtime matches your calculation within 5 %, and the start latency and turnaround are measured.],
  [The receiver reports zero lost packets in 10,000 at 1 m.],
)
#evidence([Source; the airtime calculation; scope captures; the statistics log.])
] <lab-radio-packet>

#lab([Sensitivity and the packet-error waterfall], goal: [measure a receiver properly, including the limits of your own bench.], time: [8 h], kit: [Both reworked LaunchPads, the die-cast box with an SMA bulkhead fitted and the USB power bank inside, the attenuators (three 30 dB, one 20 dB, one 10 dB), SMA cables, the tinySA, two 50 Ω terminators, copper tape.])[
+ Measure each attenuator and cable at 868 MHz with the tinySA's generator and input at levels well above its noise floor, and sum them to get the chain's loss.
+ Program the transmitter to step through its power settings from 0 to +14 dBm by itself, 1,000 packets at each, carrying the setting in the payload: once the lid is on, no cable except the coaxial one may leave the box.
+ Put the transmitter in the box on the power bank, its J7 to the bulkhead, and seal the lid's seam with copper tape. Outside, a 110 dB chain (three 30 dB and the 20 dB) runs to the receiver's J7, with the receiver a metre away on its own USB lead. Both boards' PCB antennas are already disconnected by the rework, which is half of your isolation.
+ Leakage floor: disconnect the chain from the receiver and terminate both, then run the transmitter's sequence and record what the receiver still hears. This is your bench's floor.
+ Run the sequence through the chain, recording packet error rate and mean RSSI at each level. Plot packet error rate against received power for 50 kbit/s, then add the 10 dB attenuator and repeat for TI's long-range mode.
+ Compare your 1 % points with SWRA588A's figures, correcting for your longer packet using the bit-error model.

#done-when(
  [Both waterfalls are plotted, and the leakage floor is at least 10 dB below every level you report, or the notebook shows how you improved the isolation until it was.],
  [Your 1 % packet-error points agree with TI's sensitivity within 3 dB after the packet-length correction.],
)
#evidence([Attenuator calibration; the leakage measurements; both waterfalls; the comparison.])
] <lab-radio-per>

#lab([The telemetry protocol], goal: [design a protocol from requirements and budgets, then build it end to end.], time: [2 weekends], kit: [Both LaunchPads, the MSP-EXP432E401Y as a stand-in flight controller, the Raspberry Pi 5.])[
+ List what the ground needs from the drone (attitude, rates, altitude estimates, battery voltage, current and used capacity, control-link quality, arming state, faults) with the rate and resolution of each, and the commands the ground may send.
+ Choose the 869.40–869.65 MHz sub-band and compute the airtime budget at 10 % duty cycle. Pack the fields in fixed point and choose a packet rate that fits with 30 % margin.
+ Write the radio bridge: COBS-framed, CRC-checked frames arrive over UART from the flight controller and leave over the air; commands come back with acknowledgement, retry and sequence numbers. Enforce the duty-cycle budget with a token bucket in the radio firmware, and test it by flooding the bridge.
+ Write the ground side: the second LaunchPad forwards frames over USB serial to the Pi, which decodes, logs to CSV and plots live.
+ Measure end-to-end latency from the flight controller's frame to the Pi's decode, and command round-trip time.

#done-when(
  [Telemetry streams at the designed rate, and the measured transmit duty cycle over 10 minutes is within the budget, including under flooding.],
  [Latency and command round trip are measured, and a dropped command is retried and executed once.],
  [A two-page protocol specification exists that another engineer could implement from.],
)
#evidence([The specification; the budget calculation; source; the duty-cycle and latency measurements.])
] <lab-radio-protocol>

#lab([Range in the field], goal: [find where your link budget meets the real world.], time: [5 h outdoors], kit: [Both LaunchPads with whip antennas on power banks, a 1.5 m pole or tripod for the ground antenna, the Tarot frame, a phone for positions.])[
+ Fix the ground station at 1.5 m. Walk away along a clear path with the other radio, logging RSSI and packet error rate with positions every 25 m, until the error rate exceeds 10 %. Plot received power against distance over your Lab 1.5.6 budget.
+ Mount the radio on the drone frame (motors off) at the planned position and rotate the frame in 45° steps at a fixed distance. Plot the pattern and find the nulls.
+ Raise the remote radio well above the ground station (a window or a hill) and record what happens near the vertical.

#done-when(
  [Measured and predicted received power are on one plot, with the discrepancy explained in terms of ground reflection, obstruction and antenna orientation.],
  [The frame-mounted pattern is measured and the radio's position on the drone is decided from it.],
)
#evidence([Logs with positions; the plots; photographs of the set-ups.])
] <lab-radio-range>

#lab([Demodulate your own packets], goal: [decode a radio signal from samples with nothing but NumPy.], time: [6 h], kit: [RTL-SDR, the transmitting LaunchPad with the 30 dB attenuator into a short antenna on the SDR, Python with NumPy and SciPy.])[
+ Capture 2 s of your 50 kbit/s packets at 1.024 MS/s centred 100 kHz below the carrier (to keep the dongle's DC spike out of the signal).
+ Shift to baseband, low-pass, and apply an FM discriminator. Measure the deviation and the frequency offset from the trace.
+ Recover symbol timing, correlate for your sync word, slice the bits, undo the whitening using the sequence in TI's documentation, and check the CRC.

#done-when(
  [At least 99 of 100 strong packets decode with a correct CRC, and the measured deviation is within 10 % of 25 kHz.],
)
#evidence([The demodulator notebook with plots at each stage; the decoded payloads against what was sent.])
] <lab-radio-sdr>

== Problem set

+ Compute the airtime of your Lab 3.2.2 packet at 50 kbit/s and in long-range mode, and the maximum packet rates in the 868.0–868.6 MHz and 869.40–869.65 MHz sub-bands.
+ The receiver's channel filter is 87 kHz wide and its noise figure 7 dB. Estimate its sensitivity for an SNR requirement of 9 dB and compare with −110.5 dBm.
+ Using the noncoherent FSK formula, find the $E_b \/ N_0$ for a 1 % packet error rate with 3-byte and with 34-byte packets. How many decibels separate them?
+ Two ±20 ppm crystals: give the worst-case offset at 869.5 MHz and the fraction of an 87 kHz filter it consumes. What would a ±2 ppm TCXO change?
+ A drone flies at 60 m altitude, 400 m horizontally from a ground antenna at 1.5 m over flat ground with reflection coefficient −1. Compute the path difference, the phase difference and the received power relative to free space.
+ An ideal half-wave dipole has the pattern $cos(pi/2 cos theta) \/ sin theta$. Compute its relative gain at 30°, 60° and 80° from broadside. What does this mean for a vertical ground antenna and a drone overhead?
+ Design a token bucket that enforces 10 % over any hour but lets a 20 s burst through at the start of a flight. Give the bucket size and fill rate, and the worst case it permits.
+ A 40-byte telemetry frame crosses a 115,200 baud UART with COBS framing and a 2-byte CRC. What is the worst-case overhead, and the maximum frame rate?
+ Your chain has 110 dB of attenuation and the transmitter runs at 0 dBm. How much isolation must the leakage path have for a valid measurement at the 1 % point with 10 dB of margin? List three things that raise the isolation and estimate what each is worth.

== Deliverables and stretch

*Deliverables.* The reworked boards; the packet-radio firmware; the waterfall measurements with the leakage floor; the telemetry protocol specification, bridge firmware and ground station; the field-test report; the demodulator.

*Stretch.* Add listen-before-talk with frequency agility in the 868.0–868.6 MHz sub-band and measure the throughput gain over the plain duty cycle. Add forward error correction (a Hamming or convolutional code) to your packets and measure the waterfall's shift. Look at the ExpressLRS 2.4 GHz link on the tinySA Ultra's high band and identify its hop pattern. Flash the BeaglePlay's CC1352P7 as a Linux-attached ground station.

#checklist(
  [*Lab 3.2.1:* both boards reworked to J7; power table within ±1.5 dB; harmonics and frequency error measured.],
  [*Lab 3.2.2:* own packet radio; airtime within 5 % of calculation; 10,000 packets at 1 m with no loss.],
  [*Lab 3.2.3:* two waterfalls with a measured leakage floor; 1 % points within 3 dB of TI's after correction.],
  [*Lab 3.2.4:* telemetry at the designed rate within the duty-cycle budget; latency measured; specification written.],
  [*Lab 3.2.5:* field data plotted over the link budget; antenna position on the drone decided.],
  [*Lab 3.2.6:* 99 of 100 packets decoded from an SDR capture.],
  [*Problem set:* all nine answered with units.],
  [*You can explain*, without notes: what each field of a packet is for, why the error-rate curve is a waterfall, how you would prove a receiver's sensitivity, how a duty cycle shapes a protocol, and why commands and telemetry need different reliability.],
)
