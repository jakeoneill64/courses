#import "../lib/template.typ": *

= Virtualisation and hypervisors <ch-virt>

#chapter-meta(
  weeks: [5 weeks],
  builds: [A KVM VMM that boots Linux with your own 16550, virtio-blk and virtio-net, two vCPUs, a passed-through 82599 virtual function and live migration; your Chapter 4.1 kernel as its guest; a bare-metal VT-x hypervisor running Linux; Compute's VMM API; a hardened multi-tenant host; an Arm port.],
  needs: [The lab server with VT-x, VT-d and SR-IOV enabled in its firmware, the X520-DA2 with its DAC and the P4510; QEMU, Firecracker and Cloud Hypervisor; the Raspberry Pi 5; your Chapter 4.1 kernel, your Lab 2.7.2 loader and your VFIO program from Lab 4.3.8.],
)

#why[
  Compute is a hypervisor with a billing model. Every tenant instance OMH sells runs on a virtual machine monitor that must isolate tenants from each other and from the host, give them fast storage and networking, move them between modules during rolling updates, and never let a guest near the keys Modulus holds. A founder who cannot read a VM-exit reason, or say why a guest's disk write is slow, cannot specify the product or price it. This chapter builds the stack twice: on KVM, the way you will ship it, and on bare metal with VT-x, so that nothing KVM does is magic.
]

#skip-test(
  rule: [If all five are easy, do Labs 4.4.2, 4.4.4 and 4.4.6 only.],
  [A guest executes `cpuid`. List, in order, every hardware and software step from that instruction to the guest receiving a result, on Intel with KVM.],
  [Name the two levels of translation under EPT and who owns each. What does a guest page fault that the guest kernel handles look like to the hypervisor?],
  [Why does a virtio driver need a memory barrier between writing a descriptor and writing the available index, and what does the packed ring layout change?],
  [A passed-through NIC DMAs to guest physical address 0x1000. Name every table consulted before a byte moves, and what keeps the DMA out of another tenant's memory.],
  [In live migration, what is dirty-page tracking, what happens in the final stop-and-copy phase, and why does a passed-through device make migration hard?],
)

== Core ideas

*Trap and emulate, and why it needed hardware.* Popek and Goldberg showed in 1974 that a machine is virtualisable if every sensitive instruction traps when run with reduced privilege. Classic x86 was not: `popf` and `sgdt`, among others, behaved differently in ring 3 without trapping. VMware translated binaries around the gap and Xen modified the guest (paravirtualisation) until Intel's VT-x (2005) and AMD's SVM (2006) added a mode above ring 0 and a hardware structure, the VMCS on Intel and the VMCB on AMD, that says which guest actions cause a VM exit. A hypervisor is then a loop: enter the guest with `vmlaunch` or `vmresume`, run until an exit, read the exit reason, emulate or fix up, and enter again.

*VMX in detail.* `vmxon` enters VMX root operation. The VMCS holds guest state (loaded on entry), host state (loaded on exit), execution controls (which events exit: CPUID, HLT, port I/O, MSR access, control-register writes, external interrupts, EPT violations), exit information (reason, qualification, guest linear and physical address) and entry controls such as event injection. Software touches it only through `vmread` and `vmwrite` by field encoding. CPUID, INVD and `vmcall` always exit; everything else is a control bit, constrained by the allowed-0 and allowed-1 settings in the `IA32_VMX_*` capability MSRs. A wrong field produces "VM-entry failure due to invalid guest state" and nothing more, so the SDM's list of checks on guest state is your debugger.

*Memory: EPT.* Without hardware help a hypervisor shadows the guest's page tables and traps every change to them. Extended Page Tables (Intel) and nested page tables (AMD) add a second translation: guest virtual to guest physical by the guest's tables, then guest physical to host physical by the hypervisor's. A TLB miss becomes a two-dimensional walk of up to 24 memory reads, which is why huge pages matter more under virtualisation. An EPT violation is the hypervisor's page fault, and lazy allocation, MMIO emulation, dirty tracking and ballooning all live in its handler. VPIDs tag TLB entries per guest so that switching need not flush them, and `invept` drops cached EPT translations.

