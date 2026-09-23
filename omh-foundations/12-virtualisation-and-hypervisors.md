# Module 12: Virtualisation and hypervisors

**Part IV · 5 weeks · Needs: the server (VT-x, VT-d, EPT), the Pi (ARM KVM), QEMU, your Module 9 kernel and UEFI loader, the NIC bound to `vfio-pci` from Lab 11.6.**

## Why this module (and what it buys OMH)

Compute is a hypervisor with a billing model. Every tenant instance OMH sells runs on a
virtual machine monitor that must isolate tenants from each other and from the host, hand
them fast storage and network, move them between modules for rolling updates, and never
let a guest see the keys that Modulus holds. Clusters runs on Compute. Functions is
Compute with a very short boot. A founder who cannot read a VM-exit reason or explain why a
guest's disk write is slow cannot specify, buy, debug or price the core of the product.
This module builds the whole stack twice: once on top of KVM, the way you will ship, and
once on bare metal with VT-x, so that nothing KVM does is magic.

## Skip test

1. A guest executes `cpuid`. List, in order, every hardware and software step from that
   instruction to the guest receiving a result, on Intel with KVM.
2. What are the two levels of address translation under EPT, who owns each, and what does
   a guest page fault that the guest kernel can handle look like to the hypervisor?
3. Why does a virtio device need a memory barrier between writing a descriptor and writing
   the available index, and what does the `VIRTIO_F_RING_PACKED` layout change?
4. A guest with a passed-through NIC issues a DMA to guest physical address 0x1000. Name
   every table consulted before a byte moves, and what prevents the DMA from reaching
   another tenant's memory.
5. Live migration: what is dirty page tracking, what does the hypervisor do in the final
   stop-and-copy phase, and why does a passed-through device make migration hard?

If all five are easy, do Labs 12.2, 12.4 and 12.6.

## Core ideas

**Trap and emulate, and why it needed hardware.** Popek and Goldberg: a machine is
virtualisable if every sensitive instruction traps when executed at reduced privilege.
Classic x86 was not: `popf`, `sgdt` and friends silently behaved differently in ring 3.
VMware binary-translated around it; Xen paravirtualised the guest; then Intel added VT-x
and AMD added SVM in 2005 and 2006, giving the hypervisor a new mode (VMX root) above
ring 0 and a hardware-managed structure (the VMCS, or VMCB on AMD) that says which guest
actions cause a VM exit. A modern hypervisor is a loop: `vmlaunch`/`vmresume`, run until
exit, read the exit reason, emulate or fix up, resume.

**VMX in detail.** `vmxon` enters root operation. The VMCS holds guest state (registers
the CPU loads on entry), host state (registers it loads on exit), execution controls
(which events exit: CPUID, HLT, I/O ports, MSR access, CR writes, external interrupts,
EPT violations), exit information (reason, qualification, guest linear and physical
address) and entry controls (event injection). Fields are accessed with `vmread`/`vmwrite`
by encoding, never by pointer. Unconditional exits: CPUID, `vmcall`, INVD. Everything else
is a control bit. Getting the VMCS right is the whole difficulty of a bare-metal
hypervisor; the OSDev and Intel SDM checklists exist because a wrong field gives
"VM-entry failure, invalid guest state" and nothing else.

**Memory: EPT and nested paging.** Without hardware help, a hypervisor must shadow the
guest's page tables and trap every update. Extended Page Tables (Intel) and Nested Page
Tables (AMD) add a second translation: guest virtual to guest physical by the guest's
tables, guest physical to host physical by the hypervisor's. Page walks become two
dimensional (up to 24 memory accesses on a TLB miss), which is why huge pages matter more
under virtualisation. An EPT violation is the hypervisor's page fault: lazy allocation,
MMIO emulation, dirty tracking and memory ballooning all live there. `invept` and VPIDs
(tagged TLBs) keep switches cheap.

