#import "lib/template.typ": *
#show: course-doc.with(unit: "4", title: "Systems Software and the Product", short: "Systems Software and the Product",
  subtitle: "Kernels, Linux, drivers, virtualisation, data paths and the product",
  chapters: ("Write a kernel", "Linux kernel internals", "Linux device drivers", "Virtualisation and hypervisors", "Storage and network data paths", "Product engineering", "Capstone: Module Zero"))
#contents()

#about-unit(unit: "4",
  intro: [Unit 4 is the software a server company runs on its hardware, and the product built from both. You write a 64-bit SMP kernel with an NVMe driver, then learn Linux from the inside: building, tracing, bisecting and hardening it. You write Linux drivers for TI parts that mainline lacks, build a KVM virtual machine monitor with your own virtio devices, and measure storage and network data paths from `io_uring` and the kernel stack to SPDK and DPDK. Then you write the documents that turn a prototype into a product, and assemble Module Zero: two nodes under your BMC that attest, form a quorum, run tenants and survive a pulled cable.],
  rows: (
    ([4.1], [A 64-bit SMP kernel with paging, user mode, an NVMe driver and a filesystem, on QEMU and the server], [5]),
    ([4.2], [Linux built, traced, bisected and hardened on the server and the Pi; the node kernels], [3.5]),
    ([4.3], [Mainline TI drivers by overlay, your own OPT4048 and ADS1220 drivers, fan control, PCIe and VFIO], [5]),
    ([4.4], [A KVM VMM with virtio devices, VFIO pass-through and live migration; a bare-metal hypervisor], [5]),
    ([4.5], [Storage and network paths measured; SPDK; Reed-Solomon; NVMe over Fabrics; XDP and DPDK; a Blocks prototype], [2.5]),
    ([4.6], [Module Zero's specification, threat model, update architecture, test plan, compliance plan and cost model], [2]),
    ([4.7], [Module Zero, demonstrated from a cold start and recorded], [6 to 8]),
  ),
  before: [The server, the Pi, Board A and Board B from Chapter 3.4, and the lab network from the Handbook must all be working. Chapter 4.5 can follow 4.3 directly, and 4.6 can be read alongside the capstone's first two weeks.],
)

#include "u4/ch1-kernel.typ"
#include "u4/ch2-linux.typ"
#include "u4/ch3-drivers.typ"
#include "u4/ch4-virt.typ"
#include "u4/ch5-datapath.typ"
#include "u4/ch6-product.typ"
#include "u4/ch7-capstone.typ"

#signoff(unit: "4",
  chapters: ("Write a kernel", "Linux kernel internals", "Linux device drivers", "Virtualisation and hypervisors", "Storage and network data paths", "Product engineering", "Capstone: Module Zero"),
  review: (
    [Trace a 4 KiB read from a guest's `read(2)` through your VMM, the host kernel and the NVMe drive to the flash and back, naming every queue, copy, exit and interrupt.],
    [Walk a page fault through your kernel and then through Linux, and explain each difference.],
    [Write from memory the probe function of an I#super[2]C IIO driver like your OPT4048 driver, and explain each call and what device-tree binding it relies on.],
    [Explain how Module Zero admits a node from power-on to joining the quorum, and what happens when a node's firmware changes.],
    [Present the Module Zero recording and your retrospective to someone who builds servers, and defend the cost model against their questions.],
  ),
)
