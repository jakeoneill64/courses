#import "../lib/template.typ": *

= Linux device drivers <ch-drivers>

#chapter-meta(
  weeks: [5 weeks],
  builds: [Mainline TI drivers bound by overlay and read line by line; an upstream-ready OPT4048 IIO driver; an ADS1220 driver streaming the load cell through a data-ready trigger; an EMC2101 hwmon driver through which the kernel runs a fan curve; a regmap driver that makes your FPGA a gpiochip, interrupt controller and character device; a PCIe driver with MSI and DMA; a minimal 82599 driver and a VFIO userspace driver; an NVMe debugfs patch.],
  needs: [The Raspberry Pi 5 and its kernel tree from Chapter 4.2; TMP117, INA228 and OPT4048 (Adafruit 6335) breakouts; the ADS1220 load-cell rig from Lab 1.2.4; the EMC2101 breakout (Adafruit 4808) with the Noctua NF-A8 PWM fan and a 12 V bench supply; the ULX3S with Lab 2.2.5’s bitstream; logic analyser; QEMU; the lab server with the X520-DA2, its DAC and the P4510.],
)

#why[
  An OMH module is a Linux machine surrounded by hardware Linux must drive: fans and thermal sensors, power monitors, PSUs on PMBus, drive-bay signals, the management board, NICs, NVMe drives and FPGA glue logic. Some of it has upstream drivers; the rest will be OMH's to write and maintain. The thread that began with the register map in Lab 2.2.4 ends here, with your FPGA presented as standard kernel devices, and the TI sensors from Chapter 1.3 become IIO and hwmon devices that OpenBMC can read. The PCIe and VFIO labs are the base of Compute's device passthrough in Chapter 4.4.
]

#skip-test(
  rule: [If all five are easy, do Labs 4.3.2, 4.3.5 and 4.3.8 only.],
  [For an I#super[2]C sensor on the Pi, which `bus_type` is involved, how did the device come to exist, how was the driver matched, and what does `probe` receive?],
  [When is `dma_alloc_coherent` correct and when `dma_map_single`, what does the IOMMU change, and what bug appears on a non-coherent Arm SoC that x86 hides?],
  [Write a device-tree node for an SPI ADC with its data-ready line on a GPIO. What validates the binding, and what validates the node?],
  [MSI, MSI-X and INTx: what does the driver do differently for each, and why does a multi-queue device need MSI-X?],
  [Why must an `ioremap`ped BAR be accessed with `readl` and `writel` instead of through the pointer, and what does `writel` do on Arm that a plain store does not?],
)

== Core ideas

