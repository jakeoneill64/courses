#import "lib/template.typ": *
#show: course-doc.with(unit: "3", title: "Control, Radio and Boards", short: "Control, Radio and Boards",
  subtitle: "Motors, radio links, microwave radar, printed circuit boards and a drone that flies on them",
  chapters: ("Motors, estimation and feedback control", "Radio links", "Microwave synthesis and FMCW radar", "Board design and bring-up", "The drone: integration, test and flight"))
#contents()

#about-unit(unit: "3",
  intro: [Unit 3 is where the course's hardware meets physics you can see and hear. You write field-oriented motor control on a C2000, characterise an IMU and close attitude loops on a rig; build a packet radio below TI's stacks and prove its sensitivity; program a microwave synthesiser and configure TI's 60 GHz radar as an altimeter; design, fabricate and bring up four boards, two for the drone and two that become Module Zero's first node; and integrate everything into a quadcopter that hovers, holds altitude and reports telemetry over your own link.],
  rows: (
    ([3.1], [A thrust stand, FOC from scratch, an IMU noise model, an attitude estimator, PID on a rig], [4]),
    ([3.2], [A packet radio, a measured sensitivity waterfall, a telemetry protocol, an SDR demodulator], [3]),
    ([3.3], [A synthesiser you program, a measured chirp, an FMCW simulator, a radar altimeter], [3]),
    ([3.4], [Boards P, F, A and B, specified, reviewed, fabricated and brought up], [6 + fabrication]),
    ([3.5], [DShot, CRSF and the flight software; assembly, tuning, hover and altitude hold], [5]),
  ),
  before: [Set up the Windows PC before Chapter 3.2 and read the Handbook's safety rules on lithium packs and propellers before Chapter 3.1. Board A's specification can start as soon as Chapter 2.6 is done, to keep fabrication off the critical path.],
)

#include "u3/ch1-control.typ"
#include "u3/ch2-radio.typ"
#include "u3/ch3-radar.typ"
#include "u3/ch4-boards.typ"
#include "u3/ch5-drone.typ"

#signoff(unit: "3",
  chapters: ("Motors, estimation and feedback control", "Radio links", "Microwave synthesis and FMCW radar", "Board design and bring-up", "The drone: integration, test and flight"),
  review: (
    [Explain the drone's control loops from gyroscope to propeller, with their rates, delays and phase margins, using your flight logs.],
    [Explain how you proved your receiver's sensitivity, what limited the measurement, and how you knew the leakage was small enough.],
    [Derive an FMCW radar's beat frequency, then choose a chirp for a 15 m altimeter with 5 cm resolution and check it against the IWRL6432’s limits.],
    [Walk the bring-up of a new board from the microscope to running firmware, using one failure from your errata as the example.],
    [Present your flight-test report to someone who builds drones and answer their questions.],
  ),
)
