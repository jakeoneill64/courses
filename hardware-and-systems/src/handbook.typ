#import "lib/template.typ": *
#show: course-doc.with(unit: "0", title: "Handbook", short: "Handbook",
  subtitle: "How the course works, what to buy, how to set up the bench, and how to track your progress",
  chapters: ("The course", "How to work", "Safety on the bench", "The kit", "Setup", "Reference library", "Progress tracker"))
#contents()
#include "h/ch1-course.typ"
#include "h/ch2-working.typ"
#include "h/ch3-safety.typ"
#include "h/ch4-kit.typ"
#include "h/ch5-setup.typ"
#include "h/ch6-library.typ"
#include "h/ch7-tracker.typ"
