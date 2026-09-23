# Module 6: Convnets and transfer learning

**Part III · 1 week · Needs: Module 5. Data: Oxford-IIIT Pets (torchvision); CIFAR-10 for the FLOP counter.**

## Why this module

Almost no business trains a vision model from scratch. The working pattern is to take
a backbone someone pretrained on ImageNet, replace its head, and fine-tune on a few
thousand of your own labelled images: defect photos, receipts, shelf images, scans.
Doing that well is a craft with a small number of decisions (which layers to unfreeze,
at what learning rates, with what augmentation, and how to tell whether the mistakes
are the model's or the labels'), and this module makes each decision once, with
numbers, on a dataset small enough to iterate on in minutes.

The Oxford Computer Vision week will move fast through architectures, detection and
segmentation; the Deep Neural Networks week assumes you can read a convnet diagram and
count its cost. So the first third of the module is convolution as arithmetic: output
sizes, receptive fields, parameters against FLOPs, and why a depthwise separable
convolution is eight times cheaper. You will be able to look at a model card and know
whether the model runs on a phone before anyone benchmarks it.

Structurally, this is where the Module 5 harness meets pretrained weights, and where
three later threads begin. Module 8 asks what pretraining looks like without labels.
Module 9 replaces the convolution with attention, and the Vision Transformer paragraph
here is the preview. Module 13 exports the model you fine-tune here to ONNX and runs it
from C++.

## Skip test

Answer cold, in writing.

1. A 3×3 convolution with stride 2, padding 1 and dilation 2 is applied to a 224×224
   map with 64 channels, producing 128. Give the output size, the parameter count and
   the multiply-accumulates.
2. What is a 1×1 convolution for? Write the cost of a depthwise separable 3×3
   convolution relative to a dense one and evaluate it for 256 channels.
3. You have 3,000 labelled images across 37 classes. Choose between a linear probe on
   frozen features, full fine-tuning and training from scratch; say what decides it and
   what learning rates you would use where.
4. You fine-tune a BatchNorm network with batch size 16 on a dataset unlike ImageNet.
   What goes wrong with the running statistics, and give two remedies.
5. Explain Grad-CAM in three sentences, including why a ReLU is applied to the map.
6. Validation accuracy is 93%, but two classes are confused with each other 30% of the
   time. Give three hypotheses and the check that distinguishes each.

If all six are easy, do Labs 6.3 and 6.4 only, and the write-up.

## Core ideas

**A convolution is a linear map with two constraints: locality and weight sharing.**
Each output pixel depends only on a k×k neighbourhood of the input, and every output
pixel uses the same k×k×C_in weights. Those constraints are the whole reason convnets
work on images: they bake in translation equivariance and cut parameters from
(H·W·C)² for a dense layer to k²·C_in·C_out, independent of image size. Lab 6.1 makes
the linearity concrete by unrolling the input into patches (im2col) so that the
convolution is one matrix multiply, which is also roughly how cuDNN and MPS compute it.
The output size is ⌊(H + 2p − d(k−1) − 1)/s⌋ + 1 for padding p, dilation d and stride
s; "same" padding with p = (k−1)/2 keeps the size at stride 1, and every stride-2 layer
halves it.

**The receptive field grows additively with kernel size and multiplicatively with
stride.** Track two numbers through the network: the receptive field r and the jump j
(the input-pixel distance between adjacent output pixels). A layer with kernel k and
stride s updates r ← r + (k−1)·j and j ← j·s. Stacked 3×3 convolutions grow r slowly
at stride 1 and fast after each downsampling, which is why almost all the receptive
field of a ResNet comes from its last two stages; ImageNet ResNet-18 ends at 435 pixels,
larger than the image. Dilation widens r without adding parameters or downsampling,
which segmentation networks use to keep resolution. The theoretical receptive field
overstates what the network uses: the effective receptive field is roughly Gaussian and
much smaller, which Lab 6.2 measures.

