#import "../lib/template.typ": *

= Motors, estimation and feedback control <ch-control>

#chapter-meta(
  weeks: [4 weeks],
  builds: [A calibrated thrust stand and a measured model of the drone's motor and propeller; field-oriented control written from scratch on a C2000 microcontroller, compared against a commercial ESC; an IMU driver with a measured noise model; an attitude estimator running on the flight-controller LaunchPad; a calibrated magnetometer; a PID controller that holds the drone frame level on a one-axis rig, designed in simulation first.],
  needs: [The Chapter 1.2 load-cell rig with the ADS1220, a second INA228 with the Bourns 1 mΩ shunt, the LAUNCHXL-F280025C, BOOSTXL-DRV8323RS and LVBLDCMTR, two SunnySky motors with props, two CloudPhoenix ESCs, the 3S pack and charger, an MSP-EXP432E401Y, the LSM6DSOX and LIS3MDL breakouts, the Tarot frame, the oscilloscope, the bench supply, safety glasses.],
)

#why[
  A server module and a drone are both machines that hold a variable at a setpoint against disturbances: inlet temperature through fan speed, attitude through motor thrust. Fan control, power capping, PCIe link training and the drone's flight controller all rest on the same three skills: measuring the thing you control, estimating what you cannot measure, and closing a loop with known stability margins. This chapter teaches them on hardware where a bad loop is visible and audible. It also builds the drone's propulsion model, its attitude estimator and its first controller, which Chapter 3.5 assembles into something that flies.
]

#skip-test(
  rule: [If all five are easy, do Labs 3.1.1, 3.1.5 and 3.1.7 only.],
  [A propeller gives 300 g of thrust at 5,000 rpm. Assuming thrust proportional to the square of speed, what speed gives 600 g, and roughly how does the electrical power scale?],
  [Write the Clarke and Park transforms, and explain why a current controller in the rotating frame needs only DC setpoints in steady state.],
  [A gyroscope has a constant bias of 0.5 °/s. What is the attitude error after 60 s of pure integration, and how does a complementary filter bound it?],
  [Derive the discrete PID update with a filtered derivative on the measurement and integrator clamping. Why differentiate the measurement rather than the error?],
  [A loop has 45° of phase margin at a crossover of 20 Hz. How much pure delay can you add before it becomes unstable?],
)

== Core ideas

*Propulsion.* A brushless motor with a fixed-pitch propeller produces thrust $T = k_T omega^2$ and drag torque $Q = k_Q omega^2$, so mechanical power is $Q omega = k_Q omega^3$. Doubling thrust needs $sqrt(2)$ times the speed and about $2^(1.5) approx 2.8$ times the power, which is why a heavy drone's flight time falls quickly. The motor's KV constant gives no-load speed per volt; the SunnySky X2212-13 is 980 KV, so on a 3S pack it spins at most about 12,000 rpm before load. The figures that matter for a design are measured: thrust per watt at hover, the current at full throttle, and the time constant from a throttle step to a thrust step. The last one limits how fast any attitude controller can be.

#fig("/figures/u3-thrust-stand.svg", caption: [The thrust stand. The propeller blows upward, so thrust presses down on the load cell exactly as a calibration mass does. The INA228 measures the ESC's input power through the 1 mΩ shunt with a Kelvin connection.])

*Brushless DC motors.* Three phase windings on the stator, permanent magnets on the rotor (outrunners such as the X2212 put the magnets on a rotating bell). Counting magnets gives the pole count: a typical 2212 outrunner has 14 magnets, 7 pole pairs, so one mechanical revolution is seven electrical cycles. Each phase is a resistance $R$, an inductance $L$ and a back-EMF proportional to speed. A six-step (trapezoidal) drive energises two phases at a time and times commutation from the back-EMF zero crossing on the floating phase; hobby ESCs such as the CloudPhoenix do this, or a refined version of it. Field-oriented control (FOC) drives all three phases with sinusoidal currents whose vector is held at 90 electrical degrees to the rotor's magnetic axis, which gives the most torque per amp and the quietest operation.

*Field-oriented control.* Measure two phase currents (the third is their negative sum), transform them to a stationary two-axis frame with the Clarke transform, then rotate them into the rotor frame with the Park transform:

$ i_alpha = i_a, quad i_beta = (i_a + 2 i_b) / sqrt(3), quad i_d = i_alpha cos theta + i_beta sin theta, quad i_q = -i_alpha sin theta + i_beta cos theta $

