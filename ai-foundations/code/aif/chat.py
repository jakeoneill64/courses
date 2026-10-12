from .bpe import BPE

# snippet:begin template
START, END = "<|im_start|>", "<|im_end|>"


def render(messages: list[dict], add_generation_prompt: bool = True) -> str:
    text = "".join(f"{START}{m['role']}\n{m['content']}{END}\n" for m in messages)
    return text + (f"{START}assistant\n" if add_generation_prompt else "")


# snippet:end template


# snippet:begin masked
def encode_for_training(
    tok: BPE, messages: list[dict], limit: int
) -> tuple[list[int], list[int]]:
    """Token ids, and labels that are -100 except on the assistant's replies."""
    ids, labels = [], []
    for m in messages:
        head = tok.encode(f"{START}{m['role']}\n")
        body = tok.encode(f"{m['content']}{END}") + tok.encode("\n")
        ids += head + body
        if m["role"] == "assistant":
            labels += [-100] * len(head) + body[:-1] + [-100]
        else:
            labels += [-100] * (len(head) + len(body))
    return ids[:limit], labels[:limit]


# snippet:end masked
