#import "../lib/template.typ": *

= Signals on wires and RF fundamentals <ch-rf>

#chapter-meta(
  weeks: [2.5 weeks],
  builds: [A time-domain reflectometry measurement of a cable; a calibrated vector network analyser and a set of measured S-parameters; a quarter-wave antenna tuned to 868 MHz; a protected spectrum-analyser setup; an FM receiver written from scratch in Python on an RTL-SDR; link budgets for the drone's radios.],
  needs: [Oscilloscope, SN74HC14N, a 10 m BNC coaxial cable with tee and 50 Ω terminator, tinySA Ultra, LiteVNA 64, RTL-SDR Blog V4, Mini-Circuits 10, 20 and 30 dB SMA attenuators, SMA cables, adapters and terminators, two Linx 868 MHz whip antennas, an SMA bulkhead socket and a scrap of copper-clad board.],
)

#why[
  At some frequency every wire becomes a transmission line and every trace becomes an antenna. For OMH that frequency arrives with PCIe, DDR and 25 Gbit Ethernet, where impedance, reflections and loss decide whether a board works; for the drone it arrives with the 868 MHz telemetry link, the 2.4 GHz control link and the 60 GHz radar. Signal integrity, EMC and radio are one subject seen from three sides. This chapter teaches its language (decibels, impedance, reflection, S-parameters, noise) and its instruments, so that Unit 3’s radios and boards are engineering rather than folklore.
]

#skip-test(
  rule: [If all five are easy, do Labs 1.5.3 and 1.5.5 only.],
  [Convert +20 dBm into milliwatts and into volts RMS across 50 Ω. A signal passes through 30 dB of attenuation and a cable with 1.5 dB of loss: what reaches the far end?],
  [A 50 Ω line is terminated in 100 Ω. What are the reflection coefficient, the VSWR and the return loss? What fraction of the power reaches the load?],
  [At what length does a PCB trace carrying an edge with a 1 ns rise time start to behave as a transmission line, assuming 6 ps/mm of delay?],
  [Compute the free-space path loss at 868 MHz over 2 km. With +14 dBm transmitted, 2 dBi antennas at each end and a receiver sensitivity of −105 dBm, what is the fade margin?],
  [What is the thermal noise floor in a 100 kHz bandwidth, and what does a 6 dB noise figure do to it?],
)

== Core ideas

*Decibels.* A ratio of powers in decibels is $10 log_10 (P_2 \/ P_1)$; a ratio of voltages across the same impedance is $20 log_10 (V_2 \/ V_1)$. Absolute power is quoted against a reference: dBm against 1 mW, so 0 dBm is 1 mW, +20 dBm is 100 mW and +30 dBm is 1 W. Gains and losses in a chain add in decibels. Antenna gain is quoted in dBi (against an ideal isotropic radiator) or dBd (against a half-wave dipole, which has 2.15 dBi). Noise and interference add as powers, so convert to milliwatts before adding them.

*Phasors and impedance.* A sine at one frequency is a rotating vector; a resistor, capacitor and inductor relate voltage and current by a complex impedance: $R$, $1 \/ (j omega C)$ and $j omega L$. Series LC circuits resonate at $f_0 = 1 \/ (2 pi sqrt(L C))$, where the reactances cancel; the quality factor Q is the ratio of stored to dissipated energy per cycle, and sets bandwidth.

*Transmission lines.* A pair of conductors with distributed inductance $L$ and capacitance $C$ per unit length carries waves at $v = 1 \/ sqrt(L C)$, which is $c \/ sqrt(epsilon_"eff")$: about 0.66 $c$ in solid-polyethylene coax and about 6 ps/mm on FR-4 microstrip. The ratio of voltage to current in a travelling wave is the characteristic impedance $Z_0 = sqrt(L \/ C)$, set by geometry, not length. When a wave meets a load $Z_L$, a fraction reflects:

$ Gamma = (Z_L - Z_0) / (Z_L + Z_0), quad "VSWR" = (1 + |Gamma|) / (1 - |Gamma|), quad "RL" = -20 log_10 |Gamma|. $

An open end reflects the whole wave with the same sign, a short reflects it inverted, a matched load absorbs it. A wire is a transmission line, rather than a node, once its round-trip delay is a significant fraction of the signal's rise time; a common rule is one sixth. With 1 ns edges that is about 25 mm of FR-4, regardless of the clock frequency.

#fig("/figures/u1-tdr.svg", caption: [A step launched into 10 m of coax with three terminations, as Lab 1.5.1 will capture it. The time to the reflection gives the cable's velocity; its sign and size give the termination.])

