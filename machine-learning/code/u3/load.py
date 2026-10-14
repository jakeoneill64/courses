import argparse
import math

import numpy as np
import torch
import torch.nn.functional as F

from transformers.utils import logging as hf_logging

from aif import bpe, chat, check, data, device, gpt, sample


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="HuggingFaceTB/SmolLM2-135M")
    args = parser.parse_args()
    dev = device.device()
    # snippet:begin load
    folder = data.model_files(args.model)
    tok = bpe.BPE.from_huggingface(folder / "tokenizer.json")
    model = gpt.from_huggingface(folder).to(dev).eval()
    # snippet:end load
    c = model.config
    print(
        f"{args.model}: {gpt.param_count(c) / 1e6:.1f}M parameters, {c.n_layers} layers of width {c.d_model}"
    )
    hf_logging.disable_progress_bar()

    # snippet:begin reference
    from transformers import AutoModelForCausalLM, AutoTokenizer

    ref_tok = AutoTokenizer.from_pretrained(folder)
    ref = AutoModelForCausalLM.from_pretrained(folder, dtype=torch.float32).to(dev).eval()
    prompts = [
        "The capital of France is",
        "def fibonacci(n):\n    ",
        "In 1905, Einstein published",
        "Les chats sont",
    ]
    worst = 0.0
    for p in prompts:
        ids = tok.encode(p)
        check.expect(f"tokens of {p!r}", ids == ref_tok(p)["input_ids"])
        x = torch.tensor([ids], device=dev)
        with torch.no_grad():
            worst = max(worst, (model(x) - ref(x).logits).abs().max().item())
    # snippet:end reference
    print(
        f"tokens identical to Hugging Face's on {len(prompts)} prompts; largest logit difference {worst:.1e}"
    )
    check.expect("logits match", worst < 1e-3, f"{worst:.2e}")
    del ref

    eot = tok.special["<|endoftext|>"]
    for p in prompts[:2]:
        out = sample.generate(model, tok.encode(p), 40, stop=eot, temperature=0.0)
        print(f"greedy continuation of {p!r}:\n    {tok.decode(out)!r}")

    folder_i = data.model_files(args.model + "-Instruct")
    instruct = gpt.from_huggingface(folder_i).to(dev).eval()
    # snippet:begin chat
    messages = [{"role": "user", "content": "Give me three tips for learning to juggle."}]
    prompt = tok.encode(chat.render(messages))
    reply = sample.generate(instruct, prompt, 400, stop=tok.special[chat.END], temperature=0.0)
    # snippet:end chat
    print(f"chat template: {chat.render(messages)!r}")
    ended = bool(reply) and reply[-1] == tok.special[chat.END]
    print(
        f"the instruction-tuned model replies in {len(reply)} tokens"
        f"{', ending its turn with ' + chat.END if ended else ', stopped at the limit'}:"
    )
    for line in tok.decode(reply).replace(chat.END, "").strip().splitlines():
        print(f"    {line}")
    base_reply = sample.generate(
        model, prompt, 60, stop=tok.special[chat.END], temperature=0.0
    )
    print("the base model, given the same prompt, continues:")
    print(f"    {tok.decode(base_reply)[:240]!r}")

    # snippet:begin stories
    text = data.tinystories("valid").read_text()[:400_000]
    ids = tok.encode(text)
    x = torch.tensor(ids[: len(ids) // 1024 * 1024], device=dev).view(-1, 1024)
    with torch.no_grad():
        losses = [F.cross_entropy(model(r[None, :-1]).float()[0], r[1:]).item() for r in x]
    bpb = float(np.mean(losses)) / math.log(2) * len(ids) / len(text.encode())
    # snippet:end stories
    print(
        f"on TinyStories' validation text: {np.mean(losses):.3f} nats per token, {bpb:.3f} bits per byte"
    )


if __name__ == "__main__":
    check.main(main)