In the rotor frame the currents are DC in steady state. Torque is $tau = 3/2 p lambda_m i_q$ for $p$ pole pairs and magnet flux linkage $lambda_m$, so you command $i_q$ for torque and hold $i_d = 0$. Two PI controllers produce $v_d$ and $v_q$; the inverse Park transform and space-vector modulation turn them into three PWM duty cycles. Tune each current loop by pole-zero cancellation: $K_p = L omega_c$ and $K_i = R omega_c$ in continuous time for a crossover $omega_c$, kept below about a tenth of the PWM frequency. A speed loop, slower again, sets $i_q$.

#fig("/figures/u3-foc.svg", caption: [Field-oriented control as Lab 3.1.2 builds it. Everything inside the dashed box runs once per PWM period, triggered by the ADC conversion that the PWM itself starts.])

*Estimating the rotor angle.* A sensorless drive estimates $theta$ from what it measures. Integrate the stator voltage minus the resistive drop to get flux, subtract $L i$, and the remainder is the magnet's flux vector, whose angle is the rotor angle: $psi_(alpha beta) = integral (v_(alpha beta) - R i_(alpha beta)) dif t - L i_(alpha beta)$. A phase-locked loop on that angle gives a clean speed. The method fails at standstill, where there is no back-EMF, so the motor starts in open loop (a rotating current vector the rotor follows) and hands over to the observer above a few hundred rpm. TI's InstaSPIN FAST estimator and its enhanced sliding-mode observer (eSMO), both in the C2000 Motor Control SDK, are industrial versions of the same idea; you will compare yours against them.

*Timing is the design.* Centre-aligned PWM puts all three low-side switches on at the counter's zero, so the low-side shunts see the phase currents then. The ePWM module triggers the ADC at that instant, the ADC interrupt runs the whole control step, and the new duty cycles load at the next period. At a 20 kHz PWM rate the budget is 50 µs including the trigonometry, which is why the C2000 has a trigonometric math unit. Dead time between the high and low switches prevents shoot-through and distorts the output voltage slightly at low current, which a careful controller compensates.

*Inertial sensors.* A MEMS gyroscope measures angular rate with a vibrating proof mass and the Coriolis force; a MEMS accelerometer measures specific force, which is gravity plus any acceleration. ST's LSM6DSOX packs both, with programmable ranges, output rates up to 6.66 kHz, on-chip anti-alias and digital filters, and a FIFO. Their errors are those of Chapter 1.3 with time added: bias, bias drift with temperature, scale factor, cross-axis sensitivity, and noise. Gyro noise integrates into an attitude random walk; gyro bias integrates into an attitude error that grows linearly. An Allan deviation plot separates these terms from a long static log: the slope of $-1/2$ at short averaging times is angle random walk, and the flat minimum is bias instability.

*Vibration and aliasing.* Motors and propellers shake the frame at the rotation frequency and its harmonics, from about 80 Hz at hover to several hundred hertz. If the IMU's output rate and filters let that through, it aliases into low frequencies that look like real motion (Chapter 1.2’s aliasing, with a drone attached). Soft mounting, the sensor's own low-pass filters, a high output rate with digital filtering, and notch filters that track motor speed are the standard defences.