#fig("/figures/u4-virt-2d-walk.svg", caption: [The two-dimensional walk. Every guest page-table pointer is a guest physical address the EPT must translate first, so four guest levels over four EPT levels cost 24 reads.])

*Interrupts and timers.* A guest expects a local APIC, an I/O APIC, a PIT, and an HPET or TSC-deadline timer. Emulating the APIC in software costs an exit per end-of-interrupt write; APICv and posted interrupts deliver interrupts into a running guest in hardware. Injection on entry, interrupt windows while the guest has interrupts masked, and the bookkeeping of pending interrupts are where hypervisor bugs cluster. Guest timers are host timers that inject on expiry, and the TSC is offset per guest and may be scaled.

*Devices: emulated, paravirtual, passed through.* Emulating a real device such as an e1000 is slow because its driver touches many registers per operation and each access exits. virtio devices are designed to be emulated: descriptor tables in guest memory, an available ring the driver writes, a used ring the device writes, a notification each way and feature negotiation, over PCI or MMIO. vhost moves the data path into a kernel thread, vhost-user into another process (DPDK, SPDK), and vDPA into hardware behind a vendor control path. Passthrough hands a real device to the guest through VFIO: the IOMMU translates its DMA with the same guest-physical-to-host map as the EPT, and interrupt remapping stops it signalling an arbitrary vector. SR-IOV makes passthrough scale: each port of the X520’s 82599 can present virtual functions, each its own PCI function with MSI-X vectors and usually its own IOMMU group, while the PF driver keeps the MAC and VLAN filters and anti-spoofing.

*KVM.* Linux as the hypervisor. `KVM_CREATE_VM` on `/dev/kvm` returns a VM descriptor and `KVM_CREATE_VCPU` one per vCPU; `KVM_SET_USER_MEMORY_REGION` maps host memory into guest physical space; `KVM_RUN` runs a vCPU until an exit KVM cannot handle itself, reported in the shared `kvm_run` structure as port I/O, MMIO, halt, shutdown or an internal error. The in-kernel interrupt controller, `KVM_IRQFD` and `KVM_IOEVENTFD` let devices signal and be signalled without a round trip to userspace. The VMM (QEMU, Firecracker, Cloud Hypervisor, crosvm, kvmtool) owns the descriptors, emulates devices and handles what KVM hands back. On Arm, KVM runs at EL2 with stage-2 translation and nearly the same ioctls, which is why Firecracker runs on both.

#fig("/figures/u4-virt-virtqueue.svg", caption: [A virtio-blk read on a split virtqueue. The barriers stop either side seeing an index before the data it covers.])

#fig("/figures/u4-virt-exit.svg", caption: [Where an exit is handled decides its cost: CPUID never leaves the kernel, port I/O round-trips through your VMM, and an ioeventfd doorbell wakes a device thread while the vCPU carries on.])

*Boot inside a VM.* A VMM decides how much firmware the guest gets: none, by loading a bzImage through the Linux boot protocol, filling `boot_params` with an E820 map and a command line, and starting the vCPU at the 32-bit entry point; a minimal firmware such as qboot; or full UEFI with OVMF. Direct boot lets a microVM boot in about 125 ms, which a functions service needs. Get the 16550 serial port at 0x3F8 working first, because until it works the guest is a black box.

*Isolation and security.* The hypervisor is the trust boundary between tenants. Its attack surface is device emulation, where most historical VM escapes were found, the instruction emulator, shared memory, and side channels such as Spectre, L1TF and MDS that leak between threads on one core. The defences are small device models, seccomp and namespaces around each VMM process, core scheduling so that sibling hyperthreads never run different tenants, and buffer and cache flushes on the transitions where the CPU needs them. Memory encryption (AMD SEV-SNP, Intel TDX, Arm CCA) removes the hypervisor from the guest's trust base; the lab server's Xeon supports none of these, so study what each protects on paper.

