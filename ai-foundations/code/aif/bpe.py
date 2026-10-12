import json
from collections import Counter, defaultdict
from heapq import heapify, heappop, heappush
from pathlib import Path

import regex

# snippet:begin pattern
GPT2_PATTERN = r"""'(?:[sdmt]|ll|ve|re)| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"""
DIGIT = regex.compile(r"(\p{N})")
# snippet:end pattern


# snippet:begin chunks
def chunks(text: str, pattern: regex.Pattern, split_digits: bool) -> list[str]:
    if not split_digits:
        return pattern.findall(text)
    out = []
    for piece in DIGIT.split(text):
        if piece:
            out.extend(pattern.findall(piece))
    return out


# snippet:end chunks


# snippet:begin merge-word
def merge_pair(ids: list[int], pair: tuple[int, int], new: int) -> list[int]:
    out, i = [], 0
    while i < len(ids):
        if i + 1 < len(ids) and ids[i] == pair[0] and ids[i + 1] == pair[1]:
            out.append(new)
            i += 2
        else:
            out.append(ids[i])
            i += 1
    return out


# snippet:end merge-word


class BPE:
    """A byte-level BPE tokeniser: every token is a byte string, so any text can be encoded."""

    def __init__(
        self,
        token_bytes: list[bytes],
        merges: list[tuple[int, int, int]],
        special: dict[str, int],
        pattern: str = GPT2_PATTERN,
        split_digits: bool = True,
    ):
        self.token_bytes = token_bytes
        single = {t[0]: i for i, t in reversed(list(enumerate(token_bytes))) if len(t) == 1}
        self.byte_id = [single.get(b) for b in range(256)]
        self.rank = {(a, b): r for r, (a, b, _) in enumerate(merges)}
        self.merged = {(a, b): new for a, b, new in merges}
        self.special = special
        self.special_ids = {i: s for s, i in special.items()}
        self.pattern_text = pattern
        self.pattern = regex.compile(pattern)
        self.split_digits = split_digits
        names = sorted(special, key=len, reverse=True)
        self.special_split = (
            regex.compile("(" + "|".join(regex.escape(s) for s in names) + ")")
            if names
            else None
        )
        self.cache: dict[str, list[int]] = {}

    @property
    def vocab_size(self) -> int:
        return len(self.token_bytes)

    # snippet:begin encode-chunk
    def encode_chunk(self, data: bytes) -> list[int]:
        ids = [self.byte_id[b] for b in data if self.byte_id[b] is not None]
        while len(ids) > 1:
            pairs = set(zip(ids, ids[1:]))
            best = min(pairs, key=lambda p: self.rank.get(p, len(self.rank)))
            if best not in self.rank:
                break
            ids = merge_pair(ids, best, self.merged[best])
        return ids

    # snippet:end encode-chunk

    # snippet:begin encode
    def encode(self, text: str) -> list[int]:
        out = []
        parts = self.special_split.split(text) if self.special_split else [text]
        for part in parts:
            if part in self.special:
                out.append(self.special[part])
                continue
            for chunk in chunks(part, self.pattern, self.split_digits):
                ids = self.cache.get(chunk)
                if ids is None:
                    ids = self.encode_chunk(chunk.encode("utf-8"))
                    self.cache[chunk] = ids
                out.extend(ids)
        return out

    def decode(self, ids: list[int]) -> str:
        return b"".join(self.token_bytes[i] for i in ids).decode("utf-8", errors="replace")

    # snippet:end encode

    def save(self, path: Path) -> None:
        merges = [[a, b] for (a, b), _ in sorted(self.rank.items(), key=lambda kv: kv[1])]
        spec = {
            "pattern": self.pattern_text,
            "split_digits": self.split_digits,
            "merges": merges,
            "special": self.special,
        }
        Path(path).write_text(json.dumps(spec))

    @classmethod
    def load(cls, path: Path) -> "BPE":
        spec = json.loads(Path(path).read_text())
        return from_merges(
            [tuple(m) for m in spec["merges"]],
            list(spec["special"]),
            spec["pattern"],
            spec["split_digits"],
        )

    @classmethod
    def from_huggingface(cls, path: Path) -> "BPE":
        return _from_huggingface(Path(path))


