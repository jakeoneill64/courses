import argparse
import time
from pathlib import Path

import torch

from aif import bpe, check, corpus, data, results


def code_sample(limit: int = 2_000_000) -> str:
    folder = Path(torch.__file__).parent / "nn" / "modules"
    text = "".join(p.read_text() for p in sorted(folder.glob("*.py")))
    return text[:limit]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sizes", type=int, nargs="+", default=[512, 1024, 2048, 4096, 8192, 16384]
    )
    args = parser.parse_args()
    stories = data.tinystories("valid").read_text()[:2_000_000]
    code = code_sample()
    # snippet:begin sweep
    start = time.perf_counter()
    counts = corpus.count_file(data.tinystories("train"))
    print(
        f"counted {sum(counts.values()):,} chunks ({len(counts):,} distinct) in "
        f"{time.perf_counter() - start:.0f} s"
    )
    rows = []
    for size in args.sizes:
        start = time.perf_counter()
        tok = bpe.train(counts, size, special=[corpus.EOT])
        seconds = time.perf_counter() - start
        per_story = len(stories.encode()) / len(tok.encode(stories))
        per_code = len(code.encode()) / len(tok.encode(code))
        rows.append(
            {"vocab": size, "stories": per_story, "code": per_code, "seconds": seconds}
        )
        print(
            f"vocabulary {size:6d}: {per_story:5.2f} bytes per token on stories, "
            f"{per_code:5.2f} on Python "
            f"code; trained in {seconds:4.1f} s"
        )
    # snippet:end sweep
    smol = bpe.BPE.from_huggingface(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    )
    reference = {
        "vocab": smol.vocab_size,
        "stories": len(stories.encode()) / len(smol.encode(stories)),
        "code": len(code.encode()) / len(smol.encode(code)),
    }
    print(
        f"SmolLM2 ({reference['vocab']:,} tokens, trained on web text and code): "
        f"{reference['stories']:.2f} on stories, {reference['code']:.2f} on code"
    )
    results.save("u2-bpe-sweep", {"rows": rows, "smollm2": reference})
    check.expect("compression grows with vocabulary", rows[-1]["stories"] > rows[0]["stories"])


if __name__ == "__main__":
    check.main(main)