**Parameters and FLOPs are different quantities and diverge in opposite directions
through a network.** A 3×3 convolution costs k²·C_in·C_out parameters and
H_out·W_out·k²·C_in·C_out multiply-accumulates. Early layers have few channels and
large maps, so they dominate compute; late layers have many channels and small maps, so
they dominate parameters. ResNet-50's 25.6M parameters and 4.1 GMACs at 224×224 come
from different layers. Memory is a third axis: activations scale with H·W·C and are
what limits batch size during training. Pooling and strided convolution both
downsample; strided convolution costs parameters and learns the downsampling, and has
mostly replaced max-pooling in modern designs. A 1×1 convolution is a per-pixel linear
layer across channels: it changes channel count cheaply, mixes information after a
depthwise layer, and forms the bottleneck in ResNet-50's blocks.

**Depthwise separable convolutions buy most of the accuracy at a fraction of the
cost.** Split the 3×3 convolution into a depthwise 3×3 that filters each channel
separately (k²·C parameters) and a 1×1 pointwise that mixes channels (C_in·C_out). The
cost ratio to a dense convolution is 1/C_out + 1/k², about 1/8 for 3×3 at typical
widths (Problem 2). MobileNet is that observation applied throughout, with width and
resolution multipliers for trading accuracy against latency; it is the reason a
classifier runs at 30 frames per second on a phone, and the ancestor of everything the
Oxford Edge AI week deploys.

**The lineage is a sequence of one-idea-at-a-time changes.** LeNet (1998) established
the pattern of convolution, pooling and a dense head. AlexNet (2012) scaled it to
ImageNet with ReLU, dropout and two GPUs and won by a margin that ended the feature
engineering era. VGG (2014) showed that stacks of 3×3 convolutions beat larger kernels
at equal receptive field and that depth was the lever, at 138M parameters and 15.5
GMACs. ResNet (2015) made depth trainable with the identity shortcut from Module 5, and
ResNet-50's bottleneck block (1×1 down, 3×3, 1×1 up) is still the default backbone in
industry a decade later. EfficientNet (2019) searched for a small base network and
then scaled depth, width and resolution together by fixed ratios (compound scaling),
which gave a family with the best accuracy per FLOP of its time.

**ConvNeXt and the Vision Transformer are the two current endpoints, and they
converge.** The Vision Transformer (2020) cuts the image into 16×16 patches, embeds
each as a token, and runs a standard transformer encoder with no convolutions at all;
it has almost no built-in image prior, so it underperforms convnets on ImageNet-scale
data and overtakes them when pretrained on hundreds of millions of images. ConvNeXt
(2022) took a ResNet and adopted the transformer's macro-design choices one at a time
(patchify stem, 7×7 depthwise kernels, inverted bottleneck, LayerNorm, GELU, fewer
activations), and matched ViTs at equal compute with a pure convnet. The lesson is that
the training recipe and the macro-architecture mattered more than attention itself.
Module 9 builds the transformer; `timm` gives you both families with pretrained
weights, and `convnext_tiny` is the backbone this module uses.

**Transfer learning is the default, and it has three regimes chosen by data size and
similarity.** Feature extraction freezes the backbone and trains only a linear head on
pooled features; it is logistic regression on a learned representation (Problem 5),
trains in seconds, and works when your images resemble the pretraining data. Full
fine-tuning updates every weight and wins when you have thousands of labelled images or
the domain differs; Kornblith, Shlens and Le found it beats the linear probe on almost
every dataset and that better ImageNet models transfer better. Between them sits
partial unfreezing: train the head, then unfreeze the last stage, then the rest. Use
discriminative learning rates, roughly 10× lower for the backbone than the head,
because the pretrained weights are already good and large steps destroy them; warm up
and decay as in Module 5. BatchNorm complicates fine-tuning: the running statistics
belong to ImageNet, small batches make new estimates noisy, and the safe options are
to keep the backbone's BatchNorm in `eval()` mode (frozen statistics) or to use a
backbone with LayerNorm, which is one reason ConvNeXt fine-tunes easily.

**Augmentation at training time and at test time are different tools.** Training
augmentation regularises: RandomResizedCrop and flip are the baseline, RandAugment
adds colour and geometric operations, Mixup and CutMix mix examples. For fine-tuning on
a few thousand images over 10 to 15 epochs, crop and flip are worth about a point and
the stronger policies are close to neutral; they pay off in long runs. Test-time
augmentation averages predictions over deterministic transforms of each test image
(the image and its horizontal flip is the minimum) and buys a few tenths of a point at
twice the inference cost, which is a trade you would make in a batch pipeline and not
in a latency-bound API. Real image datasets are also long-tailed: the rare classes are
where errors concentrate and where accuracy hides them, so report per-class recall and
macro F1, and reach for class-balanced sampling, reweighting or logit adjustment when
the tail matters to the business.

