# ML Foundations

## Machine learning from the maths to a trained model, for the Oxford MSc in AI for Business

A self-directed, lab-driven course for one student: a strong software engineer with
good C++ who already understands gradient descent and backpropagation, has built some
neural networks, has a surface reading of transformers, and is heading into the Oxford
MSc in Artificial Intelligence for Business (Department of Computer Science with Saïd
Business School).

The course has two jobs. First, fill the two gaps you named: unsupervised learning, and
the practical craft of actually training networks that work. Second, make the Oxford
courses feel like revision rather than first contact. The MSc's machine-learning stream
is built from one-week intensives (Classical Machine Learning, Deep Neural Networks,
Generative AI with Large Language Models, Computer Vision, Edge AI, Knowledge Graphs,
Security and Privacy of ML, Human-AI Interaction), each assessed by a written assignment
that analyses a dataset and explains the methods chosen. Every module here ends with a
short write-up in that style so the habit is formed before you arrive.

---

## What you will have built

- k-means, Gaussian mixture EM, PCA and a matrix-factorisation recommender from scratch
  in NumPy, each checked against scikit-learn, then applied to real retail and ratings
  data with a defensible answer to "how many clusters" and "is this segmentation real".
- A training harness you wrote and trust: data pipeline, mixed precision, schedulers,
  checkpointing, experiment tracking, and a debugging checklist you have used to find
  three planted bugs. A ResNet trained on CIFAR-10 to above 93% from random init, with
  an ablation table showing what each trick was worth.
- A variational autoencoder with the ELBO derived by hand, a small diffusion model, a
  contrastive self-supervised encoder whose linear probe beats a supervised baseline
  trained on the same labelled fraction, and an anomaly detector on real fraud data.
- A GPT implemented from an empty file, trained on text, with a KV cache you added and
  a BPE tokeniser you wrote. Then a fine-tuned encoder for intent classification, a LoRA
  fine-tune of a small open LLM on your Mac, and a retrieval-augmented system with an
  evaluation set and numbers you can defend.
- Tabular models that beat sensible baselines on churn and marketing data, with
  calibration, SHAP explanations, an uplift model, and an A/B analysis with correct
  confidence intervals.
- A served model behind an HTTP API with drift monitoring, an ONNX export running from
  C++, a model card, and a one-page mapping of the system onto the EU AI Act's risk
  tiers.
- A capstone: an end-to-end business ML project with unsupervised, supervised and LLM
  components, a written report in Oxford assignment format, and a ten-minute talk.

---

## Structure

Four parts, fourteen modules plus setup, about nineteen weeks at 10 to 12 hours a week.
A ten-week fast track is below. Weeks are a guide, not a contract.

