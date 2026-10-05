#import "../lib/template.typ": *

= The kit <h-kit>

Every item the course uses is listed below, by the unit that first needs it, with the exact product, part number, seller and price. The tables are generated from one file, `kit.yaml`, so the course and the shopping list cannot disagree. Each item's name links to the page that was checked; the seller links to the same page.

== How to read and use the tables

- *Prices* are for one unit, as the seller showed them on 4 October 2026. "inc VAT" prices include UK VAT; "+ VAT" prices (DigiKey UK, some distributors) exclude it, so add 20 %; "+ import VAT" items come from sellers outside the UK, and the courier collects import VAT and a handling fee on delivery. The Isle of Man is inside the UK VAT area, so UK sellers charge VAT as normal.
- *Quantities* are what the course needs. Where a lab consumes parts (an attenuator you might overload, a breakout you might damage), buy the spare the table suggests.
- *Stock moves.* Several items were back-ordered or sold out when checked; their notes give an alternative or a date. Check stock and price on the day you order.
- *Not verified* marks four items with no fixed listing. The used server and the used enterprise NVMe drive are bought second-hand: use the checklist later in this part, and expect to pay what a UK refurbisher charges. The small power bank and the isopropyl alcohol are bought locally, because couriers will not easily carry lithium cells or flammable liquids to the Isle of Man.
- *Delivery.* DigiKey UK delivers free above £65 before VAT, so batch DigiKey orders. Lithium batteries and 18650 cells travel by road courier only: confirm the seller delivers them to you before you order.
- *Optional* items are for stretch work or are alternatives to a required item. They are counted separately in the totals.

== When to order

#tbl(columns: (auto, 1fr), header: ([When], [What]),
  [Before Unit 1], [Everything in the Unit 1 table. Also the ULX3S (it ships from the United States), the LP-MSPM0G3507 (back-ordered when checked) and the Raspberry Pi SSD or its alternative (out of stock when checked).],
  [During Unit 1], [The rest of the Unit 2 table, including the used server, its NIC and the managed switch: Chapter 2.4 needs the server, and choosing a good one takes time.],
  [During Unit 2], [The Unit 3 table except the CM5. TI's motor, radio, synthesiser and radar boards had limited stock (the LVBLDCMTR had three at DigiKey), so order them early. Order the Windows PC before Chapter 3.2.],
  [During Chapter 3.4], [Board fabrication and the CM5 module, once Board B has passed its design review.],
  [During Unit 3], [The Unit 4 table.],
)

== Unit 1 kit

#kit-summary(unit: 1)
#kit-table(unit: 1)

== Unit 2 kit

#kit-summary(unit: 2)
#kit-table(unit: 2)

== Unit 3 kit

#kit-summary(unit: 3)
#kit-table(unit: 3)

== Unit 4 kit

#kit-summary(unit: 4)
#kit-table(unit: 4)

== Fabrication budget

Custom boards have no part number until you design them, so the course budgets for them instead. These are estimates for five boards of each design at a low-cost fabricator in late 2026, before delivery; get real quotes from your fabricator's website with your Gerber files, and log them for Chapter 4.6.

#tbl(columns: (auto, 1fr, auto), header: ([Board], [What is ordered], [Estimate]), align: (left, left, right),
  [P], [Two layers, 2 oz copper, bare boards; you solder the parts yourself], [£15 to £30, plus parts about £25 a board],
  [F], [Four layers, assembly of the IMU, barometer, flash and regulator; connectors hand-soldered], [£60 to £120],
  [A], [Four layers, assembly of the MCU, Ethernet magnetics and fine-pitch parts], [£90 to £180],
  [B], [Six layers with controlled impedance, assembly of the CM5 connectors and the M.2 slot], [£180 to £350],
)

== Buying a used rack server

The server is bought second-hand. A Dell PowerEdge R730 (2U) is the recommendation: quieter than the 1U R630, with full-height PCIe slots for the U.2 adapter. A Supermicro X11 board in a 2U chassis is the alternative. Search a UK refurbisher or eBay UK with terms such as `dell r730 e5-2680 v4 idrac8 enterprise`, filter to UK sellers that accept returns, and check sold listings to see what they really fetch.

#checklist(title: [Before you buy], intro: [Every line must be true of the listing, or confirmed by the seller in writing.],
  [The model and generation are clear from photographs or the service tag. Avoid the R620 and R720: an older generation with iDRAC7 and DDR3.],
  [The CPUs are Xeon E5-2600 v4 (Dell) or Xeon Scalable (Supermicro X11): both support VT-x, VT-d and SR-IOV. Both sockets are populated if you want every memory slot usable, with both heatsinks.],
  [At least 64 GB of registered ECC DDR4, with no mixed module types, shown in a photograph or a screenshot.],
  [The BMC licence is stated: iDRAC8 Enterprise on Dell, which you need for the remote console. Ask for the iDRAC or BMC firmware version; recent versions serve Redfish.],
  [A storage controller that can pass drives straight through (HBA330, H330, or H730 in HBA mode), with drive caddies.],
  [PCIe risers fitted, with a full-height slot for the U.2 adapter and a slot for the X520.],
  [Two power supplies and UK C13 mains leads.],
  [A TPM fitted, or a TPM header on the board. Dell 13th-generation TPM modules bind to the board they are fitted to, so buy one with the server or a new sealed module.],
  [Photographs of the iDRAC or BMC system summary with no hardware errors.],
  [Rails if you will rack it, and a delivery quote for 20 to 30 kg to your address.],
)

When it arrives, enable virtualisation, VT-d and SR-IOV in the BIOS, update the BIOS and iDRAC firmware, and record the service tag and every component in your notebook.

== Things you make

- *The load-cell and thrust stand (Labs 1.2.4 and 3.1.1).* Two blocks of 18 mm plywood to mount the bar, bolted with the screws the load cell's datasheet specifies, on a base heavy enough not to move: a 400 × 200 mm offcut of 18 mm plywood with the base block screwed down. A 120 × 120 mm plywood platform on the free end.
- *The one-axis rig (Labs 3.1.7 and 3.5.5).* An A-frame of 18 mm plywood about 400 mm tall carrying a 10 mm steel rod through two pipe clips, with the rod passing through the frame's centre plates; mechanical stops at ±30° made from two blocks.
- *The RF box (Lab 3.2.3).* Drill the die-cast box's end for the SMA bulkhead (a 6.5 mm hole for a 1/4-36 thread), fit the bulkhead with its washer for a ground contact, and tape the lid seam with copper tape.
- *The magnetometer mast (Lab 3.1.6).* A 10 mm wooden dowel or carbon tube at the height your measurements choose, with the LIS3MDL at its top and its cable twisted down the mast.
- *The tether (Lab 3.5.6).* 1.5 m of paracord tied to the frame's centre plates and to a 10 kg anchor such as a kettlebell or a bucket of sand.