*Live migration and snapshots.* Pre-copy marks all guest memory dirty and copies it while the guest runs, then repeatedly copies the pages dirtied since the last pass, tracked through write-protected EPT entries, the CPU's page-modification log or KVM's dirty ring. When the remainder is small it pauses the guest, sends the rest with the vCPU and device state, and resumes on the destination. A guest that dirties memory faster than the link drains it never converges, so the hypervisor throttles it or switches to post-copy, which runs the guest on the destination and fetches pages on demand. A snapshot is a migration to a file, which is how Firecracker restores a microVM faster than it boots one. A passed-through device breaks migration unless it can save its state through VFIO's migration interface, so Compute must choose between passthrough speed and migratable instances, or sell both.

#fig("/figures/u4-virt-precopy.svg", caption: [Pre-copy for an 8 GiB guest on a 10 Gb/s link, in a model where each round's dirty pages saturate a working set. A hot guest stalls above the downtime budget until it is throttled.])

*Nested virtualisation and the management plane.* KVM can run KVM: the L1 hypervisor's VMX instructions trap to L0, which emulates them with shadow VMCSs and EPT on EPT. It is slow and invaluable for developing a hypervisor. Above the VMM sits the management plane, libvirt in general or a purpose-built agent with an API like Firecracker's. Compute's control plane will talk to a VMM API on each module, and this chapter decides its shape: create, configure devices, boot, pause, snapshot, migrate, destroy and report metrics.

*Arm virtualisation.* EL2 with stage-2 translation, the GIC's virtual CPU interface, the generic timer's virtual counter, and VHE, which lets the host kernel run at EL2. The Pi 5 adds two practical details. Its default kernel uses 16 KiB pages, so guest memory regions must be 16 KiB aligned. Its GIC-400 is a GICv2 whose 8 KiB virtual CPU interface is not aligned to a 16 KiB page, so KVM traps guest accesses to it instead of mapping them. The exit vocabulary differs (HVC calls, data aborts for MMIO, WFI) while the VMM code barely changes.

== Reading

- Bugnion, Nieh and Tsafrir, _Hardware and Software Support for Virtualization_ (Morgan & Claypool, 2017): all of it; it is short and the best single text on the subject.
- Intel SDM volume 3: the VMX chapters from "Introduction to Virtual Machine Extensions" to "VMX Instruction Reference" (VMCS, VM entries and exits, EPT, APIC virtualisation), read closely before Lab 4.4.4, with the appendix of basic exit reasons as a desk reference. The VT-d specification's chapters on DMA remapping and interrupt remapping.
- The virtio 1.3 specification: chapter 2 (basic facilities), 4.1 (PCI transport), 5.1 (network device) and 5.2 (block device). Draw the split ring on paper before Lab 4.4.2.
- Linux `Documentation/virt/kvm/api.rst` for the ioctls in Lab 4.4.1; `Documentation/arch/x86/boot.rst` and `zero-page.rst` for direct boot; `Documentation/arch/arm64/booting.rst` for Lab 4.4.7.
- kvmtool, small enough to read entirely; Firecracker's `src/vmm`; Cloud Hypervisor's `vmm/src/cpu.rs`; QEMU's `accel/kvm/kvm-all.c` and `hw/virtio/virtio.c`.
- Agache et al., "Firecracker: Lightweight Virtualization for Serverless Applications" (NSDI 2020); Clark et al., "Live Migration of Virtual Machines" (NSDI 2005); Popek and Goldberg, "Formal Requirements for Virtualizable Third Generation Architectures" (CACM, 1974).

== Labs

Write the VMM in C or C++ with nothing beyond libc and the kernel's headers. It is the one you extend for the rest of the course: Chapter 4.5 adds a vhost-user disk to it.

