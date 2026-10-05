#import "../lib/template.typ": *

= Microwave synthesis and FMCW radar <ch-radar>

#chapter-meta(
  weeks: [3 weeks],
  builds: [A TI frequency synthesiser programmed from your own register calculator over SPI from the Pi; measured lock time, loop dynamics and fractional spurs; a frequency chirp generated and measured sample by sample; an FMCW radar simulator written from first principles; a configured 60 GHz TI radar measuring range as an altimeter, read over UART by your own parser; raw radar samples captured and processed with your simulator's signal chain.],
  needs: [LMX2572EVM with its Reference PRO board, the bench supply with an SMA power lead, the IWRL6432BOOST, the FTDI C232HM cable, the tinySA, the RTL-SDR, the 10 and 30 dB attenuators and 50 Ω terminators, the oscilloscope, the Raspberry Pi 5, the Windows PC with TICS Pro, UniFlash and MMWAVE-L-SDK, a tape measure.],
)

#why[
  Every high-speed interface in a server begins at a phase-locked loop: PCIe, Ethernet SERDES, DDR and the CPU's own clocks are all synthesised from a crystal, and their jitter budgets are phase-noise budgets in disguise. Microwave synthesis is that subject at its clearest, because you can see the spectrum. Radar is the payoff: a chirp from a synthesiser, mixed with its own echo, gives range as a frequency, and TI's 60 GHz radar-on-a-chip does it at milliwatts. The drone uses one as its altimeter in Chapter 3.5. You will understand every number in its configuration because you will have simulated the whole chain first.
]

#skip-test(
  rule: [If all five are easy, do Labs 3.3.4 and 3.3.5 only.],
  [A fractional-N synthesiser has a 100 MHz phase-detector frequency and a VCO range of 3.2 to 6.4 GHz. Give a divider setting and an output divider that produce 868.000 MHz.],
  [Where does an integer-boundary spur appear when the VCO runs at 3,500.1 MHz with a 100 MHz phase detector and the output is the VCO divided by four?],
  [An FMCW radar sweeps 4 GHz in 40 µs. What beat frequency does a target at 10 m produce, and what is the range resolution?],
  [How does an FMCW radar measure velocity, and what sets the maximum unambiguous velocity?],
  [Why does a phase-noise skirt on a spectrum analyser not tell you a synthesiser's phase noise unless the analyser is much better than the source?],
)

== Core ideas

*The phase-locked loop.* A voltage-controlled oscillator (VCO) is free-running and drifts; a crystal reference is stable but fixed. A PLL divides the VCO's output by $N$, compares its phase with the reference (after an $R$ divider) at the phase-frequency detector, and drives the VCO's tuning voltage through a charge pump and a loop filter until the two agree. In lock, $f_"VCO" = N f_"PD"$. An output (channel) divider then reaches frequencies below the VCO's range: the LMX2572’s VCO covers 3.2 to 6.4 GHz, and its divider takes the output down to 12.5 MHz.

#fig("/figures/u3-pll.svg", caption: [The LMX2572 as a block diagram. Lab 3.3.1 computes every number in this picture, writes it over SPI and checks the result on the spectrum analyser.])

*Fractional-N.* With an integer $N$, the output step is $f_"PD"$, which is too coarse at 100 MHz. A fractional-N synthesiser switches $N$ between neighbouring integers with a delta-sigma modulator so that its average is $N + "NUM"\/"DEN"$; with a 32-bit denominator the step is a fraction of a hertz. The price is noise and spurs. Quantisation noise is pushed to high offsets, where the loop filter removes it. Spurs appear where the fraction is nearly an integer: an integer-boundary spur sits at the distance between $f_"VCO"$ and the nearest multiple of $f_"PD"$, divided by the output divider, and only the loop filter attenuates it. Moving $f_"PD"$ or the VCO frequency moves the spur.