def from_merges(
    merges: list[tuple[int, int]],
    special: list[str],
    pattern: str = GPT2_PATTERN,
    split_digits: bool = True,
) -> BPE:
    token_bytes = [bytes([b]) for b in range(256)]
    triples = []
    for a, b in merges:
        triples.append((a, b, len(token_bytes)))
        token_bytes.append(token_bytes[a] + token_bytes[b])
    ids = {s: len(token_bytes) + i for i, s in enumerate(special)}
    token_bytes += [s.encode("utf-8") for s in special]
    return BPE(token_bytes, triples, ids, pattern, split_digits)


# snippet:begin count
def count_chunks(
    texts, pattern: str = GPT2_PATTERN, split_digits: bool = True, special: list[str] = ()
) -> Counter:
    compiled = regex.compile(pattern)
    splitter = regex.compile("|".join(regex.escape(s) for s in special)) if special else None
    counts = Counter()
    for text in texts:
        for part in splitter.split(text) if splitter else [text]:
            counts.update(chunks(part, compiled, split_digits))
    return counts


# snippet:end count


# snippet:begin train
def train(
    counts: Counter,
    vocab_size: int,
    special: list[str] = (),
    pattern: str = GPT2_PATTERN,
    split_digits: bool = True,
) -> BPE:
    words = [list(chunk.encode("utf-8")) for chunk in counts]
    freq = list(counts.values())
    pairs = Counter()
    where = defaultdict(set)
    for i, w in enumerate(words):
        for p in zip(w, w[1:]):
            pairs[p] += freq[i]
            where[p].add(i)
    heap = [(-n, p) for p, n in pairs.items()]
    heapify(heap)

    merges = []
    while len(merges) < vocab_size - 256 - len(special) and heap:
        n, best = heappop(heap)
        if pairs.get(best, 0) != -n:
            continue
        new = 256 + len(merges)
        merges.append(best)
        changed = set()
        for i in where.pop(best):
            w = words[i]
            merged = merge_pair(w, best, new)
            if len(merged) == len(w):
                continue
            for p in zip(w, w[1:]):
                pairs[p] -= freq[i]
                changed.add(p)
            for p in zip(merged, merged[1:]):
                pairs[p] += freq[i]
                where[p].add(i)
                changed.add(p)
            words[i] = merged
        for p in changed:
            if pairs[p] > 0:
                heappush(heap, (-pairs[p], p))
            else:
                del pairs[p]
    return from_merges(merges, list(special), pattern, split_digits)


# snippet:end train


# snippet:begin byte-map
def gpt2_byte_map() -> dict[int, str]:
    """The byte-to-character table GPT-2 uses to store token bytes as printable text."""
    printable = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(ord("¡"), ord("¬") + 1))
        + list(range(ord("®"), ord("ÿ") + 1))
    )
    table, extra = {}, 0
    for b in range(256):
        if b in printable:
            table[b] = chr(b)
        else:
            table[b] = chr(256 + extra)
            extra += 1
    return table


# snippet:end byte-map


def _from_huggingface(path: Path) -> BPE:
    spec = json.loads(path.read_text())
    model = spec["model"]
    if model["type"] != "BPE":
        raise ValueError(f"{path}: not a BPE tokeniser")
    char_to_byte = {c: b for b, c in gpt2_byte_map().items()}
    vocab = model["vocab"]
    added = {t["content"]: t["id"] for t in spec.get("added_tokens", [])}
    size = max(max(vocab.values()), max(added.values(), default=0)) + 1
    token_bytes = [b""] * size
    for text, i in vocab.items():
        token_bytes[i] = (
            text.encode("utf-8") if text in added else bytes(char_to_byte[c] for c in text)
        )
    triples = []
    for m in model["merges"]:
        a, b = m.split(" ") if isinstance(m, str) else m
        triples.append((vocab[a], vocab[b], vocab[a + b]))
    pre = spec.get("pre_tokenizer") or {}
    steps = pre.get("pretokenizers", [pre])
    split_digits = any(s.get("type") == "Digits" and s.get("individual_digits") for s in steps)
    return BPE(token_bytes, triples, added, GPT2_PATTERN, split_digits)