**Grad-CAM shows where the evidence for a prediction came from.** Take the feature maps
A^k of the last convolutional stage (for ConvNeXt-T at 224, 768 maps of 7×7). The
weight of map k for class c is the spatial mean of the gradient of the class score,
α_k = (1/Z) Σ_ij ∂y^c/∂A^k_ij; the map is ReLU(Σ_k α_k A^k), upsampled to the input.
The ReLU keeps only regions that push the score up; regions that push it down belong to
other classes and would clutter the picture (Problem 6). It is coarse, at the
resolution of the last stage, and it is a faithfulness check rather than an
explanation: a map on the background when the prediction is right tells you the model
has learned a shortcut, which is exactly the finding you want before deployment.

**Error analysis starts with the worst losses and suspects the labels first.** Sort
the validation set by loss and look at the top 30 images: in a real dataset a good
fraction are mislabelled, ambiguous or corrupt, and no architecture change fixes that.
The confusion matrix names the pairs that are hard, and in Pets they are visually
similar breeds, not random. Data-centric ML is the discipline of improving the data
instead of the model, and confident learning is its main tool: estimate, with
out-of-fold predictions, the joint distribution of given and true labels, and flag
examples whose given label the model consistently rejects. With 10% uniform label
noise a fine-tuned model still trains well because it fits the clean majority first
and memorises the noise late, which is why the training-loss curve on noisy data has a
second drop that validation never shares (Lab 6.5).

**Detection and segmentation are the same backbones with different heads and
metrics.** Detection outputs boxes and classes: two-stage detectors propose regions and
classify them, single-stage detectors predict from a grid of anchors, and DETR treats
it as set prediction with a transformer and no anchors or non-maximum suppression.
Semantic segmentation classifies every pixel with an encoder-decoder such as FCN or
U-Net, whose skip connections carry resolution from encoder to decoder. The metrics are
intersection over union for a box or mask and mean average precision over IoU
thresholds for a detector. The Oxford Computer Vision week covers these; the point here
is to recognise that everything you learn about backbones, fine-tuning and Grad-CAM
transfers unchanged.

**Forward links.** Module 8 replaces ImageNet labels with a contrastive objective and
asks whether the linear probe still works; the probe you build here is the evaluation
it uses. Module 9 builds the transformer that the ViT paragraph previewed and Module 10
fine-tunes one with LoRA using the same discriminative-learning-rate logic. Module 13
exports this module's fine-tuned model to ONNX, runs it from C++, and writes its model
card, where the confusion pairs and Grad-CAM findings become the documented
limitations.

## Reading

- Zhang, Lipton, Li, Smola, *Dive into Deep Learning* (free), ch. 7 (convolutional
  networks), ch. 8 (modern convnets) and §14.1 to 14.2 (image augmentation and
  fine-tuning).
- Prince, *Understanding Deep Learning* (free), ch. 10 (convolutional networks).
- Howard and Gugger, ch. 5 to 7. They use the Pets dataset throughout; compare their
  numbers with yours.
- Krizhevsky, Sutskever, Hinton, "ImageNet Classification with Deep Convolutional
  Neural Networks", 2012; Simonyan and Zisserman, "Very Deep Convolutional Networks for
  Large-Scale Image Recognition", 2015; He, Zhang, Ren, Sun, "Deep Residual Learning
  for Image Recognition", 2015.
- Howard et al., "MobileNets: Efficient Convolutional Neural Networks for Mobile Vision
  Applications", 2017; Tan and Le, "EfficientNet: Rethinking Model Scaling for
  Convolutional Neural Networks", 2019.
- Liu et al., "A ConvNet for the 2020s", 2022; Dosovitskiy et al., "An Image is Worth
  16×16 Words: Transformers for Image Recognition at Scale", 2020. Read the ConvNeXt
  paper's roadmap figure closely; it is the lineage in one picture.