*The Smith chart.* Every passive impedance maps to a point inside the unit circle of the reflection coefficient $Gamma$. Circles of constant resistance and arcs of constant reactance are drawn on it, so a series inductor moves a point along a resistance circle and a length of line rotates it around the centre. It is the map on which matching networks are designed and on which a network analyser shows an antenna.

#fig("/figures/u1-smith.svg", caption: [Matching a 25 − j15 Ω load to 50 Ω at 868 MHz with an L-network: a series inductor moves the point to the unit-conductance circle, then a shunt capacitor moves it to the centre.], width: 78%)

*S-parameters.* At radio frequencies voltages and currents at a port are hard to measure; incident and reflected waves are easy. A two-port is described by four complex numbers per frequency: $S_(11)$ (reflection at the input), $S_(21)$ (transmission forward), $S_(12)$ (transmission backward) and $S_(22)$ (reflection at the output). A cable has $S_(21)$ close to 0 dB minus its loss; a 20 dB attenuator has $S_(21) = -20$ dB and small $S_(11)$; a filter's $S_(21)$ is its passband and stopband. A vector network analyser measures them after a calibration with known standards (short, open, load and through) removes its own errors and those of its cables. Uncalibrated measurements are meaningless above a few hundred megahertz.

*Antennas.* An antenna is a matched transition from a transmission line to free space. A half-wave dipole is resonant at about 0.47 to 0.48 free-space wavelengths and has 2.15 dBi of gain; a quarter-wave monopole needs a ground plane to supply the missing half. Gain is directivity, not amplification: an antenna concentrates power in some directions at the expense of others. Near metal, carbon fibre or a hand, an antenna detunes and its pattern distorts, which is why antenna placement on a drone is a measurement, not a guess. Polarisation must match between the two ends, or a few to 20 dB is lost.

*Propagation and the link budget.* In free space the received power falls with the square of distance and of frequency:

$ "FSPL" = 20 log_10 (d) + 20 log_10 (f) + 32.44 quad (d "in km", f "in MHz"). $

The link budget adds transmitter power and antenna gains, subtracts path loss and cable losses, and compares the result with the receiver's sensitivity. The difference is the fade margin, which must cover multipath, obstruction of the Fresnel zone (the ellipsoid around the line of sight that must be mostly clear, about 9 m in radius at the midpoint of a 1 km link at 868 MHz) and antenna nulls. Low drones lose margin to the ground.

#fig("/figures/u1-link-budget.svg", caption: [The 868 MHz telemetry link budget at 1 km, stage by stage. The fade margin is what is left for everything free-space propagation ignores.])

*Noise.* A matched resistor at 290 K delivers $k T B$ of noise power, −174 dBm in each hertz of bandwidth. A receiver's noise figure is how much worse it is than that. Sensitivity is approximately $-174 + 10 log_10 B + "NF" + "SNR"_"min"$ dBm: halving the data rate halves the bandwidth and buys 3 dB. Every radio datasheet's sensitivity table is this equation evaluated.

*Instruments and how not to destroy them.* A spectrum analyser sweeps a narrow filter (the resolution bandwidth) across a band and shows power against frequency. Narrower RBW lowers the displayed noise floor by $10 log_10$ of the ratio and slows the sweep. Its input is a mixer with a maximum safe power, typically a few dBm: a radio transmitting +20 dBm connected directly will destroy it. Always put enough attenuation in front, and know the arithmetic: +20 dBm through 30 dB is −10 dBm. A software-defined radio digitises a band around a tuned frequency as complex samples, $I + j Q$, so negative and positive frequencies around the centre are distinct, and does everything else in software.

#fig("/figures/u1-instrument-chain.svg", caption: [The conducted test setup used from here on. The attenuators protect the instrument, set the received level, and stop the transmitter seeing a mismatch.])

== Reading

- Bogatin, _Signal and Power Integrity, Simplified_, 3rd ed., chapters 1 to 3 and 7 to 8 (transmission lines and reflections).
- Pozar, _Microwave Engineering_, 4th ed., chapters 2 (transmission-line theory), 4.3 (S-parameters) and 5.1 (L-section matching). Dense; read for the ideas and do the worked examples.
- The ARRL Handbook or Antenna Book chapters on dipoles, monopoles and feed lines, for intuition from people who build antennas.
- Lyons, _Understanding Digital Signal Processing_, 3rd ed., chapter 8 (quadrature signals) before Lab 1.5.5.
- The tinySA Ultra and your VNA's user guides, including their specified maximum input levels.

== Labs

#safety[Never connect any transmitter output directly to the tinySA, the VNA or the RTL-SDR. Keep at least 40 dB of attenuation between a +20 dBm radio and any of them, and check the arithmetic in the notebook before you connect anything.]

