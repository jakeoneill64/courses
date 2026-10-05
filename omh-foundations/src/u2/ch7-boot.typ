#import "../lib/template.typ": *

= Boot and platform firmware <ch-boot>

#chapter-meta(
  weeks: [3.5 weeks],
  builds: [A boot sector and a two-stage loader into long mode; a UEFI loader; Secure Boot with your own keys on QEMU and the server; measured boot with an event-log replay and a remote-attestation verifier that admits and refuses machines; an Arm boot chain with U-Boot, a device-tree overlay and signed FIT images; a zero-touch netboot that installs, attests and joins; a Redfish client and an OpenBMC build with your own sensor.],
  needs: [The lab server with its TPM and BMC, QEMU with OVMF and swtpm, the Raspberry Pi 5, the managed switch, a TMP117 breakout.],
)

#why[
  OMH's site promises that a module "powers on, attests its firmware to the control plane, finds its peers across the backplane and starts serving", with OpenBMC, Redfish and measured boot on the specification sheet. This chapter is that paragraph. By its end you will have netbooted a machine with no local configuration, measured its firmware and kernel into a TPM, verified a quote against a policy on another machine, refused an unsigned bootloader, driven a BMC over Redfish and built OpenBMC. Module Zero's join protocol in Chapter 4.7 is assembled from these labs.
]

#skip-test(
  rule: [If all five are easy, do Labs 2.7.4, 2.7.6 and 2.7.7.],
  [Why can x86 firmware not use RAM for its first few thousand instructions, and what does it use instead?],
  [Explain the difference between Secure Boot and measured boot, and give a failure each catches that the other cannot.],
  [PCR 4 holds a value after boot. Describe exactly how it was computed and what you need to reproduce it from the event log.],
  [A remote verifier receives a TPM quote. List what it must check before believing the PCR values, including how it knows the quote came from a real TPM.],
  [Draw the packet sequence for a PXE boot from power-on to the kernel's first instruction, naming the protocols and DHCP options.],
)

== Core ideas

