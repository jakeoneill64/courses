# Module 8: Boot and platform firmware

**Part III · 3 weeks · Needs: the server with TPM and BMC, QEMU with OVMF and swtpm, the Pi, a managed switch.**

## Why this module (and what it buys OMH)

Read the FLEET capability on your own hardware page: "It powers on, attests its firmware to
the control plane, finds its peers across the backplane and starts serving." Then the
spec sheet: "OpenBMC · Redfish · measured boot". This module is that paragraph. By the end
you will have netbooted a machine with no local configuration, measured its firmware and
kernel into a TPM, verified a quote against a policy on another machine, refused an
unsigned bootloader, driven a BMC over Redfish, and built OpenBMC. Everything in the
capstone's join protocol is assembled from these labs.

## Skip test

1. Why can x86 firmware not use RAM for the first few thousand instructions, and what does
   it use instead?
2. Explain the difference between Secure Boot and measured boot, and give a failure each
   one catches that the other cannot.
3. PCR 4 holds a value after boot. Describe exactly how it was computed and what you need
   to reproduce it from the event log.
4. A remote verifier receives a TPM quote. List what it must check before believing the
   PCR values, including how it knows the quote came from a real TPM.
5. Draw the packet sequence for a PXE boot from power-on to the kernel's first instruction,
   naming the protocols and the DHCP options involved.

If all five are easy, do Labs 8.4, 8.6 and 8.7.

## Core ideas

**Power-on reality on x86.** The first instruction fetch is at 0xFFFFFFF0 in 16-bit real
mode, from SPI flash mapped below 4 GiB by the chipset. There is no working DRAM yet; the
memory controller must be trained (Module 5). Firmware runs early code with the cache
configured as RAM (CAR, "no-evict mode"), then initialises memory via a vendor blob
(Intel FSP or AMD AGESA), then relocates itself into DRAM and enumerates the platform. On
the way it configures SMM, loads microcode, sets up ACPI tables, enumerates PCIe and assigns
BARs, and only then looks for something to boot.

**UEFI.** A specification for firmware structure and the interface it offers to bootloaders
and operating systems. Phases: SEC (security, CAR), PEI (pre-EFI initialisation, memory),
DXE (driver execution, most of the work), BDS (boot device selection), then transient
system load. Boot services (memory allocation, protocols, file access, ExitBootServices)
exist until the OS takes over; runtime services (variables, time, capsule update, reset)
persist. An EFI application is a PE/COFF binary on a FAT-formatted EFI System Partition.
Boot order lives in NVRAM variables. EDK2 is the reference implementation; OVMF is its
QEMU build; most vendor firmware is EDK2 plus a large closed layer.

**coreboot.** An open alternative that does the minimum initialisation and hands off to a
payload (a UEFI implementation, GRUB, LinuxBoot, or a Linux kernel as the bootloader).
Google and several hyperscalers use it because auditable firmware is the base of a
measured chain. LinuxBoot in particular replaces DXE and BDS with a Linux kernel, which is
the direction an OMH platform team would seriously consider.

**Secure Boot.** A signature chain enforced by firmware. The Platform Key (PK) owns the
Key Exchange Keys (KEK), which own the allowed-signatures database (db) and the forbidden
database (dbx). Firmware executes only PE binaries signed by a db key (or whose hash is in
db) and not in dbx. Linux distributions boot through Microsoft-signed shim, which then
verifies GRUB and the kernel with its own keys and the Machine Owner Key (MOK) list. On your
own hardware you enrol your own PK and sign everything yourself. Secure Boot answers "was
this allowed to run"; it says nothing about what actually ran.

**The TPM and measured boot.** A Trusted Platform Module is a small, slow, tamper-resistant
chip with keys that never leave it and Platform Configuration Registers that can only be
extended: PCR_new = SHA256(PCR_old || measurement). Firmware extends measurements of itself
into PCR 0, its configuration into PCR 1, option ROMs into 2 and 3, the bootloader into 4,
the GPT into 5, Secure Boot state and keys into 7; the bootloader or a unified kernel image
extends the kernel, initrd and command line into 8, 9 or 11; the kernel's Integrity
Measurement Architecture extends file hashes into 10. Each extend is logged in the TCG
event log with the digest and a description. Because extend is a hash chain, the final PCR
value commits to the exact sequence of measurements, and a verifier who replays the log
must arrive at the same values. This is the Static Root of Trust for Measurement (SRTM);
a Dynamic RTM (Intel TXT, AMD SKINIT) lets a late launch re-establish trust without a
reset.

