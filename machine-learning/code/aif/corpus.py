import os
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

from . import bpe

EOT = "<|endoftext|>"


# snippet:begin ranges
def ranges(path: Path, parts: int, separator: bytes = EOT.encode()) -> list[tuple[int, int]]:
    size = path.stat().st_size
    cuts = [0]
    with open(path, "rb") as f:
        for i in range(1, parts):
            f.seek(size * i // parts)
            block = f.read(1 << 20)
            at = block.find(separator)
            if at >= 0:
                cuts.append(size * i // parts + at)
    cuts.append(size)
    return [(a, b) for a, b in zip(cuts, cuts[1:]) if b > a]


# snippet:end ranges


def documents(path: Path, start: int, end: int) -> list[str]:
    with open(path, "rb") as f:
        f.seek(start)
        text = f.read(end - start).decode("utf-8", errors="replace")
    return [d.strip() for d in text.split(EOT) if d.strip()]


def _count(args) -> Counter:
    path, start, end, split_digits = args
    return bpe.count_chunks(documents(path, start, end), split_digits=split_digits)


def count_file(path: Path, split_digits: bool = True, workers: int | None = None) -> Counter:
    workers = workers or os.cpu_count()
    jobs = [(path, a, b, split_digits) for a, b in ranges(path, workers * 4)]
    total = Counter()
    with ProcessPoolExecutor(workers) as pool:
        for counts in pool.map(_count, jobs):
            total.update(counts)
    return total


# snippet:begin encode-part
def _encode(args) -> np.ndarray:
    path, start, end, tokenizer = args
    tok = bpe.BPE.load(tokenizer)
    eot = tok.special[EOT]
    out = []
    for doc in documents(path, start, end):
        out.extend(tok.encode(doc))
        out.append(eot)
    return np.array(out, dtype=np.uint16)


def encode_file(path: Path, tokenizer: Path, out: Path, workers: int | None = None) -> int:
    workers = workers or os.cpu_count()
    jobs = [(path, a, b, tokenizer) for a, b in ranges(path, workers * 4)]
    with ProcessPoolExecutor(workers) as pool, open(out, "wb") as f:
        n = 0
        for ids in pool.map(_encode, jobs):
            ids.tofile(f)
            n += len(ids)
    return n


# snippet:end encode-part