*Attitude estimation.* The gyroscope is accurate over short times and drifts; the accelerometer's estimate of the gravity direction is noisy and corrupted by acceleration but does not drift. A complementary filter blends them with crossover frequency $omega_c$: high-pass the integrated gyro, low-pass the accelerometer angle. In discrete form, $hat(theta)_k = alpha (hat(theta)_(k-1) + omega_k Delta t) + (1 - alpha) theta_(a,k)$ with $alpha = tau \/ (tau + Delta t)$. In three dimensions you integrate a quaternion and correct it towards the accelerometer's gravity vector (and the magnetometer's north) with a proportional-integral term; this is Mahony's filter, and the integral term estimates the gyro bias. A Kalman filter does the same blending with a model of each noise source and is optimal when that model is right.

#fig("/figures/u3-complementary.svg", caption: [A complementary filter's two paths. The gyroscope is trusted above the crossover frequency and the accelerometer below it; the sum passes every frequency with unit gain.], width: 92%)

*Magnetometers.* A compass needs a magnetoresistive sensor, as Chapter 1.3 showed. The LIS3MDL measures Earth's field easily, but on a drone it also measures the frame's steel screws (hard iron, a constant offset), nearby ferrous material that bends the field (soft iron, an ellipsoidal distortion), and the field of the battery current, which changes with throttle. Calibration fits an ellipsoid to readings taken in many orientations; the current term is measured and either compensated or avoided by mounting the sensor on a mast.

*Feedback control.* A plant with transfer function $G(s)$ and a controller $C(s)$ in unity feedback have loop gain $L = C G$. The crossover frequency, where $|L| = 1$, sets the closed-loop bandwidth; the phase margin there sets how much the response overshoots and how much delay the loop tolerates, $Delta t_max = "PM" \/ omega_c$ with the margin in radians. Every filter, every sample period and every millisecond of motor lag takes phase. PID is a pragmatic controller: proportional for stiffness, integral for zero steady-state error, derivative for damping. In a digital implementation, differentiate the measurement (so a setpoint step does not kick), low-pass the derivative, clamp or back-calculate the integrator so it does not wind up when the motors saturate, and add feedforward where you know the plant.

*Cascaded loops.* Drones use a fast inner loop on angular rate (gyro only, 1 to 8 kHz) and a slower outer loop on angle (estimator output, a few hundred hertz) whose output is the inner loop's setpoint. Each outer loop should be at least three to five times slower than the loop inside it. A mixer converts the roll, pitch, yaw and collective thrust commands into four motor commands, and must decide what to give up when a motor saturates.

#fig("/figures/u3-cascade.svg", caption: [The cascade you build on the rig in Lab 3.1.7 and fly in Chapter 3.5. The motor's own lag, measured in Lab 3.1.1, is part of the plant the rate loop must control.])

*Design in simulation, verify on the rig.* A one-axis model is two lines: $J dot.double(theta) = l (T_1 - T_2) - b dot(theta)$ with each motor's thrust lagging its command by the measured time constant. With $J$ from the frame's geometry and a swing test, $l$ the arm length, and the motor model from the thrust stand, you can choose gains, predict the step response, and see what a 4 ms delay does before you power anything.

== Reading

- Hanselman, _Brushless Motors: Magnetics, Design and Control_ (2012), chapters 1 to 4, or the first half of Krishnan, _Permanent Magnet Synchronous and Brushless DC Motor Drives_.
- TI SPRUJ26 (the C2000 Motor Control SDK universal lab guide), the sections on the build levels, current-loop tuning and the eSMO observer; TI's DRV8323RS datasheet sections on the gate driver, current-sense amplifiers and SPI registers; the BOOSTXL-DRV8323Rx user's guide (SLVUB01C) and schematic.
- TI TIDUCF1, _High-Speed Sensorless-FOC Reference Design for Drone ESCs_, for what a production drone ESC needs (45 kHz PWM, electrical frequencies above 1 kHz).
- Åström and Murray, _Feedback Systems_ (free online), chapters 1, 8 to 11 and 13; or Franklin, Powell and Emami-Naeini, _Feedback Control of Dynamic Systems_, chapters 3, 4, 6 and 8.
- Mahony, Hamel and Pflimlin, "Nonlinear Complementary Filters on the Special Orthogonal Group" (IEEE TAC, 2008), sections I to IV; Madgwick's 2010 report on the gradient-descent orientation filter.
- IEEE Std 952 Annex C, or El-Sheimy et al., "Analysis and Modeling of Inertial Sensors Using Allan Variance" (IEEE TIM, 2008).
- ST's LSM6DSOX datasheet and application note AN5272; ST's LIS3MDL datasheet.
- Mellinger and Kumar, "Minimum Snap Trajectory Generation and Control for Quadrotors" (ICRA 2011), section II, or chapters 2 and 3 of Beard and McLain, _Small Unmanned Aircraft_, for the rigid-body model Chapter 3.5 needs.

== Labs

#safety[Spinning propellers cut. Wear safety glasses for every powered motor test. Fit propellers only when the motor is clamped to the stand or the rig, stand out of the propeller's plane, and arm only after you have checked that your kill switch disarms. Remove propellers before you flash firmware, change wiring or debug. The LiPo rules from Chapter 1.4 apply to every lab that uses the pack.]

#lab([The thrust stand], goal: [measure the drone's propulsion so that every later design uses numbers, not guesses.], time: [8 h], kit: [Load-cell rig and ADS1220 from Lab 1.2.4, Raspberry Pi 5, SunnySky motor and 10 × 4.5 prop, one CloudPhoenix ESC, the 3S pack, the second INA228 with its on-board shunt removed and the Bourns 1 mΩ shunt wired in its place, oscilloscope, calibration masses, safety glasses.])[
+ Rebuild the load-cell rig as a stand: the bar's fixed end bolted to a heavy base, a plywood platform on the free end, the motor on the platform with the propeller blowing air upward, and at least two propeller diameters of clear air above it. Calibrate with masses placed on the platform from 0 to 1 kg, and check linearity.
+ Desolder the 15 mΩ shunt from the second INA228 board, wire its IN+ and IN− to the Bourns shunt's sense screws with a twisted pair, and recompute your calibration from Lab 1.3.3 for 1 mΩ and 20 A full scale.
+ Drive the ESC from one of the Pi's hardware PWM channels with standard servo pulses (1,000 to 2,000 µs at 50 Hz) and calibrate the ESC's throttle range. Probe one motor phase with the scope and compute speed from the electrical frequency and the pole-pair count you counted on the bell.
+ Sweep throttle in 10 % steps to 80 %, holding each for 3 s and logging thrust, voltage, current and speed. Fit $k_T$ from thrust against speed squared, and plot grams per watt against thrust. Mark the hover point for a 1.2 kg drone.
+ Step throttle from 30 % to 50 % and back while sampling the ADS1220 at 2,000 samples per second in turbo mode. Fit a first-order time constant to the thrust response, up and down.

#done-when(
  [The calibration is linear to 0.5 % of full scale, and the sweep table and fitted $k_T$ are in the notebook.],
  [Grams per watt at hover thrust is stated with its uncertainty and compared with the maker's table.],
  [The thrust time constant is measured for steps up and down.],
)
#evidence([Stand photographs; calibration data; sweep CSV and plots; the step-response fits.])
] <lab-thrust>

