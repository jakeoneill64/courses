#import "../lib/template.typ": *

= The analogue signal chain <ch-analogue>

#chapter-meta(
  weeks: [2 weeks],
  builds: [Two op-amp stages measured against their datasheets; a second-order filter with a measured Bode plot; a characterised 16-bit ADC with a demonstrated alias; a calibrated load cell on a 24-bit ADC that becomes Unit 3’s thrust stand.],
  needs: [Bench kit, function generator, Raspberry Pi 5, LM358P and TLV2372IP op-amps, LM4040 reference, the Adafruit ADS1115 and Olimex BB-ADS1220 breakouts, the SparkFun 5 kg load cell.],
)

#why[
  Every sensor in this course produces an analogue quantity that something must amplify, filter and digitise before software sees it: the shunt voltage behind a power reading, the bridge output of a load cell, the beat frequency of a radar. The chain's weakest link sets the accuracy of the whole measurement, and a datasheet's headline resolution is almost never that link. This chapter is how you will judge every ADC, front end and sensor you choose for OMH's boards and the drone.
]

#skip-test(
  rule: [If all five are easy, do Labs 1.2.3 and 1.2.4 only.],
  [An op-amp with a 1 MHz gain-bandwidth product is wired as a non-inverting amplifier with a gain of 21. What is its −3 dB bandwidth, and what limits a 4 V peak-to-peak output at 50 kHz if the slew rate is 0.5 V/µs?],
  [Design a unity-gain Sallen-Key low-pass filter with a 1 kHz Butterworth response. Give component values and say what sets Q.],
  [A 12-bit ADC samples at 10 kSa/s. Where does a 9.3 kHz tone appear in the sampled data, and what must sit in front of the ADC to stop it?],
  [What is the thermal noise voltage of a 10 kΩ resistor over a 10 kHz bandwidth at room temperature, and how does it compare with one LSB of a 16-bit ADC with a ±2.048 V range?],
  [Why does a ratiometric bridge measurement not care about the exact excitation voltage?],
)

== Core ideas

*The chain.* A measurement passes through a transducer (physical quantity to voltage or current), conditioning (gain, level shift, impedance buffering), an anti-alias filter, a sample-and-hold, a quantiser, and digital filtering. Each stage adds error: offset, gain error, nonlinearity, noise, drift and bandwidth limits. You budget them the way you budget power.

#fig("/figures/u1-signal-chain.svg", caption: [The signal chain, with the dominant error each stage adds. Unit 3’s thrust stand, radar and power telemetry are all instances of this picture.])

*The op-amp, with negative feedback.* An ideal op-amp has infinite gain, infinite input impedance and zero output impedance. With negative feedback two rules follow: the output does whatever it must to make the two inputs equal, and the inputs draw no current. The non-inverting amplifier has gain $G = 1 + R_f \/ R_g$; the inverting amplifier has $G = -R_f \/ R_"in"$. A real op-amp departs from the ideal in ways the datasheet quantifies, and each departure becomes an error term:

- *Gain-bandwidth product.* Open-loop gain falls at 20 dB per decade, so the closed-loop bandwidth is roughly GBW divided by the noise gain $1 + R_f \/ R_g$. A 1 MHz part at a gain of 100 has about 10 kHz of bandwidth.
- *Slew rate.* The output can change only so fast. A sine of peak amplitude $A$ at frequency $f$ needs $2 pi f A$ volts per second; above that the output becomes a triangle.
- *Input offset voltage and bias current.* A few millivolts of offset, multiplied by the gain, appears at the output as a DC error. Zero-drift parts such as TI's OPA2333 reduce it to microvolts at the cost of bandwidth.
- *Supply rails.* "Rail-to-rail" inputs and outputs reach within tens of millivolts of the supplies. An LM358 on 5 V cannot drive its output above about 3.5 V; a TLV2372 can reach nearly 5 V. On single-supply boards this decides whether your signal fits.
- *Stability.* A capacitive load or a feedback capacitor in the wrong place adds phase shift and turns an amplifier into an oscillator. Read the "capacitive load" figure in the datasheet before driving a cable or an ADC input.

#fig("/figures/u1-opamps.svg", caption: [The two basic configurations. With feedback, the inverting input of the inverting amplifier is a virtual ground; the non-inverting amplifier presents the source with the op-amp's very high input impedance.], width: 90%)

*Filters.* A first-order RC low-pass has its −3 dB point at $f_c = 1 \/ (2 pi R C)$ and falls at 20 dB per decade. Two poles fall at 40 dB per decade. The unity-gain Sallen-Key low-pass is the workhorse second-order active filter: with equal resistors $R$, the capacitor to the output $C_1$ and the capacitor to ground $C_2$,

