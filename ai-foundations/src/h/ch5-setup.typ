#import "../lib/template.typ": *

= Setup <h-setup>

This part sets up the companion code and checks your machine. It takes about an hour, most of it downloads.

== What you need

- *A computer with 16 GB of memory or more.* 32 GB is comfortable for Unit 3, which fine-tunes models with up to 360 million parameters and runs one with 1.7 billion. Part 4 says what each kind of machine can do.
- *A GPU, ideally.* An Apple Silicon Mac uses its GPU through PyTorch's Metal backend, MPS; a Linux or Windows machine with an NVIDIA GPU uses CUDA. Without a GPU, Units 1 and the C++ chapters run normally and the rest runs slowly, with smaller settings.
- *About 15 GB of free disk space* for the datasets, the models and the checkpoints your runs write.
- *A terminal and an editor.* Any editor with Python support will do.
- *For Chapters 4.6 and 4.7*, a C++20 compiler, CMake 3.25 or later and Ninja. *For the Vulkan track of Chapter 4.4*, the Vulkan SDK as set up in Part 5 of Vulkan Foundations' Handbook; the Metal track needs only macOS and the companion code.

== Python and uv

The course uses `uv`, a fast installer and environment manager for Python, to give everyone the same versions of everything. Install it from its website, or with Homebrew on macOS:

```bash
brew install uv
```

`uv` installs the right version of Python itself, so no separate Python installation is needed. Unpack the code archive, then from its folder:

```bash
cd ai-foundations/code
uv sync
```

`uv sync` reads `pyproject.toml` and the lock file `uv.lock`, creates a virtual environment in `.venv`, and installs Python 3.12, NumPy, PyTorch, the Hugging Face libraries used for downloads and for reference implementations, Matplotlib and SciPy, at exactly the versions this course was run with. Every program then runs through `uv run`, which uses that environment:

```bash
uv run -m u1.gradcheck
```

Programs are modules inside the packages `u1` to `u4`, so they are run with `-m` and a dotted name, from the `code` folder.

#snippet("pyproject.toml", "project", caption: [The project's dependencies], lang: "toml")

== The self-test

`aif.selftest` checks the installation: it reports the versions, the processor, the memory and the device PyTorch will use, multiplies matrices on the CPU and the GPU and checks the results, runs a gradient, checks that the data folders are writable, and, with `--download`, fetches MNIST and CIFAR-10.

#console(read("/src/console/h-selftest.txt"), caption: [The self-test on the M2 Pro])

If the device line says `cpu` on a machine with a GPU, PyTorch cannot see the GPU: on a Mac, check that you are running an arm64 build of macOS 14 or later; on Linux, that the NVIDIA driver is installed and `nvidia-smi` works. To force a device, set `AIF_DEVICE`, for example `AIF_DEVICE=cpu uv run -m u1.deep`.

== Data and models

Programs download what they need on first use, from the Hugging Face Hub, into `code/data`, at the exact revision recorded in `aif/data.py`. Nothing needs an account. Set `AIF_DATA` to put the data elsewhere, and `AIF_RUNS` for the folder where runs write checkpoints and logs.

#snippet("aif/data.py", "fetch", caption: [Every download goes through one function, pinned to a revision])

#tbl(columns: (1fr, auto, auto, auto), header: ([Dataset or model], [Size], [Licence], [Used in]), align: (left, right, left, left),
  [MNIST, handwritten digits], [18 MB], [MIT], [1.3–1.7],
  [CIFAR-10, small colour photographs], [144 MB], [none stated; distributed by its authors for research], [1.8],
  [TinyStories, synthetic children's stories, version 2], [2.25 GB], [CDLA-Sharing 1.0], [Unit 2, 4],
  [SmolLM2 135M, base and instruction-tuned], [540 MB], [Apache 2.0], [Units 2–4],
  [SmolLM2 360M, base and instruction-tuned], [1.45 GB], [Apache 2.0], [Units 3, 4],
  [SmolLM2 1.7B, instruction-tuned], [3.4 GB], [Apache 2.0], [3.6, 3.8, 4.8],
  [smol-smoltalk, conversations, one shard], [280 MB], [Apache 2.0], [3.2, 3.3, 3.6, 4.8],
  [UltraFeedback, binarised preference pairs], [233 MB], [MIT], [3.4],
  [ARC, science exam questions], [1 MB], [CC BY-SA 4.0], [3.6],
  [SQuAD 1.1, questions on Wikipedia paragraphs], [16 MB], [CC BY-SA 4.0], [3.7, 3.8],
)

The licences permit study and experiment. If you publish models you train on these datasets, check each licence's terms for redistribution; CDLA-Sharing and CC BY-SA ask that derived data be shared under the same terms.

== Troubleshooting

#tbl(columns: (1fr, 1.4fr), header: ([Symptom], [Cause and fix]),
  [`uv: command not found`], [`uv` installed to a folder not on your `PATH`. Open a new terminal, or follow the installer's instruction to add it.],
  [`ModuleNotFoundError: No module named 'aif'`], [The program was run from the wrong folder or without `-m`. Run `uv run -m u1.gradcheck` from the `code` folder.],
  [The device is `cpu` on a Mac], [The Python is an x86 build running under Rosetta. Delete `.venv` and run `uv sync` from a native arm64 terminal.],
  [`MPS backend out of memory`], [Another program holds GPU memory, or a batch is too large. Close other applications, or lower the batch: `--batch` in Units 1 and 2, `--batch-tokens` in Unit 3, where `u3.lora` prints the memory it uses.],
  [Downloads fail or stall], [A proxy or firewall blocks huggingface.co. Set `HF_ENDPOINT` to a mirror, or download the files listed in `aif/data.py` by hand into `code/data`.],
  [A program's check fails on your machine], [Compare your numbers with the console listing in the chapter. Small differences in timings and in the last digits of losses are expected; a failed check is not, and is worth a careful look before you continue.],
)