*Power-on on x86.* The first fetch is at 0xFFFF_FFF0 in 16-bit real mode, from SPI flash mapped below 4 GiB. DRAM is not usable until the memory controller is trained. Firmware runs early code with the cache configured as RAM (no-evict mode), initialises memory through a vendor blob (Intel FSP or AMD's equivalent), relocates into DRAM and enumerates the platform: SMM, microcode, ACPI tables, PCIe enumeration and BAR assignment, and only then a search for something to boot.

*UEFI.* A specification for firmware structure and for the interface it offers bootloaders and operating systems. Its phases are SEC (security and cache-as-RAM), PEI (memory initialisation), DXE (driver execution, most of the work), BDS (boot device selection) and then the OS loader. Boot services (memory allocation, protocols, file access, `ExitBootServices`) exist until the OS takes over; runtime services (variables, time, capsule update, reset) persist. An EFI application is a PE/COFF binary on a FAT EFI System Partition; boot order lives in NVRAM variables. EDK2 is the reference implementation and OVMF its QEMU build.

#fig("/figures/u2-measured-boot.svg", caption: [The x86 boot phases and what each extends into the TPM. Every stage measures the next before running it, so the final PCR values commit to the exact sequence of code that ran.])

*coreboot and LinuxBoot.* coreboot does the minimum initialisation and hands off to a payload: a UEFI implementation, GRUB, or a Linux kernel acting as the bootloader (LinuxBoot). Hyperscalers use it because auditable firmware is the base of a measured chain; an OMH platform team would consider it seriously.

*Secure Boot.* A signature chain enforced by firmware. The Platform Key (PK) owns the Key Exchange Keys (KEK), which own the allowed database (db) and the forbidden database (dbx). Firmware runs only PE binaries signed by a db key and not listed in dbx. Distributions boot through Microsoft-signed shim, which verifies GRUB and the kernel against its own keys and the Machine Owner Key list. On your own hardware you enrol your own PK and sign everything. Secure Boot answers "was this allowed to run"; it says nothing about what actually ran.

*The TPM and measured boot.* A TPM is a small, slow, tamper-resistant chip whose keys never leave it and whose Platform Configuration Registers can only be extended: $"PCR"_"new" = "SHA256"("PCR"_"old" || "measurement")$. Firmware extends itself into PCR 0, its configuration into PCR 1, option ROMs into 2 and 3, the bootloader into 4, the partition table into 5, and Secure Boot state into 7; the bootloader or a unified kernel image extends the kernel, initrd and command line (PCRs 8, 9 or 11); IMA extends file hashes into PCR 10. Each extend is logged in the TCG event log. Because extend is a hash chain, the final values commit to the exact sequence, and a verifier replaying the log must arrive at the same values.

*Attestation.* The Endorsement Key (EK) is unique per TPM, with a manufacturer certificate proving the TPM is genuine. An Attestation Key (AK) is created in the endorsement hierarchy and proven to belong to the same TPM by credential activation. A quote is a TPM-signed statement of selected PCRs plus a verifier-supplied nonce. Sealing binds a secret to PCR values so it unseals only in the same boot state; this is how a disk key can be released only to your kernel. RFC 9334 names the parties: Attester, Verifier and Relying Party, exchanging evidence, endorsements, reference values and appraisal policy. OMH's control plane is the Verifier, the module the Attester and the quorum the Relying Party.

#fig("/figures/u2-attestation.svg", caption: [The attestation protocol Lab 2.7.4 builds. The nonce defeats replay; credential activation ties the AK to a genuine TPM; the event-log replay ties the PCRs to known software.])

*Measured boot in the small.* Microcontrollers and BMCs do the same with DICE (each stage derives a key from the previous stage's secret and the next stage's hash) and with hardware roots of trust such as OCP's Caliptra. SPDM lets a host attest its PCIe devices. Your Chapter 2.6 bootloader is the first link of such a chain.

*Arm and RISC-V boot chains.* On Arm, a boot ROM loads a first stage, which loads Trusted Firmware-A (BL2, then BL31 as the EL3 monitor, optionally a secure OS) and then U-Boot (BL33) at EL2, which loads a kernel and a device tree. The Pi is special: its GPU firmware does the early work. RISC-V runs a zero-stage loader, OpenSBI in M-mode providing the Supervisor Binary Interface, then U-Boot in S-mode. U-Boot is a small OS in its own right: drivers, filesystems, networking, scripting, its own device tree, and verified boot of signed FIT images.

*What the kernel expects.* On x86, the boot protocol in `Documentation/arch/x86/boot.rst`: a real-mode header, `boot_params`, the command line, an initrd and an entry point, or the EFI stub that lets the kernel run as an EFI application. On arm64, an image header and the DTB address in `x0`. On RISC-V, the hart ID in `a0` and the DTB in `a1`, with OpenSBI resident.

*Netboot and zero-touch.* The NIC's option ROM or the UEFI network stack does DHCP; the server replies with an address and a boot file (options 66 and 67, choosing by the client architecture in option 93); the client fetches it over TFTP (PXE) or HTTP (UEFI HTTP boot). iPXE, chain-loaded, scripts the rest: fetch a kernel and initrd over HTTP with per-machine URLs. A node with no local state then fetches its configuration from the control plane, which is the zero-touch join, and the control plane can require attestation before handing out anything sensitive.

#fig("/figures/u2-netboot.svg", caption: [UEFI netboot with iPXE chain-loading, from DHCP to a running installer. Lab 2.7.6 builds every server in this picture.])

*The BMC.* A separate SoC (an ASPEED AST2500 or AST2600 on nearly every server) with its own Ethernet, flash and Linux, powered whenever the chassis has standby power. It controls host power and reset, reads sensors over I#super[2]C and PMBus, drives fans, and provides a serial console over the network, virtual KVM and media, and firmware update for itself and the host. Host and BMC talk over LPC or eSPI, I#super[2]C, and MCTP with PLDM. IPMI is the legacy protocol; Redfish is its RESTful, schema-driven replacement. OpenBMC is the Linux Foundation's BMC distribution: phosphor daemons on D-Bus, `bmcweb` serving Redfish, entity-manager and hwmon for sensors, and a firmware-update flow. OCP's DC-SCM specification puts the BMC on a replaceable card, which a rack-module company should read before designing anything.

*Firmware storage and update.* SPI NOR flash, often two chips for A/B, write-protected under BMC or strap control. UEFI capsules and Redfish `UpdateService` are the sanctioned paths. A rolling fleet update that drains and rejoins one module at a time is orchestration on top of these plus re-attestation after reboot.

== Reading

- Zimmer, Rothman and Marisetty, _Beyond BIOS_, 3rd ed., chapters 1 to 4, 7 and 9.
- UEFI specification: chapter 2 (overview), boot and runtime services (skim), and the Secure Boot chapter.
- Arthur and Challener, _A Practical Guide to TPM 2.0_ (free from Apress): chapters 1 to 3, 9 to 12 and 21.
- TCG PC Client Platform Firmware Profile, sections 2, 3 and 7; RFC 9334 in full.
- Linux `Documentation/arch/x86/boot.rst`, `arm64/booting.rst` and `riscv/boot.rst`; coreboot's getting-started and payloads pages; the LinuxBoot book.
- OpenBMC architecture, `bmcweb` and code-update documents; DMTF Redfish specification DSP0266 chapters 1 to 7 and the Redfish mockup server; OCP DC-SCM 2.0 (skim); iPXE scripting and chain-loading.

== Labs

#lab([A boot sector, then a two-stage loader], time: [1 weekend])[
+ Write a 512-byte MBR boot sector that prints a string through BIOS interrupt 10h and then through the 16550 at 0x3F8 directly. Boot it in QEMU with `-drive format=raw` and explain every byte, including the signature at offset 510.
+ Stage two loads more sectors with BIOS 13h, collects the BIOS memory map with interrupt 15h function E820h, enables A20, sets up a GDT, enters protected mode, builds identity-mapped page tables and enters long mode, then loads an ELF64 from a known LBA, copies its segments and jumps, passing the memory map to the payload. Your Lab 2.5.3 program is the payload; your Chapter 4.1 kernel will be.
+ Use QEMU's `-d int,cpu_reset` and the monitor's `info registers` when it triple-faults.

#done-when(
  [Your Lab 2.5.3 program runs from your own boot sector in QEMU, and the notebook has an annotated hex dump of the sector.],
)
] <lab-bootsector>

