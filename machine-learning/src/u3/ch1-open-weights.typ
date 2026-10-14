#import "../lib/template.typ": *

= Open weights <ch-open-weights>

#chapter-meta(
  time: [5 hours],
  builds: [SmolLM2's published weights and tokeniser loaded into the transformer and BPE encoder you wrote, and matched to Hugging Face's reference implementation to within rounding; the chat template that turns text completion into conversation; and comparisons of the base and instruction-tuned models, and of SmolLM2 with your own model on TinyStories.],
  needs: [Unit 2, in particular Chapters 2.1 and 2.4.],
)

#why[
  Almost all practical work with language models starts from someone else's pretrained weights, because few can afford the pretraining and many good models are published. Loading those weights into code you wrote yourself tests all of Unit 2, since every name, shape and convention of the architecture must match exactly or the model produces nonsense. It also provides the capable base model that the following chapters fine-tune, align, evaluate and equip with tools.
]

#skip-test(
  rule: [If all four are easy, read the section on chat templates and do Labs 3.1.3 and 3.1.4.],
  [Which files make up a model on the Hugging Face Hub, and what does each hold?],
  [What does a `safetensors` file contain, and why is it safer to load than a pickled PyTorch checkpoint?],
  [What is a chat template, and what happens if a model is prompted without the one it was trained with?],
  [How do a base model and its instruction-tuned version differ in what they were trained on and in how they respond?],
)

== Core ideas

=== What a published model is

A model on the Hugging Face Hub is a folder of files. `config.json` describes the architecture: the number of layers, the model and feed-forward widths, the heads and key-value heads, the vocabulary size, the rotary base and whether the embeddings are tied. `model.safetensors` holds every tensor by name. `tokenizer.json` holds the tokeniser: its vocabulary, merges, pre-tokeniser and special tokens, the format Chapter 2.1 already reads. `tokenizer_config.json` usually holds the _chat template_, and the model card, `README.md`, describes the model, its training and its licence.

The `safetensors` format is deliberately simple: an eight-byte length, a JSON header giving each tensor's name, type, shape and byte range, and the raw bytes. Loading it cannot run code. The older PyTorch checkpoint format is a Python pickle, which can run arbitrary code when loaded, a real risk with files downloaded from the internet.

=== Loading the weights

SmolLM2 is a Llama-architecture model, so its tensors correspond one to one with Chapter 2.4's model under different names, and loading renames them:

#snippet("aif/gpt.py", "hf-names", caption: [Building a `Config` from `config.json` and renaming SmolLM2's tensors to this course's])

The model is constructed on the `meta` device, which records shapes without allocating memory, and the converted tensors are assigned in place, so no memory is spent on random initial weights that would only be overwritten. The rotary tables, which are computed rather than stored, are rebuilt for the context length requested. With the tokeniser from Chapter 2.1, loading takes three lines:

#snippet("u3/load.py", "load", caption: [SmolLM2, in your own code])

=== The reference test

Hugging Face's `transformers` library is the reference implementation of SmolLM2. The program runs both on the same four prompts (a sentence, code, an unfinished fact and French) and compares the tokens and the logits:

#snippet("u3/load.py", "reference", caption: [Your tokeniser and model against the reference])

#console-part("/src/console/u3-load.txt", to: 3, caption: [Identical tokens, and logits that agree to within rounding])

The tokens are identical, and the logits agree to within the rounding of float32 arithmetic. The two implementations perform the same operations through different kernels that add in different orders, which changes the last digits. Any difference in the rotary convention, the normalisation's epsilon, the order of the gate and up projections or the grouping of key-value heads would show here as a large disagreement, and generation would quickly fall apart.

=== Base models and chat

A _base model_ is the result of pretraining alone: it continues text. Asked a question, it may answer, or continue with more questions, or repeat itself, depending on what such text was followed by in its training data:

#console-part("/src/console/u3-load.txt", from: 3, to: 10, command: false, caption: [The base model continues text])

The first continuation is a loop, a characteristic failure of greedy decoding from a small base model, which Chapter 2.7's sampling methods address. To make a model converse, it is fine-tuned on conversations written in a fixed format, the _chat template_, that marks where each speaker's turn begins and ends. SmolLM2 uses the ChatML convention, with its own special tokens:

#snippet("aif/chat.py", "template", caption: [SmolLM2's chat template])

#snippet("u3/load.py", "chat", caption: [A conversation rendered, encoded and answered])

#console-part("/src/console/u3-load.txt", from: 10, to: -1, command: false, caption: [The same question to the instruction-tuned model and to the base model])

The instruction-tuned model answers in the assistant's role, with a structure it learned from its fine-tuning data, and ends its turn with `<|im_end|>`. Its answer also shows the limits of a model of 135 million parameters, since it reads "juggle" as juggling tasks rather than balls. The base model, given the same tokens, does not reply. It repeats the question as if it were a heading, then loops, writing the same tip three times. Chapters 3.2 to 3.4 make the instruction-tuned model from the base model, by the same methods its authors used.

=== SmolLM2 on TinyStories

