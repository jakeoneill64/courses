#import "../lib/template.typ": *

= Representations <ch-representations>

#chapter-meta(
  time: [7 hours],
  builds: [A convolutional residual network trained on CIFAR-10 to over 90% in about twenty minutes; the space of features it learned, examined through nearest neighbours; contrastive learning, which learns features from unlabelled images by telling two views of the same image apart from all others; and a linear probe that measures how much each set of features knows.],
  needs: [Chapters 1.6 and 1.7.],
)

#why[
  A trained network is a classifier on top of a _representation_: everything below the last layer turns raw input into features in which the classes are easy to separate, and those features are often worth more than the classifier. They let similar inputs be found by comparing vectors, they transfer to tasks the network was never trained on, and, as this chapter shows, they can be learned without any labels at all. Unit 2's token embeddings and Chapter 3.7's text embeddings for retrieval are representations of the same kind, and Chapter 3.7 trains its embeddings with this chapter's loss.
]

#skip-test(
  rule: [If all four are easy, read the section on contrastive learning and do Labs 1.8.3 and 1.8.4.],
  [How many weights does a $3 times 3$ convolution from 64 to 128 channels have, and why so few compared with a dense layer between the same feature maps?],
  [What does data augmentation do to the training set, in terms of Chapter 1.6's ideas?],
  [Write down a contrastive loss for two views of each of $N$ images, and say what it rewards.],
  [What is a linear probe, and why is it used to compare representations?],
)

== Core ideas

=== Convolutions

Chapter 1.5's networks treated an image as a list of 784 numbers: shuffle the pixels in the same way for every image and they would learn exactly as well. That throws away what makes images images. Nearby pixels are related, and the same pattern means the same thing wherever it appears. A _convolutional layer_ builds both facts in. Each output is computed from a small neighbourhood of the input, here $3 times 3$ pixels across all input channels, and the same weights, the _kernel_, are applied at every position:

$ y_(c, i, j) = b_c + sum_(c') sum_(u, v in {-1, 0, 1}) w_(c, c', u, v) x_(c', i + u, j + v). $

A layer from 64 to 128 channels has $64 times 128 times 9 = 73{,}728$ weights whatever the image's size; a dense layer between the same $32 times 32$ feature maps would need over 8 billion. Sharing weights across positions makes the layer _equivariant_ to translation: shift the input and the output shifts with it. Stacking layers widens what each unit sees, its _receptive field_, and _pooling_, which keeps the largest value in each $2 times 2$ window, halves the resolution so that later layers see more of the image for the same cost.

#fig("u1-conv", width: 86%, caption: [A $3 times 3$ convolution: each output value is the weighted sum of a neighbourhood of the input, with the same kernel at every position.]) <fig-conv>

=== A network for CIFAR-10

CIFAR-10 has 60,000 colour images of $32 times 32$ pixels in ten classes: aeroplanes, cars, birds, cats, deer, dogs, frogs, horses, ships and lorries. This chapter's network is a small residual network known as ResNet9, from David Page's work on training CIFAR-10 quickly. Its building block is a convolution followed by Chapter 1.7's batch normalisation and a ReLU, and two such blocks with a residual connection around them:

#snippet("u1/vision.py", "conv-block", caption: [Convolution, normalisation, activation; and a residual pair])

#snippet("u1/vision.py", "network", caption: [ResNet9: four stages of growing width, and a linear classifier])

The network ends by taking each channel's largest value over the whole image, which makes its 512 features independent of where in the image a pattern appeared, and a linear layer turns them into ten logits. Those logits are scaled by $1\/8$: the max-pooled features are large, and without the scale the first steps at a learning rate of 0.2 produce huge logits and diverge.

Fifty thousand images are few for 6.6 million parameters. _Data augmentation_ manufactures more: every time an image is used, it is padded, cropped at a random offset and flipped left to right at random. A cat shifted by three pixels or seen in a mirror is still a cat, so the network is trained on many plausible images for each real one, which is regularisation in the sense of Chapter 1.6 that encodes knowledge about the task.

#snippet("u1/vision.py", "augment", caption: [Random crops and flips for a whole batch at once, on the GPU])

Training uses SGD with Nesterov momentum, weight decay, a learning rate that rises linearly for the first quarter of training and falls linearly to zero, and _label smoothing_, which trains towards a target that puts 0.82 on the true class and 0.02 on each other class instead of all of it on the true class, so the network gains nothing by pushing its logits towards infinity.

#snippet("u1/cifar.py", "train", caption: [Sixteen epochs on CIFAR-10])

#console(read("/src/console/u1-cifar.txt"), caption: [ResNet9 on CIFAR-10])

The network reaches 92.5% in sixteen epochs, about twenty-two minutes on the M2 Pro. Accuracy climbs unevenly while the learning rate is high, as at epoch 6, and steadily as it falls. The training loss ends near 0.96 and cannot go much lower: with label smoothing of 0.2, the entropy of the smoothed target, about 0.87 nats, is the least any prediction can score. David Page's version of the recipe, with more refinements and 16-bit arithmetic, reaches 94% in under a minute on a single data-centre GPU, a measure of what tensor cores are worth to convolutions.

=== The feature space

Remove the classifier and the network maps each image to a vector of 512 features. Normalised to unit length, the cosine similarity between two such vectors measures how alike the network considers two images, and the most similar images to a query are its _nearest neighbours_:

#snippet("u1/cifar.py", "neighbours", caption: [Five nearest neighbours of six test images, by cosine similarity])

#fig("u1-neighbours", caption: [Six test images, left, and the five test images whose features are most similar to each. The network was trained only to name ten classes, yet its neighbours share pose, colour and setting as well as class.]) <fig-neighbours>

Twenty-nine of the thirty neighbours share their query's class, and over 2,000 test images the nearest neighbour has the same class 89.6% of the time, although the network was trained only to name images, never to place similar ones together. The neighbours share more than the class: an aeroplane seen against the sky finds others against the sky, and a bird among leaves finds birds among leaves. The one mistake is the classic one, a fluffy brown dog whose neighbour is a long-haired cat.

Searching by similarity of learned vectors is the core of retrieval, and Chapter 3.7 does it with text.

=== Learning without labels

Supervised features need labels, and labels are expensive. _Contrastive learning_ learns features from unlabelled images with a task that the data supplies itself: make two random views of each image, and train the network to recognise which views came from the same image. The views are much stronger distortions than the ones used for classification: a random crop of between a fifth and all of the image, resized; a random flip; random changes of brightness, contrast and saturation; and sometimes a conversion to grey.

#snippet("u1/vision.py", "strong-augment", caption: [A random view: crop and resize, flip, colour changes, grey])

#fig("u1-views", caption: [Three training images, left, and six random views of each. Recognising that two views come from the same image requires features that ignore position, scale and colour, and keep shape and texture.]) <fig-views>

The encoder, ResNet9 without its classifier, maps every view to 512 features, and a small _projection head_ maps those to 128 dimensions where the loss is computed. For a batch of $N$ images there are $2 N$ views. Each view's _positive_ is the other view of its image; its _negatives_ are the remaining $2 N - 2$. The _InfoNCE_ loss, from Aaron van den Oord and colleagues, treats this as a classification among the other $2 N - 1$ views. With $z_i$ the normalised projection of view $i$, $j$ its positive and $tau$ a temperature,

$ cal(L)_i = -log exp(z_i dot z_j \/ tau) / (sum_(k != i) exp(z_i dot z_k \/ tau)), $

averaged over all $2 N$ views. It is Chapter 1.3's cross-entropy with similarities for logits:

#snippet("u1/contrastive.py", "info-nce", caption: [The InfoNCE loss over a batch of paired views])

#derivation[
  Write $p_(i k)$ for the softmax of $z_i dot z_k \/ tau$ over $k != i$. By Chapter 1.3's result, the gradient of $cal(L)_i$ with respect to the similarity $z_i dot z_k$ is $(p_(i k) - [k = j]) \/ tau$, and so, treating $z_i$ as free,
  $ (partial cal(L)_i) / (partial z_i) = 1 / tau (sum_(k != i) p_(i k) z_k - z_j). $
  Descent moves $z_i$ towards its positive and away from a weighted average of all candidates, weighted by how strongly the model currently confuses each with the positive. The most similar negatives, the hardest, receive most of the push, and a smaller temperature concentrates it further on them. An encoder that maps every image to the same vector makes all similarities equal and the loss $log(2 N - 1)$, its value at chance; the negatives are what make that collapse costly.
]

Training is the usual loop, with no labels anywhere:

#snippet("u1/contrastive.py", "simclr", caption: [Contrastive training: two views of each image, one loss])

=== Measuring a representation

A representation is good if a simple classifier can read the task off it. A _linear probe_ freezes the encoder, computes features for the labelled training set, and trains only a linear classifier on them; its test accuracy measures how linearly separable the classes are in the representation. The program probes three encoders with identical architecture: an untrained one, the contrastive one, and the supervised network's.

#snippet("u1/vision.py", "probe", caption: [A linear probe: standardised features, one linear layer, cross-entropy])

#console(read("/src/console/u1-contrastive.txt"), caption: [Linear probes of three encoders])

A probe on the untrained network already reaches 52%, five times chance: random convolutions followed by a maximum over positions still respond to colours, edges and textures, and those separate many images. Twenty epochs of contrastive learning, with no labels at all, raise it to 75%, more than half of the way to the 92% of the supervised network, which was trained on the very labels the probe is tested against. The InfoNCE loss, 6.9 nats at chance, is still falling at 3.2 when training stops: contrastive learning needs far longer runs and larger batches than supervised learning. SimCLR's authors trained for hundreds of epochs with batches of 4,096 images, and their largest networks' probes matched a supervised network's on ImageNet.