#lab([Field-oriented control from scratch], goal: [make a motor do exactly what your code says, at 20,000 decisions a second.], time: [3 weekends], kit: [LAUNCHXL-F280025C, BOOSTXL-DRV8323RS, LVBLDCMTR, bench supply at 24 V limited to 2 A, oscilloscope, Code Composer Studio with C2000Ware.])[
+ Read the BoosterPack schematic and record the shunt resistance, the current-sense amplifier's gain options and the phase-voltage divider ratios. Seat the BoosterPack on the LaunchPad site TI's Motor Control SDK documents for this pair. Configure the DRV8323RS over SPI: gate drive current, dead time, overcurrent response, and a sense-amplifier gain that maps 5 A to most of the ADC's range.
+ Use C2000Ware's driverlib for peripheral set-up only; write the control code yourself. Configure three ePWM modules for centre-aligned complementary PWM at 20 kHz with dead band, and trigger ADC conversions of the three currents and the bus voltage at the counter's zero. Toggle a GPIO in the ADC interrupt and measure the timing on the scope.
+ Calibrate the current offsets with the gate driver disabled. Measure the motor's phase resistance at DC and its inductance from the current rise after a voltage step.
+ Close the current loops in the rotor frame with a forced angle (the angle generated by your code). Tune $K_p$ and $K_i$ from $R$, $L$ and a crossover of 2 kHz, and capture an $i_q$ step response.
+ Spin the motor in open loop with a rotating current vector, then implement the flux observer and a phase-locked loop, and hand over to closed-loop angle above 500 rpm. Add a speed PI loop.
+ Only now, build TI's universal motor control lab for the same hardware and compare its FAST or eSMO angle estimate with yours.

#done-when(
  [The $i_q$ step settles within 1 ms with under 10 % overshoot.],
  [The motor starts and enters closed loop on ten attempts out of ten, and holds speed setpoints from 500 to 3,000 rpm within 2 %.],
  [The ADC interrupt's execution time is measured and is under 60 % of the PWM period.],
)
#evidence([Register settings with their reasons; the R and L measurements; current-loop and speed-loop captures; the comparison with TI's estimator.])
] <lab-foc>

#lab([Your FOC against a commercial ESC], goal: [learn what a production ESC does better and worse than your code.], time: [6 h], kit: [Lab 3.1.2’s set-up, a SunnySky motor and prop on the thrust stand, a CloudPhoenix ESC, the 3S pack, the INA228 with the 1 mΩ shunt, safety glasses.])[
+ Re-identify $R$ and $L$ for the SunnySky motor and retune your current loops. Raise the PWM frequency to 40 kHz and check that the control step still fits.
+ Run your FOC on the thrust stand from the pack with a firmware current limit of 10 A. Repeat the thrust sweep of Lab 3.1.1 to the highest throttle the limit allows.
+ Repeat the sweep on the same motor and prop with the CloudPhoenix. Compare grams per watt at four thrust levels, phase-current waveforms on the scope (through a current probe or the BoosterPack's sense output), acoustic noise on a phone's sound meter, and the thrust step response.

#done-when(
  [Both sweeps are on one plot with efficiency differences quantified, and the notebook explains each difference from the waveforms.],
)
#evidence([The sweeps, waveform captures and the written comparison.])
] <lab-foc-vs-esc>