**TPM anatomy for attestation.** The Endorsement Key (EK) is unique per TPM, with a
certificate from the manufacturer proving it is a genuine TPM. An Attestation Key (AK) is
created under the endorsement hierarchy and proven to belong to the same TPM via a
credential-activation protocol. A quote is a TPM-signed statement of selected PCR values
plus a verifier-supplied nonce, signed by the AK. Sealing binds a secret to PCR values so
it can only be unsealed when the machine booted into the same state; this is how a LUKS
key can be released only to your kernel. The Remote Attestation Procedures architecture
(RFC 9334) names the parties: Attester, Verifier, Relying Party, and their evidence,
endorsements, reference values and appraisal policy. OMH's control plane is the Verifier;
the module is the Attester; the quorum is the Relying Party.

**Measured boot in the small.** MCUs and BMCs do the same with DICE (each boot stage
derives a key from the previous stage's secret and the next stage's hash) and with a
hardware root of trust like OCP's Caliptra. SPDM lets a host attest its PCIe devices. Your
Module 7 bootloader is the first link of such a chain.

**ARM and RISC-V boot chains.** ARM: a boot ROM in the SoC loads a first-stage loader from
flash or SD, which loads Trusted Firmware-A (BL2 → BL31 as the EL3 monitor, optionally BL32
as a secure OS) and then U-Boot (BL33) at EL2, which loads a kernel and a device tree blob.
The Pi is a special case: its GPU firmware does the early work, then `start.elf` loads the
kernel or a U-Boot binary. RISC-V: a zero-stage loader, then OpenSBI in M-mode providing the
Supervisor Binary Interface, then U-Boot in S-mode, then the kernel. U-Boot is a
mini-operating system with drivers, filesystems, networking, scripting, a device tree of
its own, signed-image verification (FIT images), and Secure Boot equivalents.

**What the kernel expects.** On x86, the boot protocol documented in
`Documentation/arch/x86/boot.rst`: a real-mode header, `boot_params` (the "zero page"),
the command line, an initrd address, and either the 16-bit, 32-bit or 64-bit entry point,
or the EFI stub which lets the kernel be launched directly as an EFI application. On ARM64,
an image header, the DTB address in `x0`, EL2 or EL1 entry with MMU off. On RISC-V, `a0`
holds the hart id and `a1` the DTB, and OpenSBI stays resident to serve `ecall`s.