*Loop dynamics.* The charge-pump current, the VCO gain (66 MHz/V on this EVM) and the loop filter set the loop bandwidth and phase margin; the EVM is designed for 115 kHz and 48°. Inside the bandwidth the output follows the reference and phase-detector noise multiplied by $N$ (20 log#sub[10] $N$ in decibels); outside it the VCO's own noise dominates. Wider loops lock faster and suppress more VCO noise but pass more reference noise and spurs. Lock time is the VCO calibration (choosing a band and capacitor setting) plus the loop's analogue settling, which you can watch on the tuning voltage.

*Phase noise and jitter.* A real oscillator's spectrum is not a line but a skirt: single-sideband phase noise $cal(L)(f)$ in dBc/Hz at offset $f$. Integrated over the offsets that matter, it is RMS jitter, which is how PCIe and Ethernet budgets state it. Measuring it needs an instrument cleaner than the source; the tinySA's own local oscillator is far noisier than the LMX2572, so on it you see the analyser. That lesson, that every measurement includes the instrument, matters more than the number.

*FMCW radar.* A frequency-modulated continuous-wave radar transmits a chirp whose frequency rises linearly with slope $S = B \/ T_c$ over bandwidth $B$. The echo from a target at range $R$ returns after $tau = 2R\/c$ and, mixed with the chirp still being transmitted, produces a beat at $f_b = 2 R S \/ c$. A Fourier transform of the sampled beat signal over one chirp is a range profile. Range resolution is $Delta R = c \/ 2B$, about 3.75 cm for 4 GHz. The maximum range is set by the highest beat frequency the receiver's IF filter and ADC pass: $R_max = f_"IF,max" c \/ 2S$.

#fig("/figures/u3-fmcw.svg", caption: [FMCW in one picture: the transmitted and received chirps, the beat frequency between them, and the range profile its Fourier transform produces. Lab 3.3.4 simulates exactly this.])

*Velocity and angle.* A moving target changes the echo's phase from chirp to chirp by $Delta phi = 4 pi v T_c \/ lambda$, so a second Fourier transform across chirps, at each range bin, gives velocity: the range-Doppler map. The maximum unambiguous velocity is $lambda \/ 4 T_c$ and the velocity resolution $lambda \/ 2 T_f$ for a frame of length $T_f$. With several receive antennas spaced $lambda\/2$ apart, the echo's phase across antennas gives its angle, and a third transform over antennas gives an angle spectrum. With two transmitters taking turns (TDM-MIMO), two transmit and three receive antennas act as a six-element virtual array.

#fig("/figures/u3-range-doppler.svg", caption: [A simulated range-Doppler map for the altimeter configuration: the floor as a strong stationary return and a walking person at 4 m. A CFAR detector marks cells that rise above their local noise estimate.], width: 92%)

*Detection.* A constant-false-alarm-rate (CFAR) detector compares each cell with the average of its neighbours, excluding a guard band, and declares a detection when it exceeds that average by a set factor. It adapts to clutter and noise floors that vary across the map. Windowing before each transform trades resolution for sidelobe level: a Hann window widens the main lobe but drops the first sidelobe from −13 dB to −31 dB, which keeps a strong floor return from hiding a weak target beside it.

*The radar equation and the ground.* For a point target received power falls as $1\/R^4$; for an extended surface filling the beam, such as the ground beneath a drone, it falls closer to $1\/R^2$, which is why altimeters are easy. Specular surfaces (calm water, polished floors) reflect away from the radar when it tilts; rough ground scatters back. On a drone the beam also sees the propellers, whose blades produce micro-Doppler sidebands, so mounting and range gating matter.

*TI's IWRL6432.* A 57 to 64 GHz FMCW radar-on-a-chip with two transmitters, three receivers, the chirp synthesiser, mixers, IF filters and ADCs, a hardware FFT accelerator and an Arm Cortex-M4F, designed for low-power sensing. The BoosterPack adds the antennas, an XDS110 debugger and a USB connection that powers the board and carries a UART. TI's MMWAVE-L-SDK provides a demo that runs the full chain on the chip and reports results over the UART as frames of type-length-value records; you configure it with text commands that set the chirp, the frame and the processing. Its raw ADC samples can also be streamed out over SPI, which Lab 3.3.6 uses to check the chip's processing against your own.

== Reading

- TI SNAU217B, _LMX2572EVM Evaluation Instructions_, all of it; the LMX2572 datasheet's sections on the PLL, VCO calibration, the channel divider, ramping, the register map and the recommended power-up sequence.
- Banerjee, _PLL Performance, Simulation, and Design_ (free from TI), chapters on loop filters, phase noise, spurs and lock time. Use TI's PLLatinum Sim tool alongside it.
- TI SPYY005, _The Fundamentals of Millimeter Wave Radar Sensors_; TI SWRA553, _Programming Chirp Parameters in TI Radar Devices_; and the "Introduction to mmWave Sensing: FMCW Radars" training series on TI's website.
- Richards, _Fundamentals of Radar Signal Processing_, 2nd ed., the chapters on the radar equation, waveforms and range processing, Doppler processing and CFAR detection.
- TI SWRU596, the IWRL6432BOOST user's guide: switch settings, flashing, and the BoosterPack and DCA1000 connectors. The MMWAVE-L-SDK documentation for the motion and presence demo's command-line interface and output format, and for SPI ADC streaming.

== Labs

#safety[The LMX2572EVM takes 3.0 to 3.6 V on its VCC connector: set the bench supply to 3.30 V with a 200 mA limit before connecting it, and check the polarity of your power lead with the meter. Terminate every unused RF output with 50 Ω. Fit the 10 dB attenuator on the tinySA input for every synthesiser measurement.]

#lab([A PLL you program], goal: [replace the vendor's GUI with a calculator and an SPI bus you own.], time: [8 h], kit: [LMX2572EVM, Reference PRO, bench supply with an SMA power lead, tinySA with the 10 dB attenuator, two 50 Ω terminators, Raspberry Pi 5, jumper wires, the Windows PC with TICS Pro.])[
+ Set up the EVM as SNAU217B section 2 describes: 3.3 V on VCC, the Reference PRO's 100 MHz output on OSCinP through the SMA adaptor with its other output terminated, RFoutAP through the attenuator to the tinySA and RFoutAM terminated. In TICS Pro, load the default mode and write all registers. Confirm 3 GHz on the tinySA and the lock LED.
+ Export TICS Pro's register file. Then remove the ribbon cable, keep the Reference PRO powered from a USB charger, and wire the Pi's SPI0 (SCLK, MOSI, CE0) and ground to the EVM's SCK, SDI and CSB test points, with a GPIO to CE and MUXout to a GPIO input. Set MUXout_SW switch 2 to Break so MUXout can carry readback.
+ Write `lmx2572.py`: from the datasheet's register map, compute the VCO frequency, channel divider, `PLL_N`, `PLL_NUM` and `PLL_DEN` for a requested output, patch those fields into TICS Pro's baseline, and program the device using the datasheet's power-up sequence. Read registers back over MUXout.
+ Lock at 868.000 MHz and 2,440.000 MHz. Check frequency and level on the tinySA and lock detect on MUXout. Then generate the same two frequencies in TICS Pro and diff its registers against yours.

#done-when(
  [Your code locks at both frequencies with lock detect asserted, and the tinySA confirms each within its frequency accuracy.],
  [Every register difference from TICS Pro's export is explained in the notebook.],
)
#evidence([The calculator source; the register diffs; tinySA captures; the readback log.])
] <lab-pll>

