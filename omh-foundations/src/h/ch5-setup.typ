#import "../lib/template.typ": *

= Setup <h-setup>

Four computers do the work: your workstation (a Mac), the Raspberry Pi 5 on the bench, a small Windows PC for TI's Windows-only tools, and, from Chapter 2.4, the rack server. Set each up as it arrives; the checklist at the end of this part is the done-when for the whole handbook.

== The workstation

macOS on Apple silicon runs almost everything: the toolchains, the FPGA flow, KiCad, Code Composer Studio, the simulators, Python and Typst. Kernel and hypervisor work happens on the server, never on the machine you keep your life on. Install Homebrew, then:

```bash
brew install git cmake ninja python@3.13 pkg-config autoconf automake libtool \
  libusb hidapi qemu verilator icarus-verilog ngspice picocom tio typst
brew install --cask kicad gcc-arm-embedded
brew tap riscv-software-src/riscv && brew install riscv-tools
```

- *FPGA tools.* The distribution versions of Yosys and nextpnr lag; use the OSS CAD Suite build for `darwin-arm64` from YosysHQ's releases, unpacked to `~/opt/oss-cad-suite` and added to your `PATH`. It includes Yosys, nextpnr-ecp5, openFPGALoader, Verilator and SymbiYosys.
- *OpenOCD from source.* The last OpenOCD release predates the MSPM0 support and renames TI's board files, so build git master:
  ```bash
  git clone https://github.com/openocd-org/openocd.git && cd openocd
  ./bootstrap && ./configure --enable-xds110 --enable-cmsis-dap && make -j8 && sudo make install
  ```
- *TI's Code Composer Studio* (version 21 or later, native on Apple silicon), with support for MSP432, C2000 and the SimpleLink CC13xx devices. Inside it, install C2000Ware with the Motor Control SDK (Chapter 3.1) and the SimpleLink Low Power F2 SDK (Chapter 3.2).
- *Logic analysis.* PulseView from the sigrok project's download page; optionally Saleae Logic 2.
- *Python.* A virtual environment for the course's scripts:
  ```bash
  python3 -m venv ~/venvs/omh && source ~/venvs/omh/bin/activate
  pip install numpy scipy matplotlib pandas pyserial pyftdi pyyaml jupyterlab
  ```
- *Simulators in the browser or on the desktop.* Falstad (Chapter 1.1), Digital by hneemann (Chapter 2.1), Surfer or GTKWave for waveforms.

== The Raspberry Pi 5

Install the current 64-bit Raspberry Pi OS with Raspberry Pi Imager, with SSH enabled and your key installed. Then enable I#super[2]C and SPI in `raspi-config`, fit the Active Cooler, and install:

```bash
sudo apt install -y git build-essential python3-venv python3-dev i2c-tools \
  gpiod libgpiod-dev device-tree-compiler minicom
python3 -m venv ~/venv && ~/venv/bin/pip install smbus2 spidev gpiod numpy scipy matplotlib pyserial
```

Plug the TMP117 into the Qwiic cable on the Pi's I#super[2]C pins and run `i2cdetect -y 1`; it should appear at 0x48. From Chapter 2.7 the Pi also boots from NVMe through the M.2 HAT+, and from Chapter 4.2 you build its kernel.

== The Windows PC

Several TI tools run only on x86 Windows: SmartRF Studio 7 for the CC1312R (Chapter 3.2), TICS Pro for the LMX2572 (Chapter 3.3), UniFlash and the mmWave visualiser for the IWRL6432 (Chapter 3.3), and bqStudio for the optional fuel-gauge stretch. Windows on an Apple-silicon Mac does not work for them, because the debug-probe drivers are x86 only. Set up the refurbished OptiPlex (or any x86 Windows 10 or 11 PC) with:

- SmartRF Studio 7, TICS Pro and UniFlash from TI's website, which also installs the XDS110 drivers;
- MMWAVE-L-SDK for the IWRL6432 and its visualiser;
- FTDI's D2XX driver for the C232HM cable (Chapter 3.3);
- Python, so the same scripts run on it when needed.

Keep it on the bench network; it needs no other software.

== The server

When the server arrives (Chapter 2.4 needs it), work through this list before installing anything else.

