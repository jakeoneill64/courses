from aif import bpe, check, data

EXAMPLES = [
    "Once upon a time",
    "Tom had 1234567 apples.",
    "hello Hello HELLO",
    "strawberry",
    "Supercalifragilistic",
    "日本語",
    "🙂",
    "def f(x):\n    return x",
    "the end. ",
    "the end.",
]


# snippet:begin pieces
def pieces(tok: bpe.BPE, text: str) -> str:
    out = []
    for i in tok.encode(text):
        raw = tok.token_bytes[i]
        try:
            out.append(raw.decode("utf-8").replace("\n", "\\n").replace(" ", "·"))
        except UnicodeDecodeError:
            out.append("<" + raw.hex() + ">")
    return "|".join(out)


# snippet:end pieces


def main() -> None:
    ours = bpe.BPE.load(data.DATA / "tinystories" / "bpe8192.json")
    smol = bpe.BPE.from_huggingface(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "tokenizer.json", kind="model")
    )
    for text in EXAMPLES:
        check.expect(
            "round trip",
            ours.decode(ours.encode(text)) == text and smol.decode(smol.encode(text)) == text,
        )
        print(repr(text))
        print(f"  TinyStories 8,192: {len(ours.encode(text)):2d} tokens  {pieces(ours, text)}")
        print(f"  SmolLM2 49,152:    {len(smol.encode(text)):2d} tokens  {pieces(smol, text)}")


if __name__ == "__main__":
    check.main(main)