**Netboot and zero-touch.** A NIC's option ROM or the UEFI network stack does DHCP; the
server replies with an IP and a next-server and boot filename (options 66 and 67, plus the
client's architecture in option 93); the client fetches the file over TFTP (PXE) or HTTP
(UEFI HTTP boot). iPXE is a boot firmware that can be chain-loaded and then scripts the
rest: fetch a kernel and initrd over HTTP with per-MAC or per-serial URLs, pass a command
line, boot. A node with no local state then fetches its configuration from the control
plane, which is the zero-touch join. The control plane can require an attestation before
handing out anything sensitive.

**The BMC.** A separate SoC (ASPEED AST2500/2600 on nearly every server) with its own
Ethernet, flash and Linux, powered whenever the chassis has standby power. It controls host
power and reset, reads sensors over I2C and PMBus, drives fans, provides a serial console
over LAN, a virtual keyboard-video-mouse, virtual media, and firmware update for itself
and the host BIOS. Host and BMC talk over LPC or eSPI (KCS for IPMI), I2C (IPMB), and MCTP
with PLDM for modern platform management. IPMI is the legacy protocol; Redfish is its
RESTful, JSON, schema-driven replacement from DMTF. OpenBMC is the Linux Foundation's
open BMC distribution built on Yocto: phosphor daemons communicating over D-Bus,
`bmcweb` serving Redfish, `phosphor-hwmon` and `entity-manager` for sensors, and a
firmware-update flow. OCP's DC-SCM specification puts the BMC on a replaceable card with a
standard connector, which is what a rack-module company should read before designing
anything.

**Firmware storage and update.** SPI NOR flash, often two chips for A/B, with write
protection controlled by the BMC or by hardware straps. UEFI capsules and Redfish
`UpdateService` are the sanctioned update paths. A rolling fleet update that "drains and
rejoins a single module at a time" is orchestration on top of these primitives plus
re-attestation after reboot.

## Reading

- Zimmer, Rothman, Marisetty, *Beyond BIOS*, 3rd ed., ch. 1 to 4, 7, 9 (UEFI architecture,
  boot flow, Secure Boot, TPM).
- UEFI Specification: ch. 2 (overview), ch. 7 (boot services, skim), ch. 8 (runtime
  services), ch. 32 (Secure Boot and driver signing).
- Arthur and Challener, *A Practical Guide to TPM 2.0*: ch. 1 to 3, 9 to 12 (hierarchies,
  keys, PCRs, attestation), ch. 21 (attestation use cases). Free from Apress.
- TCG PC Client Platform Firmware Profile Specification, sections 2 to 3 and 7 (what is
  measured where, the event log format). TCG EFI Protocol Specification.
- RFC 9334, Remote Attestation Procedures Architecture. Short; read all of it.
- Linux `Documentation/arch/x86/boot.rst`; `Documentation/arch/arm64/booting.rst`;
  `Documentation/arch/riscv/boot.rst`.
- coreboot documentation: "Getting started" and the "Payloads" pages; the LinuxBoot book.
- Bootlin Embedded Linux training slides, sections on bootloaders and U-Boot.
- OpenBMC documentation: architecture overview, `bmcweb` Redfish, code-update design.
- DMTF Redfish Specification (DSP0266) ch. 1 to 7 and the Redfish mockup server.
- OCP DC-SCM 2.0 specification, skim for what a BMC card is expected to provide.
- iPXE documentation: scripting and chainloading.

## Labs

### Lab 8.1: A boot sector, then a two-stage loader

1. Write a 512-byte MBR boot sector in assembly: print a string through BIOS interrupt 10h,
   then through the 16550 at 0x3F8 directly. Boot it in QEMU with `-drive format=raw`.
   Explain every byte, including the signature at 510.
2. Stage two: the boot sector loads more sectors with BIOS 13h, enables A20, sets up a GDT,
   enters protected mode, then sets up identity-mapped page tables and enters long mode.
   Load an ELF64 from a known LBA, parse its program headers, copy segments, jump to the
   entry. Your Module 6 Lab 6.3 binary is the payload.
3. Use QEMU's `-d int,cpu_reset` and the monitor's `info registers` when it triple-faults.

Done when: your Module 6 x86 program runs from your own boot sector in QEMU, and your
notebook has an annotated hex dump of the boot sector.

### Lab 8.2: A UEFI loader

1. With gnu-efi (or EDK2 if you prefer the full tooling), write an EFI application that
   prints the firmware vendor and revision, dumps the memory map with types, and locates
   the ACPI RSDP via the configuration table.
2. Load a file from the ESP via the Simple File System protocol: your ELF64 kernel payload.
   Parse it, allocate pages for it via `AllocatePages`, copy segments.
3. Retrieve the graphics framebuffer via GOP. Build a boot-information structure (memory
   map, framebuffer, RSDP, command line). Call `ExitBootServices` (handle the retry-on-map-
   change case correctly), set up your own page tables, jump to the payload with the
   structure pointer.
4. Run under OVMF in QEMU, then on the server from a USB stick's ESP. This loader becomes
   the real bootloader for your Module 9 kernel.

Done when: the loader launches your payload on QEMU and on the server, and the payload
prints the memory map it was handed.

### Lab 8.3: Secure Boot with your own keys

1. Generate PK, KEK and db key pairs (`openssl`), produce the EFI signature lists and
   authenticated variables (`efitools`: `cert-to-efi-sig-list`, `sign-efi-sig-list`).
2. In OVMF (the Secure Boot build with `OvmfPkgX64` secure variant), enter setup mode,
   enrol your PK, KEK and db. Sign your Lab 8.2 loader with `sbsign`. Boot it. Then boot the
   unsigned version and observe the refusal. Then sign it with a key not in db.
3. Repeat on the server: back up the vendor keys first, then take ownership (clear PK,
   enrol yours). Document the recovery path before you begin.
4. Boot a distribution kernel through shim and MOK on the server, and explain in your
   notebook which key verified which binary at each step.

Done when: your loader boots only when signed by your db key, on both OVMF and the server,
and you have a written recovery procedure that you have tested.

### Lab 8.4: Measured boot and remote attestation

1. QEMU with `swtpm` as a TPM 2.0 (`-chardev socket ... -tpmdev emulator -device tpm-tis`).
   Boot a Linux distribution image. Read PCRs with `tpm2_pcrread`. Dump the event log from
   `/sys/kernel/security/tpm0/binary_bios_measurements` and parse it with `tpm2_eventlog`.
2. Replay: write a Python script that reads the raw event log and recomputes PCRs 0 to 7
   from the digests by chaining SHA-256 extends. It must match `tpm2_pcrread` exactly.
   Change the kernel command line and boot again; show which PCR changed and which event
   explains it.
3. Sealing: `tpm2_createpolicy` over PCRs 0, 4 and 7, seal a secret, unseal it. Reboot with
   a different bootloader (your Lab 8.2 loader) and show unsealing fails. Then do the same
   on the server with its real TPM and seal a LUKS key with `systemd-cryptenroll
   --tpm2-pcrs=0+7`.
4. Attestation protocol: on the attester, create an EK (`tpm2_createek`) and AK
   (`tpm2_createak`), export the EK certificate from the TPM's NV (real TPMs ship one; for
   swtpm, generate a CA and issue one). Write a verifier service (any language) that:
   receives the EK cert and AK public key; verifies the EK cert chain to a manufacturer or
   your CA; runs credential activation (`tpm2_makecredential`/`tpm2_activatecredential`) to
   prove the AK lives in that TPM; sends a nonce; receives `tpm2_quote` output plus the
   event log; verifies the signature with the AK, the nonce, and the PCR digest; replays the
   log; compares to a stored reference set per firmware version; returns admit or refuse.