**Interrupts and timers.** A guest expects a local APIC, an I/O APIC, a PIT and an HPET or
a TSC deadline timer. Emulating the APIC in software costs an exit per EOI; APICv and
posted interrupts let the hardware deliver interrupts directly into a running guest.
Interrupt injection at entry, interrupt windows when the guest has interrupts masked,
and the pending-interrupt bookkeeping are where hypervisor bugs cluster. Timers are
emulated by host timers that inject guest interrupts on expiry; the TSC is offset per
guest and, if you allow it, scaled.

**Devices: emulated, paravirtual, passed through.** Emulating a real device (e1000, AHCI)
is slow because a real driver pokes many registers per operation, each an exit. virtio
defines devices designed to be emulated: a shared-memory ring of descriptors, an
available ring the driver writes, a used ring the device writes, a notification (a write
to a doorbell or an MSI) in each direction, and feature negotiation. virtio-blk,
virtio-net, virtio-scsi, virtio-console, virtio-fs, virtio-vsock, virtio-gpu, virtio-iommu
share this transport over PCI, MMIO or channel I/O. vhost moves the data path into a
kernel thread; vhost-user moves it into another userspace process (DPDK, SPDK); vDPA puts
a virtio data path in hardware with a vendor control path. Passthrough hands a real
device to the guest through VFIO: the IOMMU translates the device's DMA with the same
guest-physical-to-host-physical map the EPT uses, and interrupts are remapped so the
device cannot signal an arbitrary vector. SR-IOV virtual functions make passthrough
scale.

**KVM.** Linux as the hypervisor. `/dev/kvm` creates a VM file descriptor; `KVM_CREATE_VCPU`
creates vCPU descriptors; `KVM_SET_USER_MEMORY_REGION` maps host memory into guest physical
space; `KVM_RUN` runs a vCPU until an exit KVM cannot handle itself, which it reports in a
shared `kvm_run` structure: I/O port access, MMIO access, halt, shutdown, or an internal
error. In-kernel irqchip, `KVM_IRQFD` and `KVM_IOEVENTFD` let devices signal and be
signalled without a round trip to userspace. The VMM (QEMU, Firecracker, Cloud Hypervisor,
crosvm, kvmtool) is the process that owns the file descriptors, emulates devices, and
handles what KVM hands back. On ARM, KVM runs at EL2 and uses stage-2 translation; the
ioctl interface is nearly identical, which is why Firecracker runs on both.