#lab([Hello from a guest, through /dev/kvm], time: [1 weekend], kit: [The lab server.])[
+ Open `/dev/kvm`, check that `KVM_GET_API_VERSION` returns 12, create a VM, `mmap` 64 MiB and register it at guest physical address 0 with `KVM_SET_USER_MEMORY_REGION`. Create a vCPU and `mmap` its `kvm_run`, sized by `KVM_GET_VCPU_MMAP_SIZE`. Note which of `ept`, `vpid`, `enable_apicv`, `pml` and `nested` are set in `/sys/module/kvm_intel/parameters/`.
+ Run a 16-bit real-mode guest of a few bytes that `out`s a string to port 0x3F8 and halts. Set registers with `KVM_SET_REGS` and `KVM_SET_SREGS`, loop on `KVM_RUN`, print on `KVM_EXIT_IO` and stop on `KVM_EXIT_HLT`.
+ Run a 64-bit guest: build page tables and a GDT in guest memory, set CR0, CR3, CR4, EFER and the segment registers for long mode, and run a flat binary compiled from C that writes to the serial port and reads an MMIO address you do not back with memory. Handle `KVM_EXIT_MMIO`.
+ Create the in-kernel irqchip (`KVM_CREATE_IRQCHIP`) and PIT (`KVM_CREATE_PIT2`), and inject an interrupt from a host timer thread with `KVM_IRQ_LINE`. The guest installs an IDT and counts ticks.
+ Run `perf kvm stat` while the guest runs, report exits per second by reason, and measure the cost of one round trip through `KVM_RUN` in nanoseconds.

#done-when(
  [A 64-bit guest you built from nothing runs, takes MMIO exits and receives injected interrupts.],
  [The notebook has an exit-cost table by reason.],
)
#evidence([The program; the exit statistics and round-trip timing.])
] <lab-virt-hello>

#lab([Boot Linux with your own virtio-blk and virtio-net], time: [2 weekends])[
+ Direct boot: load a bzImage as `boot.rst` describes, fill `boot_params` (the E820 map from `zero-page.rst`, command line, initrd, `loadflags`) and start the vCPU in protected mode at the 32-bit entry. Emulate a 16550 at 0x3F8 well enough for `earlyprintk` and then the 8250 driver: THR, RBR, IER, IIR and LSR, with an interrupt on receive. Boot a minimal kernel and a Buildroot initramfs to a shell.
+ virtio-blk over PCI: emulate configuration space through ports 0xCF8 and 0xCFC with one device carrying the virtio vendor ID and the block device ID, its common, notify, ISR and device capabilities in a BAR served from MMIO exits, feature negotiation, the split virtqueue with the barriers the specification requires, and MSI-X or INTx on completion. Back it with a file and boot with `root=/dev/vda`.
+ virtio-net on a `tap` device, with a TX and an RX queue and the virtio-net header. Give the guest an address, `ping` the host and run `iperf3`.
+ Move notifications off the vCPU thread with `KVM_IOEVENTFD` for doorbells, `KVM_IRQFD` for completions and a thread per virtqueue, and measure the change in exits and throughput.
+ Add a second vCPU: describe it in an MP table or ACPI MADT, run it on its own thread, and let the in-kernel irqchip carry IPIs. Confirm that `nproc` prints 2 and that a parallel build keeps both busy.

#done-when(
  [Linux boots from your virtio-blk to a shell on your serial port, runs `ping` and `iperf3` over your virtio-net, and keeps both vCPUs busy.],
  [The time from the first `KVM_RUN` to the shell prompt is recorded.],
)
#evidence([The boot log with timing; the measurements before and after ioeventfd and irqfd.])
] <lab-virt-vmm>