*A driver is glue between a bus and a subsystem.* The bus (platform, I#super[2]C, SPI, PCI) discovers a device or is told about it and calls a matching driver's `probe`; the subsystem (IIO, hwmon, gpio, net, block) presents the device to userspace through a standard ABI. Chapter 4.2 showed the machinery. The driver supplies ID tables (`of_match_table`, `i2c_device_id`, `pci_device_id`) and a `probe` whose managed `devm_*` resources need no unwinding, returning `-EPROBE_DEFER` while a regulator, clock or IIO channel it needs is missing. Good drivers are thin: the mainline TMP117 driver is about 250 lines.

*Device tree and bindings.* Undiscoverable hardware is a device-tree node with `compatible`, `reg`, `interrupts`, `*-supply`, `*-gpios` and its own properties, linked to other nodes by phandle. Each binding is a YAML schema under `Documentation/devicetree/bindings/`; `make dt_binding_check` checks schemas and `make dtbs_check` checks trees against them. On the Pi, an overlay compiled with `dtc -@` and loaded by `dtoverlay=` in `config.txt`, or from U-Boot as in Lab 2.7.5, targets the board's `i2c_arm`, `spi0` and `gpio` labels. On an ACPI server the device arrives through `_HID` and `_CRS`, or `PRP0001` with a `_DSD` carrying the same `compatible`, so a driver using `device_property_*` serves both.

#fig("/figures/u4-drivers-binding.svg", caption: [One overlay, three mainline drivers and yours, linked by phandles; at run time the kernel alone runs the fan curve. Lab 4.3.4 builds this.])

*Buses and regmap.* I#super[2]C offers `i2c_transfer` and SMBus helpers; SPI offers `spi_sync` over a list of transfers. Above both, you declare to regmap the register and value widths, flag bits, padding, volatile registers and cache, and it does the framing, locking, caching and a debugfs dump. `regmap-irq` builds an interrupt controller from status and mask registers and `gpio-regmap` builds a gpiochip, so a driver for simple glue logic can be a few dozen lines.

*Interrupts.* `request_threaded_irq` splits a handler into a hard part that runs with interrupts disabled and a thread that may sleep. A chip behind I#super[2]C or SPI is reachable only from the thread, so an interrupt controller behind such a bus records mask changes, writes them in `irq_bus_sync_unlock`, and dispatches with `handle_nested_irq`. An IRQ domain maps its hardware interrupt numbers to Linux ones, so another driver, or `gpiomon`, can take an interrupt from an FPGA pin.

*Subsystems are ABIs.* An IIO channel has a type, an optional modifier such as `IIO_MOD_X`, and attributes such as `raw`, `scale` and `processed`, so userspace computes real units without knowing the part. Buffered capture adds a trigger whose top half stores a timestamp and whose thread reads the device and pushes a scan with `iio_push_to_buffers_with_ts`. hwmon uses a fixed vocabulary (`temp1_input` in millidegrees, `fan1_input` in RPM, `pwm1` from 0 to 255) that `sensors` and OpenBMC's sensor daemons read, and Redfish reports through them; the PMBus core makes a PMBus device into hwmon in a few dozen lines. The thermal framework joins sensors to cooling devices through zones and trip points in the device tree. When no subsystem fits, a misc character device with a versioned uAPI header is the fallback. sysfs is a stable ABI and debugfs is not.

#fig("/figures/u4-drivers-drdy.svg", caption: [A data-ready trigger on the ADS1220. The hard interrupt only takes a timestamp; the delay before the first clock grows with load, and one longer than a period loses a sample.])

*DMA and MMIO.* Devices see bus addresses, which are IOVAs behind an IOMMU. `dma_alloc_coherent` suits long-lived structures both sides write, such as descriptor rings; `dma_map_single` and `dma_map_sg` suit per-transfer buffers and hand ownership over explicitly, because on a non-coherent SoC the map, unmap and sync calls are where caches are cleaned and invalidated. x86 keeps DMA coherent in hardware, so a missing sync works there and corrupts data on a non-coherent Arm SoC. `dma_set_mask_and_coherent` declares the address bits a device drives. Registers are `ioremap`ped and accessed with `readl` and `writel`, volatile accesses with barriers: on Arm, `writel` orders an earlier descriptor write before the doorbell. PCIe writes are posted, so only a read-back proves a `writel` arrived.

*PCI, network, block and userspace drivers.* A `pci_driver` enables the device, maps its BARs, enables bus mastering, sets its DMA mask and asks `pci_alloc_irq_vectors` for MSI-X, MSI or INTx. MSI-X gives each queue of a multi-queue device its own vector, steerable to the CPU that owns the queue. `pci_error_handlers` recover from AER events, and `pci_enable_sriov` creates virtual functions, each with BARs and MSI-X vectors for a VM to own, as on the X520’s 82599. A network driver is a `net_device` with descriptor rings in coherent memory, NAPI polling under load, offloads and `ethtool` operations; `e1000e` shows the shape and `ixgbe` how much of a production driver is error handling. A block driver implements blk-mq's `queue_rq`; `drivers/nvme/host/pci.c` is your Chapter 4.1 driver grown up. UIO serves simple devices; VFIO hands a whole PCI device to a process (regions to `mmap`, interrupts as eventfds, DMA through an IOMMU domain it controls) through the container and group interface or through iommufd and `/dev/vfio/devices/vfioN`. QEMU, DPDK and SPDK take over devices this way, and so will your VMM in Chapter 4.4 and your data paths in Chapter 4.5.

*Robustness and upstreaming.* Time out every wait for hardware, write a reset path and exercise it, and bounds-check every value a device returns: a PCIe device that has dropped off the bus reads `0xFFFFFFFF`, and a prototype on SPI can return garbage for one transaction. KUnit tests logic in the kernel, kselftest tests behaviour from userspace, and QEMU device models and `i2c-stub` stand in for missing hardware. Upstream work has its tools (`checkpatch.pl`, `get_maintainer.pl`, `make W=1`, sparse) and its order: the binding before the driver, and a cover letter saying how you tested. Upstream drivers are the cheapest to maintain, because whoever changes a kernel API must fix every in-tree caller.

#fig("/figures/u4-drivers-ring.svg", caption: [An RX descriptor ring in the 82599’s terms: the driver posts buffers by advancing RDT, the NIC fills them and advances RDH, and NAPI cleans and refills. Lab 4.3.8 drives one.])

== Reading

- Corbet, Rubini and Kroah-Hartman, _Linux Device Drivers_, 3rd ed. (free): chapters 1 to 3, 5 to 10, 12, 14 and 15, for concepts. Bootlin's free driver labs on I#super[2]C, platform drivers, interrupts and DMA.
- Madieu, _Linux Device Driver Development_, 2nd ed.: the chapters on the device tree, I#super[2]C and SPI drivers, regmap, the IRQ framework, DMA and IIO.
- In the kernel's `Documentation/`: the IIO driver API with its triggered-buffer page, the hwmon kernel API and sysfs interface, the DMA API how-to, the PCI and MSI how-tos, VFIO, writing binding schemas, and submitting patches.
- In the kernel's source: `tmp117.c`, `ina238.c`, `opt4060.c`, `ti-ads131e08.c`, `emc2305.c`, `pmbus_core.c`, `regmap-irq.c`, the `e1000e` driver and the NVMe driver's `pci.c`. QEMU's `hw/misc/edu.c` with `docs/specs/edu.rst`.
- The OPT4048 (SBOSA84), ADS1220 (SBAS501) and EMC2101 datasheets; the Intel 82599 datasheet's sections on descriptors, MSI-X and SR-IOV; Emmerich et al., "User Space Network Drivers" (ANCS 2019), and its ixy code, an 82599 driver in about a thousand lines of C.

== Labs

The Pi labs build in the kernel tree you configured in Chapter 4.2, whose kernel refuses unsigned modules: build in the tree, where `make modules_install` signs them, or use `scripts/sign-file`.

#lab([Mainline TI drivers by overlay], time: [6 h], kit: [Pi 5, TMP117 and INA228 breakouts, the fan and bench supply from Lab 1.3.3.])[
+ Add this chapter's options to your Chapter 4.2 configuration fragments, merge them, rebuild and install:
  ```ini
  CONFIG_TMP117=m
  CONFIG_SENSORS_INA238=m
  CONFIG_GENERIC_ADC_THERMAL=m
  CONFIG_IIO_HRTIMER_TRIGGER=m
  CONFIG_I2C_STUB=m
  CONFIG_PMBUS=m
  ```
+ Extend your Lab 2.7.5 overlay: give the TMP117 the `vcc-supply` its binding requires, and add the INA228 (`"ti,ina228"`) with `shunt-resistor` in micro-ohms from your four-wire measurement in Lab 1.3.3 and `ti,shunt-gain` for your range. Find both in `dmesg`.
+ Read the TMP117’s `in_temp_raw` and `in_temp_scale` and the INA228 through `sensors`, and explain why `i2cget -y 1 0x48 0x0F w` is refused. Unbind both drivers, run your Python drivers from Labs 1.3.1 and 1.3.3 with the fan at three duties, rebind, and tabulate kernel against Python.
+ Annotate every function of `tmp117.c` and `ina238.c`. Find the SHUNT_CAL the driver writes and the current LSB it gives with your shunt, compare them with your Lab 1.3.3 calibration, and list what your Python drivers did that these do not, such as the TMP117’s alert and the INA228’s charge register.

#done-when(
  [Both devices bind from your overlay, and kernel and Python readings agree within the parts' resolution or each difference is explained.],
  [The annotations give the current LSB the driver uses with your shunt and every feature each driver omits.],
)
#evidence([Overlay, comparison table and annotated sources.])
] <lab-drv-mainline>

