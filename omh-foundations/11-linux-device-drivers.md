# Module 11: Linux device drivers

**Part IV · 4 weeks · Needs: the Pi with BME280 and EMC2101, your FPGA SPI peripheral, QEMU, the server with the NIC and NVMe drive.**

## Why this module (and what it buys OMH)

An OMH module is a Linux box surrounded by hardware that Linux must talk to: drive bays and
their presence and LED signals, fans and thermal sensors, PSUs over PMBus, a BMC over
I2C or MCTP, NICs, NVMe, and whatever glue logic you put in an FPGA. Some of that has
upstream drivers; some will be yours. The driver chain begun in Module 3 (a register map),
carried through Module 7 (a microcontroller drives it), finishes here: Linux drives it,
and userspace sees a gpiochip, a hwmon device, an IIO sensor, a character device. The
PCIe and VFIO labs are the foundation for Compute's device passthrough.

## Skip test

1. Draw the Linux device model for an I2C sensor on a Raspberry Pi: which `bus_type`, how
   the device came to exist, how the driver was matched, and what `probe` receives.
2. `dma_alloc_coherent` versus `dma_map_single`: when is each correct, what does the IOMMU
   change, and what bug appears on ARM that x86 hides?
3. Write a device-tree node and a `compatible` string for a custom SPI peripheral with an
   interrupt line on a GPIO. Which framework validates your binding?
4. MSI versus MSI-X versus INTx: what does the driver do differently, and why does a
   multi-queue device need MSI-X?
5. A PCIe device's BAR is `ioremap`ped. Why must you use `readl`/`writel` rather than
   dereferencing the pointer, and what does `writel` do that a plain store does not on ARM?

If all five are easy, do Labs 11.2, 11.3 and 11.6.

## Core ideas

**A driver is glue between a bus and a subsystem.** The bus (platform, I2C, SPI, PCI, USB)
discovers or is told about a device and hands it to a matching driver's `probe`. The
subsystem (IIO, hwmon, gpio, net, block, input, tty) gives the driver a way to expose the
device to userspace through a standard ABI. Good drivers are thin; the frameworks do the
work.

**The device model.** `struct device` and `struct device_driver` attached to a `struct
bus_type`, matched by ID tables (`of_match_table` for device tree, `acpi_match_table`,
`i2c_device_id`, `pci_device_id`). `probe` acquires resources; `remove` releases them.
Managed resources (`devm_*`) release automatically on failure or removal, which is why
modern drivers have almost no error-unwinding code. Deferred probe handles dependencies
that are not yet available (a regulator, a clock, a GPIO controller) by retrying later.

**Platform devices and the device tree.** Non-enumerable hardware is described in the DT:
a node with `compatible`, `reg`, `interrupts`, `clocks`, `gpios`, and custom properties. The
kernel creates a `platform_device` per node and matches drivers by `compatible`. Bindings
are documented as YAML schemas under `Documentation/devicetree/bindings/` and validated
with `dt_binding_check` and `dtbs_check`. On ACPI systems the same device would appear
via a `_HID` and `_CRS` and be matched by `acpi_match_table`; the driver code is the same.

**Buses you will use.** I2C: `i2c_client`, `i2c_transfer`, and `regmap` to abstract register
access with caching and locking. SPI: `spi_device`, `spi_sync` with transfer lists, also
behind `regmap`. GPIO: consumer API (`gpiod_get`, `gpiod_set_value`) for using pins,
`gpio_chip` provider API for exposing them. Pinctrl, clocks and regulators as frameworks
your driver asks for by name from the DT. Interrupts: `request_threaded_irq` for anything
that takes time, IRQ domains that let a GPIO controller or your FPGA act as an interrupt
controller.

**DMA.** Devices see bus addresses, not virtual addresses, and possibly not physical ones
either when an IOMMU is present. Coherent allocations (`dma_alloc_coherent`) are for
long-lived descriptor rings that both sides read and write; streaming mappings
(`dma_map_single`, `dma_map_sg`) are for per-transfer buffers and require explicit
ownership handoff, including cache maintenance on non-coherent architectures. DMA masks
declare what the device can address. Scatterlists describe non-contiguous buffers.
DMA-BUF shares buffers between drivers. The IOMMU makes all of this safe and makes VFIO
possible.

**MMIO.** `ioremap` a BAR or a `reg` range; access with `readl`/`writel` and friends, which
add the barriers and volatile semantics that make device access ordered and visible.
Posted writes mean a `writel` may not have reached the device when the next instruction
runs; a read-back forces it.