#lab([Your kernel as a guest, then a passed-through virtual function], time: [2 weekends], kit: [The server with SR-IOV enabled, the X520’s ports joined by the DAC.])[
+ Boot your Chapter 4.1 kernel in your VMM: load its ELF and build the boot-information structure as your Lab 2.7.2 loader does. Fix what breaks, recording whether each fault was the kernel's or the VMM's. Its NVMe driver will find no controller, so give it a virtio-blk driver or emulate enough of an NVMe controller (admin queue, one I/O queue) for it to run; the second teaches you what QEMU's `hw/nvme` does and is worth the week.
+ Create four virtual functions on port 0, still on `ixgbe`, by writing 4 to its `device/sriov_numvfs` in sysfs. Set VF 0’s MAC address and VLAN from the host with `ip link set <port> vf 0`, and bind VF 0 to `vfio-pci`.
+ Pass it through with your Lab 4.3.8 VFIO code: present its configuration space on your PCI bus with the values VFIO reports; map the regions VFIO marks mmap-capable into guest physical space, and forward the rest, including the MSI-X table, from MMIO exits with `pread` and `pwrite`; map all guest RAM for DMA with guest physical addresses as IOVAs; and route each MSI-X vector's eventfd into `KVM_IRQFD` through GSI routing.
+ Boot Linux in your VMM, let `ixgbevf` bind in the guest, and run `iperf3 -P 4` through the VF to port 1 in a host network namespace, then through your virtio-net.
+ Kill the VMM under load and confirm the VF recovers, since VFIO resets it on release. Then leave part of guest RAM out of the IOMMU mapping and show that the host logs a DMA fault where memory would otherwise have been corrupted.

#done-when(
  [Your Chapter 4.1 kernel runs as a guest of your VMM.],
  [A Linux guest drives the VF through the IOMMU at over 9 Gb/s, and the deliberate DMA fault is caught.],
)
#evidence([The passthrough code; the throughput table against virtio-net; the fault log.])
] <lab-virt-passthrough>

#lab([A bare-metal VT-x hypervisor], time: [3 weekends])[
Your Chapter 4.1 kernel becomes a hypervisor. Develop it under QEMU with `-enable-kvm -cpu host`, which offers nested VMX, then move to the server.
+ Check CPUID and `IA32_FEATURE_CONTROL`, set CR4.VMXE, allocate the VMXON region and a VMCS with the revision ID, and run `vmxon`, `vmclear` and `vmptrld`. Derive every control field from the `IA32_VMX_*` capability MSRs, which say which bits must be 0 and which must be 1.
+ Fill the VMCS for a guest running a flat 64-bit binary in memory you allocate: guest state; host state (your kernel's segments, CR3, a host stack, the RIP of your exit handler); execution controls with CPUID, HLT, port I/O and MSR exits; and EPT with four-level tables you build. When `vmlaunch` fails, `vmread` the VM-instruction error field and find the check you broke in the SDM.
+ In the exit handler, save the guest's registers and switch on the exit reason: run CPUID on the host and hide the VMX bit; send port I/O to 0x3F8 to your console; idle on HLT; on an EPT violation allocate a frame or emulate an MMIO device you define; on anything else dump the VMCS and stop.
+ Run Linux as the guest with Lab 4.4.2’s direct boot, a 16550 and virtio-blk over the MMIO transport, which is simpler than PCI for a first pass. Emulate the local APIC timer or use the VMX preemption timer so the guest schedules, and reach a shell.
+ Time-slice two guests, each with its own EPT and serial console, and show that a guest overwriting all of its physical memory does not disturb the other.
+ Count exits per reason, print them on your console, and compare them with KVM's from Lab 4.4.1.

#done-when(
  [Linux boots to a shell on your hypervisor on the server.],
  [Two guests run concurrently and cannot see each other's memory, and the exit statistics are written up beside KVM's.],
)
#evidence([The hypervisor; the VMCS setup documented field by field; the exit statistics.])
] <lab-virt-vtx>

