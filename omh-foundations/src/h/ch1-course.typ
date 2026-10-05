#import "../lib/template.typ": *

= The course <h-course>

OMH Foundations is a lab-driven course in hardware and low-level systems for one student: a strong software engineer who is founding OMH, a company that will design, manufacture and support rack modules delivering cloud-class services on its own hardware. It starts at electrons and ends with two working systems you built from the transistor up: a quadcopter that flies on your firmware, your boards, your radio protocol and a TI radar altimeter, and Module Zero, a two-node fleet of engineering-sample server modules that attest their firmware, form a quorum, run tenant virtual machines on your hypervisor and store data erasure-coded across NVMe. Every claim on the OMH hardware page (zero-touch join, measured boot, OpenBMC and Redfish, rolling firmware updates, encryption with keys held in Modulus) maps to something you will have built a small, honest version of.

The course is built around specific Texas Instruments silicon wherever TI makes the part: precision sensors (TMP117, HDC3022, INA228, TMAG5273, OPT3101, OPT4048), converters (ADS1115, ADS1220), power (TPS62933, TPS25947, LM74700), microcontrollers (MSP432E401Y, MSPM0G3507, C2000 F280025C), motor control (DRV8323RS), sub-gigahertz radio (CC1312R), microwave synthesis (LMX2572) and millimetre-wave radar (IWRL6432). Where TI makes nothing suitable, such as MEMS inertial sensors, the course says so and names the part it uses instead.

== What you will have built

- A CMOS NAND gate from discrete transistors, a 4-bit adder from logic ICs, and then a pipelined RV32I CPU with caches and M-mode traps on an FPGA, running C you compiled.
- Library-free drivers and metrology for five TI sensors and two TI converters, an error budget for a real measurement, characterised TI power stages and protection, and a characterised drone battery.
- A transmission-line measurement, a tuned antenna, an FM receiver written from samples, and link budgets checked in the field.
- Bare-metal firmware for TI's MSP432E401Y with no vendor library: your own linker script, startup code, drivers, fault handler and a signed A/B bootloader with anti-rollback.
- A boot chain you understand byte by byte: a boot sector, a UEFI loader, Secure Boot with your own keys, measured boot into a TPM, remote attestation with a nonce, zero-touch netboot, and OpenBMC.
- Field-oriented motor control written from scratch on a C2000, an IMU noise model, an attitude estimator and a PID controller tuned on a rig.
- A packet radio written below TI's protocol stacks with a measured sensitivity waterfall, a telemetry protocol designed to a duty-cycle budget, and a software demodulator.
- A frequency synthesiser programmed from your own register calculator, a measured chirp, an FMCW radar simulator, and a TI 60 GHz radar configured as an altimeter.
- Four printed circuit boards you specified, designed, reviewed, had fabricated and brought up: the drone's power module and flight-controller board, a BMC-lite management controller on the MSP432E401Y, and a Compute Module 5 carrier with PCIe NVMe and a TPM.
- A 450 mm quadcopter that hovers, holds altitude on radar and barometer, and reports telemetry over your 868 MHz link.
- A 64-bit SMP kernel with user mode and an NVMe driver; Linux drivers for TI parts that mainline Linux lacks; a KVM virtual machine monitor with your own virtio devices; storage and network data paths measured from `io_uring` to SPDK and from the kernel stack to DPDK.
- A written product specification, threat model, update architecture, manufacturing test plan, compliance plan and cost model, and the Module Zero demonstration that ties it together.

== Four units

#tbl(columns: (auto, 1fr, auto), header: ([Unit], [Chapters], [Weeks]), align: (left, left, right),
  [*1* Circuits, Sensors and Signals], [Electricity, components and measurement; the analogue signal chain; sensors with TI silicon; power conversion and batteries; signals on wires and RF fundamentals], [11.5],
  [*2* Logic, Processors and Firmware], [Digital logic; HDL and FPGA; build a CPU; memory and interconnect; privilege and the platform; bare-metal firmware; boot and platform firmware], [21],
  [*3* Control, Radio and Boards], [Motors, estimation and feedback control; radio links; microwave synthesis and FMCW radar; board design and bring-up; the drone], [21, plus fabrication],
  [*4* Systems Software and the Product], [Write a kernel; Linux kernel internals; Linux device drivers; virtualisation and hypervisors; storage and network data paths; product engineering; the Module Zero capstone], [about 29],
)

The weeks assume 12 to 15 hours a week: two weekday evenings of reading and problem sets and one long session on the bench or in the debugger. The whole course is about eighty weeks. Weeks are a guide; done-when criteria are the contract.

#fig("/figures/h-timeline.svg", caption: [The course as a schedule at 12 to 15 hours a week. The two board orders in Chapter 3.4 are in fabrication while you work on the rest of the chapter and the first, software-only labs of Chapter 3.5.])

#fig("/figures/h-map.svg", caption: [The course map. Each unit builds on the units before it; the drone in Chapter 3.5 and Module Zero in Chapter 4.7 are where the threads end.])

== The threads

Six threads run through the units, and most chapters advance more than one.

- *Power.* Ohm's law and decoupling (1.1), converters, protection and batteries (1.4), the power trees that become Boards P and A (3.4), the drone's energy budget (3.5) and Module Zero's power telemetry (4.7).
- *Sensing and measurement.* The signal chain (1.2), TI sensors and error budgets (1.3), the IMU and magnetometer (3.1), radar (3.3), and the hwmon and IIO drivers that put them in Linux (4.3).
- *Compute and firmware.* Logic to a CPU (2.1 to 2.4), privilege (2.5), bare-metal firmware (2.6), the flight software (3.5), your kernel (4.1) and Linux (4.2).
- *Trust.* The signed bootloader (2.6), Secure Boot, measured boot and attestation (2.7), the BMC (2.7, 3.4), the threat model (4.6) and Module Zero's join protocol (4.7).
- *Radio and high-speed signals.* Transmission lines and link budgets (1.5), the 868 MHz link (3.2), synthesis and radar (3.3), and PCIe and Ethernet routing on Board B (3.4).
- *The product.* Supply chains and kit (this handbook), design reviews and respins (3.4), flight-test reports (3.5), and the specification, compliance and cost documents (4.6).

== Order and flexibility

The units run in order, and so do the chapters within them, with four sanctioned exceptions. Board A's specification (Lab 3.4.1) can start as soon as Chapter 2.6 is done, so that fabrication lead time stays off the critical path. Chapters 3.2 and 3.3 do not depend on 3.1 and can run in either order. Chapter 4.5 can follow 4.3 directly. Product engineering (4.6) can be read alongside the capstone's first two weeks.

== Conventions

Spelling is British. "The Pi" is the Raspberry Pi 5; "the server" is the used x86 rack server from the kit; "the FPGA" is the ULX3S; "the LaunchPad" is the MSP-EXP432E401Y unless a lab names another; "the Windows PC" is the small x86 machine that runs TI's Windows-only tools. Your workstation is assumed to be a Mac with Apple silicon; commands on the Pi and the server assume Raspberry Pi OS and Debian or Ubuntu. Prices are those shown by the named seller on 4 October 2026. Labs are numbered unit.chapter.lab, so Lab 2.6.6 is the sixth lab of Chapter 2.6.