#lab([Reflections on a cable], goal: [see a transmission line in the time domain.], time: [3 h], kit: [SN74HC14N oscillator from Lab 1.1.4, 10 m BNC coax, BNC tee, 50 Ω terminator, oscilloscope.])[
+ Drive the coax through a 47 Ω series resistor from one SN74HC14N output running at about 100 kHz. Probe the near end with the spring ground tip.
+ Capture the near-end waveform with the far end open, shorted and terminated in 50 Ω.
+ From the delay to the reflection compute the cable's velocity factor; compare with the cable's datasheet.
+ Replace the 47 Ω source resistor with a short and explain the extra steps in terms of a second reflection at the source.

#done-when(
  [Three captures show the open, short and matched cases with the reflection labelled.],
  [The velocity factor is within 5 % of the datasheet value.],
)
#evidence([The four captures; the velocity calculation.])
] <lab-tdr>

#lab([The network analyser and S-parameters], goal: [calibrate an instrument and trust its numbers.], time: [4 h], kit: [LiteVNA 64 with its calibration kit, SMA cables and adapters, an Amphenol 50 Ω terminator, the 10, 20 and 30 dB attenuators, the two Linx 868 MHz antennas.])[
+ Calibrate from 50 MHz to 3 GHz with short, open, load and through at the ends of your test cables. Save the calibration.
+ Measure the terminator ($S_(11)$ should be better than −30 dB), then an open and a short, and find them on the Smith chart.
+ Measure $S_(21)$ of each attenuator and of a cable; compare with their ratings.
+ Measure $S_(11)$ of each 868 MHz antenna in free space. Read off the resonant frequency, the −10 dB bandwidth and the VSWR at 868 MHz.
+ Remove the calibration and repeat one measurement to see how wrong an uncalibrated instrument is.

#done-when(
  [Each attenuator measures within 0.5 dB of its rating up to 1 GHz.],
  [Both antennas' resonance, bandwidth and VSWR at 868 MHz are tabulated.],
  [The uncalibrated comparison is captured.],
)
#evidence([Exported Touchstone (.s1p and .s2p) files; screenshots of the Smith chart and $S_(21)$ traces.])
] <lab-vna>

#lab([Build and tune an antenna], goal: [make a resonant antenna and see what a drone frame does to it.], time: [3 h], kit: [SMA bulkhead socket, copper-clad board at least 15 cm square, 1 mm copper wire, LiteVNA 64.])[
+ Compute the free-space quarter-wavelength at 868 MHz. Solder a wire 5 % longer than that to the bulkhead's centre pin, with the bulkhead mounted through the middle of the copper-clad ground plane.
+ Measure $S_(11)$ and trim the wire in 2 mm steps until the resonance is at 868 MHz. Record length against resonant frequency.
+ Bring a hand, then an aluminium plate, then a carbon-fibre sheet (or the drone frame) to 2 cm from the antenna and record the shift.

#done-when(
  [The antenna resonates within 10 MHz of 868 MHz with return loss better than 15 dB.],
  [The detuning table shows the shift for each nearby material.],
)
#evidence([Length-against-frequency table; $S_(11)$ captures before and after trimming; the detuning table.])
] <lab-antenna>

#lab([The spectrum analyser, safely], goal: [read a spectrum and know what the instrument is telling you.], time: [3 h], kit: [tinySA Ultra, RTL-SDR Blog V4, attenuators, an antenna for each.])[
+ With an antenna, find the FM broadcast band, a mobile-network downlink and Wi-Fi at 2.4 GHz. Measure the noise floor at RBW settings of 3 kHz, 30 kHz and 300 kHz and compare the change with $10 log_10$ of the RBW ratio.
+ Use the tinySA's signal-generator output at −30 dBm through 20 dB of attenuation into the RTL-SDR. Predict the level at the SDR and check it. The tinySA Ultra's input is rated +6 dBm absolute maximum and 0 dBm for normal use; keep below both.
+ Build a 10 + 20 dB chain and measure it with the generator and the analyser. Confirm the dB arithmetic.
+ Write the attenuation you will use in Chapter 3.2 for the CC1312R's +14 dBm maximum into each instrument, with the maximum input of each.

#done-when(
  [The noise-floor change with RBW agrees with $10 log_10$ of the ratio within 2 dB.],
  [The protection plan for each instrument is written with numbers from its manual.],
)
#evidence([Screenshots of the three bands and the RBW comparison; the protection plan.])
] <lab-spectrum>