$ f_0 = 1 / (2 pi R sqrt(C_1 C_2)), quad Q = 1/2 sqrt(C_1 / C_2). $

A Butterworth response (maximally flat, $Q = 0.707$) needs $C_1 = 2 C_2$. Higher Q peaks and rings; lower Q droops early. Phase matters as much as magnitude: a filter delays signals, and in a control loop that delay is lost phase margin, which Chapter 3.1 will charge you for.

#fig("/figures/u1-sallen-key.svg", caption: [A 1 kHz Sallen-Key low-pass filter and its response. The measured points are what Lab 1.2.2 should produce; the curves are the second-order model.])

*Sampling and aliasing.* Sampling at $f_s$ cannot distinguish a tone at $f$ from tones at $|f - k f_s|$ for any integer $k$. Everything above $f_s \/ 2$ (the Nyquist frequency) folds back into the band you care about, indistinguishable from real signal. The only cure is to remove it before the sampler, with an analogue anti-alias filter, or to sample so fast that a simple filter suffices and then decimate digitally.

#fig("/figures/u1-aliasing.svg", caption: [A 9.3 kHz tone sampled at 10 kSa/s is indistinguishable from a 700 Hz tone. The samples are the same; only the analogue filter in front of the ADC can tell them apart.])

*Quantisation.* An $N$-bit converter with full-scale range FSR has a step of $"LSB" = "FSR" \/ 2^N$. Quantisation alone limits the signal-to-noise ratio of a full-scale sine to $6.02 N + 1.76$ dB. Real converters add thermal noise, reference noise and nonlinearity, so datasheets quote an effective number of bits, $"ENOB" = ("SINAD" - 1.76) \/ 6.02$, or noise-free bits. A 24-bit delta-sigma converter with 18 noise-free bits is an excellent 18-bit converter.

*Converter architectures.* A successive-approximation (SAR) ADC samples instantly onto a capacitor and binary-searches the value; it is fast, has no latency, and needs a driver that can recharge its sampling capacitor in time. A delta-sigma ADC oversamples with a one-bit quantiser and filters digitally; it is slow, precise and has a built-in sinc filter that rejects some interference (for example 50 and 60 Hz at a chosen data rate) and attenuates, but does not remove, aliases. TI's ADS1115 (16-bit, up to 860 samples per second) and ADS1220 (24-bit, up to 2,000) are both delta-sigma; the ADC inside the TM4C microcontroller you meet in Unit 2 is a 12-bit SAR.

*Noise.* A resistor generates thermal noise of density $sqrt(4 k T R)$, about 4 nV/√Hz for 1 kΩ at room temperature; over a bandwidth $B$ the RMS voltage is that density times $sqrt(B)$. Averaging $N$ independent samples reduces random noise by $sqrt(N)$, so every factor of four in oversampling buys one bit, until offset, drift and 1/f noise stop helping.

*References.* An ADC measures relative to its reference. A 0.1 % reference makes at best a 0.1 % measurement, whatever the bit count. The cure for a poor reference is a ratiometric measurement: excite the sensor from the same voltage the ADC uses as its reference, and the reference cancels.

*Bridges.* A Wheatstone bridge of four strain gauges produces a differential output of a few millivolts per volt of excitation at full load. A 5 kg load cell rated at 2 mV/V gives 10 mV at full scale from 5 V. Measured ratiometrically with a 24-bit ADC and a gain of 128, the noise floor is a fraction of a gram.

#fig("/figures/u1-bridge.svg", caption: [A load cell measured ratiometrically. The excitation that drives the bridge is also the ADC's reference, so supply drift cancels.], width: 92%)

*Grounding and interference.* A measurement is the difference between two wires; currents flowing in the ground wire add their voltage drop to your signal. Keep sensor returns separate from motor and LED currents, twist signal pairs, and use differential inputs when the sensor is far from the ADC.

== Reading

- Horowitz and Hill, _The Art of Electronics_, 3rd ed.: chapter 4 (op-amps: 4.1 to 4.4), chapter 6 (filters: 6.1 to 6.3), chapter 13 sections 13.1 to 13.9 (ADCs and DACs).
- TI, _Op Amps for Everyone_ (free; SLOD006): chapters 3, 5 and 16 (Sallen-Key filters).
- The ADS1115 and ADS1220 datasheets, cover to cover: register maps, noise tables, digital filter response.
- Kester (Analog Devices), "MT-001 Taking the Mystery out of the Infamous Formula SNR = 6.02N + 1.76 dB" and "MT-002 What the Nyquist Criterion Means to Your Sampled Data System" (free tutorials).