| # | Module | Weeks | Headline lab | Oxford course it feeds |
|---|--------|-------|--------------|------------------------|
| 0 | [Setup](00-setup.md) | 0.5 | Environment, GPU sanity check, labs repo, datasets cached | all |
| **I** | **Foundations, fast** | | | |
| 1 | [Maths and probability for ML](01-maths-and-probability-for-ml.md) | 1 | Derive cross-entropy from MLE; PCA via SVD; logsumexp and why | CML, DNN |
| 2 | [Classical supervised learning](02-classical-supervised-learning.md) | 1 | Beat a logistic baseline on churn with a tuned GBM, calibrated, with honest CV | CML |
| **II** | **Unsupervised learning** | | | |
| 3 | [Clustering and mixture models](03-clustering-and-mixture-models.md) | 1.5 | k-means and GMM-EM from scratch; segment real retail customers; prove the clusters are stable | CML |
| 4 | [Dimensionality reduction and embeddings](04-dimensionality-reduction-and-embeddings.md) | 1 | PCA, t-SNE, UMAP failure modes; a MovieLens recommender by matrix factorisation | CML, KDG |
| **III** | **Practical deep learning** | | | |
| 5 | [Training networks properly](05-training-networks-properly.md) | 2 | Your own harness; ResNet on CIFAR-10 above 93%; find three planted bugs; ablation table | DNN |
| 6 | [Convnets and transfer learning](06-convnets-and-transfer-learning.md) | 1 | Fine-tune a pretrained backbone on Oxford-IIIT Pets; augmentation study; Grad-CAM | DNN, VIS |
| 7 | [Autoencoders, VAEs and diffusion](07-autoencoders-vaes-and-diffusion.md) | 1.5 | Derive the ELBO; VAE with latent traversals; a small DDPM on MNIST | DNN, LLM |
| 8 | [Self-supervised learning and anomaly detection](08-self-supervised-and-anomaly-detection.md) | 1 | SimCLR on CIFAR-10 then a linear probe; fraud detection with isolation forest and an autoencoder | DNN, SPM |
| 9 | [Sequence models and transformers](09-sequence-models-and-transformers.md) | 2 | Attention in NumPy; GPT from scratch with your own BPE tokeniser and KV cache | DNN, LLM |
| 10 | [LLMs in practice](10-llms-in-practice.md) | 1.5 | Fine-tune an encoder on Banking77; LoRA a 0.5B model on your Mac; RAG with an eval set | LLM |
| **IV** | **ML in the business** | | | |
| 11 | [Reinforcement learning and bandits](11-reinforcement-learning-and-bandits.md) | 1 | Tabular Q-learning; REINFORCE on CartPole; a Thompson-sampling bandit against A/B | CML, LLM |
| 12 | [Experimentation, causality and interpretability](12-experimentation-causality-and-interpretability.md) | 1 | A/B analysis done right; uplift on Hillstrom; SHAP and a fairness audit | ABD, AIG |
| 13 | [ML systems and governance](13-ml-systems-and-governance.md) | 1 | Serve a model, monitor drift, run it from C++ via ONNX, write the model card | AIP, AIG, LRE |
| 14 | [Capstone](14-capstone.md) | 2 | End-to-end business ML project, report and talk | all |

Dependencies: 1 before everything; 2 before 3 and 12; 5 before 6, 7, 8, 9; 9 before 10;
3 and 4 before 8. Modules 11, 12 and 13 can be taken in any order after 10.

### Fast track (ten weeks)

If the MSc starts soon: do 0, 3, 4, 5, 7, 9, 10 in full; do only the headline lab and
the write-up for 2, 6, 8 and 12; skip 1 unless the Module 1 skip test hurts; skip 11
and 13; do a one-week capstone. That covers both named gaps and the material the
Classical ML, Deep Neural Networks and Generative AI courses assume.

---

## How to work the course

**Implement before you import.** Every core algorithm is written first in NumPy or bare
PyTorch and checked against the library version. Then use the library freely. The MSc
assignments reward explaining why a method works and why you chose it, and you cannot
explain what you have only called.

**Paper before blog post.** When a module names a paper, read the paper (at least the
abstract, method and main table) before any explainer. You will be reading papers on the
MSc with a week to absorb each course; practise now on classics with good explainers to
fall back on.

**Keep a lab notebook.** One markdown file per module in your labs repo. Record the
hypothesis, the run, the number, the gap. Loss curves and confusion matrices go in.
Every experiment gets a tracked run with its config; if you cannot reproduce a number,
it is not a result.

**Write it up.** Each module ends with a short write-up (500 to 800 words) in the shape
the Oxford assignments take: the problem, the data, the method and why it fits, the
results with an honest baseline, the limitations, what you would do next. Write for a
technical manager who will not run your code. This is the single most transferable
habit for the MSc.

**Take the skip test.** Each module opens with a skip test. If every question is easy
and you would be comfortable being interviewed on it, do only the headline lab and the
write-up. Your background means Module 1 and the first half of Module 5 may go fast; be
honest about Modules 3, 4, 7 and 8, which are where you said the gaps are.

**Cadence.** Two weekday evenings for reading, derivations and problem sets, one long
weekend session for the labs. Training runs that take an hour go on before dinner.

**Labs repo.** Create a separate repository, one package per module:

```
ml-course-labs/
  pyproject.toml           one environment for the whole course (see Module 0)
  common/                  your training harness, grows from Module 5 onward
  01-maths/                notebooks/, derivations.md
  02-tabular/              churn/, notebook.md
  03-clustering/           kmeans.py, gmm.py, retail/, notebook.md
  04-embeddings/           pca.py, mf.py, movielens/
  05-training/             harness/, cifar/, bugs/, ablations.md
  06-transfer/             pets/
  07-generative/           vae/, ddpm/
  08-selfsup/              simclr/, fraud/
  09-transformers/         attention.py, gpt/, bpe.py
  10-llms/                 banking77/, lora/, rag/
  11-rl/                   qlearn.py, reinforce.py, bandits.py
  12-causal/               ab/, uplift/, shap/
  13-systems/              serve/, onnx-cpp/, model-card.md
  14-capstone/
```

