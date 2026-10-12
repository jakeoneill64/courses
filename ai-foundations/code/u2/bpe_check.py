import random
from collections import Counter

from tokenizers import Tokenizer

from aif import bpe, check, data


# snippet:begin naive
def naive_merges(counts: Counter, merges: int) -> list[tuple[int, int]]:
    words = {tuple(chunk.encode("utf-8")): n for chunk, n in counts.items()}
    out = []
    for new in range(256, 256 + merges):
        pairs = Counter()
        for w, n in words.items():
            for p in zip(w, w[1:]):
                pairs[p] += n
        best = min(pairs, key=lambda p: (-pairs[p], p))
        out.append(best)
        words = {tuple(bpe.merge_pair(list(w), best, new)): n for w, n in words.items()}
    return out


# snippet:end naive


def main() -> None:
    text = data.tinystories("valid").read_text()[:3_000_000]
    counts = bpe.count_chunks([text], special=["<|endoftext|>"])
    # snippet:begin compare
    fast = bpe.train(counts, 256 + 200 + 1, special=["<|endoftext|>"])
    learned = [p for p, _ in sorted(fast.rank.items(), key=lambda kv: kv[1])]
    check.expect("the fast trainer's merges", learned == naive_merges(counts, 200))
    # snippet:end compare
    print("the first 200 merges of the fast trainer equal the naive trainer's")
    print("the first ten:", ", ".join(repr(fast.decode([256 + i])) for i in range(10)))

    tok = bpe.BPE.load(data.DATA / "tinystories" / "bpe8192.json")
    rng = random.Random(0)
    samples = ["".join(chr(rng.randint(32, 0x2FFF)) for _ in range(500)) for _ in range(20)]
    samples += [text[i : i + 5000] for i in range(0, 1_000_000, 50_000)]
    check.expect("round trips", all(tok.decode(tok.encode(s)) == s for s in samples))
    print(
        f"{len(samples)} texts, from stories to random Unicode, decode to exactly themselves"
    )

    # snippet:begin smollm2
    path = data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    mine, reference = bpe.BPE.from_huggingface(path), Tokenizer.from_file(str(path))
    code = (data.ROOT / "aif" / "gpt.py").read_text()
    tests = samples + [code[i : i + 3000] for i in range(0, len(code), 3000)]
    tests += [
        "<|im_start|>user\nWhat is 17*23?<|im_end|>\n",
        "  two leading spaces",
        "tab\tand\nnewline",
    ]
    same = sum(mine.encode(t) == reference.encode(t).ids for t in tests)
    # snippet:end smollm2
    print(
        f"SmolLM2's vocabulary loaded into aif.bpe: identical tokens to Hugging Face's on {same} of "
        f"{len(tests)} texts"
    )
    missing = [b for b in range(256) if mine.byte_id[b] is None]
    print(
        f"SmolLM2's vocabulary has no token for {len(missing)} byte values, which both encoders drop: "
        f"{', '.join(hex(b) for b in missing[:6])}, ..."
    )
    check.expect("identical to Hugging Face", same == len(tests))


if __name__ == "__main__":
    check.main(main)
