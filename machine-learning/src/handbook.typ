#import "lib/template.typ": *
#show: course-doc.with(unit: "0", title: "Handbook", short: "Handbook",
  subtitle: "How the course works, how to work, the maths you need, machines for machine learning, and setup",
  chapters: ("The course", "How to work", "The maths you need", "Machines for machine learning", "Setup", "Reference library", "Progress tracker"))
#contents()
#include "h/ch1-course.typ"
#include "h/ch2-working.typ"
#include "h/ch3-maths.typ"
#include "h/ch4-machines.typ"
#include "h/ch5-setup.typ"
#include "h/ch6-library.typ"
#include "h/ch7-tracker.typ"
