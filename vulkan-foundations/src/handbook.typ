#import "lib/template.typ": *
#show: course-doc.with(unit: "0", title: "Handbook", short: "Handbook",
  subtitle: "How the course works, what you need, how GPUs and Vulkan fit together, and how to set up",
  chapters: ("The course", "How to work", "GPUs from the outside in", "Vulkan and OpenGL", "Setup", "Reference library", "Progress tracker"))
#contents()
#include "h/ch1-course.typ"
#include "h/ch2-working.typ"
#include "h/ch3-gpus.typ"
#include "h/ch4-opengl.typ"
#include "h/ch5-setup.typ"
#include "h/ch6-library.typ"
#include "h/ch7-tracker.typ"