#lab([Loop dynamics, spurs and lock time], goal: [see the loop filter work, and find the spurs a fractional-N synthesiser makes.], time: [6 h], kit: [Lab 3.3.1’s set-up, oscilloscope with a 10× probe on the Vtune test point.])[
+ Lock time: alternate between 868 and 900 MHz from your code. Trigger the scope on CSB's last rising edge and capture MUXout's lock detect and the tuning voltage. Separate VCO calibration time from analogue settling.
+ Loop dynamics: make a small frequency step that needs no VCO calibration and capture the tuning voltage's settling. Estimate the natural frequency and damping, and compare with the 115 kHz and 48° design. Reduce the charge-pump current to a quarter and repeat.
+ Spurs: set the VCO to 3,500.1, 3,500.5 and 3,502 MHz with the output divider at 4, and find the integer-boundary spur at the output in each case. Tabulate its offset and level, then move it by changing the phase-detector frequency.
+ Phase noise, honestly: capture the noise skirt of the LMX2572 at 868 MHz and of the tinySA's own generator at the same frequency and settings. Explain why they look alike.

#done-when(
  [Lock time is split into calibration and settling, and the loop's natural frequency is measured at two charge-pump currents with the change explained.],
  [The spur offsets match your prediction at all three settings.],
)
#evidence([Scope captures; the settling fits; the spur table; the two phase-noise captures with the explanation.])
] <lab-pll-dynamics>

