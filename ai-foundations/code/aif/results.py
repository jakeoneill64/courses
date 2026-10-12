import json

from .data import RUNS


def save(name: str, value) -> None:
    RUNS.mkdir(parents=True, exist_ok=True)
    (RUNS / f"{name}.json").write_text(json.dumps(value, indent=1))


def load(name: str):
    return json.loads((RUNS / f"{name}.json").read_text())
