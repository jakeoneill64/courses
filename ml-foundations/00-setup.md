# Module 0: Setup

**Half a week. Do it in one sitting; the dataset downloads run while you read Module 1.**

## What this module buys you

An environment that builds from one file, a GPU path you have measured rather than
assumed, a labs repository with the shape the rest of the course expects, and every
dataset cached locally so a lab never stalls on a download. It also fixes two habits
early: every experiment is tracked, and every module ends in a write-up.

---

## Hardware

Your Mac (Apple M2 Pro, 32 GB unified memory) is enough for every lab in this course.
PyTorch's MPS backend runs on the GPU cores. Expect roughly a 5 to 10× speedup over the
CPU on convnets and transformers at the sizes used here; the smoke test below measures
yours. Three things to know about MPS before you hit them:

- No float64 tensors. Keep everything float32, and cast NumPy arrays explicitly.
- A few operators are unimplemented. Set `PYTORCH_ENABLE_MPS_FALLBACK=1` in your shell
  and PyTorch will run those on the CPU with a warning instead of crashing.
- Autocast to float16 works and roughly doubles throughput on large matmuls. bfloat16
  support depends on the PyTorch version; the smoke test reports which you have.

For the handful of runs that would take more than about two hours on the Mac (the full
ablation grid in Module 5, the longer SimCLR run in Module 8), use a free hosted GPU:
Google Colab or Kaggle Notebooks both give a T4 for free. Keep the code identical; only
the `device` string changes. The course never requires a paid GPU.

---

## Environment

One project, one lock file, for the whole course. Use `uv`; it is fast, handles Python
versions, and the lock file makes every result reproducible.

```bash
brew install uv
```

Create the labs repo from the starter files in this directory:

```bash
mkdir -p ~/code/ml-course-labs && cd ~/code/ml-course-labs && git init
cp ~/Desktop/ONeill-Website/ml-course/starter/pyproject.toml .
cp ~/Desktop/ONeill-Website/ml-course/starter/smoke_test.py .
cp ~/Desktop/ONeill-Website/ml-course/starter/cache_datasets.py .
cp ~/Desktop/ONeill-Website/ml-course/starter/notebook-template.md .
cp ~/Desktop/ONeill-Website/ml-course/starter/writeup-template.md .
uv python install 3.12
uv sync
```

`uv sync` installs the core group: NumPy, SciPy, pandas, scikit-learn, PyTorch with
torchvision, matplotlib, JupyterLab, MLflow, LightGBM, XGBoost, Optuna, UMAP, timm,
Gymnasium, SHAP, pytest and ruff. The `llm`, `causal` and `serve` groups are installed
when their modules arrive:

```bash
uv sync --group llm      # Module 9 onward: transformers, datasets, peft, sentence-transformers, faiss
uv sync --group causal   # Module 12: dowhy, econml
uv sync --group serve    # Module 13: fastapi, uvicorn, onnx, onnxruntime
```

Add to `~/.zshrc`:

```bash
export PYTORCH_ENABLE_MPS_FALLBACK=1
export TOKENIZERS_PARALLELISM=false
export HF_HOME=~/.cache/huggingface
```

Editor: VS Code or Cursor with the Python and Jupyter extensions, pointed at
`.venv/bin/python`. Or run `uv run jupyter lab`. Notebooks are for exploration; anything
you will run twice goes in a `.py` file with a `main()` and gets committed.

---

## Smoke test

```bash
uv run python smoke_test.py
```

It prints library versions, trains a small MLP on synthetic data on the CPU and on MPS,
checks the loss actually falls, times both, runs a convnet forward pass under autocast,
and reports whether bfloat16 is available. Read the output; the CPU-to-GPU ratio is your
first data point on where the course's compute will go.

---

## Experiment tracking

Use MLflow locally from day one; it needs no account. In every training script:

```python
import mlflow
mlflow.set_tracking_uri("file:./mlruns")
mlflow.set_experiment("05-cifar")
with mlflow.start_run(run_name=cfg.name):
    mlflow.log_params(vars(cfg))
    ...
    mlflow.log_metrics({"train_loss": loss, "val_acc": acc}, step=epoch)
```

and `uv run mlflow ui` to browse. If you prefer Weights and Biases, the free tier is
fine and the API is nearly identical; pick one and use it for everything. The rule is
that no number goes in a notebook or write-up without a run it came from.

---

## Datasets

Cache everything now so no lab waits on a download:

```bash
uv run python cache_datasets.py
```

The script fetches each dataset in its own try block and reports what succeeded. What
it pulls, and what each is for:

| Dataset | Source | Modules |
|---|---|---|
| California housing, Adult, Bank Marketing | scikit-learn / OpenML | 1, 2, 12 |
| Telco Customer Churn (IBM sample) | IBM's GitHub mirror, CSV | 2, 12, 14 |
| Online Retail II | UCI repository, id 502 | 3, 14 |
| MovieLens `ml-latest-small` and `ml-1m` | GroupLens | 4 |
| MNIST, Fashion-MNIST, CIFAR-10 | torchvision | 5, 7, 8 |
| Oxford-IIIT Pets | torchvision | 6 |
| Credit Card Fraud (ULB) | OpenML `CreditCardFraudDetection`, or Kaggle | 8 |
| Tiny Shakespeare, TinyStories (subset) | Karpathy's GitHub; Hugging Face | 9 |
| Banking77, IMDB, AG News | Hugging Face `datasets` | 9, 10 |
| Hillstrom email marketing challenge | MineThatData, CSV | 12 |

Two things are manual. Kaggle datasets need a free account and `~/.kaggle/kaggle.json`
if you go that route instead of OpenML. And for Module 10 install Ollama
(`brew install ollama`) and pull one small chat model and one embedding model:

```bash
ollama pull qwen2.5:1.5b
ollama pull nomic-embed-text
```

---

## Labs repo layout

```
ml-course-labs/
  pyproject.toml  uv.lock  smoke_test.py  cache_datasets.py
  data/                    gitignored; the cache script fills it
  mlruns/                  gitignored; MLflow's store
  common/                  the training harness, from Module 5 onward
  01-maths/ ... 14-capstone/
    notebook.md            lab notebook, from notebook-template.md
    writeup.md             the module write-up, from writeup-template.md
    *.py, tests/           code that runs twice lives here, with pytest tests
```

Add `data/`, `mlruns/`, `.venv/`, `*.ckpt`, `*.pt` and `wandb/` to `.gitignore`. Commit
the lock file.

---

## The two templates

**Lab notebook** (`notebook-template.md`): a dated entry per session with hypothesis,
what you ran (the MLflow run name), the number, and the gap between prediction and
result. It is deliberately terse. The habit that matters is writing the prediction
down before you look at the result.

**Write-up** (`writeup-template.md`): 500 to 800 words, six headings, written for a
technical manager who will not run your code. This is the shape of the Oxford
assignments. Do it for every module, even the ones you find easy; the point is fluency.

---

## Done when

- `uv run python smoke_test.py` passes on both CPU and MPS and you have written the
  speedup ratio and bfloat16 status in `00-setup/notebook.md`.
- `uv run python cache_datasets.py` reports success for everything except any Kaggle
  item you chose to skip.
- `uv run mlflow ui` shows the smoke test's run.
- The labs repo has its first commit, with the lock file in and `data/` ignored.
- `uv run pytest` runs (zero tests collected is fine) and `uv run ruff check .` is clean.

## Next

Module 1 is a fast pass over the maths that every later module leans on, pitched at
someone who already knows what a gradient is.