#lab([A UEFI loader], time: [1 weekend])[
+ With gnu-efi (or EDK2), write an EFI application that prints the firmware vendor and revision, dumps the memory map with types, and finds the ACPI RSDP in the configuration table.
+ Load your ELF64 payload from the ESP through the Simple File System protocol, allocate pages and copy its segments.
+ Get the framebuffer through GOP and build a boot-information structure (memory map, framebuffer, RSDP, command line). Call `ExitBootServices`, handling the retry when the map changes, then set up your own page tables and jump to the payload.
+ Run it under OVMF in QEMU, then on the server from a USB stick. This loader boots your Chapter 4.1 kernel.

#done-when(
  [The loader launches your payload on QEMU and on the server, and the payload prints the memory map it was handed.],
)
] <lab-uefi-loader>

#lab([Secure Boot with your own keys], time: [1 weekend])[
+ Generate PK, KEK and db key pairs with `openssl`, and produce EFI signature lists and authenticated variables with `efitools`.
+ In OVMF's Secure Boot build, enter setup mode and enrol your keys. Sign your Lab 2.7.2 loader with `sbsign` and boot it; then boot the unsigned version and see it refused; then sign with a key not in db.
+ Repeat on the server: back up the vendor keys first, write and test the recovery procedure, then take ownership.
+ Boot a distribution kernel through shim and MOK on the server and record which key verified which binary at each step.