#lab([An upstream-ready IIO driver for the OPT4048], time: [2 weekends], kit: [Pi 5, OPT4048 breakout (Adafruit 6335), a desk lamp, a box that encloses both.])[
+ Learn from the datasheet (SBOSA84) the register map, each channel's exponent, 20-bit mantissa, counter and CRC, and the channel-1 lux equation. Its address table gives ADDR tied to VDD and to SCL the same address, so check yours with `i2cdetect`, then decode one `i2ctransfer` result by hand.
+ Write `ti,opt4048.yaml` with `compatible`, `reg`, `vdd-supply` and an optional `interrupts` until `make dt_binding_check DT_SCHEMA_FILES=ti,opt4048.yaml` is clean. Add the node to your overlay and check it with `make dtbs_check`.
+ Write `drivers/iio/light/opt4048.c` from the datasheet alone: 16-bit big-endian regmap; a device-ID check that fails `probe` clearly; continuous conversion with automatic range; raw `IIO_INTENSITY` channels with `IIO_MOD_X`, `_Y`, `_Z` and `IIO_MOD_LIGHT_CLEAR`; `integration_time`; a processed `IIO_LIGHT` channel in lux; CRC and stale-counter checks; `debugfs_reg_access`. Add a KUnit test of the decode and CRC that includes a corrupted word.
+ Only now read `opt4060.c` and `as73211.c`. The OPT4060’s register map is close to the OPT4048’s and a maintainer will ask why a new driver is needed, so decide between a new driver and extending `opt4060.c`, and make the series implement your decision.
+ Prepare the series (binding, driver, MAINTAINERS entry) clean under `checkpatch.pl --strict`, `make W=1` and `make C=1`, with recipients from `get_maintainer.pl` and a cover letter giving your testing and your decision. Make it with `git format-patch --cover-letter`, mail it to yourself, and apply it to a clean tree with `git am`.

