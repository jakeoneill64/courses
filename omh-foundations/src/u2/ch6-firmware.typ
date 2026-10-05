#import "../lib/template.typ": *

= Bare-metal firmware <ch-firmware>

#chapter-meta(
  weeks: [3.5 weeks],
  builds: [Firmware for the MSP432E401Y from a blank directory, with no vendor library: startup code, linker script, clocks, an interrupt-driven UART, I#super[2]C and SPI masters reading TI sensors and driving your FPGA, DMA-fed ADC streaming, a fault handler that survives reset, a watchdog, and a signed A/B bootloader with anti-rollback. Then a port to a Cortex-M0+ to see what a different core removes.],
  needs: [Two MSP-EXP432E401Y LaunchPads, the LP-MSPM0G3507, OpenOCD built from git master, `arm-none-eabi-gcc`, the TMP117 and INA228 breakouts, the EMC2101 fan controller with a 4-pin fan, your Chapter 2.2 FPGA peripheral, logic analyser.],
)

#why[
  A baseboard management controller is a microcontroller-class SoC running exactly this kind of code: power sequencing, fan control from temperature, sensor polling over I#super[2]C and PMBus, a serial console, a watchdog and a signed firmware update that must never brick the board. The drone's flight controller is the same code with a control loop in the middle. Module Zero's management board in Chapter 3.4 and the drone in Chapter 3.5 both run firmware you write here. The habits this chapter builds, reading a reference manual before any code, owning the linker script and treating every interrupt as a concurrency problem, separate firmware that ships from firmware that demonstrates.

  The rule for this chapter: no TI driverlib, no SysConfig, no SDK and no Arduino. Registers and the reference manual only. Afterwards, use whatever you like, because you will know what it hides.
]

#skip-test(
  rule: [If all five are easy, do Labs 2.6.1, 2.6.5 and 2.6.6.],
  [From power-on, list what a Cortex-M4 does before the first instruction of `main`, and which steps are hardware and which are your startup code.],
  [Write a linker script that places `.text` in flash and `.data` and `.bss` in SRAM and gives the startup code the symbols it needs. What is `KEEP` for?],
  [A UART ISR and `main` share a ring buffer. Which variables need `volatile`, what does `volatile` not give you, and how do you make the head and tail updates safe without disabling interrupts?],
  [Decode a hard fault: which registers give the cause and the faulting address, and how do you find the PC of the faulting instruction from the stacked frame?],
  [Design an A/B firmware update with rollback protection that cannot be bricked by power loss at any instant. What state must be atomic, and how do you make it so?],
)

== Core ideas

*Anatomy of a microcontroller.* A Cortex-M4F core with a Nested Vectored Interrupt Controller (NVIC), a SysTick timer, an MPU and an FPU; internal flash, SRAM and EEPROM; and peripherals on AHB and APB buses, all at fixed addresses in one 4 GiB map. The MSP432E4 Technical Reference Manual (TI SLAU723A, 1,817 pages) documents everything outside the core; Arm's Cortex-M4 Devices Generic User Guide documents the core. The memory-map section is the first thing you read for any new part.

#fig("/figures/u2-mcu-map.svg", caption: [The MSP432E401Y's address map and the reset sequence. Hardware loads the stack pointer and reset vector from the first two words of flash; everything after that is your startup code.])

*Reset.* The core reads the vector table at address 0: word 0 is the initial stack pointer and word 1 the reset handler. Hardware loads SP and jumps. From there it is your code: copy `.data` from flash to SRAM, zero `.bss`, optionally run constructors, set up clocks, call `main`. Nothing else has happened. The chip is running from its internal 16 MHz oscillator with every peripheral unclocked.

*Linker scripts.* `MEMORY` names the regions with their addresses and sizes. `SECTIONS` places input sections into output sections in those regions, defines the symbols startup code uses (`_sdata`, `_edata`, `_sbss`, `_estack`) and controls alignment. `.data` has a load address in flash (`AT>`) and a run address in SRAM. `KEEP` stops `--gc-sections` discarding the vector table. The map file tells you where every byte went.

