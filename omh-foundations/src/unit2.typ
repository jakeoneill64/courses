#import "lib/template.typ": *
#show: course-doc.with(unit: "2", title: "Logic, Processors and Firmware", short: "Logic, Processors and Firmware",
  subtitle: "From transistors to a CPU, firmware and a measured boot chain",
  chapters: ("Digital logic", "HDL and FPGA", "Build a CPU", "Memory and interconnect", "Privilege and the platform", "Bare-metal firmware", "Boot and platform firmware"))
#contents()

#about-unit(unit: "2",
  intro: [Unit 2 builds a computer from the transistor up and then boots one you did not build, knowing every step. You make gates from MOSFETs, a pipelined RISC-V CPU on an FPGA with caches and privilege, bare-metal firmware for TI's MSP432E401Y with a signed A/B bootloader, and a boot chain on the server from a boot sector to Secure Boot, measured boot, remote attestation, netboot and OpenBMC. Board A in Unit 3 runs this unit's firmware; Module Zero in Unit 4 joins its fleet through this unit's attestation.],
  rows: (
    ([2.1], [CMOS gates from transistors, an adder in logic ICs, a setup-time violation, a state machine], [2]),
    ([2.2], [A UART, an asynchronous FIFO with a formal proof, a memory-mapped peripheral over SPI], [3]),
    ([2.3], [A pipelined RV32IM CPU passing riscv-tests and running your C on the FPGA], [4]),
    ([2.4], [Caches on your CPU, an SDRAM controller, memory experiments, PCIe by hand], [3]),
    ([2.5], [M-mode and U-mode on your CPU, x86-64 bare metal, ACPI and SMBIOS read by hand], [2]),
    ([2.6], [Library-free MSP432E401Y firmware with DMA, fault handling and a signed A/B bootloader], [3.5]),
    ([2.7], [UEFI loader, Secure Boot, measured boot and attestation, netboot, Redfish and OpenBMC], [3.5]),
  ),
  before: [Finish the Handbook's setup checklist for the FPGA tools, OpenOCD and QEMU. Order the server during Unit 1 so it is set up before Chapter 2.4.],
)

#include "u2/ch1-logic.typ"
#include "u2/ch2-fpga.typ"
#include "u2/ch3-cpu.typ"
#include "u2/ch4-memory.typ"
#include "u2/ch5-privilege.typ"
#include "u2/ch6-firmware.typ"
#include "u2/ch7-boot.typ"

#signoff(unit: "2",
  chapters: ("Digital logic", "HDL and FPGA", "Build a CPU", "Memory and interconnect", "Privilege and the platform", "Bare-metal firmware", "Boot and platform firmware"),
  review: (
    [Explain metastability and show, with your formal proof, why your asynchronous FIFO's pointers cross clock domains safely.],
    [Walk a load-use hazard and a taken branch through your pipeline cycle by cycle, and say what your forwarding and flush logic does in each.],
    [Explain a cache miss on the server from the core to DRAM and back, using your Lab 2.4.3 measurements.],
    [From reset to `main` on the MSP432E401Y, and from power-on to a login on the server, name every stage and what each one verifies before it runs the next.],
    [Show how your A/B bootloader survives a power cut at every point, and how a TPM quote convinces a remote verifier of what booted.],
  ),
)