---

## Reference library

Buy or download up front; the module files say which chapters when. Everything marked
free is legally free online from the authors.

| Book, paper or course | Used in |
|---|---|
| Deisenroth, Faisal, Ong, *Mathematics for Machine Learning* (free) | 1, 3, 4 |
| Murphy, *Probabilistic Machine Learning: An Introduction* (free) | 1, 2, 3, 4, 7 |
| Murphy, *Probabilistic Machine Learning: Advanced Topics* (free) | 7, 8 |
| Bishop and Bishop, *Deep Learning: Foundations and Concepts* (free) | 5, 7, 9 |
| Hastie, Tibshirani, Friedman, *The Elements of Statistical Learning* (free) | 2, 3, 4 |
| James, Witten, Hastie, Tibshirani, *An Introduction to Statistical Learning with Python* (free) | 2 |
| Goodfellow, Bengio, Courville, *Deep Learning* (free) | 5, 7 |
| Zhang, Lipton, Li, Smola, *Dive into Deep Learning* (free, runnable) | 5, 6, 9 |
| Prince, *Understanding Deep Learning* (free) | 5, 7, 9, 11 |
| Howard and Gugger, *Deep Learning for Coders with fastai and PyTorch* (free) | 5, 6 |
| Karpathy, *Neural Networks: Zero to Hero* video series and nanoGPT (free) | 5, 9 |
| Jurafsky and Martin, *Speech and Language Processing*, 3rd ed. draft (free) | 9, 10 |
| Sutton and Barto, *Reinforcement Learning: An Introduction*, 2nd ed. (free) | 11 |
| Huyen, *Designing Machine Learning Systems* | 13, 14 |
| Huyen, *AI Engineering* | 10, 13 |
| Molnar, *Interpretable Machine Learning* (free) | 12 |
| Facure, *Causal Inference for the Brave and True* (free) | 12 |
| Kohavi, Tang, Xu, *Trustworthy Online Controlled Experiments* | 12 |
| Aggarwal, *Outlier Analysis*, 2nd ed. | 8 |
| Papers: Kingma and Welling 2013; Ho et al. 2020; Chen et al. 2020 (SimCLR); Vaswani et al. 2017; Hu et al. 2021 (LoRA); Lewis et al. 2020 (RAG); McInnes et al. 2018 (UMAP); Lundberg and Lee 2017 (SHAP) | 4, 7, 8, 9, 10, 12 |

---

## Progress

Tick as each module's "done when" criteria all hold and the write-up is in the repo.
Date it.

- [ ] 00 Setup: environment builds, GPU sanity check passes, datasets cached
- [ ] 01 Maths and probability for ML
- [ ] 02 Classical supervised learning
- [ ] 03 Clustering and mixture models
- [ ] 04 Dimensionality reduction and embeddings
- [ ] 05 Training networks properly
- [ ] 06 Convnets and transfer learning
- [ ] 07 Autoencoders, VAEs and diffusion
- [ ] 08 Self-supervised learning and anomaly detection
- [ ] 09 Sequence models and transformers
- [ ] 10 LLMs in practice
- [ ] 11 Reinforcement learning and bandits
- [ ] 12 Experimentation, causality and interpretability
- [ ] 13 ML systems and governance
- [ ] 14 Capstone: report submitted to yourself, talk recorded

---

## Conventions

Spelling is British. "The Mac" means your Apple Silicon machine; "the GPU" means its
MPS backend unless a module says CUDA. Python is 3.12, PyTorch is 2.x, scikit-learn is
1.5 or later. Commands assume zsh on macOS. Datasets are the free, public ones named in
each module; nothing needs a paid account, though a free Weights and Biases or Kaggle
account is used where noted. Oxford course codes (CML, DNN, VIS, LLM, LRE, KDG, SPM, HAI,
AIG, AIP, SLA, ABD) are from the Software Engineering Programme's subject list and are
used only to show what each module feeds.