#done-when(
  [The binding passes `dt_binding_check` and your node passes `dtbs_check`.],
  [In the closed box, the four raw channels match hand-decoded reads within 1 %, and the lux value equals the datasheet's conversion of the channel-1 code.],
  [The KUnit test passes, and the series passes all three checks and applies with `git am`.],
)
#evidence([The series as an mbox; the box measurements; the KUnit log; the register-map comparison.])
] <lab-drv-opt4048>

#lab([The ADS1220 over SPI: a data-ready trigger and a buffer], time: [1 weekend], kit: [Pi 5, the ADS1220 load-cell rig from Lab 1.2.4, logic analyser.])[
+ Write a binding for `ti,ads1220` with `spi-cpha` (only SPI mode 1 works), `interrupts` for DRDY and a `vref-supply` for the bridge excitation, and an overlay on `&spi0` chip select 0 that disables the `spidev` node there.
+ Write the driver. Regmap covers RREG and WREG with `read_flag_mask = 0x20`, `write_flag_mask = 0x40` and `reg_shift = REGMAP_UPSHIFT(2)`; other commands are plain SPI transfers. Expose your Lab 1.2.4 input with `raw`, a `scale` from the reference voltage and gain, `hardwaregain` and `sampling_frequency`, plus the internal temperature sensor; a direct read runs a single-shot conversion and waits for DRDY with a timeout.
+ Add buffered capture modelled on `ti-ads131e08.c`: continuous conversion from `preenable`, a trigger fired from the DRDY interrupt with `iio_trigger_poll`, and a handler that clocks out the three data bytes (no RDATA is needed after DRDY) and calls `iio_push_to_buffers_with_ts`. Keep the trigger to this device with `iio_trigger_validate_own_device`; under any other trigger, read with RDATA.
+ At 1,000 SPS, compare an hrtimer trigger made through configfs with DRDY: repeated and missed conversions and timestamp jitter, explained by the two clocks.
+ Stream the load cell with `iio_readdev` at 20 SPS with mains rejection and at 2,000 SPS in turbo mode, and compare the noise in grams with your Python driver's.
+ At 2,000 SPS, histogram the delay from DRDY falling to the first SCLK edge over a minute of logic-analyser capture, half of it under `stress-ng --cpu 4`.

#done-when(
  [At 2,000 SPS the scans read in a minute equal the DRDY pulses captured, and ten minutes of stream show no timestamp gap over 1.5 periods.],
  [The noise at 20 SPS matches Lab 1.2.4 within 10 %, both latency histograms are plotted, the triggers are compared in numbers, and the binding passes `dt_binding_check`.],
)
#evidence([Stream logs, histograms and the trigger comparison.])
] <lab-drv-ads1220>

#lab([Fan control: a hwmon driver, a thermal zone and PMBus], time: [2 weekends], kit: [Pi 5, EMC2101 breakout (Adafruit 4808), Noctua NF-A8 PWM fan, 12 V bench supply, the TMP117 and INA228 from Lab 4.3.1, logic analyser.])[
Mainline Linux has no EMC2101 driver, so you write it.

#safety[The breakout must never see the fan's 12 V. Feed the fan from the bench supply through the INA228 with a 0.5 A limit, connect only its PWM and tachometer wires to FAN and TACH (with the TACH pull-up jumper soldered), and join the grounds.]

