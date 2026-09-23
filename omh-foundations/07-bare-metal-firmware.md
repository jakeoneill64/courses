# Module 7: Bare-metal firmware

**Part III · 3 weeks · Needs: Nucleo-F411RE, Pico ×2, BME280, EMC2101, INA226, logic analyser, your FPGA SPI peripheral.**

## Why this module (and what it buys OMH)

A baseboard management controller is a microcontroller-class SoC running exactly this kind
of code: power sequencing, fan control from temperature, sensor polling over I2C and PMBus,
a serial console mux, a watchdog, and a signed firmware update path that must never brick
the board. Module Zero's management board (Module 14) runs firmware you write here. The
habits this module builds, such as reading a reference manual before any code, owning the
linker script, and treating every interrupt as a concurrency problem, are the ones that
separate firmware that ships from firmware that demos.

The rule for this module: no vendor HAL, no CubeMX, no Arduino. Registers and the
reference manual only. After the module, use whatever you like, because you will know
what it is hiding.

## Skip test

1. From power-on, list what a Cortex-M4 does before the first instruction of `main`, and
   which of those steps are hardware and which are your startup code.
2. Write a linker script that puts `.text` in flash, `.data` and `.bss` in SRAM, and gives
   startup code the symbols it needs. What is `KEEP` for?
3. A UART ISR and `main` share a ring buffer. Which variables need `volatile`, what does
   `volatile` not give you, and how do you make the head/tail update safe without
   disabling interrupts?
4. Decode a hard fault: which registers tell you the cause and the faulting address, and
   how do you find the PC of the faulting instruction from the stacked frame?
5. Design an A/B firmware update with rollback protection that cannot be bricked by power
   loss at any instant. What state must be atomic, and how do you make it so on flash?

If all five are easy, do Labs 7.1, 7.5 and 7.6.

## Core ideas

**Anatomy of a microcontroller.** A Cortex-M core, a Nested Vectored Interrupt Controller
(NVIC), a SysTick timer, an optional MPU, internal flash and SRAM, and peripherals hanging
off AHB and APB buses, all at fixed addresses in one 4 GiB map. The reference manual
(RM0383 for the F411) is the datasheet for everything outside the core; the ARM generic
user guide covers the core. The memory map chapter is the first thing you read for any
new part.

**Reset.** The core reads the vector table at address 0: word 0 is the initial stack
pointer, word 1 the reset handler. Hardware loads SP and jumps. From there it is your code:
copy `.data` from flash to SRAM, zero `.bss`, optionally run constructors, set up clocks,
call `main`. Nothing else has happened; the chip is running from an internal RC oscillator
at a low speed with all peripherals unclocked.

**Linker scripts.** `MEMORY` names the regions and their addresses and sizes. `SECTIONS`
places input sections into output sections in regions, defines symbols (`_sdata`,
`_edata`, `_sbss`, `_estack`) that startup code uses, and controls alignment. `.data` has a
load address in flash (`AT>`) and a run address in SRAM. `KEEP` stops the linker from
discarding the vector table under `--gc-sections`. The map file tells you where every byte
went and is your first stop when flash fills up.

**Clocks.** Everything starts slow. To run at 100 MHz you configure the PLL from the
external crystal (HSE), wait for lock, set flash wait states to match, switch the system
clock source, and enable the clock to each peripheral you use. A peripheral with no clock
reads as zero and ignores writes, which is the most common first bug.

**GPIO and alternate functions.** Each pin has a mode (input, output, alternate, analog),
a speed, a pull, and an alternate-function number that muxes it to a peripheral. The
datasheet's pin table, not the reference manual, says which function is on which pin.

**Peripherals as registers.** A UART is a baud-rate register, a control register, a status
register and a data register. SPI adds a clock-phase and polarity configuration. I2C is
open-drain (Module 1), addresses, ACK bits, clock stretching, and a state machine that is
notoriously easy to hang if you do not handle every error condition. Timers have a
prescaler, a counter, an auto-reload and capture/compare channels; PWM is a timer compare
toggling a pin. The ADC samples a multiplexed input into a register. DMA copies between
peripheral registers and memory on a trigger without the core, with circular buffers and
half-transfer interrupts for continuous streams. The watchdog resets the chip if not fed.

