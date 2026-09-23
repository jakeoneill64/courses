# Module 0: Setup and lab kit

**1 week, mostly waiting for parcels. Order the Core and Firmware tiers on day one.**

## What this module buys OMH

A bench and a lab machine you can crash, short and reflash without consequences. Every
later module assumes this environment exists. Setting it up is also your first exposure
to the supply-chain reality of hardware: lead times, stock, substitutes.

---

## Lab kit

Buy in tiers. Core and Firmware are needed by Module 1 and Module 3 respectively. The
Server tier is needed by Module 5. The Board tier is needed by Module 14, but the scope
and bench supply pay for themselves from Module 1 onward if you can afford them early.

### Core tier (Modules 1 to 4)

| Item | Suggestion | Approx. USD | Notes |
|---|---|---|---|
| Multimeter | Brymen BM235, UNI-T UT61E+, or Aneng AN8008 | 40–120 | Needs µA range and continuity beeper |
| Breadboards and jumper wires | 2 large breadboards, mixed wire kit | 20 | |
| Passive component kit | Resistor (E12, 1/4 W), ceramic and electrolytic capacitor assortments | 25 | |
| Discrete semis | 20× 2N7000 (N-MOSFET), 10× BS250 (P-MOSFET), 10× 2N3904, 10× IRLZ44N, 1N4148 and 1N5819 diodes, LEDs | 20 | Logic-level parts matter for 3.3 V labs |
| Logic ICs | 74HC00, 04, 08, 14, 32, 86, 74, 161, 245, 573 (3 each), NE555 (3) | 20 | |
| Logic analyser | Saleae Logic 8 (400) or an 8-channel 24 MHz FX2 clone with PulseView (10) | 10–400 | The clone is enough until Module 7 |
| FPGA board | ULX3S with ECP5-85F | 150–220 | HDMI out, 32 MB SDRAM, open toolchain. Budget alternative: Tang Nano 20K (30) |
| USB to serial adapters | 2× FTDI FT232RL or CP2102 (3.3 V) | 10 | |
| Small parts | Pushbuttons, 10k potentiometer, 12 V server fan (4-pin PWM), piezo, photoresistor | 15 | |

### Firmware tier (Modules 7 onward)

| Item | Suggestion | Approx. USD | Notes |
|---|---|---|---|
| MCU board | ST Nucleo-F411RE | 15 | On-board ST-LINK, Arduino headers, well-documented reference manual |
| Second vendor MCU | 2× Raspberry Pi Pico (one becomes a debug probe) | 10 | |
| I2C sensor | BME280 breakout | 8 | Temperature, pressure, humidity; simple register map |
| Fan controller | EMC2101 breakout | 8 | I2C fan PWM with tachometer: the BMC fan path |
| Current sensor | INA226 breakout | 8 | Power rail monitoring over I2C |
| Secure element | ATECC608 breakout or Infineon OPTIGA Trust M eval | 10 | Used for the Modulus-adjacent labs |

### Server tier (Modules 5 onward)

| Item | Suggestion | Approx. USD | Notes |
|---|---|---|---|
| Lab server | Used Supermicro X11 (Xeon E5 v4 or Scalable) 1U/2U, or Dell R630/R730 | 200–450 | Needs VT-x, VT-d, ECC, a BMC with Redfish and serial-over-LAN, a TPM header, PMBus PSUs. It will be loud. |
| Quiet alternative | Lenovo ThinkCentre Tiny or Dell OptiPlex Micro, Intel 8th gen or newer | 120–200 | Loses BMC, PMBus and PCIe slots. Only if noise makes the server impossible. |
| TPM 2.0 module | Matching the server's header (Supermicro AOM-TPM-9670V or equivalent) | 20–40 | Some boards have it onboard; check |
| NIC | 2× Intel X520-DA2 (82599) or Mellanox ConnectX-4 Lx, plus one SFP+ DAC cable | 80 | SR-IOV, DPDK, RDMA-capable. The 82599 datasheet is the best-documented NIC in existence |
| NVMe drives | 1 used enterprise drive with power-loss protection (Intel P4510, Samsung PM983), 1 cheap consumer drive to sacrifice | 100 | |
| Linux SBC | Raspberry Pi 5 (8 GB) with M.2 HAT+ and a small NVMe | 130 | Exposed GPIO, I2C, SPI, PCIe; mainline kernel; ARM KVM |
| TPM for the Pi | LetsTrust TPM (SLB9670, SPI) | 20 | |
| Serial console | USB to serial adapters from the Core tier; a null-modem DB9 cable if the server has a serial port | 5 | |
| Managed switch | Any small managed gigabit switch with VLANs | 40 | For the PXE and fleet labs |

### Board tier (Modules 1 and 14; buy early if you can)