5. Run it against QEMU and against the server. Change the server's kernel command line and
   show refusal. Update the reference set and show admission.

Done when: your verifier admits a machine in a known state and refuses one that differs,
and your notebook diagrams the protocol with what each message proves.

### Lab 8.5: ARM boot chain and device tree

1. Build Trusted Firmware-A, U-Boot and a mainline kernel for QEMU's `virt` machine. Boot
   with a device tree you pass explicitly. Inspect the DTB with `dtc -I dtb -O dts`.
2. Build U-Boot for the Pi 5 (or Pi 4). Boot Linux through U-Boot instead of the stock
   path. In U-Boot's shell, inspect the environment, `fdt print`, `md` a peripheral
   register, load a kernel over TFTP with `dhcp` and `tftpboot`.
3. Write a device tree overlay for a GPIO LED and the BME280 on I2C. Apply it from U-Boot
   with `fdt apply`. Confirm the kernel finds the sensor (`/sys/bus/iio`).
4. Create a FIT image containing the kernel, DTB and initrd, signed with your key; enable
   verified boot in U-Boot and show it refuses an unsigned FIT.

Done when: the Pi boots through U-Boot with your overlay and a signed FIT, and refuses an
unsigned one.

### Lab 8.6: Zero-touch netboot

1. On the workstation or Pi as a provisioning server: `dnsmasq` for DHCP on the lab VLAN
   with TFTP, serving iPXE's UEFI binary (`ipxe.efi`) to UEFI clients (option 93 matching)
   and `undionly.kpxe` to BIOS clients. iPXE chainloads an HTTP script from a small web
   service you write.
2. The service returns a per-machine script keyed by MAC (later by attested identity): it
   fetches a live kernel and initrd over HTTP with a command line that names a config URL.
   Boot the server this way with no local disk involvement.