**Interrupts.** The NVIC has per-interrupt enable, priority and pending bits; higher
priority preempts lower; the core stacks eight registers automatically and calls a C
function with no special prologue. Latency is about 12 cycles plus whatever you disabled.
Design rules: ISRs are short, communicate through ring buffers or flags, never block.
`volatile` forces the compiler to reload, but gives no atomicity; use `LDREX/STREX`, disable
interrupts for the shortest critical section, or design single-producer single-consumer
buffers where head and tail are each written by one side.

**Polling, interrupts, DMA.** Polling burns the core; interrupts cost per event; DMA costs
nothing per byte but has setup complexity. A UART at 115200 interrupting per byte is fine;
an ADC at 1 MSa/s is not.

**Faults.** Bus fault, usage fault, memory-management fault, all escalating to hard fault
if not enabled. The Configurable Fault Status Register (CFSR), Hard Fault Status (HFSR),
Bus Fault Address (BFAR) and Memory Fault Address (MMFAR) say what happened; the stacked
frame says where. A good fault handler prints all of it to the UART and writes it to a
no-init RAM region before resetting, so the next boot can report it.

**Debugging.** SWD is a two-wire debug port; OpenOCD speaks it via the on-board ST-LINK and
exposes a GDB server. You can halt, step, read any register or memory, set hardware
breakpoints and watchpoints, and flash. Semihosting or ITM gives `printf` through the
debugger without a UART.

**Bootloaders.** A bootloader is the first program in flash; it decides whether to jump to
the application (set VTOR, set SP, jump) or accept a new image. An A/B scheme keeps two
application slots and a small metadata region; the update writes the inactive slot,
verifies a signature over the image, then atomically flips the active pointer. Rollback
protection stores a monotonic version and refuses older images. Power loss at any point
must leave a bootable system, which means the flip is the last write and is either a
single-word write or a two-phase commit that the bootloader can complete on next boot.

**Code size and C in embedded.** `-Os`, `-ffunction-sections -fdata-sections
-Wl,--gc-sections`, no `printf` with floats unless you need it, `-fno-exceptions
-fno-rtti` if C++, and look at the map file. C++ is fine in firmware with those flags and
no heap surprises; many teams use it. Static analysis (cppcheck, clang-tidy) and MISRA-style
rules exist because firmware bugs are expensive to fix in the field.

**RTOS.** After you have done it bare, an RTOS (FreeRTOS, Zephyr) gives you tasks, queues
and timers. Zephyr in particular is what a modern BMC-adjacent MCU would run, and its device
tree and driver model mirror Linux's. Do Lab 7.7 if time allows.

## Reading

- STM32F411 Reference Manual (RM0383): ch. 2 (memory map), 3 (flash), 6 (RCC clocks), 8
  (GPIO), 9 (DMA), 10 (interrupts/EXTI), 11 (ADC), 13 (timers), 18 (I2C), 19 (UART), 20 (SPI),
  21 (watchdog). Read each chapter the day you use it, fully.
- STM32F411 datasheet: pin tables and electrical characteristics.
- ARM Cortex-M4 Devices Generic User Guide: ch. 2 (core, exception model), ch. 4 (NVIC,
  SysTick, SCB with the fault registers).
- White, *Making Embedded Systems*, 2nd ed., ch. 2 to 8 and 10.
- Yiu, *Definitive Guide to Cortex-M3/M4*: ch. 4 (architecture), 7 to 8 (exceptions),
  12 (fault handling), 13 (startup and linker), 22 (debugging).
- Memfault's Interrupt blog: "From Zero to main()" series (bootstrapping C, linker scripts,
  bare metal), "Cortex-M Fault Debugging", "Device Firmware Update Cookbook".
- Miro Samek, *Modern Embedded Systems Programming* video lessons 1 to 15.

## Labs

### Lab 7.1: Blink from a blank directory