*Clocks.* Everything starts slow. To run at 120 MHz you start the main oscillator from the LaunchPad's 25 MHz crystal, configure the PLL and wait for lock, set the flash and EEPROM timing (MEMTIM0) for the new speed before switching, and then select the PLL as the system clock (RSCLKCFG). Each peripheral is clocked separately through its RCGC register, and you must wait for its PR (peripheral ready) bit. A peripheral with no clock reads as zero and ignores writes: the most common first bug.

*GPIO and alternate functions.* Each pin has a direction, a digital-enable bit (forget it and the pin does nothing), pull-ups and pull-downs, drive strength, and an alternate-function select with a port-control field that muxes it to a peripheral. The data register is address-masked: address bits 9 to 2 select which pins a read or write touches, so you can change one pin without a read-modify-write. The datasheet's pin table, not the reference manual, says which function is available on which pin; the LaunchPad user's guide (SLAU748B) says which pins reach the BoosterPack headers.

*Peripherals as registers.* A UART is a baud-rate divisor, a line control register, a status register and a data register. SPI (the QSSI module) adds clock phase and polarity. I#super[2]C is open-drain (Chapter 1.1), addresses, ACKs, clock stretching and a state machine that is easy to hang if you do not handle every error. Timers have a prescaler, a counter, a load value and capture/compare; PWM is a compare toggling a pin. The ADC's sample sequencers convert a programmed list of channels on a trigger. The micro-DMA (µDMA) controller copies between peripherals and memory without the core, including ping-pong buffers for continuous streams. Two watchdogs, one on the system clock and one on the independent precision oscillator, reset the chip if not fed.

*Interrupts.* The NVIC has per-interrupt enable, priority and pending bits; higher priority preempts lower; the core stacks eight registers automatically and calls a plain C function. Latency is about 12 cycles plus whatever you disabled. Rules: ISRs are short, communicate through ring buffers or flags, and never block. `volatile` forces the compiler to reload but gives no atomicity; use `LDREX`/`STREX`, disable interrupts for the shortest critical section, or design single-producer single-consumer buffers where head and tail each have one writer.

*Polling, interrupts and DMA.* Polling burns the core; interrupts cost per event; DMA costs nothing per byte but takes setup. A UART at 115200 interrupting per byte is fine; an ADC at 1 MSa/s is not.

*Faults.* Bus, usage and memory-management faults escalate to hard fault unless enabled. CFSR, HFSR, BFAR and MMFAR say what happened; the stacked frame says where. A good fault handler prints them, writes them to a no-init RAM region and resets, so the next boot can report the crash.

*Debugging.* SWD is a two-wire debug port. The LaunchPad's on-board XDS110 speaks it; OpenOCD drives the XDS110 and exposes a GDB server. You can halt, step, read any register or memory, set hardware breakpoints and watchpoints, and flash. The XDS110 also provides the back-channel UART on UART0 (pins PA0 and PA1), which appears on your workstation as a serial port.

*Bootloaders.* A bootloader is the first program in flash; it decides whether to jump to an application (set VTOR, set SP, jump) or to accept a new image. An A/B scheme keeps two application slots and a small metadata record; an update writes the inactive slot, verifies a signature over it, and then switches the active slot atomically. Rollback protection stores a monotonic minimum version and refuses older images. Power loss at any instant must leave a bootable system, so the switch is the last write and must be interpretable even if it was interrupted. The MSP432E401Y gives you useful hardware: flash erased in 16 KB blocks and programmed a 32-bit word at a time (or 32 words through the write buffer), 6 KB of EEPROM for small records that change, and a SHA-256 accelerator.

#fig("/figures/u2-ab-boot.svg", caption: [The A/B layout used in Lab 2.6.6 and the metadata commit. Two EEPROM records with sequence numbers and CRCs mean an interrupted commit always leaves one valid record, and the bootloader always knows which slot to try.])

