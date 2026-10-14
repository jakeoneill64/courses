import json
import sys
from pathlib import Path

import numpy as np

from aifig import C, plot, save

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
sys.path.insert(0, str(ROOT.parent / "code"))


def load(name):
    return json.loads((DATA / f"{name}.json").read_text())


def smooth(values, n=10):
    values = np.asarray(values, dtype=float)
    return np.array([values[max(0, i - n + 1) : i + 1].mean() for i in range(len(values))])


def grpo():
    history = np.array(load("u3-grpo")["history"], dtype=float)
    fig, (reward, length) = plot(h=54, ncols=2, gridspec_kw={"wspace": 0.3})
    reward.plot(history[:, 0], history[:, 1], color=C["light"], lw=0.8)
    reward.plot(history[:, 0], smooth(history[:, 1]), color=C["navy"])
    reward.set_xlabel("step")
    reward.set_ylabel("mean reward")
    reward.set_ylim(0, 1)
    length.plot(history[:, 0], history[:, 2], color=C["light"], lw=0.8)
    length.plot(history[:, 0], smooth(history[:, 2]), color=C["coral"])
    length.set_xlabel("step")
    length.set_ylabel("mean reply length (tokens)")
    length.set_ylim(0, None)
    save(fig, "u3-grpo")


if __name__ == "__main__":
    for fn in (grpo,):
        fn()
