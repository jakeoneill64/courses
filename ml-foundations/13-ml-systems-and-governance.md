# Module 13: ML systems and governance

**Part IV · 1 week · Needs: Modules 2, 5 and 10. Data: Telco Customer Churn, CIFAR-10, the Module 10 RAG corpus.**

## Why this module

The model is a small part of a machine-learning system, and it is the part that gets all
the attention. Sculley et al. counted what surrounds it (data collection, feature
pipelines, serving, monitoring, configuration, and the glue between them) and found the
model to be a few percent of the code and less of the trouble. This module is about the
rest: getting a model into production, keeping it honest once it is there, and writing
down what it is for and not for, in a form a regulator, a customer and the engineer who
inherits it can use. It feeds three Oxford courses. AI in Practice is about deployment
realities; Edge AI is about running models under compute and memory constraints, which is
the ONNX and quantisation work here; and AI Governance wants model cards, risk tiers and
the vocabulary of the EU AI Act.

It is also where your C++ pays off. A ResNet exported to ONNX and run from a CMake
project against ONNX Runtime is a real deployment path for edge devices and for cost, and
you will benchmark it against PyTorch on your Mac's CPU and GPU. The habit of Module 5,
measure rather than assume, applies to latency exactly as it did to accuracy.

Structurally, Module 14 requires a served endpoint with a model card, drift monitoring
and a governance mapping. This module builds each part once so the capstone can assemble
them.

## Skip test

Answer cold, in writing.

1. Define training-serving skew, give two causes, and describe one test that catches it
   before a customer does.
2. What does an ONNX file contain? Name two PyTorch constructs that do not export cleanly
   and say how you verify an export is correct.
3. Write the PSI formula. What do 0.1 and 0.25 mean in practice, and why are most drift
   alerts pipeline failures?
4. Write FGSM. Why does a network at 94% on CIFAR-10 fall to near zero at ε = 8/255, and
   what does adversarial training cost?
5. Name the EU AI Act's risk tiers, list what Articles 9 to 15 require of a high-risk
   system, and classify a CV-screening model with a reason.
6. What should a reader of a model card be able to decide? Name its sections.

If all six are easy, do Labs 13.2 and 13.6 only, and the write-up.

## Core ideas

**The model is the smallest part of the system, and the system is where it fails.**
Sculley et al. named the debts: glue code, pipeline jungles nobody owns, undeclared
dependencies on upstream tables that change without notice, and feedback loops where the
model's outputs become its inputs. The commonest production bug is training-serving skew:
features computed at training time from a warehouse differ from those computed at request
time from live systems, in units, defaults, time zones or missing-value handling, and the
model quietly degrades. The defence is one feature function used in both places, tested.
Batch inference (score everyone nightly) and online inference (score on request) sit at
different corners of a latency, throughput and cost triangle; most business models are
batch, and the ones that need online serving need it for a reason you can state.

**A model is a file, and the file format decides where it can run.** A PyTorch state dict
needs the defining class and a Python runtime; a pickled pipeline is arbitrary code
execution on load and must never cross a trust boundary. `torch.export` captures the
graph as an intermediate representation; ONNX is the interchange format other runtimes
read, produced by `torch.onnx.export`, which since PyTorch 2.5 offers a dynamo-based
exporter alongside the legacy TorchScript tracer. Data-dependent Python control flow,
custom operators and some in-place patterns export wrongly or not at all, and dynamic
batch dimensions must be declared. An export is verified, never assumed: same inputs,
outputs within 1e-4, identical argmax over a thousand examples.

**ONNX Runtime is a C++ inference engine, and the C++ path is the deployment path.** It
loads the graph, applies graph optimisations (constant folding, operator fusion) and
dispatches to an execution provider: CPU by default, CoreML on Apple hardware, CUDA or
TensorRT on NVIDIA. Intra-op threads parallelise one operator, inter-op threads run
independent branches, and for single-image latency one thread often wins. A C++ program
against it has no interpreter, a small footprint and predictable latency, which is why it
runs on edge devices and saves money at scale. Python and C++ use the same engine; the
difference you measure in Lab 13.2 is tensor conversion overhead.