#lab([An FM receiver from scratch], goal: [understand complex baseband by building a receiver in software.], time: [6 h], kit: [RTL-SDR Blog V4, its antenna, Python with NumPy and SciPy.])[
+ Capture 10 seconds of complex samples at 2.4 MSa/s centred 250 kHz away from a strong FM station (to keep the station away from the DC spike). Plot the spectrum and a waterfall.
+ Shift the station to 0 Hz by multiplying by a complex exponential, low-pass filter and decimate to about 240 kSa/s.
+ Demodulate with the polar discriminator, the angle of $x[n] dot overline(x[n-1])$, then apply 50 µs de-emphasis (the European standard) and decimate to 48 kHz. Write a WAV file and listen.
+ Measure the signal-to-noise ratio of the demodulated audio in a quiet passage, and repeat with the antenna disconnected through 20 dB of attenuation.

#done-when(
  [The WAV file is intelligible broadcast audio, produced by your code from raw samples with no SDR library beyond the capture.],
  [The spectrum, waterfall and SNR comparison are in the notebook.],
)
#evidence([The notebook or script; the plots; a short audio clip.])
] <lab-fm>

#lab([Link budgets for the drone], goal: [decide whether the drone's radios will reach before building them.], time: [3 h, paper and Python])[
+ For the 868 MHz telemetry link: transmit power at the level you choose in Chapter 3.2, 2 dBi antennas, 1 dB of cable loss at each end, and the CC1312R's sensitivity from its datasheet at your intended data rate. Compute the free-space range and the range with a 20 dB fade margin.
+ For the 2.4 GHz control link: the receiver's published sensitivity and the transmitter's power. Compute the same two ranges.
+ Plot received power against distance for both links on one log axis with the sensitivity lines.
+ Compute the first Fresnel radius at the midpoint of each link at 500 m and say how high the drone and the ground antenna must be.

#done-when(
  [Both budgets are tabulated with sources for every number, and the plot is committed.],
  [The notebook states the data rate and power you will use for telemetry and why.],
)
#evidence([Budget tables; the plot; the Fresnel calculation.])
] <lab-link-budget>

== Problem set

+ A receiver's sensitivity is −110 dBm at 50 kbit/s. Estimate it at 5 kbit/s and at 500 kbit/s, assuming bandwidth scales with data rate. What does the drone gain and lose at each extreme?
+ A 50 Ω coax with velocity factor 0.66 is 3 m long. How long does a reflection take to return? A 2 ns edge is launched; is this cable a transmission line for it?
+ Design an L-network to match 12 Ω to 50 Ω at 868 MHz. Give both topologies and the component values, and say which you would choose for harmonic suppression.
+ A quarter-wave transformer matches 50 Ω to 100 Ω. What impedance and electrical length does it need, and what happens to the match at 1.5 times the design frequency?
+ Two signals at −60 dBm and −63 dBm fall in the same channel. What is the total power?
+ A spectrum analyser's displayed noise floor is −120 dBm at 10 kHz RBW. Can it see a −135 dBm/Hz noise-like signal 20 MHz wide? What setting helps?
+ A radio with a 6 dB noise figure must decode a signal that needs 10 dB SNR in a 150 kHz bandwidth. What is its sensitivity?
+ Explain why an RTL-SDR shows a spike at its centre frequency and why the FM lab tunes 250 kHz away.

== Deliverables and stretch

*Deliverables.* Touchstone files and captures from the VNA; the tuned antenna, kept for Chapter 3.2; the FM receiver script; the drone's link budgets with your chosen telemetry data rate and power.

*Stretch.* Build a 868 MHz low-pass filter from 0805 C0G capacitors and an air-wound inductor on copper-clad board, design it on the Smith chart and measure it on the VNA. Wind an H-field near-field probe from semi-rigid coax and find the loudest frequencies of the buck EVM from Chapter 1.4 with the tinySA.

#checklist(
  [*Lab 1.5.1:* three termination captures and a velocity factor within 5 %.],
  [*Lab 1.5.2:* calibrated measurements of terminator, attenuators, cable and antennas, with Touchstone files committed.],
  [*Lab 1.5.3:* antenna tuned within 10 MHz of 868 MHz with return loss better than 15 dB; detuning table.],
  [*Lab 1.5.4:* RBW and noise-floor comparison; the instrument protection plan written.],
  [*Lab 1.5.5:* intelligible FM audio from your own demodulator.],
  [*Lab 1.5.6:* both link budgets with sources, the plot, and the chosen telemetry rate and power.],
  [*Problem set:* all eight answered.],
  [*You can explain*, without notes: decibel arithmetic, the reflection coefficient, what each S-parameter means, the link-budget equation, and why the instruments need attenuators.],
)
