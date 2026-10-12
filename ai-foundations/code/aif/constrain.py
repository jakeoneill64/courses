import json

import torch

from .gpt import GPT, KVCache


# snippet:begin decoder
class ToolCallDecoder:
    """Generates {"tool": <one of tools>, "input": <string>} and nothing else."""

    def __init__(self, tok, tools: list[str]):
        self.tok, self.tools = tok, tools
        self.head = tok.encode('{"tool": "')
        self.middle = tok.encode('", "input": "')
        texts = [t.decode("utf-8", errors="replace") for t in tok.token_bytes]
        self.inside = torch.tensor(
            [not any(c in t for c in '"\\\n') and t != "" for t in texts]
        )
        self.closing = torch.tensor([t in ('"', '"}', '" }') for t in texts])
        self.first = [tok.encode(name)[0] for name in tools]
        assert len(set(self.first)) == len(tools), (
            "tool names must differ in their first token"
        )

    # snippet:end decoder

    # snippet:begin generate
    @torch.no_grad()
    def generate(self, model: GPT, prompt: list[int], max_new: int = 96) -> tuple[str, str]:
        device = next(model.parameters()).device
        logits = model(torch.tensor([prompt + self.head], device=device))[0, -1]
        tool = self.tools[int(logits[self.first].argmax())]
        forced = prompt + self.head + self.tok.encode(tool) + self.middle
        cache = KVCache(
            model.config, 1, len(forced) + max_new + 1, device, next(model.parameters()).dtype
        )
        logits = model(torch.tensor([forced], device=device), cache=cache)[0, -1]
        allowed = (self.inside | self.closing).to(device)
        text = []
        for _ in range(max_new):
            token = int(logits.masked_fill(~allowed, float("-inf")).argmax())
            if self.closing[token]:
                break
            text.append(token)
            logits = model(torch.tensor([[token]], device=device), cache=cache)[0, -1]
        return tool, self.tok.decode(text)

    # snippet:end generate

    @staticmethod
    def render(tool: str, text: str) -> str:
        return json.dumps({"tool": tool, "input": text})