- Kornblith, Shlens, Le, "Do Better ImageNet Models Transfer Better?", 2019. Table 1 and
  the fine-tuning versus logistic regression comparison are the parts that matter.
- Selvaraju et al., "Grad-CAM: Visual Explanations from Deep Networks via
  Gradient-based Localization", 2017.
- Northcutt, Jiang, Chuang, "Confident Learning: Estimating Uncertainty in Dataset
  Labels", 2021.
- Parkhi, Vedaldi, Zisserman, Jawahar, "Cats and Dogs", 2012. The dataset paper; note
  what accuracy they reached in 2012 and with what.
- `timm` documentation: model names and pretrained tags, `create_model`,
  `forward_features`, and the training and fine-tuning scripts in the repository.

## Labs

### Lab 6.1: Convolution from scratch, then count everything

Goal: own the arithmetic of a convolution and the cost of a network.

1. In `06-transfer/conv.py` implement `conv2d_im2col(x, w, stride, padding, dilation)`
   in NumPy: build the patch matrix with `np.lib.stride_tricks.sliding_window_view`,
   reshape to (N·H_out·W_out, k²·C_in), multiply by the reshaped weights, reshape back.
   Test against `torch.nn.functional.conv2d` in float64 on the CPU to 1e-5 for stride 1
   and 2, padding 0 and 1, dilation 1 and 2, on random inputs of shape (2, 3, 16, 16)
   with 8 output channels.
2. Implement `count_params_flops(model, input_shape)` in `06-transfer/flops.py` with
   forward hooks on `Conv2d` and `Linear`, returning parameters and multiply-accumulates
   per layer and in total. Check it on `ResNet18CIFAR(64)` against your Module 5 figure
   (11.17M, about 0.56 GMACs at 32×32), on `timm.create_model("resnet50")` at 224
   (25.6M parameters, about 4.1 GMACs) and on `convnext_tiny` (28.6M, about 4.5 GMACs;
   your hook will need `Conv2d` with groups to count depthwise layers correctly).
3. Tabulate per-layer MACs and parameters for ResNet-50 and plot both against depth on
   log axes. Mark where each is concentrated.

Done when: the conv test and the three FLOP tests pass under pytest, and the plot shows
compute concentrated in the early stages and parameters in the late ones.

### Lab 6.2: Receptive fields and filters

Goal: know how far a unit sees, in theory and in practice.

1. Implement `receptive_field(layers)` applying the r and j recursion to a list of
   (kernel, stride, dilation) tuples, and compute the receptive field after each stage
   of ImageNet ResNet-18 (expect 435 at the end) and of `ResNet18CIFAR`.
2. Confirm empirically on a randomly initialised ResNet-18 with ReLUs replaced by
   identity: take one output unit in the centre of each stage's feature map,
   backpropagate a unit gradient to the input, and measure the extent of the nonzero
   region. Repeat with ReLUs in place and a pretrained network and plot the gradient
   magnitude as an image: the effective receptive field is roughly Gaussian and much
   smaller than the theoretical box.
3. Visualise the 64 first-layer 7×7 filters of pretrained `resnet50` as a grid, and the
   96 first-layer 4×4 patchify filters of `convnext_tiny`. Name what you see (edges,
   colour opponents, Gabor-like patterns) and what is different.

Done when: the analytic and empirical receptive fields agree for the linear network,
the effective-field figure is in the notebook, and the two filter grids are there with
a paragraph.

### Lab 6.3: Oxford-IIIT Pets, three ways (headline lab)

Goal: the from-scratch ceiling, the linear probe and the full fine-tune on one dataset,
with an augmentation ablation and honest error bars.

Data: `torchvision.datasets.OxfordIIITPet`, 37 breeds (25 dog, 12 cat), 3,680 trainval
and 3,669 test images of varying size, roughly 200 per breed. Split 680 images off
trainval as validation, stratified by breed. Resize to 224 with
`RandomResizedCrop(224, scale=(0.35, 1))` and flip for training, `Resize(256)` and
`CenterCrop(224)` for evaluation, ImageNet mean and std.

1. From scratch: `torchvision.models.resnet18(weights=None)` with a 37-way head,
   trained with the Module 5 harness and recipe (SGD nesterov, one-cycle, label
   smoothing, weight decay 5e-4) for 30 epochs at batch 64. Expect roughly 60 to 75%
   test accuracy; record it as the ceiling for this data size.