**Quantisation trades precision for speed and memory, and you must measure the trade.**
Dynamic int8 converts weights offline and activations on the fly, needs no data, and
suits MatMul-heavy transformers; on a convnet it does little. Static quantisation
calibrates activation ranges on a few hundred inputs and quantises convolutions too, for a
4× smaller file and typically 1.5 to 3× CPU speedup at under half a point of accuracy on
an image classifier; per-channel weight scales recover most of any loss. LLMs use int4
weight-only quantisation (GGUF, GPTQ, AWQ) because decoding is memory-bound. Pruning
rarely speeds up dense hardware; distillation trains a small student on a large
teacher's outputs, which is how DistilBERT exists.

**Serving is an API with a schema, and the schema is your first test.** A FastAPI service
declares the request as a pydantic model whose fields mirror the training features by
name, type and allowed values, so a string in a numeric field or an unseen category fails
with a 422 at the door instead of a wrong prediction downstream. Load the model once at
start-up, offer single and batch endpoints, return the model version with every
response, and give `/health` a canned prediction so the check exercises the model. For a
gradient-boosted model, per-request overhead is most of the latency, and batching
amortises it.

**ML code is tested like other code, plus four tests other code does not need.**
Invariance tests assert a prediction does not change when something irrelevant does (a
customer ID). Directional tests assert it moves the right way when something relevant
does (a higher monthly charge does not lower churn probability), and LightGBM's monotone
constraints can make that exact. Golden tests pin predictions on a fixed set so a refactor
cannot move them silently. A training smoke test on a few hundred rows asserts the loss
falls. Breck et al.'s ML Test Score lists 28 tests across data, model, infrastructure and
monitoring, scores each 0, 1 or 2 for absent, manual or automated, and takes the minimum
over sections; most teams that think they are at 5 are at 1.

**Monitoring asks whether the world still looks like the training set.** Per feature, the
population stability index PSI = Σ (p_i − q_i) ln(p_i/q_i) over bins of the reference
distribution, with 0.1 and 0.25 as conventional warn and act thresholds inherited from
credit scoring; Kolmogorov-Smirnov for continuous features, chi-square for categoricals.
Prediction drift on the score histogram catches what per-feature checks miss.
Performance monitoring is harder because labels arrive late or never: churn labels take a
month, fraud labels a dispute cycle, and a fraction never come, so you score the labelled
tail and watch proxies for the rest. Most alerts are pipeline failures (a unit change, a
new category, a null column) rather than the world changing, which is good news if the
alert fires and very bad if nothing does.

**Retraining is a policy, and deployment is a controlled experiment.** Scheduled
retraining is simple and wastes compute; triggered retraining is responsive and needs
monitoring you trust. Either way the challenger must beat the champion on recent labelled
data, then run in shadow (scoring live traffic without acting), then as a canary on a
fraction of requests, with a one-command rollback. MLflow's registry holds versions and
aliases such as `champion`; data is versioned by hash or DVC; the lock file pins the
environment; a result you cannot reproduce from those three is not a result.

**Documentation is for a decision, and two documents cover most of them.** A model card
(Mitchell et al.) states intended and out-of-scope use, training and evaluation data,
metrics disaggregated by the groups that matter, failure modes and ethical
considerations; its reader decides whether to use the model for their case. A datasheet
(Gebru et al.) does the same for a dataset: motivation, composition, collection,
preprocessing, recommended uses, maintenance; its reader decides whether to train on it.
Both are short, versioned with the model, and the first thing an auditor asks for.

**The EU AI Act (Regulation (EU) 2024/1689) sorts systems by risk, and obligations follow
the tier.** Article 5 prohibits a short list of practices (manipulative systems, social
scoring, most real-time biometric identification in public). Annex III lists the
high-risk areas: biometrics, critical infrastructure, education, employment (including
recruitment and CV screening), essential services (including creditworthiness, with an
explicit carve-out for fraud detection), law enforcement, migration, justice. Providers of
high-risk systems meet Articles 9 to 15: a risk-management system, data governance,
technical documentation, automatic logging, transparency to deployers, human oversight,
and accuracy, robustness and cybersecurity, plus conformity assessment; deployers have
duties under Article 26. Article 50 requires that people be told they are interacting
with an AI system and that synthetic content be marked. General-purpose AI models fall
under Chapter V, with documentation and copyright duties for providers (Article 53) and
more for systemic-risk models (Article 55). Everything else is minimal risk. Prohibitions
applied from February 2025, the general-purpose provisions from August 2025, most
high-risk obligations from August 2026; check the current timetable, since amendments
have been proposed.

