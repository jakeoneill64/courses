"""Downloads every dataset the course uses into ./data so labs never wait on the network.

Each fetch is independent; a failure is reported and the script moves on. Re-running is
cheap because every source caches.
"""

import shutil
import sys
import urllib.request
import zipfile
from collections.abc import Callable
from pathlib import Path

DATA = Path("data")
DATA.mkdir(exist_ok=True)
REPORT: list[tuple[str, str]] = []


def step(name: str, fn: Callable[[], None]) -> None:
    try:
        fn()
        REPORT.append((name, "ok"))
        print(f"  ok    {name}")
    except Exception as e:  # noqa: BLE001
        REPORT.append((name, f"FAILED: {type(e).__name__}: {e}"))
        print(f"  FAIL  {name}: {type(e).__name__}: {e}")


def download(url: str, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        with urllib.request.urlopen(url, timeout=120) as r, open(dest, "wb") as f:
            shutil.copyfileobj(r, f)
    return dest


def sklearn_sets() -> None:
    from sklearn.datasets import fetch_california_housing, fetch_openml

    home = str(DATA / "sklearn")
    fetch_california_housing(data_home=home)
    fetch_openml("adult", version=2, data_home=home, as_frame=True)
    fetch_openml("bank-marketing", version=1, data_home=home, as_frame=True)


def telco_churn() -> None:
    url = (
        "https://raw.githubusercontent.com/IBM/telco-customer-churn-on-icp4d/master/data/"
        "Telco-Customer-Churn.csv"
    )
    download(url, DATA / "telco" / "Telco-Customer-Churn.csv")


def online_retail_ii() -> None:
    url = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
    z = download(url, DATA / "retail" / "online_retail_ii.zip")
    with zipfile.ZipFile(z) as zf:
        zf.extractall(DATA / "retail")


def movielens() -> None:
    for name in ["ml-latest-small", "ml-1m"]:
        z = download(f"https://files.grouplens.org/datasets/movielens/{name}.zip", DATA / "movielens" / f"{name}.zip")
        with zipfile.ZipFile(z) as zf:
            zf.extractall(DATA / "movielens")


def torchvision_sets() -> None:
    from torchvision import datasets

    root = str(DATA / "torchvision")
    for cls in [datasets.MNIST, datasets.FashionMNIST, datasets.CIFAR10]:
        cls(root, train=True, download=True)
        cls(root, train=False, download=True)
    datasets.OxfordIIITPet(root, split="trainval", download=True)
    datasets.OxfordIIITPet(root, split="test", download=True)


def credit_card_fraud() -> None:
    from sklearn.datasets import fetch_openml

    fetch_openml("CreditCardFraudDetection", version=1, data_home=str(DATA / "sklearn"), as_frame=True)


def text_corpora() -> None:
    download(
        "https://raw.githubusercontent.com/karpathy/char-rnn/master/data/tinyshakespeare/input.txt",
        DATA / "text" / "tinyshakespeare.txt",
    )


def hf_sets() -> None:
    from datasets import load_dataset

    cache = str(DATA / "hf")
    load_dataset("PolyAI/banking77", cache_dir=cache)
    load_dataset("stanfordnlp/imdb", cache_dir=cache)
    load_dataset("fancyzhx/ag_news", cache_dir=cache)
    load_dataset("roneneldan/TinyStories", split="train[:2%]", cache_dir=cache)


def hillstrom() -> None:
    url = (
        "http://www.minethatdata.com/"
        "Kevin_Hillstrom_MineThatData_E-MailAnalytics_DataMiningChallenge_2008.03.20.csv"
    )
    download(url, DATA / "hillstrom" / "hillstrom.csv")


def main() -> None:
    print("caching datasets into ./data")
    step("scikit-learn: california housing, adult, bank marketing", sklearn_sets)
    step("telco customer churn", telco_churn)
    step("online retail ii (uci 502)", online_retail_ii)
    step("movielens small and 1m", movielens)
    step("torchvision: mnist, fashion-mnist, cifar-10, oxford-iiit pets", torchvision_sets)
    step("credit card fraud (openml)", credit_card_fraud)
    step("tiny shakespeare", text_corpora)
    step("hugging face: banking77, imdb, ag_news, tinystories 2% (needs --group llm)", hf_sets)
    step("hillstrom email marketing", hillstrom)
    failed = [n for n, s in REPORT if s != "ok"]
    print(f"\n{len(REPORT) - len(failed)} succeeded, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