#done-when(
  [Your loader boots only when signed by your db key, on OVMF and on the server, and your recovery procedure has been tested.],
)
] <lab-secure-boot>

#lab([Measured boot and remote attestation], time: [2 weekends])[
+ Run QEMU with `swtpm` as a TPM 2.0 and boot a distribution. Read PCRs with `tpm2_pcrread` and parse the event log from `/sys/kernel/security/tpm0/binary_bios_measurements` with `tpm2_eventlog`.
+ Write a Python script that replays the raw event log and recomputes PCRs 0 to 7. It must match `tpm2_pcrread`. Change the kernel command line, reboot, and show which PCR changed and which event explains it.
+ Seal a secret to PCRs 0, 4 and 7 and unseal it; boot your Lab 2.7.2 loader instead and show unsealing fails. On the server, seal a LUKS key with `systemd-cryptenroll --tpm2-pcrs=0+7`.
+ Build a verifier service that receives the EK certificate and AK public key, verifies the EK chain (a manufacturer CA, or your own for swtpm), runs credential activation to prove the AK lives in that TPM, sends a nonce, receives a quote and event log, checks the signature, nonce and PCR digest, replays the log against stored reference values per firmware version, and returns admit or refuse.
+ Run it against QEMU and the server. Change the server's command line and show refusal; update the reference values and show admission.

#done-when(
  [The verifier admits a machine in a known state and refuses one that differs, and the notebook diagrams what each protocol message proves.],
)
] <lab-attestation>

#lab([Arm boot chain and a device-tree overlay], time: [1 weekend], kit: [Raspberry Pi 5, TMP117 breakout.])[
+ Build Trusted Firmware-A, U-Boot and a mainline kernel for QEMU's `virt` machine and boot with an explicit device tree. Inspect it with `dtc -I dtb -O dts`.
+ Build U-Boot for the Pi and boot Linux through it. In U-Boot's shell inspect the environment, `fdt print`, read a peripheral register with `md`, and load a kernel with `dhcp` and `tftpboot`.
+ Write an overlay for a GPIO LED and the TMP117 on I#super[2]C (`compatible = "ti,tmp117"`), apply it from U-Boot with `fdt apply`, and confirm the kernel's driver finds the sensor under `/sys/bus/iio`.
+ Make a FIT image of kernel, DTB and initrd signed with your key; enable verified boot in U-Boot and show it refuses an unsigned FIT.

#done-when(
  [The Pi boots through U-Boot with your overlay and a signed FIT, the TMP117 appears in IIO, and an unsigned FIT is refused.],
)
] <lab-arm-boot>

#lab([Zero-touch netboot], time: [2 weekends], kit: [Managed switch with a lab VLAN, the server, the Pi or workstation as provisioning server.])[
+ Run `dnsmasq` for DHCP and TFTP on the lab VLAN, serving `ipxe.efi` to UEFI clients (matched on option 93), with iPXE chain-loading a script from a small web service you write.
+ The service returns a per-machine script keyed by MAC address (later by attested identity) that fetches a kernel and initrd over HTTP with a command line naming a configuration URL. Boot the server this way with no local disk involved.
+ In that live environment, a first-boot agent fetches its configuration, partitions the disk, writes your OS image, installs your loader or systemd-boot, and enrols the TPM with your Lab 2.7.4 verifier. On reboot the installed system attests and the verifier records "joined".
+ Make the join conditional: the configuration service releases the disk-encryption key only after a passing quote.

#done-when(
  [A wiped server netboots, installs itself, attests, receives its secrets and appears as joined, with no keyboard involved.],
)
] <lab-netboot>