#lab([The IMU and its noise], goal: [characterise the sensor the drone will trust most.], time: [6 h, plus a 3 h unattended log], kit: [MSP-EXP432E401Y, LSM6DSOX breakout, logic analyser, TMP117.])[
+ Wire the LSM6DSOX to SSI2 on the LaunchPad. Write a driver from the datasheet: check WHO_AM_I, set the gyro to ±1,000 °/s and the accelerometer to ±8 g at 1.66 kHz, enable the data-ready interrupt on INT1, and read the burst of twelve output bytes in one SPI transaction. Capture and annotate the transaction.
+ Log three hours with the board still and level, with a TMP117 taped beside it. Compute the Allan deviation of each gyro axis and read off angle random walk and bias instability. Compare with the datasheet's noise density.
+ Calibrate the accelerometer by holding it still in six orientations; fit offset and scale per axis. Fit gyro bias against temperature from the long log.

#done-when(
  [The Allan deviation plot shows the $-1/2$ slope and a bias-instability floor, with both numbers extracted.],
  [Accelerometer calibration brings $|g|$ to within 0.5 % in all six orientations.],
)
#evidence([Driver source; annotated SPI capture; the Allan plot and fitted terms; calibration tables.])
] <lab-imu>

#lab([Attitude estimation], goal: [turn rates and forces into an angle you can control.], time: [8 h], kit: [Lab 3.1.4’s set-up, a protractor or printed angle scale, one SunnySky motor with ESC and prop on the thrust stand.])[
+ Implement a one-axis complementary filter at 1 kHz on the MCU and tune its crossover. Tilt the board through known angles against the scale and plot estimate against truth.
+ Implement a quaternion Mahony filter with gyro-bias estimation. Report the error after a 10-minute still period, and after a rapid 90° rotation and return.
+ Tape the IMU board to the thrust stand's base and run the motor at hover throttle. Log raw accelerometer data at 1.66 kHz and plot its spectrum. Find the motor's fundamental and harmonics, then set the sensor's on-chip filters and your own notch so that the estimator's error with the motor running is within 1° of the error with it stopped.

#done-when(
  [Static angle error under 1° and the error after the 90° manoeuvre under 2°.],
  [The vibration spectrum is annotated and the chosen filters are justified from it.],
)
#evidence([Estimator source; angle plots against the scale; the spectra before and after filtering.])
] <lab-attitude>

#lab([Magnetometer calibration and heading], goal: [get a heading you can believe on a frame full of current.], time: [5 h], kit: [LIS3MDL breakout, the LaunchPad, the frame with one motor and ESC fitted, the 3S pack, a phone compass for comparison.])[
+ Write the LIS3MDL driver. Collect about 2,000 samples while rotating the board through every orientation, fit an ellipsoid (offset and a 3 × 3 correction), and show the corrected samples on a sphere.
+ Mount the sensor on the frame and repeat. Compare the two calibrations.
+ Run one motor at four throttle levels and measure the field change at the sensor's position and at 5, 10 and 15 cm above the frame. Choose the mast height for Chapter 3.5 from the data.
+ Compute a tilt-compensated heading from the Mahony attitude and compare it with the phone at eight headings.

#done-when(
  [Corrected samples lie within 3 % of a sphere, and heading agrees with the phone within 5° at all eight headings.],
  [The mast height is chosen from measured current interference.],
)
#evidence([Raw and corrected point clouds; the interference measurements; the heading table.])
] <lab-mag>

#lab([PID on a one-axis rig], goal: [design a controller in simulation, then make it hold a real frame level.], time: [2 weekends], kit: [The Tarot frame with two opposite motors, ESCs and props fitted, a wooden A-frame with a 10 mm steel rod through the frame's centre plates as a roll axle, the LaunchPad with the IMU, the 3S pack, a push button on a 1 m lead, safety glasses.])[
+ Build the rig so the frame can only roll, with mechanical stops at ±30°. Measure the frame's inertia about the axle with a swing test (a known offset mass and the oscillation period).
+ Write the one-axis model with the motor time constant from Lab 3.1.1 and the loop delays your firmware will have. In Python, design a rate loop and an angle loop to a stated phase margin, and simulate steps and a disturbance of a 50 g mass hung from one arm.
+ Drive the two ESCs with Oneshot125 from two timer PWM outputs at 1 kHz. Wire the push button to a GPIO as a dead man's switch: the motors run only while you hold it, and releasing it disarms within 50 ms. Chapter 3.5 replaces it with the radio link.
+ Implement the cascade with derivative on measurement, derivative filtering, integrator clamping and output saturation. Bring up the rate loop alone, then close the angle loop.
+ Compare measured and simulated step responses and disturbance rejection. Find the gain at which the rig oscillates and compare it with the model's prediction.

