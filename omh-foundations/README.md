# OMH Foundations

## Hardware and low-level systems from first principles

A self-directed, lab-driven course for one student: a strong software engineer with
good C++ who is founding OMH, a company that will build rack modules delivering
AWS-class services (Compute, Storage, Blocks, Clusters, Modulus key custody and the
rest) on hardware it designs, manufactures and supports.

The course starts at electrons and ends with a two-node fleet of engineering-sample
modules that attest their firmware, join a quorum, run tenant VMs on a hypervisor you
wrote, and store data erasure-coded across NVMe. Every claim on the OMH hardware page
(zero-touch join, measured boot, OpenBMC and Redfish, rolling firmware updates, CXL
fabric, encryption with keys in Modulus) maps to something you will have built a small,
honest version of by the end.

---

## What you will have built

- A CMOS NAND gate from discrete transistors, then a 4-bit adder from logic ICs, then
  a pipelined RV32I CPU with caches and M-mode traps on an FPGA, running C you compiled.
- Bare-metal firmware for an STM32 with no vendor HAL: your own linker script, startup
  code, drivers, fault handler and a signed A/B bootloader with anti-rollback.
- A boot chain you understand byte by byte: a boot sector, a UEFI loader, Secure Boot
  with your own keys, measured boot into a TPM, and remote attestation with a nonce.
- A 64-bit kernel with paging, SMP, user mode, syscalls and an NVMe driver.
- Linux kernel modules and drivers for real hardware: an I2C sensor with a device-tree
  binding, an SPI-attached FPGA peripheral exposed as a gpiochip, a PCIe device with
  MSI and DMA, and a VFIO userspace driver.
- A KVM-based VMM that boots Linux with virtio-blk and virtio-net you implemented, plus
  a bare-metal VT-x hypervisor that runs Linux underneath itself.
- Two PCBs you designed, had fabricated, assembled and brought up: a BMC-style
  management controller and a Compute Module carrier with PCIe NVMe and a TPM.
- A written product spec, threat model, firmware update architecture, manufacturing
  test plan, compliance plan and cost model for Module Zero.

---

## Structure

Five parts, sixteen modules, about a year at 12 to 15 hours a week. Fab lead times in
Part V overlap with earlier reading. Weeks are a guide, not a contract.

| # | Module | Weeks | Headline lab |
|---|--------|-------|--------------|
| 0 | [Setup and lab kit](00-setup.md) | 1 | Workstation, toolchains, bench, parts on order |
| **I** | **Physics to logic** | | |
| 1 | [Electricity and components](01-electricity-and-components.md) | 2 | Measure a decoupling failure on a scope; build and characterise a regulator |
| 2 | [Digital logic](02-digital-logic.md) | 2 | CMOS NAND from MOSFETs; 4-bit adder in 74HC; provoke a setup-time violation |
| 3 | [HDL and FPGA](03-hdl-and-fpga.md) | 3 | UART, async FIFO with formal proof, a memory-mapped peripheral over SPI |
| **II** | **Computer architecture** | | |
| 4 | [Build a CPU](04-build-a-cpu.md) | 4 | Pipelined RV32I on the FPGA passing riscv-tests, running your C |
| 5 | [Memory and interconnect](05-memory-and-interconnect.md) | 3 | Caches on your CPU; SDRAM controller; decode a real PCIe config space by hand |
| 6 | [Privilege and the platform](06-privilege-and-platform.md) | 2 | M-mode traps and a preemptive timer on your CPU; x86 IDT and APIC in QEMU |
| **III** | **Firmware** | | |
| 7 | [Bare-metal firmware](07-bare-metal-firmware.md) | 3 | STM32 from a blank directory to DMA, hard-fault decoding and a signed bootloader |
| 8 | [Boot and platform firmware](08-boot-and-platform-firmware.md) | 3 | UEFI loader, Secure Boot, measured boot, remote attestation, PXE, OpenBMC |
| **IV** | **Kernels and hypervisors** | | |
| 9 | [Write a kernel](09-write-a-kernel.md) | 5 | 64-bit SMP kernel with user mode and an NVMe driver, on QEMU and real iron |
| 10 | [Linux kernel internals](10-linux-kernel-internals.md) | 3 | Trace write(2) to the tty; RCU list in a module; KASAN catches your bug |
| 11 | [Linux device drivers](11-linux-device-drivers.md) | 4 | IIO sensor, gpiochip for your FPGA, PCIe with MSI and DMA, VFIO userspace driver |
| 12 | [Virtualisation and hypervisors](12-virtualisation-and-hypervisors.md) | 5 | KVM VMM booting Linux with your virtio devices; bare-metal VT-x hypervisor |
| 13 | [Storage and network data paths](13-storage-and-network-data-paths.md) | 2 | io_uring vs SPDK on NVMe; Reed-Solomon in C++; NVMe-oF; XDP and DPDK |
| **V** | **Making the product** | | |
| 14 | [Board design and bring-up](14-board-design-and-bring-up.md) | 4 + fab | BMC-lite controller board; Compute Module carrier with PCIe NVMe and TPM |
| 15 | [Server product engineering](15-server-product-engineering.md) | 2 | Module Zero spec, threat model, test plan, compliance plan, cost model |
| 16 | [Capstone: Module Zero](16-capstone-module-zero.md) | 6+ | Two heterogeneous nodes attest, join, run VMs, replicate over NVMe-oF |

Dependencies are mostly linear. Two you can reorder: Module 13 can follow Module 11
directly, and Module 14's Board A can start as soon as Module 7 is done so fab lead
time is not on the critical path.

---

## How to work the course

**Build everything.** Reading is scaffolding for the labs, not a substitute. Every
module has acceptance criteria phrased as "done when". Do not move on until they hold.