3. In the live environment, a first-boot agent fetches its configuration, partitions the
   disk, writes your OS image (a Debian or Buildroot image you built), installs your
   Lab 8.2 loader or systemd-boot, and enrols the TPM with your Lab 8.4 verifier (EK cert
   upload, AK creation). Reboot. The installed system attests on boot and the verifier
   records "joined".
4. Make the join conditional: the config service refuses to hand out the disk-encryption
   key until the verifier reports a passing quote.

Done when: a wiped server netboots, installs itself, attests, receives its secrets, and
appears as joined on your control plane with no keyboard involved.

### Lab 8.7: BMC and Redfish, then OpenBMC

1. Against the server's vendor BMC: `curl` the Redfish root, walk `Systems`, `Chassis`,
   `Managers`; read power state, thermal sensors, PSU readings; power the host off and on
   via an Action; open a serial-over-LAN session; read the event log. Write a small client
   that graphs inlet temperature and fan speed over time.
2. Compare IPMI: `ipmitool -I lanplus sensor list` and `sol activate`. Note what Redfish
   models that IPMI does not.
3. Build OpenBMC for a QEMU machine (`romulus` or `ast2600-evb`). Boot it in QEMU. Log in,
   explore D-Bus with `busctl tree`, hit `bmcweb`'s Redfish endpoints. Read how a sensor
   flows from `phosphor-hwmon` to D-Bus to Redfish.
4. Write a small phosphor-style D-Bus daemon (C++ with sdbusplus) that publishes a fake
   sensor and see it appear in Redfish. This is the shape of every OMH-specific BMC
   feature.
5. Read the OpenBMC firmware-update flow and trace how a host BIOS update would be
   delivered over Redfish `UpdateService`.

Done when: your Redfish client controls and monitors the server, OpenBMC boots in QEMU
with your sensor visible, and you can describe the update flow end to end.

## Problem set

1. Explain cache-as-RAM: what state the cache must be in, why evictions must be prevented,
   and what breaks if memory training fails.
2. PCR extend: show that changing the order of two measurements changes the final value,
   and that a verifier with the log can detect a missing event but a verifier with only
   the final PCR cannot say which.
3. An attacker controls the OS but not firmware. Which PCRs can they influence? Can they
   forge a quote for a clean state? Can they replay yesterday's quote? What in your protocol
   prevents each?
4. Compare a PCR-7-based sealing policy with a PCR-4-based one across a bootloader update
   and a Secure Boot key rotation. Which breaks when, and how would OMH's rolling update
   avoid re-provisioning secrets? Read about TPM policy authorisation (`PolicyAuthorize`)
   and signed reference measurements.
5. Draw the DHCP, TFTP and HTTP exchanges in a UEFI HTTP boot with iPXE chainloading,
   including which server answers each request and which fields identify the client.
6. What does Secure Boot protect against that measured boot does not, and the reverse?
   Why does a fleet need both plus a verifier?
7. U-Boot has its own device tree and the kernel gets another. Why two? What happens if
   they disagree about a UART's address?
8. Your verifier stores one reference PCR set per firmware version. A rolling update
   changes the firmware on one module. Design the reference-value management so the fleet
   admits both old and new during the rollout and refuses a third, unknown state.
9. A BMC has network access to the host's power, console and firmware. List the ways it
   can be attacked and what OpenBMC and the DC-SCM design do about each.

## Deliverables

- Boot sector and two-stage loader; UEFI loader; signed and unsigned boot demonstrations.
- Event-log replay script; verifier service with a documented protocol; a recorded admit
  and refuse.
- Netboot provisioning service and first-boot agent; the join demonstration log.
- Redfish client; OpenBMC build with your D-Bus sensor.

## Stretch

- Build coreboot for QEMU with a LinuxBoot payload and measure the payload into the TPM.
- Implement DICE-style key derivation in your Module 7 bootloader: derive a per-boot key
  from a device secret and the application image hash, and sign a "firmware attestation"
  the host can verify. Compare with the TPM flow.
- Explore SPDM by reading the spec and the `spdm-emu` project; describe how a host would
  attest an NVMe drive's firmware.

## Next

Part IV. Module 9 replaces the payload your UEFI loader launches with a real kernel of your
own: paging, SMP, user mode, syscalls, and an NVMe driver.