*C and C++ in firmware.* `-Os`, `-ffunction-sections -fdata-sections -Wl,--gc-sections`, no `printf` with floats unless you need it, and `-fno-exceptions -fno-rtti` for C++. C++ is fine in firmware with those flags and no surprise heap use; many teams use it. Static analysis (cppcheck, clang-tidy) and MISRA-style rules exist because firmware bugs are expensive to fix in the field.

*A second core.* The Cortex-M0+ in TI's MSPM0 is a smaller design: no FPU, no `LDREX`/`STREX`, no configurable fault status registers (every fault is a hard fault) and fewer instructions. Porting your startup code to it shows which of your assumptions were about the core and which about the chip.

*An RTOS, afterwards.* FreeRTOS or Zephyr give you tasks, queues and timers once you have done it bare. Zephyr's device tree and driver model mirror Linux's, which is what Chapter 4.3 teaches.

== Reading

- TI SLAU723A, _MSP432E4 SimpleLink Microcontrollers Technical Reference Manual_: the chapters on System Control, Internal Memory, Processor Support and Exception Module, µDMA, ADC, GPIO, General-Purpose Timers, I#super[2]C, QSSI, UART, Watchdog Timers and SHA/MD5. Read each one fully on the day you use it.
- TI SLAU748B, the MSP-EXP432E401Y LaunchPad user's guide: pin assignments, BoosterPack headers and the back-channel UART jumpers. The MSP432E401Y datasheet's pin tables.
- Arm, _Cortex-M4 Devices Generic User Guide_: chapter 2 (core and exception model) and chapter 4 (NVIC, SysTick, the SCB fault registers).
- White, _Making Embedded Systems_, 2nd ed., chapters 2 to 8 and 10.
- Yiu, _The Definitive Guide to Arm Cortex-M3 and Cortex-M4 Processors_, chapters 4, 7, 8, 12, 13 and 22.
- Memfault's Interrupt blog: "From Zero to main()", "Cortex-M Fault Debugging" and the "Device Firmware Update Cookbook".

== Labs

#lab([Blink from a blank directory], time: [5 h], kit: [MSP-EXP432E401Y, USB cable.])[
+ Create `startup.s` (vector table with SP and reset handler; copy `.data`, zero `.bss`, call `main`), `linker.ld` and `main.c`. No TI headers: define the SYSCTL and GPIO register addresses yourself from the reference manual.
+ Enable the clock to GPIO port N, wait for its peripheral-ready bit, set PN1 as a digital output and toggle LED D1 with a busy loop. Use the address-masked data register to touch only PN1.
+ Build with `arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 -nostdlib -ffreestanding`. Flash and debug with OpenOCD (`-f board/ti/msp432-launchpad.cfg`) and GDB. Break at the reset handler and `stepi` until you can narrate every instruction before `main`.
+ Read the map file and find the vector table and the load address of `.data`.

#done-when(
  [D1 blinks, and the notebook narrates every instruction from reset to `main`.],
)
#evidence([The three source files; an annotated GDB session; the relevant map-file lines.])
] <lab-fw-blink>

#lab([Clocks, a proper UART and time], time: [6 h])[
+ Start the 25 MHz main oscillator, configure the PLL for a 120 MHz system clock, set MEMTIM0 for that frequency, and switch. Output a divided system clock on a pin with the clock-output function and verify it on the oscilloscope.
+ Write a UART0 driver for the back-channel port: compute the integer and fractional divisors for 115200, interrupt-driven TX and RX with lock-free ring buffers, and overrun and framing error handling. Implement `_write` so `printf` from picolibc (or your own small formatter) prints through it.
+ Measure the actual baud rate with the logic analyser and compute the error.
+ Add SysTick at 1 kHz with a millisecond counter and `delay_ms`.

#done-when(
  [The scope shows the expected clock output, and `printf` works at 115200 with a measured error under 1 %.],
)
#evidence([The divisor arithmetic; the clock capture; the baud measurement.])
] <lab-fw-uart>

