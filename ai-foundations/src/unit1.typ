#import "lib/template.typ": *
#show: course-doc.with(unit: "1", title: "Learning Machines", short: "Learning Machines",
  subtitle: "Tensors, gradients, probability, optimisers, networks, generalisation and representations, built from first principles",
  chapters: ("Tensors and what they cost", "Gradients by machine", "Models as probability", "Optimisers", "Neural networks", "Generalisation", "Training deep networks", "Representations"))
#contents()

#about-unit(unit: "1",
  intro: [Unit 1 builds the machinery that every later model runs on. It starts with tensors and the cost of arithmetic on them, writes an automatic differentiation engine and grows it into `tiny`, a small tensor library, derives the standard losses from probability, implements the optimisers in common use and checks each against PyTorch's, and trains neural networks with them. It then studies why models generalise or fail to, why deep networks are hard to train and what makes them trainable, and ends with the representations that networks learn. Chapter 1.5 trains the same network in `tiny` and in PyTorch, and from Chapter 1.7 on, programs use PyTorch directly.],
  rows: (
    ([1.1], [Views and strides, broadcasting, and a matrix multiplication from loops to the GPU], [5]),
    ([1.2], [A scalar autodiff engine and `tiny`, a tensor library checked against PyTorch], [7]),
    ([1.3], [Regression three ways, softmax regression on MNIST, a stable softmax], [5]),
    ([1.4], [Six optimisers matched to PyTorch's, paths through a valley, a range test], [5]),
    ([1.5], [Initialisation measured through depth, and MNIST to 97% in `tiny` and PyTorch], [6]),
    ([1.6], [Overfitting cured four ways, and double descent reproduced], [5]),
    ([1.7], [A 30-layer network made trainable, normalisation by hand, three bugs found], [6]),
    ([1.8], [A convolutional network on CIFAR-10, embeddings and contrastive learning], [7]),
  ),
  before: [Read the Handbook, and run `uv run -m aif.selftest` from the companion code. The unit assumes the mathematics summarised in the Handbook's maths part: vectors and matrices, derivatives and the chain rule, and the basics of probability.],
  needs: [Any recent computer. Chapters 1.1 to 1.7 run on the CPU in minutes; Chapter 1.8 trains convolutional networks and wants a GPU, though a CPU will do with patience.],
)

#include "u1/ch1-tensors.typ"
#include "u1/ch2-autograd.typ"
#include "u1/ch3-probability.typ"
#include "u1/ch4-optimisers.typ"
#include "u1/ch5-networks.typ"
#include "u1/ch6-generalisation.typ"
#include "u1/ch7-deep.typ"
#include "u1/ch8-representations.typ"

#signoff(unit: "1",
  chapters: ("Tensors and what they cost", "Gradients by machine", "Models as probability", "Optimisers", "Neural networks", "Generalisation", "Training deep networks", "Representations"),
  review: (
    [Derive, on paper, the backward steps of matrix multiplication, broadcasting and log-softmax, and explain how `tiny` implements each.],
    [Derive the mean squared error and the cross-entropy from maximum likelihood, and say what each assumes about the data.],
    [Explain, with your Chapter 1.4 measurements, when momentum helps, when Adam helps, and what a learning-rate schedule is for.],
    [Explain why a 30-layer network fails to train with PyTorch's default initialisation, and what each fix in Chapter 1.7 changes.],
    [Describe how you would decide whether a model is overfitting, and four ways to reduce it, with the evidence from your Chapter 1.6 runs.],
  ),
)