#done-when(
  [The frame holds level within ±2° and recovers from the 50 g disturbance within 1 s.],
  [Measured and simulated step responses agree in rise time and overshoot within 30 %, or the notebook explains the model error.],
  [Releasing the dead man's switch disarms within 50 ms, tested ten times.],
)
#evidence([Rig photographs; the model and simulation code; step and disturbance plots, measured over simulated; the oscillation test.])
] <lab-rig>

== Problem set

+ From your Lab 3.1.1 data, estimate hover current and flight time for a 1.2 kg drone on the 5,000 mAh pack using 80 % of capacity. How do both change if the drone gains 200 g?
+ A motor has $R = 0.13$ Ω and $L = 30$ µH per phase. Choose the current-loop gains for a 3 kHz crossover and give the discrete gains at a 40 kHz control rate. What limits the crossover from above?
+ At 10,000 rpm with 7 pole pairs, what is the electrical frequency? How many PWM periods per electrical cycle at 20 kHz and at 45 kHz? Why does TI's drone ESC design use the higher rate?
+ Space-vector modulation reaches a phase-voltage amplitude of $V_"dc" \/ sqrt(3)$, sinusoidal PWM only $V_"dc" \/ 2$. Derive both, and give the speed headroom this buys on a 3S pack.
+ An IMU gyro has an angle random walk of 0.3 °/√h and a bias instability of 5 °/h. Estimate the attitude error after 10 s and after 10 minutes of pure integration, and say which term dominates each.
+ The motor fundamental at hover is 85 Hz and the IMU is sampled at 1 kHz with no anti-alias filter. Where does the 3rd harmonic alias if the sample rate drops to 200 Hz?
+ A complementary filter runs at 1 kHz with a 0.5 Hz crossover. Compute $alpha$. What steady-state angle error does a constant 1 m/s² sideways acceleration cause?
+ Your rate loop crosses over at 30 Hz with 50° of phase margin. The IMU's digital filter adds 2 ms of delay and the ESC protocol another 1 ms. What is the new margin, and what would you change first?
+ Derive the swing-test formula for the rig's inertia and estimate its uncertainty from a 2 % period error and a 5 % error in the offset distance.

== Deliverables and stretch

*Deliverables.* The propulsion model (thrust, power and time constant against throttle) as a table and a script; the FOC firmware and the comparison report; the IMU, magnetometer and estimator drivers as a library that Chapter 3.5 links unchanged; the one-axis model, simulation and rig results.

*Stretch.* Add a second load cell to measure propeller torque and fit $k_Q$. Implement bidirectional DShot on your FOC firmware so it reports electrical rpm, and replace the CloudPhoenix on one arm with it. Implement an extended Kalman filter for attitude with gyro-bias states and compare it with Mahony on the same logs. Identify the rig's plant by injecting a chirp into the rate setpoint and fitting a transfer function.

#checklist(
  [*Lab 3.1.1:* calibrated stand; $k_T$, grams per watt at hover and the thrust time constant measured.],
  [*Lab 3.1.2:* your FOC holds speed from 500 to 3,000 rpm and starts ten times out of ten; current step within spec.],
  [*Lab 3.1.3:* your FOC and the commercial ESC compared on one plot, with the differences explained.],
  [*Lab 3.1.4:* IMU driver, Allan deviation with both noise terms, accelerometer calibration.],
  [*Lab 3.1.5:* complementary and Mahony filters within error limits; vibration filtered from a measured spectrum.],
  [*Lab 3.1.6:* magnetometer calibrated on the frame; mast height chosen from data.],
  [*Lab 3.1.7:* frame held level within ±2°; simulation and measurement compared; dead man's switch tested ten times.],
  [*Problem set:* all nine answered with units.],
  [*You can explain*, without notes: why thrust per watt falls with load, what each FOC block does, how a complementary filter splits the spectrum, what Allan deviation shows, and why delay costs phase margin.],
)