#lab([I#super[2]C and SPI masters: sensors, a fan and the FPGA], time: [8 h], kit: [TMP117, INA228, EMC2101 breakout with a 4-pin PWM fan, the ULX3S with Lab 2.2.5’s bitstream, logic analyser.])[
+ Write an I#super[2]C master driver for I2C0 on PB2 (SCL) and PB3 (SDA), the BoosterPack 1 header. Handle NACK, bus busy, arbitration loss and timeouts, and implement the bus-clear procedure from Chapter 1.3.
+ Port your Chapter 1.3 TMP117 and INA228 drivers from Python to C on this bus. Read the EMC2101’s fan tachometer and set its PWM duty.
+ Build a fan curve: the TMP117’s temperature sets the fan duty, the INA228 reports the fan's power, and the loop logs all three each second. This is a BMC's thermal loop in miniature.
+ Write an SPI master for SSI2 (PD3 clock, PD1 out, PD0 in) and talk to your FPGA peripheral: read the ID register, set GPIO, read the timer. Wire the FPGA's interrupt to a GPIO input and handle it.
+ Capture and annotate an I#super[2]C transaction with a NACK and an SPI transaction.

#done-when(
  [Temperature drives fan speed with the power logged; the FPGA answers over SPI and its interrupt arrives on the GPIO; both captures are annotated.],
)
#evidence([Driver sources; a log of the fan curve; the two annotated captures.])
] <lab-fw-buses>

#lab([DMA], time: [5 h])[
+ Configure an ADC sample sequencer, triggered by a timer, to sample a pin at 100 kSa/s into a 1,024-sample ping-pong µDMA buffer. Compute a running mean per half buffer and stream it out of the UART, also by DMA.
+ Measure CPU load: toggle a GPIO in each ISR and integrate on the scope, or count idle-loop iterations. Compare with per-sample interrupts at the same rate and note where that falls over.

#done-when(
  [The stream runs continuously with no overruns, and the notebook has a CPU-load comparison.],
)
#evidence([The µDMA control-table setup annotated; the load measurements.])
] <lab-fw-dma>

#lab([Faults and the watchdog], time: [5 h])[
+ Enable bus, usage and memory-management faults. Write one fault handler that prints CFSR, HFSR, BFAR, MMFAR and the stacked PC, LR and xPSR, writes them to a no-init RAM section and resets.
+ Trigger each: an unaligned access to a device register, a read from an unmapped address, execution from a region the MPU marks never-execute, a divide by zero with the trap enabled, and a stack overflow into an MPU guard region.
+ On boot, check the no-init region and report the previous crash.
+ Enable the PIOSC-clocked watchdog with a 500 ms timeout, fed from the main loop. Hang the loop on purpose and log the reset reason from the reset-cause register.

#done-when(
  [Each fault is decoded correctly and survives the reset into the next boot's log; the watchdog reset is identified as such.],
)
#evidence([The fault handler; a log of each fault and the watchdog reset.])
] <lab-fw-faults>

#lab([A signed A/B bootloader], time: [2 weekends])[
+ Partition flash in 16 KB blocks: bootloader (32 KB), slot A and slot B. Keep two metadata records in EEPROM, each holding a sequence number, the active slot, the image's version and a CRC. Define an image header: magic, version, size, SHA-256, signature and entry vector.
+ Bootloader: pick the valid metadata record with the highest sequence number; hash the active image with the SHA-256 accelerator; verify an ECDSA P-256 signature (micro-ecc) against a public key compiled into the bootloader; check the version against the minimum stored in EEPROM; set VTOR and SP; jump. On failure try the other slot; if both fail, stay in update mode.
+ Update mode over UART: a framed protocol with a CRC that writes the inactive slot and verifies it, then commits by writing the older metadata record with a higher sequence number, last.
+ Anti-rollback: raise the minimum version only after the new image has booted and confirmed itself healthy.
+ Test power loss during the slot write, during the metadata write and just after; every time the board must boot something valid. Load an image signed with the wrong key and an older version; both must be refused.

#done-when(
  [You can update from A to B and back over UART; every power-loss test boots; both rejection cases are demonstrated.],
)
#evidence([The layout and record format; the power-loss test log; the host-side update tool.])
] <lab-fw-bootloader>