SmolLM2-135M was trained on two trillion tokens of web text, code and mathematics. Chapter 2.5's model was trained on 300 million tokens of children's stories and is five times smaller. The program measures SmolLM2 on TinyStories' validation text:

#snippet("u3/load.py", "stories", caption: [SmolLM2's bits per byte on TinyStories])

#console-part("/src/console/u3-load.txt", from: -1, command: false, caption: [SmolLM2 on TinyStories])

SmolLM2 scores about 0.70 bits per byte, well behind your model's figure from Chapter 2.5. It spends much of its capacity on code, French and the facts of the web, so on the narrow distribution of children's stories a small model trained only on that distribution does better. On almost any other text, SmolLM2 is better by a wide margin, as Lab 3.1.4 shows.

#keyidea[
  An open-weight model is an architecture, a set of named tensors and a tokeniser. Loading it into your own implementation and matching the reference's logits to within rounding shows that your code follows every convention the model uses, and gives you a model you can fine-tune, inspect and run anywhere.
]

#inpytorch(title: [In the libraries])[
  `transformers.AutoModelForCausalLM.from_pretrained(name)` and `AutoTokenizer.from_pretrained(name)` do what this chapter's three lines do, for hundreds of architectures, and `tokenizer.apply_chat_template(messages)` renders a conversation with the template stored beside the model. `safetensors.torch.load_file` reads the weights, and `huggingface_hub.hf_hub_download` fetches files at a pinned revision, as `aif.data.fetch` does.
]

#reading(
  [Loubna Ben Allal and others, "SmolLM2: When Smol Goes Big", 2025: how the models were trained, from data to instruction tuning.],
  [The `safetensors` documentation, and the Hugging Face Hub's documentation on model cards.],
  [Hugo Touvron and others, "Llama 2: Open Foundation and Fine-Tuned Chat Models", 2023, sections 1 to 3: the path from base model to chat model.],
)

== Labs

#lab([Inside a checkpoint], goal: [Read a safetensors file without a library.], time: [1 hour], code: "code/aif/data.py")[
  + Read the first eight bytes of SmolLM2-135M's `model.safetensors` as a little-endian integer, then that many bytes of JSON, and list every tensor's name, type and shape.
  + Load one tensor yourself with NumPy from its byte range, and compare it with `safetensors`'s copy.
  #done-when(
    [Your list matches the library's, and your tensor is identical to its.],
  )
  #evidence([The code and the first ten lines of the list.])
]

#lab([A bigger model], goal: [Load SmolLM2-360M and measure what precision costs.], time: [1 hour], code: "code/u3/load.py")[
  + Run the program with `--model HuggingFaceTB/SmolLM2-360M`, and check the logits against the reference.
  + Load the model in float16 and in float32, and record the memory each takes and the largest difference in the logits.
  #done-when(
    [The float32 logits match the reference.],
    [You can state the memory saved by float16 and its cost in logit error.],
  )
  #evidence([The measurements.])
]

#lab([Correct and malformed templates], goal: [See what the chat template does for an instruction-tuned model.], time: [1.5 hours], code: "code/aif/chat.py")[
  + Hold a three-turn conversation with SmolLM2-360M-Instruct by rendering the template yourself and generating each reply.
  + Ask the same first question three wrong ways: without the template, with the roles swapped, and without the closing `<|im_end|>` after your turn. Record the replies.
  #done-when(
    [Your conversation holds context across three turns.],
    [You can describe how each malformed prompt changed the model's behaviour.],
  )
  #evidence([The four transcripts.])
]

#lab([Three models on three kinds of text], goal: [Compare models on several kinds of text.], time: [1.5 hours], code: "code/u3/load.py")[
  + Measure bits per byte for SmolLM2-135M, SmolLM2-360M and your Chapter 2.5 model on TinyStories' validation text, on 100 paragraphs of SQuAD's Wikipedia text, and on the course's own Python code.
  #done-when(
    [Your table has nine measurements.],
    [You can explain where your model wins, where it loses, and by how much.],
  )
  #evidence([The table and the explanation.])
]

#problems(
  [SmolLM2-135M's config gives 30 layers, a model width of 576, 9 heads, 3 key-value heads and a feed-forward width of 1,536. Check its parameter count of 134.5 million.],
  [Why might a tensor stored as bfloat16 in the checkpoint be converted to float32 for this course on the M2 Pro, and what does the conversion cost?],
  [A model's chat template inserts a system message that you did not write. How would you find out, and why does it matter for evaluating the model?],
  [Why does matching the reference implementation's logits exactly require running on the same device and in the same precision?],
  [What can you check to be confident that a model downloaded from the internet is the one its authors published?],
)

#checklist(
  [I can explain the files of a published model and the safetensors format.],
  [I can load published weights into my own implementation and match the reference to within rounding.],
  [I can render a chat template and explain what base and instruction-tuned models are.],
  [I can compare models fairly across different kinds of text.],
  [Lab 3.1.1–3.1.4 done-when criteria all hold, with evidence filed.],
)