1. Create `startup.s` (vector table with SP and reset handler; copy `.data`, zero `.bss`,
   call `main`, loop), `linker.ld`, `main.c`. No vendor headers. Define the RCC and GPIOA
   register addresses yourself from the reference manual.
2. Enable the GPIOA clock, set PA5 to output, toggle it with a busy loop.
3. Build with `arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -nostdlib -ffreestanding`. Flash
   with OpenOCD. Attach GDB, break at `main`, `stepi` through the startup code and read the
   disassembly until you can narrate every instruction.
4. Read the map file. Find the vector table and the `.data` load address.

Done when: the LED blinks, and your notebook narrates every instruction before `main`.

### Lab 7.2: Clocks and a proper UART

1. Configure the PLL for 100 MHz from the 8 MHz HSE (via the ST-LINK's MCO on the Nucleo)
   with correct flash latency and bus prescalers. Route the system clock to the MCO pin
   and verify with the scope.
2. Write a UART driver: init with computed baud divisor, interrupt-driven TX and RX with
   lock-free ring buffers, error handling (overrun, framing). Implement `_write` so
   `printf` from picolibc (or your own tiny formatter) prints through it.
3. Verify the actual baud rate with the logic analyser. Compute the error.
4. Add SysTick at 1 kHz with a millisecond counter and a `delay_ms`.

Done when: the scope shows 100 MHz on MCO, and `printf` works at 115200 with measured
error under 1%.

### Lab 7.3: I2C and SPI masters

1. I2C master (bit-level state machine driving the peripheral; handle NACK, bus busy,
   arbitration loss, timeout). Read the BME280's chip ID, then its calibration registers
   and a temperature. Implement the compensation formula from its datasheet.
2. Read the INA226 (bus voltage, current) and the EMC2101 (fan tachometer; set a PWM duty
   and read the resulting RPM). Build a tiny fan curve: temperature from BME280 sets duty.
   This is the BMC thermal loop in miniature.
3. SPI master (mode 0, 1 MHz): talk to your FPGA peripheral from Module 3 Lab 3.6. Read the
   ID register, set GPIO, read the timer. Wire the FPGA's interrupt line to an EXTI input.
4. Capture an I2C transaction with a NACK and an SPI transaction on the logic analyser and
   annotate both.

Done when: temperature drives fan RPM, the FPGA responds over SPI with an interrupt on
EXTI, and both captures are annotated.

### Lab 7.4: DMA

1. ADC continuous conversion at 100 kSa/s into a 1,024-sample circular DMA buffer with
   half- and full-transfer interrupts. Compute a running mean per half buffer and stream it
   over UART using DMA for TX as well.
2. Measure CPU load: toggle a GPIO on entering and leaving each ISR and integrate on the
   scope, or count idle-loop iterations. Compare to the same sample rate with per-sample
   interrupts (it will fall over; note where).

Done when: the stream is continuous with no overruns and you have a CPU-load comparison.

### Lab 7.5: Faults and the watchdog

1. Enable bus, usage and memory-management faults. Write one fault handler that prints
   CFSR, HFSR, BFAR, MMFAR and the stacked PC, LR, xPSR, then writes them to a no-init RAM
   region and resets.
2. Trigger each: unaligned access to a device register, read from an unmapped address,
   execute from SRAM with XN, divide by zero with the trap enabled, and a stack overflow
   into the MPU-protected guard region you configure with the MPU.
3. On boot, check the no-init region and print the previous crash if present.
4. Add the independent watchdog with a 500 ms timeout, fed from the main loop. Hang the
   main loop deliberately and watch the reset with the reason logged.

Done when: each fault is decoded correctly and survives the reset into the next boot's log.

### Lab 7.6: A signed A/B bootloader

1. Partition flash: bootloader (16 KiB), metadata (one sector), slot A, slot B. Define an
   image header: magic, version, size, hash, signature, entry vector.
2. Bootloader: check metadata for the active slot; verify the image's signature with
   Ed25519 (Monocypher) or ECDSA P-256 (micro-ecc) against a public key baked into the
   bootloader; check version ≥ stored minimum; set VTOR and SP; jump. On failure, try the
   other slot; if both fail, stay in the bootloader's update mode.
3. Update mode over UART: a simple framed protocol with CRC that writes the inactive slot,
   verifies, then commits by writing the metadata sector last. Make the commit atomic:
   a single word whose two valid values select A or B, written only after everything else.
4. Anti-rollback: the bootloader stores the minimum acceptable version in a
   write-once-per-update location and refuses lower.
5. Test: yank power during the write of the inactive slot, during the metadata write, and
   right after; every time the board must boot something valid. Attempt to load an image
   signed with the wrong key, and an older version. Both must be refused.
6. Application: the app from Lab 7.3, relocated to a slot, with its own vector table.

Done when: you can update A to B and back over UART, every power-loss test boots, and both
rejection cases are demonstrated.

### Lab 7.7: Second vendor, then an RTOS (optional)

1. Port Labs 7.1 and 7.2 to the RP2040 (Pico) with no SDK: note the two-stage boot ROM and
   the flash second-stage requirement. Use the second Pico as a debug probe.
2. Run Zephyr on the Nucleo with its device tree; compare its GPIO and UART drivers with
   yours; note what Zephyr's device tree does that Module 11's Linux one also does.

Done when: the Pico blinks from your code, and you have a paragraph comparing bare metal
with Zephyr for the BMC-lite board.

## Problem set

1. Compute the UART baud register value for 115200 at 100 MHz APB clock with 16×
   oversampling, and the resulting error. Repeat at 921600. At what rate does the error
   exceed 2%?
2. Design I2C pull-ups for a bus at 3.3 V with 180 pF and a 400 kHz target; check the
   sink-current limit.
3. Explain, with a concrete interleaving, a bug that `volatile` on a shared counter does
   not prevent. Fix it with `LDREX/STREX`, and separately with a critical section. When is
   each appropriate?
4. An ISR at priority 2 takes 5 µs. An ISR at priority 1 (higher) arrives 1 µs in. Draw
   the timeline. Now swap priorities. Now give them the same priority. What is the worst
   case latency for the low-priority interrupt if you also disable interrupts for 20 µs
   in a critical section in `main`?
5. A stacked frame shows PC = 0x0800_1234, LR = 0xFFFF_FFF9, CFSR = 0x0000_8200,
   BFAR = 0x4002_0000. What happened? Which stack was in use?
6. A UART receives at 921600 baud and the main loop services the ring buffer every 2 ms.
   Size the buffer. What if the main loop can stall for 50 ms during a flash erase?
7. Design the bootloader's metadata state machine so that a power loss at any point during
   the commit sequence leaves a state the bootloader can interpret unambiguously. Draw it.
   Explain why a single write-once bit per slot ("this slot is confirmed good after first
   boot") solves the "new firmware boots but crashes" case.
8. Flash sectors on the F411 are 16, 64 and 128 KiB. Erase takes up to 2 s for a 128 KiB
   sector. What does that mean for your watchdog and for interrupt latency during an
   update, and how do you design around it?
9. Why does the RP2040 need a second-stage bootloader in the first 256 bytes of flash and
   the STM32 does not?

## Deliverables

- A no-HAL firmware project with linker script, startup, clock, UART, I2C, SPI, DMA, fault
  handler and watchdog, driving the FPGA peripheral and the fan controller.
- The signed A/B bootloader with power-loss test log and the update host tool.
- Annotated logic analyser captures for I2C and SPI.

## Stretch

- Replace UART update with USB DFU using the F411's USB device peripheral, register-level.
- Implement PMBus (SMBus with PEC) and read a PMBus-capable regulator or your server's PSU
  through a level shifter and an I2C header. That is the real BMC power path.
- Write a host-side hardware-abstraction so your sensor and fan logic compiles and unit
  tests on the workstation with mocked registers.

## Next

Module 8 climbs from the microcontroller to the server: what runs before the kernel on x86
and ARM, how a TPM measures it, how a BMC manages it, and how a node netboots and proves
who it is.