#keyidea[
  A network's value lies in its representation, the features its layers compute. Convolutions build in locality and translation equivariance; augmentation builds in invariances the task respects; and a contrastive loss can learn useful features with no labels at all, by asking which views of the data belong together.
]

#hazard(title: [Pitfall])[
  Batch normalisation computes statistics over a batch. If an image's two views are normalised together, apart from most of their negatives, a network can learn to match views by the statistics they share instead of by what they show. On one device, as here, every view shares one set of statistics and nothing leaks; training across several GPUs, each normalising its own share of the batch, must synchronise the statistics or shuffle samples between devices to prevent it.
]

#inpytorch[
  `torch.nn.Conv2d`, `MaxPool2d` and `AdaptiveMaxPool2d` are this chapter's layers. `memory_format=torch.channels_last` stores images as height, width, channels, the layout convolution kernels on GPUs prefer. `torchvision.transforms.v2` provides the augmentations ready-made, and `torchvision.models` and the `timm` library provide trained networks whose features are a common starting point for new tasks.
]

#reading(
  [Yann LeCun, Léon Bottou, Yoshua Bengio and Patrick Haffner, "Gradient-Based Learning Applied to Document Recognition", _Proceedings of the IEEE_ 86(11), 1998.],
  [David Page, "How to Train Your ResNet", Myrtle.ai, 2018: the ResNet9 design and fast training on CIFAR-10.],
  [Aaron van den Oord, Yazhe Li and Oriol Vinyals, "Representation Learning with Contrastive Predictive Coding", 2018: the InfoNCE loss.],
  [Ting Chen, Simon Kornblith, Mohammad Norouzi and Geoffrey Hinton, "A Simple Framework for Contrastive Learning of Visual Representations", ICML 2020.],
)

== Labs

#lab([What augmentation buys], goal: [Measure augmentation as regularisation.], time: [1.5 hours], code: "code/u1/cifar.py")[
  + Train ResNet9 three times: without augmentation, with crops only, and with crops and flips.
  + Record training and test accuracy at the end of each run.
  #done-when(
    [Your table has three rows with both accuracies.],
    [You can explain the change in the gap between them using Chapter 1.6's ideas.],
  )
  #evidence([The table and the explanation.])
]

#lab([Fast to 93%], goal: [Find the cheapest training that reaches a target.], time: [2 hours], code: "code/u1/cifar.py")[
  + Find the shortest training run on your machine that reaches 93% test accuracy, varying the number of epochs, the batch size, the learning rate and the widths.
  + Record every run's settings, time and accuracy.
  #done-when(
    [You have a run that reaches 93%, with its time.],
    [Your log shows which change saved the most time.],
  )
  #evidence([The log of runs.])
]

#lab([Which views matter], goal: [Find which augmentations contrastive learning depends on.], time: [2 hours], code: "code/u1/contrastive.py")[
  + Train the contrastive encoder for 10 epochs three times: with crops and flips only, with crops, flips and colour changes, and with every augmentation.
  + Probe each.
  #done-when(
    [You have three probe accuracies.],
    [You can explain, in terms of what the task can be solved by, why removing colour changes hurts.],
  )
  #evidence([The accuracies and the explanation.])
]

#lab([Few labels], goal: [See when features learned without labels pay off.], time: [1.5 hours], code: "code/u1/contrastive.py")[
  + Keep 50 labelled images per class. Train ResNet9 on those 500 images alone, and train a linear probe on the contrastive features of the same 500.
  + Compare both test accuracies with the probe trained on all 50,000 labels.
  #done-when(
    [Your table has three accuracies.],
    [You can state how many labels the contrastive features are worth, roughly, and how you would measure that more precisely.],
  )
  #evidence([The table.])
]

#problems(
  [How many weights does the first convolution of ResNet9 have? How many would a dense layer from a $32 times 32 times 3$ image to a $32 times 32 times 64$ feature map have?],
  [Follow the longest path through ResNet9 and compute the receptive field of a unit at the input to the final pooling layer. Does every unit see the whole image?],
  [The network's features are a maximum over all positions. Show that they are unchanged when the input is shifted by a multiple of eight pixels, ignoring the image's edges. Why not by one pixel?],
  [With a batch of 512 images, what is the InfoNCE loss of an encoder that maps every image to the same vector? Why can a projection to 128 dimensions not make every negative similarity equal to $-1$?],
  [A linear probe on an untrained encoder does far better than chance. What in a random convolutional network could make the classes partly separable?],
)

#checklist(
  [I can explain what convolutions build into a network and count their weights.],
  [I can train a convolutional network with augmentation and explain what each part of the recipe does.],
  [I can find nearest neighbours in a feature space and interpret them.],
  [I can derive the InfoNCE loss's gradient and train an encoder contrastively.],
  [I can compare representations with a linear probe.],
  [Lab 1.8.1–1.8.4 done-when criteria all hold, with evidence filed.],
)