#lab([A chirp you can measure], goal: [generate a frequency ramp and measure its linearity sample by sample.], time: [6 h], kit: [Lab 3.3.1’s set-up, RTL-SDR, the 30 dB and 10 dB attenuators.])[
+ Configure the LMX2572’s calibration-free automatic ramp from SNAU217B section 3.2.2 (`OUT_FORCE`, `LD_DLY` and `PLL_DEN` as stated there), scaled so the output sweeps 2 MHz around 868 MHz in a triangle with 1 ms up and 1 ms down.
+ Feed the output through 40 dB of attenuation to the RTL-SDR and capture at 2.4 MS/s centred on the ramp.
+ Compute instantaneous frequency from the phase difference between samples. Fit the up and down slopes, plot the residual from a straight line, and measure what happens at each turnaround.

#done-when(
  [Measured slopes are within 1 % of the programmed slope, and linearity error and turnaround behaviour are quantified.],
)
#evidence([Register settings; the capture; frequency-against-time and residual plots.])
] <lab-chirp>

#lab([FMCW in simulation], goal: [build the whole radar signal chain before you touch the radar.], time: [8 h], kit: [Python with NumPy, SciPy and Matplotlib.])[
+ Write a simulator: chirp parameters (start frequency, slope, ADC rate and samples, chirps per frame, idle time), point targets with range, velocity and angle, and an extended floor; generate the complex beat signal at each of six virtual antennas with noise.
+ Process it: windowed range FFT, Doppler FFT, a cell-averaging CFAR detector, and an angle FFT for each detection. Show the range-Doppler map and a detection list.
+ Design the altimeter: range resolution under 5 cm, maximum range at least 15 m, 50 frames per second, and the lowest active duty cycle that meets them. Read the IWRL6432’s limits (bandwidth, slope, IF bandwidth, ADC rate) from its datasheet, and show each requirement met with the arithmetic.
+ Simulate the drone tilted by 20° over flat ground and plot the reported altitude against true height.

#done-when(
  [Simulated targets appear at the right range, velocity and angle within one bin, and the CFAR detects them with no false alarms in a noise-only run.],
  [The altimeter configuration meets every requirement, with the tilt error quantified.],
)
#evidence([The simulator; maps and detection lists; the configuration with its arithmetic.])
] <lab-fmcw-sim>

#lab([The IWRL6432 as an altimeter], goal: [configure a real radar from your design and measure it against a tape measure.], time: [8 h], kit: [IWRL6432BOOST, micro-USB cable, the Windows PC with UniFlash and the SDK's visualiser, the Raspberry Pi 5, the INA228, tape measure, a flat board as a target.])[
+ Set the SOP switches for flashing as SWRU596 describes, flash the motion and presence demo from MMWAVE-L-SDK with UniFlash, return the switches to functional mode and run TI's visualiser to confirm it works.
+ On the Pi, write a configuration loader that sends your Lab 3.3.4 configuration over the board's UART, and a parser for the demo's output frames (a magic word, a header and type-length-value records). Extract the range profile and the detections.
+ Point the radar at a wall and then down at the floor. Measure range from 0.3 to 5 m in ten steps against the tape measure, 100 frames at each, and report bias and spread.
+ Measure the board's current on its 5 V supply with the INA228 for the default configuration and yours, and compare with the duty-cycle estimate from your design.

#done-when(
  [Range error is under 3 cm RMS between 0.5 and 5 m.],
  [Measured power agrees with your duty-cycle estimate within 30 %, or the discrepancy is explained.],
)
#evidence([Loader and parser sources; the configuration; the range table; the power measurements.])
] <lab-iwrl>