+ In the BIOS: enable virtualisation (VT-x), VT-d, SR-IOV and the TPM; set the boot mode to UEFI.
+ Update the BIOS and the iDRAC (or Supermicro BMC) firmware to the latest release.
+ Give the iDRAC a static address on the management VLAN, enable Redfish and serial-over-LAN, and change the default password.
+ Install Debian stable or Ubuntu Server LTS on a small drive, leaving the NVMe drives for the labs, then install the tools:
  ```bash
  sudo apt install -y build-essential git cmake ninja-build python3-venv \
    qemu-system qemu-utils ovmf swtpm swtpm-tools tpm2-tools \
    gnu-efi sbsigntool efitools mtools dosfstools xorriso \
    libelf-dev libssl-dev bc flex bison dwarves \
    trace-cmd bpftrace fio iperf3 nvme-cli pciutils \
    dnsmasq ipxe acpica-tools dmidecode ipmitool
  ```
  Add `perf` from your distribution's package: `linux-perf` on Debian, `linux-tools-generic` on Ubuntu.
+ Confirm `lscpu | grep vmx`, `dmesg | grep -i -e DMAR -e IOMMU`, and `/dev/tpm0`.

== The lab network

The TL-SG108E carries four VLANs from Chapter 2.7 onwards. Assign them once and keep the plan in your notebook.

#tbl(columns: (auto, auto, 1fr), header: ([VLAN], [Name], [What lives on it]),
  [10], [management], [The server's iDRAC, Board A, the node agents],
  [20], [lab], [Netboot and provisioning (dnsmasq and iPXE), your workstation],
  [30], [storage], [NVMe over Fabrics and replication traffic (Chapter 4.5)],
  [40], [tenant], [Virtual machines' traffic in the capstone (Chapter 4.7)],
)

#tbl(columns: (auto, 1fr), header: ([Port], [Connection]),
  [1], [Workstation: VLAN 20 untagged, 10 tagged],
  [2], [Server iDRAC: VLAN 10 untagged],
  [3], [Server Gigabit port: VLANs 20, 30 and 40 tagged],
  [4], [Raspberry Pi 5: VLANs 20, 30 and 40 tagged],
  [5], [Board A: VLAN 10 untagged],
  [6], [Board B: VLANs 20, 30 and 40 tagged],
  [7 and 8], [Spare, or your home network uplink on VLAN 20 if you need internet access on the lab network],
)

== The labs repository

Create the repository with the layout in Part 2, push it to a private remote, and add a `setup/notebook.md` recording what arrived, what was substituted, and what is still on back-order. That is your first supply-chain log.

#checklist(title: [Setup checklist], intro: [Setup is done when every line is true. Tick the server lines when it arrives.],
  [*Bench:* meter, oscilloscope, supply, generator and load power up and pass a self-test; the logic analyser shows a signal in PulseView; the soldering station heats and holds temperature.],
  [*Workstation:* `yosys -V`, `nextpnr-ecp5 --version`, `verilator --version` and `sby --help` run from the OSS CAD Suite.],
  [*Toolchains:* `arm-none-eabi-gcc --version` runs, and `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -c hello.c` succeeds.],
  [*OpenOCD:* your git-master build connects to the MSP-EXP432E401Y with `openocd -f board/ti/msp432-launchpad.cfg` and reads the device ID.],
  [*Emulation:* `qemu-system-x86_64` with OVMF reaches the UEFI shell, and `qemu-system-riscv64 -M virt -nographic -bios default` prints the OpenSBI banner.],
  [*Code Composer Studio* builds and flashes a C2000Ware example to the F280025C LaunchPad.],
  [*Windows PC:* SmartRF Studio 7 detects a CC1312R LaunchPad over its XDS110, and TICS Pro opens the LMX2572 profile.],
  [*Pi:* boots with SSH, I#super[2]C and SPI enabled, and `i2cdetect -y 1` shows the TMP117 at 0x48.],
  [*FPGA:* `openFPGALoader -b ulx3s blink.bit` loads an example bitstream and an LED blinks.],
  [*Server:* iDRAC reachable on VLAN 10; serial-over-LAN works; Linux installed; `vmx`, the IOMMU and `/dev/tpm0` all present.],
  [*Repository:* the labs repository exists with the Part 2 layout, and the setup notebook holds the supply-chain log.],
)
