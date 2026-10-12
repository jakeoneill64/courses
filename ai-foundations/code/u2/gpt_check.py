import json

import torch

from aif import check, data, gpt


# snippet:begin breakdown
def breakdown(c: gpt.Config) -> dict[str, int]:
    attn = c.d_model * c.head_dim * (2 * c.n_heads + 2 * c.n_kv_heads)
    return {
        "embedding (tied with the output)": c.vocab_size * c.d_model,
        "attention, all layers": c.n_layers * attn,
        "feed-forward, all layers": c.n_layers * 3 * c.d_model * c.d_ff,
        "norms": c.n_layers * 2 * c.d_model + c.d_model,
    }


# snippet:end breakdown


def main() -> None:
    torch.manual_seed(0)
    ours = gpt.Config()
    smol = json.loads(
        data.fetch("HuggingFaceTB/SmolLM2-135M", "config.json", kind="model").read_text()
    )
    smol_cfg = gpt.Config(
        vocab_size=smol["vocab_size"],
        d_model=smol["hidden_size"],
        n_layers=smol["num_hidden_layers"],
        n_heads=smol["num_attention_heads"],
        n_kv_heads=smol["num_key_value_heads"],
        d_ff=smol["intermediate_size"],
    )
    for name, c in (("this course's TinyStories model", ours), ("SmolLM2-135M", smol_cfg)):
        model = gpt.GPT(c)
        actual = sum(p.numel() for p in model.parameters())
        check.expect(f"{name} parameter count", actual == gpt.param_count(c))
        print(
            f"{name}: {c.n_layers} layers, d_model {c.d_model}, {c.n_heads} query and {c.n_kv_heads} key-value "
            f"heads, d_ff {c.d_ff}, vocabulary {c.vocab_size:,}"
        )
        for part, n in breakdown(c).items():
            print(f"  {part:<34} {n:>12,}  {n / actual:6.1%}")
        print(
            f"  {'total':<34} {actual:>12,}   {gpt.train_flops_per_token(c, 512) / 1e6:,.0f} MFLOP per "
            f"training token at 512 tokens of context"
        )

    model = gpt.GPT(ours).eval()
    # snippet:begin causal
    x = torch.randint(0, ours.vocab_size, (1, 64))
    changed = x.clone()
    changed[0, 40:] = torch.randint(0, ours.vocab_size, (24,))
    with torch.no_grad():
        a, b = model(x), model(changed)
    before = (a[0, :40] - b[0, :40]).abs().max().item()
    after = (a[0, 40:] - b[0, 40:]).abs().max().item()
    # snippet:end causal
    check.expect("causal", before < 1e-5 and after > 1e-3)
    print(
        f"changing tokens 40 to 63 moves the logits at 0 to 39 by {before:.1e} and at 40 to 63 by {after:.2f}"
    )

    # snippet:begin rope
    q, k = torch.randn(64), torch.randn(64)
    cos, sin = gpt.rope_tables(64, 512, 10000.0)
    rotate = lambda v, p: gpt.apply_rope(v, cos[p], sin[p])
    pairs = [(10, 3), (110, 103), (400, 393)]
    dots = [float(rotate(q, i) @ rotate(k, j)) for i, j in pairs]
    # snippet:end rope
    check.close(
        "rotary dot products depend only on the offset", dots, [dots[0]] * 3, rtol=1e-4
    )
    print(
        f"rotated q.k at positions (10, 3), (110, 103) and (400, 393): {', '.join(f'{d:.4f}' for d in dots)}"
    )

    # snippet:begin overfit
    small = gpt.GPT(
        gpt.Config(
            vocab_size=ours.vocab_size,
            d_model=128,
            n_layers=2,
            n_heads=2,
            n_kv_heads=1,
            d_ff=384,
            max_seq=64,
        )
    )
    x = torch.randint(0, ours.vocab_size, (4, 65))
    opt = torch.optim.AdamW(small.parameters(), lr=3e-3)
    for step in range(300):
        _, loss = small(x[:, :-1], x[:, 1:])
        opt.zero_grad()
        loss.backward()
        opt.step()
    # snippet:end overfit
    check.expect("can overfit one batch", loss.item() < 0.05, f"{loss.item():.3f}")
    print(f"one batch of random tokens memorised: loss {loss.item():.4f} after 300 steps")


if __name__ == "__main__":
    check.main(main)