**Boot inside a VM.** A VMM chooses how much firmware to give the guest: none (load a
Linux bzImage directly via the boot protocol, set up `boot_params`, the E820 map and a
command line, start the vCPU in protected mode at the kernel's entry), a minimal firmware
(qboot, or Firecracker's direct boot), or full UEFI (OVMF or Cloud Hypervisor's firmware).
Direct boot is what makes a 125 ms microVM possible; it is also what Functions needs.
Serial console via an emulated 16550 at 0x3F8 is the first thing to get working, because
until it does the guest is a black box.

**Isolation and security.** The hypervisor is the trust boundary between tenants. Attack
surface: the device emulation code (historically most VM escapes), the instruction
emulator, shared memory channels, and side channels (Spectre variants, L1TF, MDS) that
leak across a core. Mitigations: minimal device models (Firecracker has a few thousand
lines of device code), seccomp and namespaces around the VMM process, core scheduling so
sibling hyperthreads never run different tenants, and flushing on context switch where
the CPU requires it. Memory encryption (AMD SEV-SNP, Intel TDX, ARM CCA) removes the
hypervisor from the guest's trust base and is the direction confidential computing has
gone; understand what it does and does not protect.

**Live migration and snapshots.** Pre-copy: mark all guest memory dirty, copy while the
guest runs, iterate over pages dirtied since the last pass (tracked via write-protected
EPT entries or the hardware page-modification log), stop the guest when the dirty set is
small, copy the remainder plus device state and vCPU registers, resume on the destination.
Post-copy starts the guest on the destination and faults pages in over the network.
Snapshot and restore is migration to and from a file, and is how Firecracker gets
sub-10 ms restores. Passthrough devices break migration unless the device supports state
save (VFIO migration support exists for a few NICs); Compute's design will choose between
passthrough performance and migratable instances, or offer both tiers.

**Nested virtualisation and the management plane.** KVM can run KVM: L1's VMX
instructions are trapped and emulated by L0, with shadow VMCS and EPT-on-EPT. It is slow
and useful for testing. Above the hypervisor sits the management plane: libvirt as the
common abstraction, or a purpose-built agent as Firecracker and Cloud Hypervisor expect.
Compute's control plane will talk to a VMM API on each module, and the shape of that API
(create, configure devices, boot, pause, snapshot, migrate, destroy, metrics) is decided
in this module.

**ARM virtualisation.** EL2 with stage-2 translation, the GIC's virtual interface, the
generic timer's virtual counter, and the VHE extension that lets a host kernel run at EL2
directly. KVM on the Pi lets you compare: the same VMM code, a different exit vocabulary
(HVC, data aborts to MMIO, WFI).

## Reading

- Bugnion, Nieh, Tsafrir, *Hardware and Software Support for Virtualization*: all of it.
  Short, precise, and the best single text on the subject.
- Intel SDM vol. 3, ch. 23 to 33 (VMX), ch. 28 (EPT), ch. 29 (APIC virtualisation),
  ch. 30 (VM exits). Read 23 to 27 closely before Lab 12.4; use 30's exit-reason table as a
  desk reference.
- Intel Virtualization Technology for Directed I/O (VT-d) specification, ch. 3 (DMA
  remapping) and ch. 5 (interrupt remapping).
- virtio 1.2 specification: ch. 2 (basic facilities), ch. 4.1 (PCI transport), ch. 5.1
  (network device), ch. 5.2 (block device). Draw the split ring on paper before Lab 12.2.
- Linux `Documentation/virt/kvm/api.rst`: read the ioctls you will use in Lab 12.1 and
  their structures; skim the rest to know what exists.
- Linux `Documentation/arch/x86/boot.rst` for direct kernel boot.
- kvmtool source (small enough to read entirely); Firecracker's `src/vmm` and its device
  models; Cloud Hypervisor's `vmm/src/cpu.rs`; QEMU `accel/kvm/kvm-all.c` and
  `hw/virtio/virtio.c` for comparison.
- Firecracker's design document and the paper: Agache et al., "Firecracker: Lightweight
  Virtualization for Serverless Applications", NSDI 2020.
- Clark et al., "Live Migration of Virtual Machines", NSDI 2005.
- Popek and Goldberg, "Formal Requirements for Virtualizable Third Generation
  Architectures", 1974. One evening.

## Labs

### Lab 12.1: Hello from a guest, via `/dev/kvm`

On the server. C or C++, no libraries beyond libc.

1. Open `/dev/kvm`, check `KVM_GET_API_VERSION`, create a VM, `mmap` 64 MiB of host memory
   and register it as guest physical 0 with `KVM_SET_USER_MEMORY_REGION`. Create one vCPU
   and `mmap` its `kvm_run` structure.
2. Load a 16-bit real-mode guest: a few bytes of machine code that write a string to
   port 0x3F8 with `out` and then `hlt`. Set registers with `KVM_SET_REGS` and
   `KVM_SET_SREGS`. Loop on `KVM_RUN`; handle `KVM_EXIT_IO` by printing the byte, and
   `KVM_EXIT_HLT` by stopping.
3. Now a 64-bit guest: build page tables and a GDT in guest memory yourself, set `CR0`,
   `CR3`, `CR4`, `EFER` and segment registers for long mode, and run a flat binary
   compiled from C that writes to the serial port and reads a value from an MMIO address
   you do not back with memory. Handle `KVM_EXIT_MMIO`.
4. Set up the in-kernel irqchip (`KVM_CREATE_IRQCHIP`), a PIT (`KVM_CREATE_PIT2`), and inject
   an interrupt from a host timer thread with `KVM_IRQ_LINE`. Your guest installs an IDT
   and counts ticks.
5. Time it: `perf stat -e kvm:*` while the guest runs. Report exits per second by reason,
   and the cost of one round trip through `KVM_RUN` in nanoseconds.

Done when: a 64-bit guest you built from scratch runs, takes MMIO exits, receives injected
interrupts, and you have an exit-cost table.

### Lab 12.2: Boot Linux with your own virtio-blk and virtio-net

Build on Lab 12.1. This is the VMM you will extend for the rest of the course.

1. Direct kernel boot: load a bzImage per `boot.rst`, fill in `boot_params` (E820 map,
   command line, initrd location, `loadflags`), start the vCPU in protected mode at the
   32-bit entry. Emulate a 16550 UART at 0x3F8 well enough for the kernel's `earlyprintk`
   and then its real `8250` driver: LSR, IER, IIR, THR, RBR, and interrupt on receive.
   Boot a kernel you built with a minimal config and an initramfs from Buildroot. Get to a
   shell.
2. virtio-blk over the PCI transport: emulate a PCI bus (config space via ports 0xCF8 and
   0xCFC) with one device: the virtio-blk vendor and device ID, the common, notify, ISR
   and device-specific capability structures in a BAR you back with MMIO exits. Implement
   feature negotiation, the split virtqueue (read descriptors from guest memory, process
   requests, write used entries, memory barriers where the spec says), and MSI-X or a
   legacy interrupt on completion. Back it with a file. Boot with `root=/dev/vda`.
3. virtio-net over a `tap` device: two queues, TX and RX, plus the header. Bring up an
   address in the guest, `ping` the host, `iperf3` to the host.
4. Move device notifications off the vCPU thread: `KVM_IOEVENTFD` for the doorbell,
   `KVM_IRQFD` for completions, a device thread per virtqueue. Measure the difference.
5. Add a second vCPU: MP table or ACPI MADT so the guest finds it, `KVM_RUN` on a second
   thread, and the IPI plumbing that the in-kernel irqchip handles for you. Confirm `nproc`
   is 2 and a parallel build uses both.

Done when: Linux boots from your virtio-blk to a shell over your serial port, pings over
your virtio-net, and both vCPUs are busy under load. Record boot time from `KVM_RUN` to
the shell prompt.

### Lab 12.3: Your own kernel as a guest, then a passed-through NIC

1. Boot your Module 9 kernel in your VMM instead of QEMU. Fix what breaks; note whether
   the breakage is in your kernel or your VMM (it will be both). Its NVMe driver will not
   find a controller: either give it a virtio-blk driver or emulate enough of an NVMe
   controller (admin queue, one I/O queue) for it to run. Doing the latter teaches you
   what QEMU's `hw/nvme` does and is worth the week.
2. Passthrough: with the NIC bound to `vfio-pci` (Lab 11.6), map its BARs into guest
   physical space (`KVM_SET_USER_MEMORY_REGION` over the `mmap`ed region for prefetchable
   BARs, MMIO exits forwarded to `pread`/`pwrite` for the rest), expose its config space
   through your emulated PCI bus with the real values from `VFIO_DEVICE_GET_REGION_INFO`,
   pin guest memory in the IOMMU with `VFIO_IOMMU_MAP_DMA` for the whole guest RAM, and
   route MSI-X vectors from VFIO eventfds to `KVM_IRQFD`.
3. Boot Linux in your VMM with the NIC visible. The in-tree driver should bind. `iperf3`
   through the passed-through NIC versus your virtio-net.
4. Reset behaviour: kill the VMM under load and confirm the device comes back cleanly
   (VFIO resets on release). Then break it: skip the IOMMU mapping for part of guest RAM
   and observe the DMA fault in `dmesg` rather than corruption.

Done when: your Module 9 kernel runs as a guest, and a Linux guest drives the real NIC
through the IOMMU with line-rate throughput.

### Lab 12.4: A bare-metal VT-x hypervisor

Your Module 9 kernel becomes a hypervisor. QEMU with `-cpu host -enable-kvm` supports
nested VMX for development; then the server.

1. Check CPUID and `IA32_FEATURE_CONTROL`, set `CR4.VMXE`, allocate the VMXON region and a
   VMCS with the revision ID, `vmxon`, `vmclear`, `vmptrld`. Handle the `IA32_VMX_*` MSRs
   that tell you which control bits are allowed and required.
2. Fill the VMCS for a guest running a flat 64-bit binary in a region of memory you
   allocate: guest state, host state (your kernel's segments, `CR3`, a host stack, `RIP` of
   your exit handler), execution controls with CPUID, HLT, I/O and MSR exits enabled, and
   EPT enabled with a four-level EPT table you build. Use the SDM's "checks on guest state"
   section as a checklist; when `vmlaunch` fails, `vmread` the instruction error field and
   look up which check you violated.
3. Exit handler: save guest GPRs, switch on exit reason. CPUID: execute on the host and
   hide the VMX bit. I/O to 0x3F8: forward to your console. HLT: idle. EPT violation:
   allocate a frame and map it, or emulate an MMIO device you define. Unhandled: dump the
   VMCS and stop.
4. Run Linux as the guest. Give it the direct-boot path from Lab 12.2 (`boot_params` and
   all), a 16550, and a virtio-blk over MMIO (the MMIO transport is simpler than PCI for
   a first pass). Emulate the local APIC timer (or use the preemption timer) so the guest
   schedules. Boot to a shell.
5. Run two guests, time-sliced, each with its own EPT and its own serial port mapped to a
   different console. Prove isolation: a guest that scribbles over all of its physical
   memory does not affect the other.
6. Measure exits with a counter per reason exposed through your console. Compare with the
   KVM numbers from Lab 12.1.

Done when: Linux boots to a shell on your bare-metal hypervisor on the server, two guests
run concurrently and cannot see each other, and the exit statistics are written up.

### Lab 12.5: Firecracker, Cloud Hypervisor and the management API

1. Run Firecracker with a kernel and rootfs. Read its API and drive it with `curl`: create
   boot source, drives, network interface, then `InstanceStart`. Time boot to shell.
   Snapshot it, restore it, time the restore.
2. Read Firecracker's `vmm/src/device_manager` and its virtio-block implementation
   alongside yours. List what it does that you did not, and why (rate limiting, seccomp,
   the jailer, MMDS, balloon).
3. Run Cloud Hypervisor with the same guest; compare the device model (PCI, hotplug,
   virtio-fs, vDPA) and the boot time.
4. Design and write the Compute VMM API for Module Zero as an OpenAPI document: instance
   lifecycle, device attach and detach, snapshot, migrate, metrics, and how a control plane
   authenticates to it. Decide whether you build on Firecracker, Cloud Hypervisor, your own
   VMM, or QEMU, and write one page justifying the choice for Compute's first release. Then
   implement the subset of that API on your Lab 12.2 VMM as an HTTP service over a Unix
   socket.

Done when: you can start, snapshot and restore a microVM through your own API, and the
architecture decision is written.

### Lab 12.6: Live migration and the multi-tenant node

1. Add dirty-page tracking to your VMM with `KVM_MEM_LOG_DIRTY_PAGES` and
   `KVM_GET_DIRTY_LOG`. Implement pre-copy migration to a second VMM process over TCP:
   iterate until the dirty set is under a threshold, pause, send vCPU state (`KVM_GET_REGS`,
   `SREGS`, `FPU`, `MSRS`, `LAPIC`), device state (your virtio-blk and virtio-net queue
   indices; the disk file is shared), and resume on the destination. Migrate a guest
   running `iperf3` and a guest writing a counter to disk; measure downtime and verify no
   corruption. Then migrate between the server and the Pi's KVM if you ported the VMM
   (stretch), or between two VMMs on the server.
2. Multi-tenant hardening on the host: run each VMM in its own cgroup with a memory limit
   and CPU quota, a seccomp filter allowing only the syscalls it needs (trace them first),
   an unprivileged user, and a network namespace. Enable core scheduling and pin vCPU
   threads to isolated cores from Module 10 Lab 10.4. Measure the isolation: one tenant
   running a memory-bandwidth hog, the other running a latency-sensitive loop; report the
   interference with and without pinning.
3. Side channels: read the kernel's `/sys/devices/system/cpu/vulnerabilities/` on the
   server, explain each entry and what the mitigation costs, and decide the policy for
   Compute (SMT on or off per tier).
4. Attestation into the VM: pass the host's Module 8 attestation result into a guest via
   the virtio-vsock or MMDS-style metadata service, so a tenant can verify it is running on
   an attested OMH module. Sketch how a vTPM per guest (`swtpm` behind virtio or an emulated
   TIS device) would extend the chain.

Done when: a running guest migrates with under 100 ms downtime and correct disk state, and
the multi-tenant host policy is written and measured.

### Lab 12.7: ARM, for comparison

On the Pi 5 with KVM enabled in the kernel:

1. Port your Lab 12.2 VMM: `KVM_ARM_VCPU_INIT` with preferred target, a GIC via
   `KVM_CREATE_DEVICE`, the generic timer, a PL011 UART emulated on MMIO exits, virtio over
   MMIO, and an Image (not bzImage) boot with a device tree you generate with `libfdt`.
2. Boot Linux. Compare exit reasons and rates with the x86 VMM for the same workload.
3. Write one page on what a Compute module built on ARM (Ampere, or a Grace-class part)
   would change in your VMM and in the product.

Done when: Linux boots in your VMM on the Pi and the comparison is written.

## Problem set

1. Give three x86 instructions that Popek and Goldberg would call sensitive but that did
   not trap in ring 3 before VT-x, and say what each one leaks or breaks.
2. A guest kernel handles a page fault entirely itself with no VM exit. Explain how that is
   possible under EPT, and name a guest page fault that does cause an exit.
3. Count the memory accesses in a worst-case two-dimensional page walk with 4-level guest
   tables and 4-level EPT. How do 2 MiB EPT pages change it? How does the VPID change the
   frequency?
4. Your virtio-blk device reads a descriptor chain and finds a descriptor pointing outside
   guest memory. What must the device do, and what happens if it just dereferences?
5. Explain why an MSI from a passed-through device must be remapped by the IOMMU, and
   describe the attack a malicious guest could mount without remapping.
6. Firecracker boots in about 125 ms; QEMU with OVMF in a few seconds. Attribute the
   difference across firmware, device enumeration, kernel decompression and init.
7. Design dirty-page tracking for a guest using 2 MiB pages: what granularity do you track
   at, what does it cost in the final stop-and-copy, and when would you split pages?
8. A tenant's vCPU thread and another tenant's vCPU thread share a physical core's two
   hyperthreads. Name two concrete side channels and the mitigation for each. What does
   the mitigation cost in Compute's capacity model?
9. Your bare-metal hypervisor must handle a guest `wrmsr` to `IA32_EFER`. What should it
   allow, refuse and virtualise, and where does the answer live in the VMCS?
10. Confidential VMs (SEV-SNP or TDX) encrypt guest memory against the hypervisor. What
    can the hypervisor still do to a guest? Which OMH claim would a confidential-compute
    tier support that plain Compute cannot?

## Deliverables

- The KVM VMM in your labs repo: direct boot, 16550, virtio-blk, virtio-net, VFIO
  passthrough, SMP, dirty tracking and migration, with a README and test scripts.
- The bare-metal VT-x hypervisor running Linux, with the VMCS setup documented field by
  field and the exit statistics.
- The Compute VMM API document and the architecture decision page.
- Measurements: exit costs, boot times, migration downtime, tenant interference with and
  without pinning.

## Stretch

- Implement a virtio-vsock device and a guest agent, which is how Compute will run
  in-guest operations (key rotation, metrics) without a network path.
- Add a virtual IOMMU (virtio-iommu) so a guest can run VFIO inside itself; test with
  nested passthrough of a VF.
- Port the bare-metal hypervisor to run your VMM's guests from a `vmcall` hypercall
  interface, and boot your Module 9 kernel as an L2 guest under KVM under your hypervisor.
- Implement a vTPM device backed by `swtpm` and extend the attestation chain into the guest
  properly: the guest's PCRs include a measurement of the host's attestation result.

## Next

Module 13 follows the bytes: from a guest's write, through virtio, blk-mq and the NVMe
driver to flash, and out over the NIC to another module. Storage and Blocks are built
from those two paths and an erasure code.