| Item | Suggestion | Approx. USD | Notes |
|---|---|---|---|
| Oscilloscope | Rigol DHO804 or Siglent SDS804X HD (12-bit, 4 channel). Used Rigol DS1054Z is fine | 300–450 | 100 MHz nominal is enough through Module 14 |
| Bench power supply | Korad KA3005P or Riden RD6006 with case | 80–120 | Current limiting is what saves your first board |
| Soldering | Pinecil v2 (30) or Hakko FX-888D (120); 858D hot-air station (50); leaded 0.5 mm solder for learning; flux pen; wick; fine tweezers | 100–200 | Use leaded solder while learning, and note RoHS for anything you ship |
| Magnification | USB microscope with stand | 30 | Needed for 0402 and QFN inspection |
| ESD | Mat and wrist strap | 20 | |
| Fab runs | Two boards, 5 pieces each, with stencil; one run assembled | 150–400 | JLCPCB or PCBWay |
| Misc | Kapton tape, isopropyl alcohol, flush cutters, calipers, a thermocouple meter | 40 | |

Total for everything is in the region of 1,800 to 2,800 USD spread over the year. The
server, scope and FPGA board are the three purchases that change what you can learn;
everything else is cheap.

---

## Workstation

A Linux workstation or a full Linux VM with at least 8 cores, 32 GB RAM and 200 GB
disk. macOS with a VM works for most software labs but not for USB device passthrough
to QEMU or for `/dev/kvm`; do kernel and hypervisor labs on the lab server or a Linux
box. Never develop kernels on the machine you keep your life on.

### Packages

```bash
sudo apt install build-essential git cmake ninja-build python3-pip python3-venv \
  qemu-system qemu-utils ovmf swtpm swtpm-tools tpm2-tools \
  gcc-riscv64-unknown-elf gcc-arm-none-eabi gdb-multiarch binutils-multiarch \
  openocd picocom minicom \
  verilator iverilog gtkwave yosys nextpnr-ecp5 openfpgaloader \
  kicad ngspice sigrok-cli pulseview \
  gnu-efi sbsigntool efitools mtools dosfstools xorriso grub-pc-bin grub-efi-amd64-bin \
  linux-source libelf-dev libssl-dev bc flex bison dwarves \
  trace-cmd bpftrace linux-tools-generic fio iperf3 nvme-cli pciutils i2c-tools \
  dnsmasq-base ipxe tftpd-hpa acpica-tools dmidecode
```

For Yosys, nextpnr and Verilator, the distro versions lag badly. Prefer the OSS CAD
Suite nightly build from YosysHQ, unpacked to `~/opt/oss-cad-suite` and added to
`PATH`. It bundles everything including SymbiYosys for formal.

### Toolchains you will build or fetch separately

- **riscv32 bare-metal**: the distro `gcc-riscv64-unknown-elf` is multilib and can emit
  `-march=rv32i -mabi=ilp32`. Verify with a hello-world before Module 4. If it cannot,
  fetch the xPack RISC-V embedded GCC.
- **x86_64-elf cross compiler**: build with crosstool-ng or the OSDev wiki recipe. The
  host compiler with `-ffreestanding -nostdlib -mno-red-zone -mcmodel=kernel` works for
  Module 9 but a real cross compiler avoids surprises.
- **Linux kernel source**: clone `torvalds/linux` and a stable branch; you will build it
  many times from Module 10.
- **Buildroot**: clone; used to make small root filesystems and OpenBMC-adjacent images.
- **kvmtool, Firecracker, Cloud Hypervisor, QEMU source**: clone for reading in Module 12.

### Simulators and tools you will use in a browser or on the desktop

- Falstad circuit simulator (Module 1)
- Digital by hneemann (Module 2): a fast, pleasant logic simulator with a real clock
- Surfer or GTKWave for waveforms (Module 3 onward)
- Saturn PCB Toolkit or the KiCad calculators for trace impedance (Module 14)

---

## Setup checklist

Done when every line is true.

- [ ] Bench: multimeter, breadboard, parts kit, FX2 logic analyser recognised by PulseView.
- [ ] `qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -nographic` reaches the UEFI shell.
- [ ] `qemu-system-riscv64 -M virt -nographic -bios default` prints the OpenSBI banner.
- [ ] OSS CAD Suite on `PATH`; `yosys -V`, `nextpnr-ecp5 --version`, `verilator --version`, `sby --help` all work.
- [ ] ULX3S: `openFPGALoader -b ulx3s blink.bit` loads an example bitstream and an LED blinks.
- [ ] Nucleo-F411RE: `openocd -f board/st_nucleo_f4.cfg` connects; `arm-none-eabi-gcc` compiles a trivial file with `-mcpu=cortex-m4 -mthumb`.
- [ ] `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -c hello.c` succeeds.
- [ ] Server: BMC reachable on the lab VLAN; serial-over-LAN works; Linux installed to a small drive; `lscpu` shows `vmx`; `dmesg | grep -i iommu` shows DMAR/IOMMU enabled; `/dev/tpm0` exists.
- [ ] Pi 5: boots Raspberry Pi OS or Debian from NVMe; I2C and SPI enabled; `i2cdetect -y 1` lists the BME280.
- [ ] Labs repo created with the directory layout from the README.
- [ ] Lab notebook for Module 0 records what arrived, what was substituted, and what is still on back order. This is your first supply-chain log.