== Labs

#lab([Op-amp stages and their limits], goal: [measure GBW, slew rate, offset and output swing, and see where each matters.], time: [4 h], kit: [LM358P, TLV2372IP, function generator, oscilloscope, 5 V supply.])[
+ Build a non-inverting amplifier with $G = 11$ ($R_f = 10$ kΩ, $R_g = 1$ kΩ) on a single 5 V supply, first with the LM358P and then with the TLV2372IP. Drive it with a 100 mV peak-to-peak sine on a 200 mV offset.
+ Measure gain against frequency from 100 Hz to 1 MHz. Find each part's −3 dB point and compare it with GBW divided by 11.
+ Rewire as a unity-gain buffer and drive a 0 to 3 V square wave. Measure the slew rate from the output edge and compare with the datasheet.
+ Ground the input of the $G = 11$ stage and measure the output DC level; compute the input offset voltage.
+ Increase the input until the output clips. Record the highest and lowest output each part reaches on 5 V.

#done-when(
  [Measured bandwidths are within a factor of two of GBW/11 for both parts, and the notebook explains the remainder.],
  [Slew rates and offsets are measured for both parts and compared with the datasheet's typical and maximum values.],
  [A table records the output swing limits and states which part you would use to drive a 0 to 3.3 V ADC input from 5 V.],
)
#evidence([Bode-style table and plot per part; slew-rate capture; offset measurement; swing table.])
] <lab-opamp>

#lab([A second-order filter and its Bode plot], goal: [design to a specification, then measure magnitude and phase.], time: [4 h], kit: [TLV2372IP, 11 kΩ resistors, 22 nF and 10 nF film or C0G capacitors, function generator, oscilloscope.])[
+ Design a unity-gain Sallen-Key low-pass with $f_0 = 1$ kHz and $Q approx 0.707$. Choose preferred values (for example $R = 11$ kΩ, $C_1 = 22$ nF, $C_2 = 10$ nF) and compute the $f_0$ and $Q$ they give.
+ Build it. At ten frequencies from 100 Hz to 20 kHz measure input and output amplitude and the phase shift (from the time delay between zero crossings).
+ Plot measured magnitude and phase against the model in Python.
+ Drive a 100 Hz square wave and capture the output. Measure the overshoot and relate it to $Q$.
+ Swap $C_1$ and $C_2$ and repeat the square-wave test. Explain what changed.

#done-when(
  [The measured −3 dB frequency is within 10 % of your design, and measured phase at $f_0$ is within 10° of −90°.],
  [The plot overlays measurement and model on log axes, committed with the data.],
  [The swapped-capacitor result is explained in terms of $Q$.],
)
#evidence([Design calculation; measurement table; overlay plot; two square-wave captures.])
] <lab-filter>

#lab([Sampling, aliasing and quantisation with the ADS1115], goal: [characterise a real converter and watch a tone fold.], time: [5 h], kit: [Raspberry Pi 5, ADS1115 breakout, LM4040 2.5 V reference, function generator.])[
+ Connect the ADS1115 to the Pi's I#super[2]C bus. Without a library, write a Python driver from the datasheet's register map: write the configuration register (input multiplexer, gain, data rate, single-shot or continuous) and read the conversion register. Confirm with `i2cdetect` and a logic-analyser capture of one conversion.
+ Short the input (differential, input to input) and record 2,000 samples at each of three gains and three data rates. Compute RMS noise in microvolts and noise-free bits, and compare with the datasheet's noise table.
+ Measure the LM4040’s output with the ADS1115 and with the multimeter. Compute both errors against the reference's nominal value and tolerance.
+ At 860 samples per second, sample a 20 Hz sine and reconstruct it. Then sample a 1,000 Hz sine: find the 140 Hz alias in an FFT of your samples, measure its amplitude, and compare with the attenuation predicted by the converter's sinc filter at 1,000 Hz.
+ Average groups of 4, 16 and 64 samples of the shorted input and plot the noise against group size.

#done-when(
  [The driver reads correct values at every gain without any library beyond `smbus2`.],
  [Your noise table agrees with the datasheet's within a factor of 1.5 at every setting.],
  [The alias appears at the predicted frequency, with an amplitude within 3 dB of the sinc-filter prediction.],
  [The averaging plot shows noise falling as $1 \/ sqrt(N)$ and the notebook says where it stops falling and why.],
)
#evidence([Driver source; noise table; FFT plot with the alias marked; averaging plot.])
] <lab-adc>