**Subsystems as ABIs.** IIO for sensors (channels, raw and scaled values, buffered capture
with triggers). hwmon for temperatures, fans, voltages, currents and power, with `sensors`
and `libsensors` as consumers, plus the PMBus core that turns a PMBus device into hwmon in a
few dozen lines. LEDs and their triggers (a drive-bay LED tied to activity). Watchdog.
Thermal zones and cooling devices (the fan curve, in the kernel). Input. The misc and
character device fallback when nothing fits, with a uAPI header and versioned ioctls.
sysfs and debugfs, and the rule that sysfs is a stable ABI and debugfs is not.

**PCI drivers.** `pci_driver` with an ID table, `pci_enable_device`, `pci_request_regions`,
`pci_iomap`, `pci_set_master`, `pci_alloc_irq_vectors` for MSI or MSI-X, `pci_irq_vector`
to get the Linux IRQ for each, DMA mask setup, and on the way out the reverse. Config
space accessors. Advanced Error Reporting callbacks (`pci_error_handlers`) for recovering
from link errors, which servers experience. Hot-plug notifications. SR-IOV: a Physical
Function enabling Virtual Functions (`pci_enable_sriov`), each VF a lightweight PCI
device that can be handed to a VM.

**Network drivers.** `net_device`, `net_device_ops`, TX and RX descriptor rings in coherent
memory, NAPI polling, offloads advertised via `features`, `ethtool` operations. Read
`e1000e` (moderate) and `ixgbe` (production) to see how much of a real driver is error
handling and offload management.

**Block and storage.** blk-mq drivers implement `queue_rq`, map hardware queues to CPUs,
and complete requests from interrupt or poll context. `drivers/nvme/host/pci.c` is the
reference; it is a few thousand lines and you already wrote its bare-metal cousin.
Above: SCSI for SAS and SATA, device-mapper, MD RAID.

**Userspace drivers.** UIO exposes registers and interrupts to userspace for simple
devices. VFIO exposes a whole PCI device (regions, interrupts as eventfds, DMA through the
IOMMU) to a userspace process, which is how QEMU, DPDK and SPDK take over a NIC or NVMe
drive. VFIO is the bridge from this module to Module 12's passthrough and Module 13's
polled data paths.

**Firmware loading, power, robustness.** `request_firmware` for devices that need a blob.
Runtime PM and system suspend callbacks. Timeouts on every wait for hardware; spurious
interrupt handling; reset paths; never trust a value the device returned without bounds
checking. Hardware lies, especially prototype hardware, and doubly so hardware you built.

**Testing and upstreaming.** KUnit for units, kselftest for behaviour, QEMU device models
for hardware you do not have (writing a small one is a legitimate technique). Coding style,
`checkpatch`, a binding document, and a cover letter. Upstream drivers are the cheapest
drivers to maintain for a decade.

## Reading

- Corbet, Rubini, Kroah-Hartman, *Linux Device Drivers*, 3rd ed.: ch. 1 to 3, 5 to 10, 12
  and 14 to 15 for the concepts. APIs have moved; the structure holds.
- Bootlin, "Linux kernel and driver development" lab book: do the I2C, platform driver,
  interrupt and DMA labs. They are current and use a real board.
- Madieu, *Linux Device Driver Development*, 2nd ed.: ch. 4 to 9 (device model, DT,
  I2C, SPI, regmap), ch. 12 to 14 (IRQ, DMA), ch. 17 (IIO), ch. 20 (PCI).
- `Documentation/driver-api/` (driver model, I2C, SPI, GPIO, PCI, IIO, hwmon,
  `dma-api-howto.rst`, `dma-api.rst`, `vfio.rst`, `pci/pci.rst`, `pci/msi-howto.rst`),
  `Documentation/devicetree/` (usage model, writing bindings, schema),
  `Documentation/ABI/`.
- Kernel source: `drivers/iio/pressure/bmp280-*.c`, `drivers/hwmon/emc2103.c` and
  `drivers/hwmon/pmbus/`, `drivers/gpio/gpio-mockup.c` and `gpio-pca953x.c`,
  `drivers/misc/` (small char devices), `drivers/net/ethernet/intel/e1000e/`,
  `drivers/nvme/host/pci.c`, `drivers/vfio/pci/`.
- QEMU `hw/misc/edu.c` and its `docs/specs/edu.rst`: a PCIe device designed for driver
  teaching.
- Intel 82599 10 GbE Controller Datasheet: sections on device registers, receive and
  transmit descriptors, MSI-X and SR-IOV. Long and excellent.

## Labs

### Lab 11.1: An I2C sensor with a device-tree binding, in IIO

On the Pi with the BME280 (write your own; compare to `bmp280` afterwards):

1. Write the DT binding YAML for `omh,bme280-course` with `reg` and an optional
   `vdd-supply`. Validate with `make dt_binding_check`. Write an overlay and load it.