+ Write `drivers/hwmon/emc2101.c`. `probe` checks the product ID at 0xFD (0x16, or 0x28 for the EMC2101-R) and the manufacturer ID at 0xFE (0x5D). Make the temperature, tachometer and status registers volatile, and read pairs in the datasheet's interlock order: diode high byte first, tachometer low byte first.
+ Register `temp1_input`, `temp2_input`, `temp2_fault`, `fan1_input` (5,400,000 divided by the tachometer count), `fan1_min`, `pwm1` from the 6-bit fan setting, `pwm1_enable` (1 manual, 2 the chip's look-up table) and `pwm1_freq`, and the look-up table as `pwm1_auto_point[1-8]_temp` and `_pwm` through `extra_groups`, since the info API has no type for it. Set the PWM for the 25 kHz 4-wire fans expect and record the duty resolution left.
+ Register a cooling device (`#cooling-cells = <2>`) and build the thermal zone of the figure above: the TMP117 through `generic-adc-thermal`, two active trips and a cooling map to your fan. The TMP117 node then needs `#io-channel-cells = <0>`, which its binding forbids: write the one-property binding patch that `dtbs_check` asks for.
+ Warm the TMP117 by hand, then with a hair dryer on low, and log temperature, cooling state, duty, RPM and fan power with no program of yours running. Check `fan1_input` against the tachometer on the logic analyser (two pulses per revolution), and run the look-up table alone through the forced-temperature register.
+ PMBus without a PMBus device: load `i2c-stub chip_addr=0x40`, preload READ_VIN (0x88), READ_IOUT (0x8C) and READ_TEMPERATURE_1 (0x8D) in LINEAR11 with `i2cset`, and read `pmbus_core.c`. Write a client driver whose `pmbus_driver_info` declares them on one page and whose `read_word_data` hook fixes a planted quirk (a READ_IOUT exponent one too small), and instantiate it with `new_device`.

#done-when(
  [`fan1_input` matches the tachometer within 2 % at three duties, `pwm1` controls the fan, and the chip's look-up table runs it alone.],
  [The thermal zone drives the fan from the TMP117 with no userspace program, logged with the fan's power; with your patch, `dtbs_check` is clean.],
  [`sensors` shows the stubbed PMBus values decoded correctly through your hook.],
)
#evidence([The binding patch; the thermal log; the PMBus driver and its `sensors` output.])
] <lab-drv-fan>

#lab([Your FPGA over SPI, through regmap], time: [2 weekends], kit: [Pi 5, the ULX3S with Lab 2.2.5’s bitstream, jumper wires, logic analyser.])[
+ Write a binding for `omh,fpga-glue` on `&spi0` chip select 1 (the ADS1220 holds 0) with `interrupts`, `gpio-controller`, `interrupt-controller` and `gpio-line-names`, adding `omh` to your tree's `vendor-prefixes.yaml`.
+ Describe Lab 2.2.5’s transaction format to regmap (widths, the read or write flag, `pad_bits` for turnaround, `reg_stride`, volatile status, input and timer registers, `REGCACHE_MAPLE` for the rest), or supply `reg_read` and `reg_write`. Fail `probe` cleanly on a wrong ID.
+ Write a `gpio_chip` by hand until `gpioset`, `gpioget` and `gpioinfo` work on FPGA pins. Add an `irq_chip` and IRQ domain on the pattern in the core ideas, with a threaded handler that reads and acknowledges the status register, until `gpiomon` sees FPGA edges. Rewrite both halves with `gpio-regmap` and `regmap-irq`, test both versions with one script, and compare line counts.
+ Expose the timer as a misc device: an `ioctl` for the compare value, defined in a versioned uAPI header, and `poll` that wakes on the compare interrupt.
+ Add a `gpio-leds` node on an FPGA pin with the `netdev` trigger on `eth0`, and find from the callers of `ledtrig_disk_activity()` why `disk-activity` stays dark for NVMe.
+ Toggle an FPGA output as fast as you can while `gpiomon` watches an input wired to it; find the rate at which events are lost, and where the time goes, with `trace-cmd record -e irq -e spi`.

#done-when(
  [`gpioset` drives an FPGA LED, `gpiomon` sees FPGA edges through your IRQ domain, and the compare interrupt wakes a process blocked in `poll`.],
  [Both driver versions pass the same tests, with line counts recorded.],
  [The LED follows Ethernet traffic, and the stress ceiling is measured with its bottleneck named.],
)
#evidence([Both driver versions, the uAPI header and the stress trace.])
] <lab-drv-fpga>