2. Linear probe: `timm.create_model("convnext_tiny.fb_in22k_ft_in1k", pretrained=True,
   num_classes=0)`, extract pooled features once for every image (3,680 × 768), then
   `LogisticRegression(C=1.0, max_iter=2000)` on standardised features with C chosen on
   the validation split. Expect roughly 88 to 93%. Repeat with `resnet50.a1_in1k`
   (2,048-dimensional features) for a second backbone.
3. Full fine-tune: the same ConvNeXt-T with `num_classes=37`, AdamW, head lr 1e-3 and
   backbone lr 1e-4, weight decay 0.05, 2-epoch warmup then cosine, 12 epochs at batch
   64, fp16 autocast, label smoothing 0.1. Expect roughly 92 to 95% top-1 and about 30
   to 90 s per epoch on the Mac. Log to MLflow under `06-pets`. Then repeat with the
   backbone frozen for the first 3 epochs and compare.
4. Augmentation ablation on the fine-tune, two seeds each: eval transforms only; crop
   and flip; crop, flip and `RandAugment(num_ops=2, magnitude=9)`; the previous plus
   Mixup with α = 0.2. Tabulate mean ± std.
5. Test-time augmentation: average the logits of each test image and its horizontal
   flip. Report the gain and the doubled inference time.
6. Report test accuracy with a 95% binomial confidence interval for the best model
   (with n = 3,669 and p near 0.94 it is about ±0.8 points) and say which differences
   in your tables are inside it.

Done when: the three regimes are in one table with seeds and confidence intervals, the
fine-tune reaches at least 92% test top-1, the augmentation table has four rows of mean
± std, and the TTA gain is reported with its cost.

### Lab 6.4: Grad-CAM and the confusion matrix

Goal: see what the fine-tuned model looks at, and where it fails.

1. In `06-transfer/pets/gradcam.py` implement `GradCAM(model, target_layer)`: a forward
   hook on `model.stages[-1]` storing the activations and a backward hook storing their
   gradient, a `__call__(x, class_idx=None)` that runs forward, backpropagates the
   chosen class score, computes the channel weights, and returns the ReLU-weighted map
   upsampled to 224×224 with bilinear interpolation. Test that the map is non-negative,
   the right shape, and that on an image with a pasted high-contrast patch that
   determines the label, the map peaks on the patch.
2. Produce overlays for 10 correct and 10 incorrect test predictions chosen by highest
   and lowest confidence, with the true and predicted breed in the title.
3. Compute the 37×37 confusion matrix on the test set, list the ten most confused
   pairs, and look at ten examples of the top pair. The classic confusions are
   American pit bull terrier with Staffordshire bull terrier and Ragdoll with Birman;
   say whether yours match and whether a human would do better.
4. Sort the test set by loss and inspect the top 30. Count how many are label errors,
   ambiguous images, or genuine model failures.

Done when: the twenty overlays and the confusion matrix are in the notebook, the
confusion-pair table has ten rows with a one-line diagnosis each, and the top-30 losses
are categorised with counts.

### Lab 6.5: Label noise and finding mislabels

Goal: measure what wrong labels cost and learn to find them.

1. In `06-transfer/pets/noise.py`, corrupt 10%, 20% and 40% of training labels
   uniformly at random (record which), fine-tune with the Lab 6.3 recipe, and plot test
   accuracy against noise rate with the clean run at zero.
2. Plot training loss per epoch for the 40% run against the clean run: the noisy run
   falls fast to a plateau while it fits the clean majority, then falls again as it
   memorises the noise, while its validation accuracy peaks early and declines. Mark
   the epoch at which memorisation starts.
3. Confident learning, on the 20% run: 5-fold cross-validated fine-tuning (3 epochs per
   fold is enough) to get out-of-fold predicted probabilities for every training image,
   rank by the probability assigned to the given label, and take the lowest 30. Report
   how many are your injected corruptions and inspect the rest by eye; some will be
   genuine label errors in the original dataset.
4. Repeat step 3 on the clean training set and inspect the lowest 30.