#lab([BMC and Redfish, then OpenBMC], time: [2 weekends])[
+ Against the server's BMC, walk the Redfish tree (`Systems`, `Chassis`, `Managers`) with `curl`; read power state, thermal sensors and PSU readings; power-cycle the host through an Action; open a serial-over-LAN session; read the event log. Write a small client that graphs inlet temperature and fan speed over time.
+ Compare with `ipmitool -I lanplus sensor list` and `sol activate`, and note what Redfish models that IPMI does not.
+ Build OpenBMC for a QEMU machine (`romulus` or `ast2600-evb`), boot it, explore D-Bus with `busctl tree` and hit `bmcweb`'s Redfish endpoints. Trace how a sensor flows from hwmon to D-Bus to Redfish.
+ Write a small phosphor-style D-Bus daemon in C++ with sdbusplus that publishes a sensor, and see it in Redfish.
+ Trace how a host BIOS update would be delivered through Redfish `UpdateService`.

#done-when(
  [Your client controls and monitors the server, OpenBMC boots in QEMU with your sensor visible in Redfish, and you can describe the update flow end to end.],
)
] <lab-redfish>

== Problem set

+ Explain cache-as-RAM: what state the cache must be in, why evictions must be prevented, and what breaks if memory training fails.
+ Show that swapping two measurements changes the final PCR, and that a verifier with the log can detect a missing event but one with only the final PCR cannot say which.
+ An attacker controls the OS but not the firmware. Which PCRs can they influence? Can they forge a quote for a clean state, or replay yesterday's? What in your protocol prevents each?
+ Compare a PCR 7 sealing policy with a PCR 4 one across a bootloader update and a Secure Boot key rotation. How would OMH's rolling update avoid re-provisioning secrets? Read about `PolicyAuthorize`.
+ Draw the DHCP, TFTP and HTTP exchanges in UEFI HTTP boot with iPXE chain-loading, including which server answers each and which fields identify the client.
+ What does Secure Boot protect against that measured boot does not, and the reverse? Why does a fleet need both and a verifier?
+ U-Boot has its own device tree and the kernel gets another. Why two, and what happens if they disagree about a UART's address?
+ A rolling update changes one module's firmware. Design reference-value management that admits both old and new during the rollout and refuses an unknown third state.
+ A BMC reaches the host's power, console and firmware over the network. List the ways it can be attacked and what OpenBMC and DC-SCM do about each.

== Deliverables and stretch

*Deliverables.* Boot sector and two-stage loader; UEFI loader; signed and unsigned boot demonstrations; the event-log replay script; the verifier with its documented protocol and a recorded admit and refuse; the netboot service and first-boot agent with the join log; the Redfish client and the OpenBMC build with your sensor.

*Stretch.* Build coreboot for QEMU with a LinuxBoot payload measured into the TPM. Add DICE-style key derivation to your Chapter 2.6 bootloader and sign a firmware attestation the host can verify. Read SPDM and the `spdm-emu` project and describe how a host would attest an NVMe drive's firmware.

#checklist(
  [*Lab 2.7.1:* the payload runs from your boot sector; the sector annotated byte by byte.],
  [*Lab 2.7.2:* the UEFI loader launches the payload on QEMU and the server.],
  [*Lab 2.7.3:* signed-only boot with your keys on both, and a tested recovery procedure.],
  [*Lab 2.7.4:* event-log replay matching the TPM; sealing demonstrated; the verifier admitting and refusing.],
  [*Lab 2.7.5:* the Pi through U-Boot with your overlay; TMP117 in IIO; unsigned FIT refused.],
  [*Lab 2.7.6:* a wiped server netboots, installs, attests and joins, hands-off.],
  [*Lab 2.7.7:* Redfish client; OpenBMC with your D-Bus sensor.],
  [*Problem set:* all nine answered.],
  [*You can explain*, without notes: the UEFI phases, how a PCR is extended and replayed, what each attestation message proves, and what a BMC can do to a host.],
)