#lab([Firecracker, Cloud Hypervisor and a VMM API for Compute], time: [1 weekend])[
+ Run Firecracker with a kernel and root file system and drive its API with `curl` over its Unix socket: `PUT /boot-source`, `/drives/rootfs`, `/network-interfaces/eth0` and `/machine-config`, then `PUT /actions` with `InstanceStart`. Time boot to shell. Pause it with `PATCH /vm`, create a snapshot, restore it in a new process with `PUT /snapshot/load`, and time the restore.
+ Read the device manager and virtio block device in Firecracker's `src/vmm` beside your own, and list what it does that you did not, and why: rate limiters, seccomp filters, the jailer, MMDS and the balloon.
+ Run the same guest under Cloud Hypervisor and compare its device model (PCI, hot-plug, virtio-fs, vDPA) and boot time.
+ Write Compute's VMM API as an OpenAPI document: instance lifecycle, device attach and detach, snapshot, migration, metrics and how the control plane authenticates. Write one page choosing the base for Compute's first release (Firecracker, Cloud Hypervisor, QEMU or your own VMM), and implement a subset of your API on your Lab 4.4.2 VMM as an HTTP service on a Unix socket.

#done-when(
  [You can start, snapshot and restore a microVM through your own API.],
  [The OpenAPI document and the architecture decision are written.],
)
#evidence([Boot and restore timings for both VMMs; the API document; the decision page.])
] <lab-virt-api>

#lab([Live migration and the multi-tenant node], time: [2 weekends])[
+ Track dirty pages with `KVM_MEM_LOG_DIRTY_PAGES` and `KVM_GET_DIRTY_LOG`, or KVM's dirty ring, and implement pre-copy migration to a second VMM process over TCP: iterate until the dirty set falls below a threshold, pause, send the vCPU state (`KVM_GET_REGS`, `SREGS`, `FPU`, `MSRS`, `LAPIC` and whatever else your guest needs) and your virtqueue indices (the disk file is shared), and resume on the destination. Migrate a guest running `iperf3` and a guest writing a counter to disk, measure the downtime and check that nothing was lost.
+ Harden the host: run each VMM in its own cgroup with `memory.max` and `cpu.max`, under a seccomp filter allowing only the system calls you traced it making, as an unprivileged user, in its own network namespace. Enable core scheduling, and pin vCPU threads to the isolated cores you configured in Chapter 4.2.
+ Measure interference: one tenant runs a memory-bandwidth hog while another runs a latency-sensitive loop. Report the latency distribution with and without pinning, and with the two tenants on sibling hyperthreads.
+ Read `/sys/devices/system/cpu/vulnerabilities/` on the server, explain each entry and what its mitigation costs, and set Compute's SMT policy for each instance tier.
+ Pass the host's attestation result from Lab 2.7.4 into a guest over virtio-vsock or an MMDS-style metadata service, so that a tenant can check it runs on an attested OMH module. Sketch how a per-guest vTPM (`swtpm` behind an emulated TIS or CRB device) would extend the chain.

#done-when(
  [A running guest migrates with under 100 ms of downtime and its disk intact.],
  [The multi-tenant policy is written and the interference is measured.],
)
#evidence([Migration logs with downtime; the seccomp filter and cgroup settings; the interference plots; the policy page.])
] <lab-virt-migrate>

#lab([Arm, for comparison], time: [1 weekend], kit: [Raspberry Pi 5.])[
+ Port your Lab 4.4.2 VMM: `KVM_ARM_PREFERRED_TARGET` and `KVM_ARM_VCPU_INIT`, a GICv2 created with `KVM_CREATE_DEVICE` (the BCM2712’s GIC-400 is a GICv2), the generic timer, a PL011 UART emulated on MMIO exits, virtio over MMIO, and an arm64 `Image` booted as `booting.rst` describes, with a device tree you generate with libfdt. Align guest memory to the host's page size.
+ On a 16 KiB-page kernel, read KVM's lines in `dmesg`, explain its warning about the GICv2 virtual CPU interface from the GIC-400’s register layout, and count the exits that result.
+ Boot Linux and compare exit reasons and rates with your x86 VMM on the same workload.
+ Write one page on what a Compute module built on Arm server silicon (Ampere, or a Grace-class part) would change in your VMM and in the product.

