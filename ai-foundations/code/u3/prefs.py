import pyarrow.parquet as pq
import torch

from aif import chat, data, gpt


def pairs(split: str, limit: int, tok, max_tokens: int = 640) -> list[dict]:
    """UltraFeedback preference pairs as token ids: the prompt, and the prompt with each reply."""
    name = f"data/{split}_prefs-00000-of-00001.parquet"
    rows = pq.read_table(
        data.fetch("HuggingFaceH4/ultrafeedback_binarized", name),
        columns=["prompt", "chosen", "rejected"],
    ).to_pylist()
    out = []
    for r in rows:
        prompt = tok.encode(chat.render([{"role": "user", "content": r["prompt"]}]))
        chosen = tok.encode(r["chosen"][-1]["content"] + chat.END)
        rejected = tok.encode(r["rejected"][-1]["content"] + chat.END)
        if len(prompt) + max(len(chosen), len(rejected)) <= max_tokens and chosen != rejected:
            out.append(
                {"prompt": prompt, "chosen": chosen, "rejected": rejected, "text": r["prompt"]}
            )
        if len(out) == limit:
            break
    return out


def sequences(
    batch: list[dict], side: str, pad_id: int, device
) -> tuple[torch.Tensor, torch.Tensor]:
    """Prompt plus reply, right-padded; labels mark the reply's tokens only."""
    rows = [(p["prompt"] + p[side], [-100] * len(p["prompt"]) + p[side]) for p in batch]
    longest = max(len(x) for x, _ in rows)
    ids = torch.full((len(rows), longest), pad_id, dtype=torch.long)
    labels = torch.full((len(rows), longest), -100, dtype=torch.long)
    for i, (x, y) in enumerate(rows):
        ids[i, : len(x)] = torch.tensor(x)
        labels[i, : len(y)] = torch.tensor(y)
    return ids.to(device), labels.to(device)


# snippet:begin hidden
def final_hidden(model: gpt.GPT, ids: torch.Tensor) -> torch.Tensor:
    T = ids.shape[1]
    cos, sin = model.cos[:T], model.sin[:T]
    x = model.embed(ids)
    for block in model.blocks:
        x = block(x, cos, sin)
    return model.norm(x)


# snippet:end hidden


# snippet:begin reward-model
class RewardModel(torch.nn.Module):
    def __init__(self, backbone: gpt.GPT):
        super().__init__()
        self.backbone = backbone
        self.score = torch.nn.Linear(backbone.config.d_model, 1)
        torch.nn.init.zeros_(self.score.weight)
        torch.nn.init.zeros_(self.score.bias)

    def forward(self, ids: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
        last = (labels != -100).long().cumsum(1).argmax(1)
        hidden = final_hidden(self.backbone, ids)
        return self.score(hidden[torch.arange(len(ids)), last]).squeeze(-1)


# snippet:end reward-model
