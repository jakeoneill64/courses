#import "lib/template.typ": *
#show: course-doc.with(unit: "3", title: "Synchronisation", short: "Synchronisation",
  subtitle: "Barriers, semaphores, fences, queues, frames in flight and render graphs, and how to prove them right",
  chapters: ("Why synchronisation is your job", "The dependency model", "Pipeline barriers in practice", "Fences, semaphores and events", "Queues and async compute", "Frames in flight", "Finding synchronisation bugs", "Render graphs"))
#contents()

#about-unit(unit: "3",
  intro: [Unit 3 makes synchronisation, the part of Vulkan where most programs go wrong, a skill you can apply with confidence. It starts by showing what the GPU does when nothing constrains it, builds the dependency model that every barrier, semaphore and fence is made of, and turns it into patterns for real command streams. It then covers the primitives between the host and the device and between queues, keeps several frames in flight safely, and catalogues the classic bugs with the tools that find them. It ends with a render graph that derives every barrier from declarations of what each pass reads and writes.],
  rows: (
    ([3.1], [A catalogue of nine hazards, each checked with and without its barrier], [4]),
    ([3.2], [Barriers derived from the model for a table of scenarios, chains and layouts], [6]),
    ([3.3], [A seven-pass pipeline with minimal barriers; the cost of barriers measured], [6]),
    ([3.4], [A host and device pipeline on a timeline semaphore; split barriers with events], [5]),
    ([3.5], [Uploads with ownership transfers; async compute overlap measured], [6]),
    ([3.6], [A simulation loop with one, two and three frames in flight], [5]),
    ([3.7], [Six classic synchronisation bugs, found and fixed], [6]),
    ([3.8], [A render graph with barrier derivation, memory aliasing and queue scheduling], [7]),
  ),
  before: [Finish Units 1 and 2. Keep the Vulkan specification's synchronisation chapter open throughout this unit.],
  needs: [The same machine and tools as Unit 2. A GPU with a separate compute or transfer queue makes Chapter 3.5's measurements more instructive.],
)

#include "u3/ch1-why.typ"
#include "u3/ch2-model.typ"
#include "u3/ch3-barriers.typ"
#include "u3/ch4-primitives.typ"
#include "u3/ch5-queues.typ"
#include "u3/ch6-frames.typ"
#include "u3/ch7-bugs.typ"
#include "u3/ch8-rendergraph.typ"

#signoff(unit: "3",
  chapters: ("Why synchronisation is your job", "The dependency model", "Pipeline barriers in practice", "Fences, semaphores and events", "Queues and async compute", "Frames in flight", "Finding synchronisation bugs", "Render graphs"),
  review: (
    [For any producer and consumer in Chapter 3.3's catalogue, write the barrier's masks and layouts from memory, and justify each with the dependency model.],
    [Draw Chapter 3.6's frame loop with three frames in flight, marking every wait and signal of the timeline semaphore and what each frame slot owns.],
    [Explain a queue family ownership transfer, release and acquire, and when an upload to another family needs none.],
    [Take a synchronisation validation report from your notebook and explain, line by line, the hazard and its fix.],
    [Derive by hand the barriers before two passes of the render graph's demonstration, and check them against its plan.],
  ),
)