#lab([A second core: the Cortex-M0+], time: [5 h], kit: [LP-MSPM0G3507.])[
+ Port Labs 2.6.1 and 2.6.2 to the MSPM0G3507 with no SDK, using its technical reference manual. Note what differs: the clock system, the boot configuration held in the NONMAIN flash region, and the core.
+ Show which of your Lab 2.6.5 fault decodes no longer exist on the M0+, and rewrite your ring buffer's atomic update without `LDREX`/`STREX`.

#safety[Do not erase or program the MSPM0’s NONMAIN flash region. It holds the boot configuration; wrong values can lock the device permanently. Your linker script and OpenOCD commands must touch MAIN flash only.]

#done-when(
  [The M0+ blinks and prints from your own startup code, and the notebook has a table of what the M4F gave you that the M0+ does not.],
)
#evidence([The port; the comparison table.])
] <lab-fw-m0>

== Problem set

+ Compute the UART's integer and fractional divisors for 115200 at 120 MHz with 16× oversampling, and the resulting error. Repeat for 921600. At what rate does the error exceed 2 %?
+ Design I#super[2]C pull-ups for a 3.3 V bus with 180 pF and a 400 kHz target, and check the sink-current limit.
+ Give a concrete interleaving that `volatile` on a shared counter does not prevent. Fix it with `LDREX`/`STREX`, and separately with a critical section. When is each appropriate, and what do you do on the M0+?
+ An ISR at priority 2 takes 5 µs; one at priority 1 (higher) arrives 1 µs in. Draw the timeline. Swap the priorities; make them equal. What is the worst-case latency for the lower one if `main` also disables interrupts for 20 µs?
+ A stacked frame shows PC = 0x0000_1234, LR = 0xFFFF_FFF9, CFSR = 0x0000_8200 and BFAR = 0x4002_0000. What happened, and which stack was in use?
+ A UART receives at 921600 and the main loop services its ring buffer every 2 ms. Size the buffer. What if the loop can stall for 50 ms during a flash erase?
+ Design the metadata state machine for Lab 2.6.6 so that power loss at any point leaves a state the bootloader can interpret. Explain why a "confirmed good after first boot" flag handles firmware that boots but crashes.
+ A 16 KB flash erase takes milliseconds and stalls flash reads on the same bank. What does that mean for interrupts and the watchdog during an update, and how do you design around it?
+ Why is EEPROM a better home than flash for the metadata records and the anti-rollback counter? What limits how often you may write it?

== Deliverables and stretch

*Deliverables.* A library-free firmware project with linker script, startup, clocks, UART, I#super[2]C, SPI, DMA, fault handler and watchdog, driving TI sensors, a fan and the FPGA; the signed A/B bootloader with its power-loss log and host tool; annotated captures; the M0+ port and comparison table.

*Stretch.* Serve the fan-curve data over Ethernet with lwIP on the MSP432E401Y's integrated MAC and PHY, as a first step toward Chapter 4.7’s management interface. Implement PMBus (SMBus with packet error checking) against a PMBus-capable regulator. Write a host-side hardware abstraction so the sensor and fan logic compiles and unit-tests on the workstation with mocked registers.

#checklist(
  [*Lab 2.6.1:* blink from your own startup and linker script; every pre-`main` instruction narrated.],
  [*Lab 2.6.2:* 120 MHz verified on the scope; `printf` over the back-channel UART with under 1 % baud error.],
  [*Lab 2.6.3:* fan curve driven by the TMP117 with INA228 power logged; FPGA over SPI with its interrupt handled.],
  [*Lab 2.6.4:* continuous DMA stream with a CPU-load comparison.],
  [*Lab 2.6.5:* five faults decoded across reset; watchdog reset identified.],
  [*Lab 2.6.6:* signed A/B update in both directions; all power-loss tests boot; wrong key and old version refused.],
  [*Lab 2.6.7:* M0+ port and the comparison table.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: everything between reset and `main`, why `volatile` is not atomicity, how to decode a fault, and why your bootloader cannot be bricked by a power cut.],
)