**Datasheet before tutorial.** When a lab involves a chip, read the relevant reference
manual chapter first and only then look at anyone else's code. The skill OMH needs is
reading primary sources cold, because that is what you will be doing with CXL
controllers, NVMe drives and BMC SoCs that have no tutorials.

**No vendor abstraction until you have written your own.** No STM32 HAL until Module 7
is done. No LiteX until you have a CPU. No kvmtool until your `/dev/kvm` program runs.
Then use them freely and read them critically.

**Keep a lab notebook.** One markdown file per module in your labs repo. Record what
you predicted, what you measured, and the gap. Scope captures and photos go in. The
notebook is also the raw material for OMH's engineering blog, which is how a hardware
company with no customers earns credibility.

**Take the skip test.** Each module opens with a short skip test. If you can answer
every question cold and would be comfortable being interviewed on it, skim the core
ideas and do only the headline lab. Your C++ background means Module 5's memory model
material and parts of Module 10 will go fast; be honest about the rest.

**Cadence.** Two weekday evenings of reading and problem sets, one long weekend
session on the bench or in the debugger. Labs with hardware need contiguous time.

**Labs repo.** Create a separate repository for coursework, one directory per module:

```
omh-course-labs/
  01-electricity/    notebook.md, scope/, sim/
  03-fpga/           rtl/, tb/, formal/, constraints/
  04-cpu/            rtl/, sw/, tests/
  07-firmware/       nucleo/, bootloader/
  09-kernel/         boot/, kernel/, user/
  11-drivers/        iio-bme280/, fpga-spi/, edu-pci/, vfio-nic/
  12-hypervisor/     vmm/, vtx/
  14-boards/         board-a-bmc-lite/, board-b-carrier/
```

---

## Reference library

Buy or download these up front; the module files say which chapters when.

| Book or spec | Used in |
|---|---|
| Horowitz and Hill, *The Art of Electronics*, 3rd ed. | 1, 14 |
| Harris and Harris, *Digital Design and Computer Architecture*, RISC-V ed. | 2, 3, 4 |
| Patterson and Hennessy, *Computer Organization and Design*, RISC-V ed. | 4, 5 |
| Nagarajan et al., *A Primer on Memory Consistency and Cache Coherence* (free) | 5 |
| Drepper, *What Every Programmer Should Know About Memory* (free) | 5 |
| Jackson and Budruk, *PCI Express Technology 3.0* (MindShare) | 5, 11 |
| RISC-V Unprivileged and Privileged ISA specs (free) | 4, 6 |
| Intel 64 and IA-32 Software Developer's Manual, vol. 3 (free) | 6, 8, 9, 12 |
| White, *Making Embedded Systems*, 2nd ed. | 7 |
| Yiu, *The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors* | 7 |
| Zimmer, Rothman, Marisetty, *Beyond BIOS*, 3rd ed. | 8 |
| Arthur and Challener, *A Practical Guide to TPM 2.0* (free, Apress Open) | 8, 15 |
| UEFI, ACPI, TCG PC Client Firmware Profile, DMTF Redfish specs (free) | 6, 8 |
| Arpaci-Dusseau, *Operating Systems: Three Easy Pieces* (free) | 9 |
| Cox, Kaashoek, Morris, *xv6: a simple, Unix-like teaching OS* (free) | 9 |
| NVMe Base and NVMe over Fabrics specs (free) | 9, 11, 13 |
| Love, *Linux Kernel Development*, 3rd ed. | 10 |
| Bootlin kernel and driver development course materials (free) | 10, 11 |
| Corbet, Rubini, Kroah-Hartman, *Linux Device Drivers*, 3rd ed. (free) | 11 |
| Madieu, *Linux Device Driver Development*, 2nd ed. | 11 |
| Bugnion, Nieh, Tsafrir, *Hardware and Software Support for Virtualization* | 12 |
| virtio 1.2 spec; Linux `Documentation/virt/kvm/api.rst` (free) | 12 |
| Johnson and Graham, *High-Speed Digital Design* | 14 |
| Bogatin, *Signal and Power Integrity, Simplified* | 14 |
| Ott, *Electromagnetic Compatibility Engineering* | 14, 15 |
| OCP specs: Open Rack v3, DC-SCM 2.0, Yosemite v3, Caliptra (free) | 15, 16 |
| IETF RFC 9334, *Remote Attestation Procedures Architecture* (free) | 8, 15, 16 |

---

## Progress

Tick as each module's "done when" criteria all hold. Date it.

- [ ] 00 Setup — kit ordered, toolchains built, QEMU boots, FPGA blinks, Nucleo blinks
- [ ] 01 Electricity and components
- [ ] 02 Digital logic
- [ ] 03 HDL and FPGA
- [ ] 04 Build a CPU
- [ ] 05 Memory and interconnect
- [ ] 06 Privilege and the platform
- [ ] 07 Bare-metal firmware
- [ ] 08 Boot and platform firmware
- [ ] 09 Write a kernel
- [ ] 10 Linux kernel internals
- [ ] 11 Linux device drivers
- [ ] 12 Virtualisation and hypervisors
- [ ] 13 Storage and network data paths
- [ ] 14 Board design and bring-up (Board A)
- [ ] 14 Board design and bring-up (Board B)
- [ ] 15 Server product engineering
- [ ] 16 Capstone: Module Zero demo recorded

---

## Conventions

Prices are approximate USD at the time of writing. Spelling is British. "Server" means
the used x86 machine from the lab kit; "the Pi" means the Raspberry Pi 5; "the FPGA"
means the ULX3S unless a module says otherwise. Commands assume Debian or Ubuntu.