#lab([PCIe with MSI and DMA in QEMU], time: [1 weekend], kit: [QEMU with `-device edu`.])[
+ Read QEMU's `docs/specs/edu.rst` and write the register map in your notebook. Then write a `pci_driver` for 1234:11e8 that enables the device, maps BAR0, checks its identification register, sets the DMA mask and requests one MSI vector. The device clamps DMA addresses to 28 bits (its `dma_mask` property), so declare exactly that.
+ Compute factorials on the device behind a character-device `ioctl`, waiting for its interrupt.
+ DMA a coherent buffer into the device's 4 KiB buffer at 0x40000 and back, and verify it. Repeat from a user buffer with `pin_user_pages` and `dma_map_sg`.
+ Add timeouts and a reset path, patch `hw/misc/edu.c` to skip an interrupt now and then, and show the driver recovers.
+ Write a KUnit test for the pure logic and a kselftest script for the character device.

#done-when(
  [DMA round trips verify from both kinds of buffer, injected faults never hang the driver, and both test suites pass.],
)
#evidence([The QEMU patch; the log of injected faults and recoveries.])
] <lab-drv-edu>

#lab([NVMe, in the tree], time: [6 h], kit: [The server with the P4510, its root file system elsewhere so the NVMe modules can be reloaded.])[
+ Read `drivers/nvme/host/core.c` and `pci.c` beside your Chapter 4.1 driver, map your steps onto the kernel's, and list what it adds: namespaces, multipath, APST, reset work, polled queues, SGLs, the controller memory buffer.
+ Add a debugfs file showing each queue's depth and completion count, rebuild and reload only the NVMe modules, and watch it while `fio` runs random reads.
+ Run `trace-cmd record -e nvme` during `fio`, pair submissions with completions by queue and command ID, and compute the latency distribution.

#done-when(
  [Your debugfs file shows live queue state, and your latency distribution agrees with a `bpftrace` histogram of the same workload, made as in Chapter 4.2.],
)
#evidence([The patch; the trace script and its plot.])
] <lab-drv-nvme>

#lab([The 82599 in the kernel, then in userspace], time: [3 weekends], kit: [The server booted with `intel_iommu=on` and reachable through its on-board ports; the X520’s ports joined by the DAC.])[
+ Read `e1000e`'s probe, ring setup, transmit and NAPI poll, and draw the ring lifecycle.
+ Leave port 1 on `ixgbe` in a network namespace so that traffic crosses the cable, unbind port 0, and write a minimal driver for it from the 82599 datasheet (QEMU's `e1000` model is a gentler start): reset, link, one RX and one TX ring in coherent memory, MSI-X, `ndo_open`, `ndo_stop`, `ndo_start_xmit` and a NAPI poll calling `napi_gro_receive`. No offloads.
+ `ping` across the cable, watch `/proc/interrupts`, and add a few `ethtool -S` counters. Compare single-stream `iperf3` with `ixgbe` and explain the gap through offloads, ring sizes and interrupt moderation.
+ Bind port 0 to `vfio-pci` and check its IOMMU group; if port 1 shares it, bind both and transmit from your own program. In C, open the container and group, set the IOMMU type, get the device, `mmap` BAR0 and read the registers you read in Lab 2.4.4.
+ Map a buffer with `VFIO_IOMMU_MAP_DMA`, bring up one RX queue whose descriptors and buffers live in it (ixy does this in a few hundred lines), and receive a frame. Route an MSI-X vector to an eventfd with `VFIO_DEVICE_SET_IRQS` and block on it.
+ Port the program to iommufd (`/dev/vfio/devices/vfioN`, `VFIO_DEVICE_BIND_IOMMUFD`, `IOMMU_IOAS_ALLOC`, `VFIO_DEVICE_ATTACH_IOMMUFD_PT`, `IOMMU_IOAS_MAP`). Write a page on what the kernel did for you (IOMMU domain, interrupt remapping, reset on release) and what would happen without an IOMMU.

#done-when(
  [`ping` crosses the cable through your driver, and the throughput gap is explained in writing.],
  [A frame reaches your buffer by DMA through the IOMMU, signalled by an eventfd, with both VFIO interfaces, and the page is written.],
)
#evidence([The ring drawing; the throughput table; both VFIO programs with a hex dump of the frame; the page.])
] <lab-drv-82599>