#done-when(
  [Linux boots in your VMM on the Pi, and the exit comparison and the page are written.],
)
#evidence([The port; the exit comparison table.])
] <lab-virt-arm>

== Problem set

+ Give three x86 instructions that Popek and Goldberg would call sensitive but that did not trap in ring 3 before VT-x, and say what each leaks or breaks.
+ A guest kernel handles a page fault with no VM exit. Explain how that is possible under EPT, and name a guest page fault that does cause an exit. Count the reads in a worst-case two-dimensional walk with four-level guest tables and four-level EPT; how do 2 MiB EPT pages change it, and how do VPIDs change how often you pay it?
+ Your virtio-blk device finds a descriptor pointing outside guest memory. What must it do, and what happens if it dereferences the address anyway?
+ Explain why an MSI from a passed-through device must be remapped by the IOMMU, and describe the attack a malicious guest could mount without remapping.
+ Firecracker boots in about 125 ms and QEMU with OVMF in a few seconds. Attribute the difference across firmware, device enumeration, kernel decompression and init.
+ An 8 GiB guest dirties 0.5 GiB/s over a 2 GiB working set and the link carries 1.1 GiB/s. With the figure's model, how many pre-copy rounds bring the remainder under 100 ms of transfer, and how long does the migration take? For a guest backed by 2 MiB pages, what granularity do you track, what does it cost in the final stop-and-copy, and when would you split pages?
+ Two tenants' vCPUs share a core's hyperthreads. Name two concrete side channels, the mitigation for each, and its cost in Compute's capacity model.
+ Your bare-metal hypervisor must handle a guest `wrmsr` to `IA32_EFER`. What should it allow, refuse and virtualise, and where in the VMCS does the answer live?
+ Confidential VMs (SEV-SNP or TDX) encrypt guest memory against the hypervisor. What can the hypervisor still do to a guest, and which OMH claim would a confidential tier support that plain Compute cannot?

== Deliverables and stretch

*Deliverables.* The KVM VMM (direct boot, 16550, virtio-blk, virtio-net, VFIO passthrough, two vCPUs, dirty tracking and migration) with a README and test scripts; the VT-x hypervisor with its VMCS setup documented field by field and its exit statistics; the Compute VMM API and architecture decision; measurements of exit costs, boot times, migration downtime and tenant interference; the Arm port and its comparison.

*Stretch.* Implement virtio-vsock and a guest agent, which is how Compute will run in-guest operations such as key rotation and metrics without a network path. Add virtio-iommu so a guest can run VFIO itself, and test it with nested passthrough of a VF. Give your bare-metal hypervisor a `vmcall` interface and boot your Chapter 4.1 kernel as an L2 guest under KVM under your hypervisor. Implement a vTPM device backed by `swtpm`, so that the guest's PCRs include a measurement of the host's attestation result.

#checklist(
  [*Lab 4.4.1:* a 64-bit guest from nothing, with MMIO exits and injected interrupts; the exit-cost table.],
  [*Lab 4.4.2:* Linux to a shell on your virtio-blk, networking over your virtio-net, two busy vCPUs, boot time recorded.],
  [*Lab 4.4.3:* your Chapter 4.1 kernel as a guest; a VF at over 9 Gb/s through the IOMMU; the DMA fault caught.],
  [*Lab 4.4.4:* Linux on your bare-metal hypervisor; two isolated guests; exit statistics beside KVM's.],
  [*Lab 4.4.5:* start, snapshot and restore through your own API; the decision written.],
  [*Lab 4.4.6:* live migration under 100 ms of downtime with the disk intact; the multi-tenant policy measured.],
  [*Lab 4.4.7:* Linux in your VMM on the Pi; the exit comparison written.],
  [*Problem set:* all nine answered, with problems 2 and 6 checked numerically.],
  [*You can explain*, without notes: every step of a VM exit and re-entry, the two-dimensional page walk, a virtqueue round trip, what the IOMMU does for passthrough, and how pre-copy converges or fails to.],
)