**The other frameworks are voluntary, and a mature team uses them anyway.** The UK has no
AI statute and asks existing regulators to apply five principles (safety, transparency,
fairness, accountability, contestability). NIST's AI Risk Management Framework organises
the work into Govern, Map, Measure and Manage and is the common language of US
procurement. ISO/IEC 42001:2023 is a certifiable management-system standard, the ISO 27001
of AI, and what a large customer asks whether you hold. None says what a good model is;
all ask whether you can show your work.

**A model leaks its training data, and the attacks are practical.** Membership inference
(Shokri et al.) decides whether a record was in the training set from the model's higher
confidence on examples it has seen; it works best on overfit models and is a breach when
the data is medical or financial. Model extraction trains a copy through an API; model
inversion reconstructs representative inputs. Differential privacy is the formal answer:
M is (ε, δ)-DP if for all neighbouring datasets D, D' and outputs S, P[M(D) ∈ S] ≤
e^ε P[M(D') ∈ S] + δ, so no single record changes any output's probability by more than
e^ε. ε = 1 is strong; ε = 8 bounds the ratio at about 3,000 and is a guarantee mostly on
paper. DP-SGD clips per-example gradients and adds noise, at an accuracy cost that is
large on small data. Data minimisation is the cheapest defence and the one regulators ask
about first.

**Adversarial examples exist because networks are locally linear in high dimensions.**
FGSM (Goodfellow et al.) steps ε in the direction of the sign of the input gradient,
x' = x + ε·sign(∇_x L); with thousands of pixels each moved an invisible 8/255, the linear
change in the logit flips the class, and an undefended CIFAR-10 model falls from 94% to
near zero. PGD (Madry et al.) takes several smaller steps with projection back into the
ε-ball and is the standard strong attack. Adversarial training on PGD examples is the
only defence that has held, at several times the training compute and roughly ten points
of clean accuracy. The realistic threat for a business is not stickers on stop signs; it
is a fraud ring probing a scoring API and a content classifier under deliberate evasion,
which is why Module 8's fraud detector needs this more than Module 5's ResNet does.

**Forward links.** Module 14 assembles all of it: the capstone's model is served with a
schema, tested with golden and directional tests, monitored with PSI, documented with a
model card and a datasheet, and placed in an EU AI Act tier with the obligations that
follow.

## Reading

- Huyen, *Designing Machine Learning Systems*, ch. 1 (overview), 3 (data engineering),
  7-9 (deployment, monitoring and drift, continual learning).
- Sculley et al., "Hidden Technical Debt in Machine Learning Systems", 2015; Breck et
  al., "The ML Test Score: A Rubric for ML Production Readiness and Technical Debt
  Reduction", 2017; Paleyes, Urma, Lawrence, "Challenges in Deploying Machine Learning: A
  Survey of Case Studies", 2022.
- Mitchell et al., "Model Cards for Model Reporting", 2019; Gebru et al., "Datasheets for
  Datasets", 2021.
- Goodfellow, Shlens, Szegedy, "Explaining and Harnessing Adversarial Examples", 2015;
  Madry et al., "Towards Deep Learning Models Resistant to Adversarial Attacks", 2018.
- Shokri, Stronati, Song, Shmatikov, "Membership Inference Attacks Against Machine
  Learning Models", 2017; Dwork and Roth, *The Algorithmic Foundations of Differential
  Privacy* (free), ch. 1-2.
- Regulation (EU) 2024/1689 (the AI Act): Articles 5, 6, 9-15, 26, 50-55 and Annex III.
  Read the Articles, not a summary; they are shorter than you expect.
- NIST AI Risk Management Framework 1.0, 2023 (free); ISO/IEC 42001:2023, the overview
  and clause structure.
- ONNX Runtime documentation: the C++ API, execution providers, and the quantisation
  guide; the `torch.onnx` and `torch.export` documentation.

## Labs

Run `uv sync --group serve` and `brew install onnxruntime hey cmake` first.

### Lab 13.1: Serve the churn model

Goal: a production-shaped API for the Module 2 model, with numbers for its latency.

1. Register the Module 2 model: `mlflow.register_model(f"runs:/{run_id}/model", "churn")`
   and set the alias `champion`. `13-systems/serve/app.py` loads
   `models:/churn@champion` once in a lifespan handler.
2. `ChurnRequest(BaseModel)` with the nineteen Telco features typed exactly (`Literal`
   for categoricals, `Field(ge=0)` for numbers, `extra="forbid"`). Endpoints:
   `POST /v1/predict`, `POST /v1/predict/batch` for up to 1,000 rows, `GET /health`
   returning the model version and a canned prediction, `GET /v1/model` for metadata.
   Build the feature frame with the Module 2 preprocessing function imported, not
   rewritten.
3. Tests with `TestClient`: a string in tenure returns 422; a golden row matches the
   offline pipeline within 1e-6; a batch of 100 equals 100 single calls.
4. Load test: `hey -z 30s -c 50 -m POST -T application/json -D row.json
   http://127.0.0.1:8000/v1/predict`, again with `uvicorn --workers 4`, then the batch
   endpoint with 100-row bodies; report p50, p99 and requests per second. Expect several
   hundred requests per second from one worker with p50 under 100 ms; if you see 20, you
   are building a DataFrame per request or reloading the model.

Done when: the pytest suite passes; the load-test table (1 worker against 4, single
against batch) is in the notebook; `/health` reports the registry version.

### Lab 13.2: ONNX and C++ (headline lab)

Goal: the Module 5 ResNet running from a C++ binary, with parity proven and latency
measured across four runtimes.

1. `onnx-cpp/export.py`: load the CIFAR-10 checkpoint, `eval()`, export on the CPU with
   `torch.onnx.export(model, (x,), "resnet_cifar.onnx", dynamo=True,
   dynamic_shapes={"x": {0: torch.export.Dim("batch")}})`, or the legacy exporter with
   `dynamic_axes` and `opset_version=17` if the dynamo path fails on your version. Record
   which you used. Run `onnx.checker.check_model`.
2. Parity: `onnxruntime.InferenceSession` on the CPU provider against PyTorch fp32 on the
   CPU for 1,000 test images: max absolute logit difference under 1e-4 and identical
   argmax; then full test-set accuracy identical to the image.
3. `onnx-cpp/CMakeLists.txt` and `main.cpp` against the headers and library under
   `brew --prefix onnxruntime`: `Ort::Env`, `Ort::SessionOptions` with
   `SetIntraOpNumThreads`, `Ort::Session`; load a PNG with the single-header stb_image,
   resize to 32×32, normalise with the CIFAR mean and standard deviation into NCHW,
   `Ort::Value::CreateTensor<float>`, `session.Run`, argmax, print the class. Dump five
   test images as PNG with labels; the C++ predictions must match Python's.
4. Benchmark single-image latency (median of 1,000 after 50 warm-up) and batch-256
   throughput for C++ ONNX Runtime, Python ONNX Runtime, PyTorch CPU and PyTorch MPS.
   Expect low single-digit milliseconds per image on the CPU runtimes, C++ and Python
   within a few percent, and MPS slowest per image but fastest batched.
5. `onnx-cpp/quantize.py`: `python -m onnxruntime.quantization.preprocess` first, then
   `quantize_dynamic(..., weight_type=QuantType.QInt8)` and `quantize_static(...,
   calibration_data_reader=<500 training images>, quant_format=QuantFormat.QDQ,
   per_channel=True)`. For each: accuracy on the 10,000 test images, file size, and
   latency in C++ and Python. Expect static int8 within half a point of fp32 at 1.5 to 3×
   the CPU speed, and dynamic to change little on a convnet.
6. CoreML: `providers=["CoreMLExecutionProvider", "CPUExecutionProvider"]` in Python (the
   macOS wheel ships it) and time it; check `Ort::GetAvailableProviders()` in C++, since
   the Homebrew build may not include it.

Done when: the parity test passes under pytest; `cmake -B build && cmake --build build`
produces a binary that matches Python on the five PNGs; the benchmark table (four runtimes
× single and batched) and the quantisation table (fp32, dynamic int8, static int8:
accuracy, size, latency) are in the notebook with the exporter used stated.

### Lab 13.3: Drift monitoring

Goal: a monitor that fires on the right windows and stays quiet on the wrong ones.

1. `13-systems/monitor.py`: `psi(ref, live, bins=10)` with quantile bins from the
   reference and a 1e-4 floor to avoid log 0; `ks(ref, live)` via
   `scipy.stats.ks_2samp`; PSI over categories and chi-square for categoricals;
   `prediction_drift` on the score histogram; `report(ref_df, live_df, model)` producing a
   per-feature table with status ok, warn (PSI above 0.1) or act (above 0.25).
2. Reference is the Module 2 training set. Live windows: a random half of the test set
   (no drift; PSI under 0.05); tenure shifted down twelve months and clipped; contract
   mix moved to 70% month-to-month; a pipeline failure with MonthlyCharges divided by 100
   and a new categorical level. Show which alerts fire, and note that KS p-values are tiny
   at n = 3,000 for trivial shifts.
3. Performance under label delay: labels arrive 30 days after prediction and 20% never
   arrive. Plot what is computable each day for 90 days, and the proxies (mean score,
   score histogram) that are always computable.
4. `13-systems/retraining-policy.md`: triggers, cadence, the validation gate (the
   challenger beats the champion on the last three months of labels), shadow period,
   canary fraction, rollback.

Done when: pytest asserts PSI of two samples from one distribution is under 0.01, PSI of
a known shifted normal matches a hand-computed value within 0.01, and the unit-bug window
trips act; the drift report for the four windows is in the notebook; the policy exists.

### Lab 13.4: Tests for ML

Goal: a test suite for the churn pipeline that would catch the bugs that actually happen.

1. `13-systems/tests/`: `test_schema.py` (column set, dtypes, ranges, categorical
   domains, on a sample of the data); `test_transforms.py` (known input to known output,
   idempotence, no NaN out); `test_invariance.py` (changing customerID leaves the
   prediction identical); `test_directional.py` (for 200 sampled customers, raising
   MonthlyCharges 20% does not lower churn probability for more than 5% of them, or for
   none if you retrain with `monotone_constraints`); `test_golden.py` (50 stored rows and
   predictions, tolerance 1e-6, regenerated only with a version bump);
   `test_training_smoke.py` (train on 500 rows for 20 rounds, assert loss falls and both
   classes are predicted).
2. Score the pipeline against the ML Test Score's 28 tests at 0, 1 or 2 each, take the
   section minimum, and name the three cheapest points you are not collecting.

Done when: all suites pass in under 60 seconds; the rubric table with your score is in
the notebook.

### Lab 13.5: Adversarial robustness

Goal: measure how brittle the CIFAR-10 ResNet is and what robustness costs.

1. `13-systems/adversarial/attacks.py`: `fgsm(model, x, y, eps)` and `pgd(model, x, y,
   eps, alpha=eps/4, steps=10, random_start=True)`, on inputs in [0, 1] with normalisation
   inside the model wrapper so ε is in pixel units; clamp to the ε-ball and to [0, 1].
2. On 1,000 test images: clean accuracy, then FGSM and PGD at ε = 2/255, 4/255 and 8/255.
   Expect PGD to take the undefended model to near zero by 8/255 and FGSM to leave a
   little more. Plot an image, its perturbation scaled by 10, the adversarial image and
   the two labels.
3. Adversarial training from the trained checkpoint with PGD-7 at ε = 8/255 for five
   epochs (each about eight times a normal epoch; one to two hours on the Mac, or Colab).
   Report clean and PGD-10 accuracy: expect clean to fall by roughly 8 to 15 points and
   robust accuracy at 8/255 to rise to roughly 30 to 45%.

Done when: the accuracy table against ε for both attacks, before and after adversarial
training, and the figure are in the notebook; pytest asserts adversarial examples stay
within the ε-ball and within [0, 1].

### Lab 13.6: Documentation and governance

Goal: the four documents an auditor would ask for, written so a stranger could act on
them.

1. `13-systems/model-card.md` for the churn model, with Mitchell et al.'s sections and the
   Module 12 fairness table as the disaggregated metrics, by contract type, tenure band
   and senior-citizen status.
2. `13-systems/model-card-rag.md` for the Module 10 RAG system: intended users, corpus
   scope and date, retrieval and answer metrics from Lab 10.3, the injection results from
   Lab 10.6 as known failures, and out-of-scope uses.
3. `13-systems/datasheet-telco.md` following Gebru et al., honest about the fact that
   IBM's sample dataset has no documented provenance.
4. `13-systems/ai-act-mapping.md`: for the churn model used to prioritise retention
   offers, the Module 8 fraud detector, the RAG assistant for internal staff, and a
   hypothetical CV-screening model: the tier, the Article or Annex III point that puts it
   there, the obligations that follow, and what you would have to build. Then map the
   high-risk one onto NIST's four functions in a paragraph.

Done when: the four documents exist; a reader of the churn card could decide whether to
use the model on a new segment; the mapping cites Articles by number and concludes that
CV screening is Annex III high-risk, fraud detection is carved out of the creditworthiness
item, and the other two are minimal risk with Article 50 noted for the assistant.

## Problem set

1. A latency budget: 200 ms end to end, with 40 ms of network, a feature lookup from a
   key-value store and inference for a 20 MB gradient-boosted model. Estimate each stage,
   find the slack, and compute what batch size a target of 2,000 predictions per second
   implies for a single process at your measured per-call latency.
2. Derive PSI as a symmetrised KL divergence between binned distributions and compute it
   for reference bins (0.10, 0.20, 0.30, 0.25, 0.15) and live bins (0.15, 0.25, 0.30,
   0.20, 0.10). Say why the 0.1 and 0.25 thresholds are conventions rather than theorems,
   and what changes them.
3. Compute the memory of a 7B-parameter model at fp16, int8 and int4, and the upper bound
   on decoding tokens per second at 200 GB/s of memory bandwidth for each. Compare with
   what Ollama reports on your Mac for a model whose size you know.
4. Derive FGSM from the first-order Taylor expansion of the loss around x under an
   L∞ constraint ‖δ‖∞ ≤ ε, and show the sign of the gradient is the maximiser. State why
   the same argument gives δ ∝ ∇L/‖∇L‖₂ under an L₂ constraint.
5. Labels arrive 30 days after prediction and 20% never arrive. Over a 90-day window,
   what fraction of predictions can be scored on day 31, day 60 and day 90? Design the
   proxy metric you would monitor for the unscorable fraction and say what it can miss.
6. Explain ε in (ε, δ)-differential privacy in terms of an attacker's posterior odds that
   a record is in the dataset, and compute the maximum change in those odds at ε = 1 and
   ε = 8. State what δ permits.
7. Classify four systems into EU AI Act tiers with a sentence of justification each: an
   AI grading school essays, a model setting motor-insurance premiums, a chatbot
   answering questions about a retailer's opening hours, and a system ranking job
   applicants. List the Article 9 to 15 obligations for the high-risk ones.
8. Design the golden test that would have caught the label-shift bug from Module 5's bug
   hunt in production: what fixed inputs, what stored outputs, what tolerance, and when in
   the pipeline it runs.

## Deliverables

- `13-systems/serve/app.py` with its tests and the load-test table.
- `13-systems/onnx-cpp/export.py`, `quantize.py`, `bench.py`, `CMakeLists.txt`,
  `main.cpp` and the parity test.
- `13-systems/monitor.py` with tests and `retraining-policy.md`; `13-systems/tests/`
  with the six suites; `13-systems/adversarial/attacks.py` with its test.
- `13-systems/model-card.md`, `model-card-rag.md`, `datasheet-telco.md` and
  `ai-act-mapping.md`.
- Notebook with the load-test, benchmark, quantisation, drift and adversarial tables.
- Write-up on the ONNX and C++ deployment, following `writeup-template.md`. The
  Limitations section must engage with what a benchmark on one Mac does and does not say
  about a production target, and with what int8 accuracy on the test set says about
  robustness under drift.

## Stretch

- Export the Banking77 encoder to ONNX and serve it from C++; tokenisation is the hard
  part, and the `tokenizers` library's Rust bindings are one route.
- A membership-inference attack with shadow models on the CIFAR-10 ResNet; report attack
  AUC and how it changes with training epochs.
- DP-SGD with Opacus on a small MLP for churn; plot accuracy against ε from 0.5 to 8.
- A canary deployment: two model versions behind a router splitting traffic 90/10, with a
  live sample-ratio check and a scripted rollback.

## Next

Module 14 is the capstone. Everything in this module becomes a checklist item there: a
schema at the door, tests, a monitor, a model card, a tier. The two weeks are for the
project; the infrastructure should take a day because you have built it once.