2. Driver: `i2c_driver` with `of_match_table`, `regmap_i2c`, read calibration data in
   `probe`, expose temperature, pressure and humidity as IIO channels with correct
   `scale` and `offset` so `iio_info` and `libiio` return real units.
3. Add buffered capture with a hrtimer trigger (`iio-trig-hrtimer`) and a software buffer;
   read a stream with `iio_readdev`.
4. Add a `debugfs` register dump. Handle a missing device gracefully (probe fails with a
   clear message).

Done when: `iio_info` shows your device with correct scaled values, buffered capture
streams, and the binding passes validation.

### Lab 11.2: Your FPGA over SPI: gpiochip, hwmon and a threaded IRQ

The register map from Module 3 Lab 3.6, on the Pi's SPI bus, interrupt line to a Pi GPIO:

1. Binding: `omh,fpga-glue` under an SPI controller node, with `interrupts` referencing the
   GPIO controller and a `spi-max-frequency`.
2. Driver with `regmap_spi` (write a custom `reg_read`/`reg_write` matching your SPI
   transaction format if regmap's default framing does not fit). Expose the GPIO
   registers as a `gpio_chip` so `gpiodetect`, `gpioinfo`, `gpioset` and `gpioget` work
   on your FPGA pins. Implement `direction_input`/`output`.
3. Make the gpiochip an interrupt controller too: an IRQ domain so that a rising edge on
   an FPGA input can be requested by another driver or by userspace via `gpiomon`. Use the
   FPGA's interrupt status and enable registers and a threaded handler on the Pi GPIO
   line.
4. Expose the timer/counter as a `hwmon` channel of an appropriate type, or as a small
   character device with an `ioctl` to set the compare value and `poll` support that wakes
   on the compare interrupt.
5. Stress: toggle FPGA GPIOs from a script at high rate while `gpiomon` watches an input
   wired to an output; count events; find your driver's ceiling and where the time goes.

Done when: `gpioset` drives an FPGA LED, `gpiomon` sees FPGA edges through your IRQ domain,
and the timer interrupt wakes a `poll`ing process.

### Lab 11.3: PCIe with MSI and DMA in QEMU

QEMU's `edu` device (`-device edu`):

1. Read `docs/specs/edu.rst`. Write the register map in your notebook before coding.
2. `pci_driver`: enable, request regions, `pci_iomap` BAR0, read the ID register, set DMA
   mask, allocate one MSI vector, request the IRQ.
3. Implement the factorial computation via the device (write operand, wait for the
   interrupt, read result) exposed through a char device `ioctl`.
4. Implement DMA: allocate a coherent buffer, program the device's DMA registers to copy
   from host to device memory and back, wait for the completion interrupt, verify. Then
   use a streaming mapping of a user buffer via `pin_user_pages` and `dma_map_sg`.
5. Add timeouts, a reset path, and a simulated fault: patch QEMU's `edu.c` to occasionally
   not raise the interrupt and confirm your driver recovers with a timeout and a reset
   rather than hanging.
6. Write a KUnit test for the pure logic and a kselftest script for the char device.

Done when: DMA round-trips verify, the fault-injected device is handled, and tests pass.

### Lab 11.4: A real NIC, minimally

On the server, with a second NIC or a VF so the machine stays reachable:

1. Read the `e1000e` driver's probe, ring setup, `ndo_start_xmit` and NAPI poll. Draw the
   descriptor ring lifecycle.
2. Write a minimal driver for either QEMU's `e1000` model or your physical 82599 (the
   datasheet makes this tractable): bring the link up, configure one RX and one TX queue
   with descriptor rings in coherent memory, allocate MSI-X vectors, register a
   `net_device`, implement `ndo_open`, `ndo_stop`, `ndo_start_xmit` and a NAPI poll that
   passes received frames to `napi_gro_receive`. No offloads.
3. `ip link set up`, assign an address, `ping` through it. Watch `/proc/interrupts` and
   `ethtool -S` (implement a few stats).
4. Measure single-stream throughput with `iperf3` versus the in-tree driver. Explain the
   gap in terms of offloads, ring sizes and interrupt moderation.

Done when: `ping` works through your driver and the throughput comparison is written up.

### Lab 11.5: NVMe, in the tree

1. Read `drivers/nvme/host/core.c` and `pci.c` guided by your Module 9 driver: map each
   step you implemented onto the kernel's version. Note what it does that you did not
   (namespaces, multipath, APST, reset work, polled queues, SGLs, CMB).
2. Add a `debugfs` file under the controller exposing per-queue depth and completion counts.
   Rebuild just the module, reload, verify with `fio` running.
3. `trace-cmd record -e nvme:*` during `fio`; correlate submit and complete events per
   command ID; compute latency distribution in a script.
