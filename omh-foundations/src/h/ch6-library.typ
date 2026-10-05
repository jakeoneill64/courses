#import "../lib/template.typ": *

= Reference library <h-library>

Each chapter's reading list names the sections to read and when. These are the books worth owning, and the free documents worth downloading before you start. A book appears once, against every chapter that uses it.

== Books to buy

#tbl(columns: (1fr, auto), header: ([Book], [Chapters]), align: (left, left),
  [Horowitz and Hill, _The Art of Electronics_, 3rd ed.], [1.1, 1.2, 1.4, 3.4],
  [Fraden, _Handbook of Modern Sensors_, 5th ed.], [1.3],
  [Erickson and Maksimović, _Fundamentals of Power Electronics_, 3rd ed.], [1.4 (for depth)],
  [Bogatin, _Signal and Power Integrity, Simplified_, 3rd ed.], [1.5, 3.4],
  [Pozar, _Microwave Engineering_, 4th ed.], [1.5],
  [Lyons, _Understanding Digital Signal Processing_, 3rd ed.], [1.5, 3.2, 3.3],
  [Harris and Harris, _Digital Design and Computer Architecture_, RISC-V ed.], [2.1, 2.2, 2.3],
  [Patterson and Hennessy, _Computer Organization and Design_, RISC-V ed.], [2.3, 2.4],
  [Hennessy and Patterson, _Computer Architecture: A Quantitative Approach_], [2.3, 2.4],
  [Jackson and Budruk, _PCI Express Technology 3.0_ (MindShare)], [2.4, 4.3],
  [White, _Making Embedded Systems_, 2nd ed.], [2.6],
  [Yiu, _The Definitive Guide to Arm Cortex-M3 and Cortex-M4 Processors_], [2.6],
  [Zimmer, Rothman and Marisetty, _Beyond BIOS_, 3rd ed.], [2.7],
  [Hanselman, _Brushless Motors: Magnetics, Design and Control_], [3.1],
  [Franklin, Powell and Emami-Naeini, _Feedback Control of Dynamic Systems_], [3.1 (or the free Åström and Murray)],
  [Beard and McLain, _Small Unmanned Aircraft: Theory and Practice_], [3.1, 3.5],
  [Proakis and Salehi, _Communication Systems Engineering_], [3.2],
  [Rappaport, _Wireless Communications: Principles and Practice_], [3.2],
  [Richards, _Fundamentals of Radar Signal Processing_, 2nd ed.], [3.3],
  [Johnson and Graham, _High-Speed Digital Design_], [3.4],
  [Ott, _Electromagnetic Compatibility Engineering_], [3.4, 4.6],
  [Simon, _Optimal State Estimation_], [3.5],
  [Love, _Linux Kernel Development_, 3rd ed.], [4.2],
  [Gregg, _BPF Performance Tools_], [4.2, 4.5],
  [Madieu, _Linux Device Driver Development_, 2nd ed.], [4.3],
  [Bugnion, Nieh and Tsafrir, _Hardware and Software Support for Virtualization_], [4.4],
)

== Free documents

#tbl(columns: (1fr, auto), header: ([Document], [Chapters]), align: (left, left),
  [TI, _Op Amps for Everyone_ (SLOD006)], [1.2],
  [NXP UM10204, _I#super[2]C-bus specification and user manual_], [1.3, 2.6],
  [TI SLAU723A, _MSP432E4 Technical Reference Manual_; SLAU748B, _MSP-EXP432E401Y LaunchPad user's guide_], [2.6, 3.4, 3.5],
  [Arm, _Cortex-M4 Devices Generic User Guide_], [2.6],
  [RISC-V Unprivileged and Privileged ISA specifications], [2.3, 2.5],
  [Intel 64 and IA-32 Software Developer's Manual, volume 3], [2.5, 2.7, 4.1, 4.4],
  [Nagarajan, Sorin, Hill and Wood, _A Primer on Memory Consistency and Cache Coherence_, 2nd ed.], [2.4],
  [Drepper, _What Every Programmer Should Know About Memory_], [2.4],
  [UEFI, ACPI, TCG PC Client Platform Firmware Profile and DMTF Redfish specifications], [2.5, 2.7, 4.7],
  [Arthur and Challener, _A Practical Guide to TPM 2.0_ (Apress Open)], [2.7, 4.6],
  [IETF RFC 9334, _Remote Attestation Procedures Architecture_], [2.7, 4.6, 4.7],
  [Åström and Murray, _Feedback Systems_, 2nd ed.], [3.1],
  [TI TIDUCF1 (drone ESC reference design) and SPRUJ26 (Motor Control SDK lab guide)], [3.1],
  [TI SWRA588A (CC1312R LaunchPad) and SWCU185 (CC13x2 Technical Reference Manual)], [3.2],
  [Banerjee, _PLL Performance, Simulation, and Design_ (TI)], [3.3],
  [TI SNAU217B (LMX2572EVM), SWRU596 (IWRL6432BOOST), SPYY005 and SWRA553 (mmWave fundamentals and chirp design)], [3.3],
  [OCP DC-SCM 2.0, Open Rack v3 and Yosemite v3 specifications], [3.4, 4.6, 4.7],
  [Raspberry Pi _Compute Module 5 Datasheet_ and the CM5 IO Board design files], [3.4],
  [Arpaci-Dusseau, _Operating Systems: Three Easy Pieces_], [4.1],
  [Cox, Kaashoek and Morris, _xv6: a simple, Unix-like teaching operating system_], [4.1],
  [NVM Express Base, PCIe Transport, NVM Command Set and NVMe over Fabrics specifications], [4.1, 4.3, 4.5],
  [McKenney, _Is Parallel Programming Hard, And, If So, What Can You Do About It?_], [4.2],
  [Corbet, Rubini and Kroah-Hartman, _Linux Device Drivers_, 3rd ed.; Bootlin's kernel and driver training materials], [4.2, 4.3],
  [OASIS virtio 1.2 specification; Linux `Documentation/virt/kvm/api.rst`], [4.4],
)

Datasheets, application notes and user's guides for each part are linked from TI's product pages; download the ones a chapter names into a `datasheets/` directory in your labs repository, so your notes can cite page numbers that will not move.