== Problem set

+ Give a case where `dma_alloc_coherent` is wrong (large per-request buffers on a non-coherent SoC) and one where `dma_map_single` is wrong (a ring the device writes asynchronously), and what fails in each.
+ A driver polls an `ioremap`ped status register through a plain pointer. What does GCC do with the loop? With `volatile` but no barrier on Arm, what can still go wrong with a DMA buffer read after the status bit changes?
+ An OPT4048 channel returns EXPONENT = 6, RESULT_MSB = 0x123 and RESULT_LSB = 0x45. Compute the mantissa, the linear code and, for channel 1, the illuminance. How many bits must the raw value hold at the largest exponent, and how do you express the lux conversion as an IIO scale without floating point?
+ The ADS1220 runs at 2,000 SPS with a 4 MHz SPI clock. What fraction of a period does the 24-bit read take? A scan is a 32-bit sample and a 64-bit timestamp: how much buffer does a second need? At what DRDY-to-SCLK delay do samples start to be lost, and what does a lost sample look like in the buffer?
+ The EMC2101’s PWM frequency is 360 kHz divided by $2 times "PWM_F" times "PWM_D"$, with a duty resolution of $1 \/ (2 times "PWM_F")$. Choose register values for a 25 kHz fan, give the resolution left, and compute the speed for a tachometer count of 2,700. Then write the device-tree node for an EMC2101 at 0x4C with its ALERT/TACH pin as an interrupt on GPIO 17, its YAML binding, and the same device in ACPI ASL.
+ Order `probe`'s resource acquisitions for a PCIe device with MSI-X, DMA and a character device so that managed resources alone make every failure path correct. Which resource still needs explicit cleanup, and why?
+ Explain, from what each vector's handler does and which CPU runs it, why a multi-queue NIC needs MSI-X instead of MSI. Trace one RX interrupt through NAPI to re-enabling the interrupt, and say what changes under sustained load.
+ What can a malicious guest that owns an 82599 VF do to the PF's traffic and to other VFs, and what do the hardware and the `ixgbe` PF driver prevent?
+ Design an `ioctl` ABI for your FPGA device that can grow (versioning, size fields, reserved space) and add a field without breaking a compiled program; compare DRM and io_uring. If the prototype returns 0xFFFFFFFF from every register for one transaction, what in your driver should notice, and what should it do?

== Deliverables and stretch

*Deliverables.* Every driver and binding with its README, test script and recorded output; the OPT4048 series as an mbox ready to send, and the TMP117 binding patch; both VFIO programs and their page; the latency histograms, throughput comparison and NVMe trace analysis.

*Stretch.* Write a QEMU model of your FPGA peripheral that talks over a socket to the Verilator simulation of its RTL, so driver and hardware develop together. Add the TMP117’s ALERT pin to the mainline driver as IIO threshold events. Add SR-IOV to your NIC driver. Write an `nvme-lite` blk-mq driver for QEMU's NVMe device. Send the OPT4048 series, the binding patch or the EMC2101 driver upstream.

#checklist(
  [*Lab 4.3.1:* TMP117 and INA228 bound by overlay and matched to your Python drivers; both sources annotated.],
  [*Lab 4.3.2:* OPT4048 verified in the box; KUnit passing; the series clean and applying.],
  [*Lab 4.3.3:* 2,000 SPS with no lost samples; noise within 10 % of Lab 1.2.4; latency histograms.],
  [*Lab 4.3.4:* fan speed within 2 % of the tachometer; the fan curve run by the kernel; PMBus through your hook.],
  [*Lab 4.3.5:* FPGA gpiochip, IRQ domain and pollable timer, in both versions; the stress ceiling explained.],
  [*Lab 4.3.6:* edu DMA from both kinds of buffer; injected faults survived.],
  [*Lab 4.3.7:* live queue state in debugfs; trace latencies matching `bpftrace`.],
  [*Lab 4.3.8:* `ping` through your 82599 driver; a frame received through the IOMMU with both VFIO interfaces.],
  [*Problem set:* all nine answered; problems 3 to 5 checked numerically.],
  [*You can explain*, without notes: how a device-tree node becomes a probed driver, when DMA should be coherent and when streaming, why an interrupt controller behind SPI writes masks in `irq_bus_sync_unlock`, and what VFIO and the IOMMU each contribute.],
)