Done when: the accuracy-against-noise plot and the two-curve memorisation figure are in
the notebook, at least 24 of the 30 flagged images in the 20% run are injected
corruptions, and you have a list of suspected genuine mislabels in the original data.

## Problem set

1. Derive the output size ⌊(H + 2p − d(k−1) − 1)/s⌋ + 1 from first principles, then
   evaluate it for the skip-test layer. Show that "same" padding at stride 1 needs
   p = d(k−1)/2 and that for even k no integer p works.
2. Count parameters and multiply-accumulates for a 3×3 convolution from C_in to C_out on
   an H×W map, for its depthwise separable equivalent, and take the ratio. Evaluate it
   for C_in = C_out = 256 at 28×28. Which of the two terms in the ratio dominates and
   when would the other?
3. State the receptive-field recursion for r and j and apply it through ImageNet
   ResNet-18: 7×7 stride-2 stem, 3×3 stride-2 max-pool, then four stages of two 3×3
   blocks with the first convolution of stages 2 to 4 at stride 2. Give r after each
   stage and explain why the 1×1 shortcuts do not enter.
4. BatchNorm running statistics were estimated on ImageNet. Explain, in terms of what
   the layer computes in `eval()` mode, why fine-tuning on a small dataset with a
   different pixel distribution can leave the network worse than its `train()`-mode
   behaviour during training suggests. Give two remedies and the cost of each.
5. Show that a linear head on frozen pooled features trained with cross-entropy is
   multinomial logistic regression on those features. Using the fact that logistic
   regression in d dimensions needs on the order of d labelled examples per class to be
   well determined, say what this implies for 768-dimensional features and 100 images
   per class, and why regularisation strength C is the hyperparameter that matters.
6. Derive Grad-CAM's channel weights by writing the class score as a function of the
   feature maps and taking the gradient, and show that for a network whose head is
   global average pooling followed by a linear layer the weights equal the head's
   weights for that class (the CAM special case). Explain why the ReLU is applied after
   the weighted sum and not before.
7. With 3,680 training images and an augmentation policy that produces a fresh random
   view each epoch, how many distinct images does the model see in 12 epochs, and how
   many independent samples from the underlying distribution? Explain why augmented
   views are correlated samples and what that does to the effective sample size.
8. Estimate the activation memory of ResNet-50 at 224×224 and batch 64 in fp16 by
   summing the output sizes of every convolution, BatchNorm and ReLU that the backward
   pass must keep. State your assumptions about which tensors are saved, and check
   against the peak memory of one training step.

## Deliverables

- `06-transfer/conv.py` and `flops.py` with pytest tests against `F.conv2d` and the
  published timm parameter and MAC counts.
- `06-transfer/pets/train.py` (from scratch and fine-tune, one config flag apart),
  `probe.py`, `gradcam.py` and `noise.py`, with tests for the Grad-CAM shape and
  positivity and for the label-corruption bookkeeping.
- Notebook with all five labs' figures and the four tables.
- Write-up on the Pets fine-tune, following `writeup-template.md`. The Limitations
  section should engage with the confidence interval of a 3,669-image test set, with
  the possibility that the ImageNet-22k pretraining data contains images resembling the
  test set, and with what the confusion pairs say about the labels themselves.

## Stretch

- Distil the fine-tuned ConvNeXt-T into a MobileNetV3-Small with the same head
  (soft-label cross-entropy at temperature 4) and report accuracy against MACs for
  both; this is the Module 13 deployment trade in miniature.
- Few-shot: fine-tune with 5, 10 and 20 images per breed and plot accuracy against
  training-set size for the linear probe and the full fine-tune. Find the crossover.
- Zero-shot with CLIP (`open_clip`, ViT-B/32): classify Pets with the prompt "a photo of
  a {breed}, a type of pet" and compare with your linear probe. Then use the CLIP image
  features as the probe's input.
- Segmentation: Pets ships with trimap masks. Fine-tune a small U-Net or
  `torchvision.models.segmentation.fcn_resnet50` to predict them and report mean IoU.

## Next

Module 7 leaves labels behind entirely: autoencoders learn a representation by
reconstruction, the VAE makes that representation a probability distribution with the
ELBO you derived in Module 3, and a diffusion model generates images from noise. The
convolutional encoder and decoder it uses are the architectures from this module run
forwards and backwards.