#lab([Raw ADC data], goal: [check the chip's processing against your own, from the same samples.], time: [6 h], kit: [IWRL6432BOOST, FTDI C232HM-DDHSL-0 cable, the Windows PC with MMWAVE-L-SDK, Python with `pyftdi` on the Pi or your workstation.])[
+ Rebuild the demo with SPI ADC streaming enabled, as the SDK's documentation describes, and connect the FTDI cable to the pins it names.
+ Capture raw ADC frames with TI's receiver tool on the Windows PC. Then write your own receiver with `pyftdi` and confirm it captures identical frames.
+ Process the frames with your Lab 3.3.4 pipeline and compare your range profile with the one the chip reports for the same frame. Measure the floor return's signal-to-noise ratio.

#done-when(
  [Your range profile's peak matches the chip's within one bin on ten consecutive frames, and the SNR of the floor return is measured.],
)
#evidence([Your receiver; the comparison plots; the SNR measurement.])
] <lab-adc>

== Problem set

+ With $f_"PD" = 100$ MHz and `PLL_DEN` $= 2^32 - 1$, give the channel divider, `PLL_N` and `PLL_NUM` for 868.000 MHz and for 2,440.000 MHz. What is the frequency step at each output?
+ For an output of 875.03 MHz with the channel divider at 4 and $f_"PD" = 100$ MHz, where is the integer-boundary spur? Choose a different phase-detector frequency that moves it beyond the loop bandwidth.
+ In-band phase noise is approximately $cal(L)_"norm" + 10 log_10 f_"PD" + 20 log_10 N$. With $cal(L)_"norm" = -229$ dBc/Hz, compare 868 MHz synthesised with $f_"PD" = 100$ MHz and with $f_"PD" = 25$ MHz. Why do designers like high phase-detector frequencies?
+ A chirp sweeps 3 GHz in 30 µs. Compute the slope, the beat frequency at 2 m and at 15 m, the range resolution, and the maximum range if the IF bandwidth is 5 MHz.
+ At 60 GHz with a 120 µs chirp period, what is the maximum unambiguous velocity? With 32 chirps per frame, what is the velocity resolution?
+ Six virtual antennas spaced $lambda\/2$ apart: what is the angular resolution at broadside, and why do you get ambiguous angles if the spacing exceeds $lambda\/2$?
+ Explain why the floor return falls as roughly $1\/R^2$ when the floor fills the beam. By how many decibels does it fall from 1 m to 10 m, and how does that compare with a point target?
+ The drone tilts 15° with a radar whose beam is wide. What range does the strongest return report for a height of 5 m over flat rough ground, and over calm water?
+ A strong signal sits 100 kHz from a weak wanted signal. If the receiver's local oscillator has −100 dBc/Hz of phase noise at 100 kHz offset, how much noise does reciprocal mixing add in a 50 kHz channel, relative to the strong signal?

== Deliverables and stretch

*Deliverables.* `lmx2572.py` with its register diffs; the loop, spur and lock-time measurements; the chirp measurement; the FMCW simulator with the altimeter design; the radar loader, parser and range measurements; the raw-ADC receiver and comparison.

*Stretch.* Use the LMX2572’s FSK mode to transmit packets your Lab 3.2.6 demodulator decodes. Characterise the IWRL6432’s range accuracy against temperature using the TMP117. Add a Kalman tracker to the simulator and the parser that follows a walking person. Reproduce the chirp measurement for a 10 MHz ramp at 2.44 GHz with the tinySA's zero-span mode.

#checklist(
  [*Lab 3.3.1:* your calculator locks at 868 MHz and 2.44 GHz; every difference from TICS Pro explained.],
  [*Lab 3.3.2:* lock time split; loop dynamics at two charge-pump currents; spur offsets predicted; the phase-noise lesson written down.],
  [*Lab 3.3.3:* chirp slope within 1 %; linearity and turnaround measured.],
  [*Lab 3.3.4:* simulator with range, Doppler, CFAR and angle; altimeter configuration meets its requirements.],
  [*Lab 3.3.5:* range error under 3 cm RMS from 0.5 to 5 m; power measured against the estimate.],
  [*Lab 3.3.6:* your processing matches the chip's within one range bin.],
  [*Problem set:* all nine answered with units.],
  [*You can explain*, without notes: how a fractional-N PLL makes a frequency and why it makes spurs, what sets loop bandwidth, how a chirp turns range into frequency, and what each FFT in a radar chain is for.],
)