4. Stretch: an out-of-tree "nvme-lite" blk-mq driver for QEMU's NVMe device: identify,
   one I/O queue, `queue_rq`, interrupt completion. It will be a few hundred lines because
   blk-mq does the rest.

Done when: your debugfs file shows live queue state and the latency script agrees with
`bpftrace` from Module 10.

### Lab 11.6: VFIO, the userspace driver

1. Bind the NIC (or a VF) to `vfio-pci`. Confirm its IOMMU group. Write a C program that
   opens the group and device, queries regions and IRQs, `mmap`s BAR0, and reads the same
   registers as Module 5 Lab 5.4.
2. Set up the IOMMU: `VFIO_IOMMU_MAP_DMA` for a buffer you allocate; program the device to
   DMA into it (the 82599 makes RX descriptors and buffers straightforward; the QEMU `edu`
   device also works for a first attempt); receive one frame in userspace.
3. Route MSI-X through an eventfd (`VFIO_DEVICE_SET_IRQS`) and wait on it for the completion.
4. Write a page: what the kernel did for you (IOMMU domain, interrupt remapping, reset on
   release) and what would go wrong without an IOMMU.

Done when: a frame lands in your userspace buffer via DMA through the IOMMU, signalled by an
eventfd. This is the seed of Module 12's passthrough and Module 13's SPDK.

### Lab 11.7: The management path: hwmon, PMBus, fans

1. On the Pi, write a driver for the EMC2101 (compare with `emc2103.c` after): hwmon fan
   input, PWM output, temperature. Register it as a thermal cooling device and bind it to a
   thermal zone built from your BME280, with trip points in the DT. Watch the kernel run
   your fan curve with no userspace.
2. If your server exposes its PSU over PMBus on an accessible bus (or with a PMBus
   regulator evaluation board on the Pi): probe it with `i2cdetect` and `i2cdump`, then
   load the generic `pmbus` driver and read `sensors`. Read `pmbus_core.c` and write a
   variant for a device with one quirk (a wrong exponent, a missing page) to see how small
   a PMBus driver is.
3. A `leds` driver for a drive-bay activity LED on an FPGA GPIO with the `disk-activity`
   trigger.

Done when: the fan curve runs in-kernel from your sensor, `sensors` shows PSU telemetry,
and an LED blinks on disk activity.

## Problem set

1. Give a case where `dma_alloc_coherent` is wrong (hint: large, per-request buffers on a
   non-coherent SoC) and one where `dma_map_single` is wrong (hint: a descriptor ring the
   device writes asynchronously).
2. Your driver `ioremap`s a BAR and reads a status register in a loop with a plain pointer
   dereference and no `volatile`. What does GCC do? Now with `volatile` but no barrier on
   ARM: what can still go wrong relative to a DMA buffer you then read?
3. Write a DT node for a fan controller at I2C address 0x4c with an alert line on GPIO 17,
   and the YAML binding. Then describe the same device in ASL for ACPI.
4. Order the resource acquisitions in a `probe` for a PCIe device with MSI-X, DMA and a
   char device such that every failure path is correct with `devm_*` alone. Which one
   resource still needs explicit cleanup, and why?
5. Explain why a multi-queue NIC needs MSI-X and not MSI, in terms of what the driver does
   in each vector's handler and which CPU runs it.
6. A VF and a PF share physical hardware. What can a malicious guest with a VF do to the
   PF's traffic, and what does the hardware and the PF driver prevent?
7. Design an `ioctl` ABI for your FPGA device that can grow: structure versioning, size
   fields, reserved space, and how you would add a field without breaking a compiled
   userspace. Compare to how `drm` and `io_uring` do it.
8. NAPI: describe the sequence from an RX interrupt to the poll function to re-enabling
   interrupts, and what happens under sustained load.
9. Your prototype FPGA occasionally returns 0xFFFFFFFF from every register for one
   transaction. What in your driver should notice, and what should it do?

## Deliverables

- Five drivers with bindings, in your labs repo, each with a README, a test script and
  the sensor or device output.
- The VFIO userspace program and its page of explanation.
- Traces, measurements and comparisons from Labs 11.4 and 11.5.

## Stretch

- Write a QEMU device model for your FPGA peripheral so the driver can be tested without
  the hardware; wire it to a socket that talks to the Verilator simulation of the RTL.
  This is a real technique for co-developing hardware and drivers.
- Implement SR-IOV enablement in your minimal NIC driver (or study `ixgbe`'s) and bind a
  VF to `vfio-pci`.
- Submit your EMC2101 or BME280 improvements upstream, or a binding fix.

## Next

Module 12: hypervisors. VFIO becomes passthrough; your kernel becomes a guest; your
Module 9 boot code runs inside a VM you created with `/dev/kvm`.
