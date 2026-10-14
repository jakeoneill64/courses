import io
import os
from pathlib import Path

import numpy as np
from huggingface_hub import hf_hub_download

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get("AIF_DATA", ROOT / "data"))
RUNS = Path(os.environ.get("AIF_RUNS", ROOT / "runs"))

# Pinned so that every number in the course can be reproduced from the same bytes.
REVISIONS = {
    "roneneldan/TinyStories": "f54c09fd23315a6f9c86f9dc80f725de7d8f9c64",
    "ylecun/mnist": "77f3279092a1c1579b2250db8eafed0ad422088c",
    "uoft-cs/cifar10": "0b2714987fa478483af9968de7c934580d0bb9a2",
    "HuggingFaceTB/SmolLM2-135M": "93efa2f097d58c2a74874c7e644dbc9b0cee75a2",
    "HuggingFaceTB/SmolLM2-135M-Instruct": "12fd25f77366fa6b3b4b768ec3050bf629380bac",
    "HuggingFaceTB/SmolLM2-360M": "f8027fd0eaeea54caa13c31d31b9fdc459c38b49",
    "HuggingFaceTB/SmolLM2-360M-Instruct": "a10cc1512eabd3dde888204e902eca88bddb4951",
    "HuggingFaceTB/SmolLM2-1.7B-Instruct": "31b70e2e869a7173562077fd711b654946d38674",
    "HuggingFaceTB/smol-smoltalk": "f73fe857d519ff6ac5af2ea67c4d3834da7b8bcc",
    "HuggingFaceH4/ultrafeedback_binarized": "3949bf5f8c17c394422ccfab0c31ea9c20bdeb85",
    "allenai/ai2_arc": "210d026faf9955653af8916fad021475a3f00453",
    "rajpurkar/squad": "7b6d24c440a36b6815f21b70d25016731768db1f",
}


# snippet:begin fetch
def fetch(repo: str, filename: str, kind: str = "dataset") -> Path:
    target = DATA / repo.replace("/", "--")
    if (target / filename).exists():
        return target / filename
    path = hf_hub_download(
        repo, filename, repo_type=kind, revision=REVISIONS[repo], local_dir=target
    )
    return Path(path)


# snippet:end fetch


def _images(rows, column: str) -> np.ndarray:
    from PIL import Image

    return np.stack([np.asarray(Image.open(io.BytesIO(row[column]["bytes"]))) for row in rows])


def _parquet_images(
    repo: str, files: dict[str, str], image: str, label: str, cache: Path
) -> dict[str, np.ndarray]:
    if not cache.exists():
        import pyarrow.parquet as pq

        arrays = {}
        for split, name in files.items():
            rows = pq.read_table(fetch(repo, name)).to_pylist()
            arrays[f"x_{split}"] = _images(rows, image)
            arrays[f"y_{split}"] = np.array([row[label] for row in rows], dtype=np.int64)
        cache.parent.mkdir(parents=True, exist_ok=True)
        np.savez(cache, **arrays)
    with np.load(cache) as f:
        return {k: f[k] for k in f.files}


def mnist() -> dict[str, np.ndarray]:
    """Images as uint8 arrays of shape (n, 28, 28), labels as int64."""
    files = {
        "train": "mnist/train-00000-of-00001.parquet",
        "test": "mnist/test-00000-of-00001.parquet",
    }
    return _parquet_images("ylecun/mnist", files, "image", "label", DATA / "mnist.npz")


def cifar10() -> dict[str, np.ndarray]:
    """Images as uint8 arrays of shape (n, 32, 32, 3), labels as int64."""
    files = {
        "train": "plain_text/train-00000-of-00001.parquet",
        "test": "plain_text/test-00000-of-00001.parquet",
    }
    return _parquet_images("uoft-cs/cifar10", files, "img", "label", DATA / "cifar10.npz")


CIFAR10_CLASSES = [
    "airplane",
    "automobile",
    "bird",
    "cat",
    "deer",
    "dog",
    "frog",
    "horse",
    "ship",
    "truck",
]


def tinystories(split: str) -> Path:
    return fetch("roneneldan/TinyStories", f"TinyStoriesV2-GPT4-{split}.txt")


def model_files(repo: str) -> Path:
    for name in ("config.json", "tokenizer.json", "model.safetensors"):
        path = fetch(repo, name, kind="model")
    return path.parent