#lab([A load cell on a 24-bit converter], goal: [build the measurement that becomes Unit 3’s thrust stand.], time: [5 h], kit: [SparkFun 5 kg straight-bar load cell (TAL220B) with two plywood mounting blocks, Olimex BB-ADS1220 breakout (solder its headers), Raspberry Pi 5, calibration masses (coins, or kitchen weights).])[
+ Mount the load cell between two plates so that the load passes through it as the maker intends. Wire excitation, signal and the ADS1220’s reference inputs ratiometrically as in the figure above.
+ Write an SPI driver for the ADS1220 in Python from its register map: SPI mode 1, gain 128, 20 samples per second with simultaneous 50/60 Hz rejection, external reference on REFP0/REFN0, and the DRDY pin on a Pi GPIO so you read each conversion as it completes.
+ Calibrate with at least five known masses spanning the range (UK coins have specified masses: a £1 coin is 8.75 g and a 2p coin 7.12 g). Fit offset and scale; report the linearity error as a percentage of full scale.
+ Leave 1 kg on the cell for 15 minutes and log the reading every second. Measure the creep.
+ Halve the excitation voltage (if your breakout allows it) and show the calibrated reading barely changes.

#done-when(
  [A fitted calibration converts counts to grams with a residual under 0.1 % of full scale at every point.],
  [The noise with no load is quoted in grams RMS, and the creep over 15 minutes is quantified.],
  [The ratiometric claim is demonstrated, or the notebook explains why your breakout could not test it.],
)
#evidence([Wiring photo; driver source; calibration plot with residuals; creep log plot.])
] <lab-loadcell>

== Problem set

+ An op-amp with 3 MHz GBW and 0.5 V/µs slew rate amplifies a 20 kHz signal with a gain of 51. What is the closed-loop bandwidth, and what is the largest undistorted output amplitude at 20 kHz?
+ Design a two-pole Butterworth low-pass at 200 Hz in front of an ADC sampling at 1 kSa/s. How much does it attenuate a tone at 800 Hz, which aliases to 200 Hz? What order would you need for 60 dB?
+ Compute the thermal noise of a 100 kΩ source resistance over 1 kHz, and say whether it matters to an ADS1220 at a gain of 128.
+ An ideal 12-bit ADC has a 3.3 V range. What is the LSB, the ideal SNR, and the SNR if the input sine is 10 dB below full scale?
+ A delta-sigma ADC at 20 samples per second has a sinc response with nulls at multiples of 20 Hz. Explain why it rejects both 50 and 60 Hz mains pickup, and what it does to a 25 Hz signal.
+ A 5 kg load cell gives 2 mV/V and is excited at 5 V; the ADS1220 at a gain of 128 has 100 nV RMS of noise at 20 samples per second. What is the resolution in grams? What does averaging ten readings give, at what cost?
+ A sensor 2 m from the ADC shares a ground wire with a fan drawing 300 mA, and the wire has 0.1 Ω of resistance. What error appears on a single-ended reading, and how do you remove it?
+ Show that a ratiometric measurement cancels the excitation voltage, and name the two errors it does not cancel.

== Deliverables and stretch

*Deliverables.* The ADS1115 and ADS1220 drivers in the labs repository, with a README stating their measured noise. The filter design and Bode overlay. The calibrated load-cell rig, labelled and kept: it is the thrust stand of Chapter 3.1.

*Stretch.* Build a two-stage instrumentation amplifier from the TLV2372IP and compare it with the ADS1220’s internal PGA. Measure the ADS1220’s internal temperature sensor against the TMP117 you meet in Chapter 1.3.

#checklist(
  [*Lab 1.2.1:* bandwidth, slew rate, offset and swing measured for both op-amps and compared with the datasheet.],
  [*Lab 1.2.2:* filter within 10 % of design, Bode overlay committed, the $Q$ experiment explained.],
  [*Lab 1.2.3:* library-free ADS1115 driver; noise table within a factor of 1.5 of the datasheet; alias found at the predicted frequency and amplitude.],
  [*Lab 1.2.4:* load cell calibrated to 0.1 % of full scale with creep quantified; the rig kept for Unit 3.],
  [*Problem set:* all eight answered with units; problems 2 and 6 checked numerically in Python.],
  [*You can explain*, without notes: GBW and slew rate, why aliasing cannot be fixed after sampling, what ENOB means, and why ratiometric measurement cancels the reference.],
)
