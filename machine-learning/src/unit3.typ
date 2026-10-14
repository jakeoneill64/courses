#import "lib/template.typ": *
#show: course-doc.with(unit: "3", title: "From Base Model to Assistant", short: "Base Model to Assistant",
  subtitle: "Open weights, fine-tuning, LoRA, preference optimisation, reinforcement learning, evaluation, retrieval and agents",
  chapters: ("Open weights", "Supervised fine-tuning", "LoRA", "Preferences", "Reinforcement learning with verifiable rewards", "Evaluation", "Retrieval", "Tools and agents"))
#contents()

#about-unit(unit: "3",
  intro: [Unit 3 follows the path from a pretrained model, which continues text, to an assistant, which answers, reasons and uses tools. It loads SmolLM2's open weights into the transformer you wrote, fine-tunes it on conversations, makes fine-tuning cheap with LoRA and 4-bit weights, and aligns it with preferences between replies. It trains a reward model to score replies from judgements of which of two replies is better, and then optimises the model on those judgements directly with DPO. It teaches a model arithmetic by reinforcement learning against a checker, and measures each of these models with confidence intervals and with a judge whose biases you also measure. It ends with the two ways assistants reach beyond their weights: retrieval from documents, and tools called in a loop.],
  rows: (
    ([3.1], [SmolLM2 loaded into your transformer, matched to Hugging Face's within rounding], [5]),
    ([3.2], [Supervised fine-tuning with loss masking, and the base and tuned models compared], [6]),
    ([3.3], [LoRA from scratch, 4-bit frozen weights, and memory measured against prediction], [6]),
    ([3.4], [A Bradley–Terry reward model, and DPO derived and implemented], [7]),
    ([3.5], [GRPO from scratch, teaching a model to do arithmetic against a checker], [7]),
    ([3.6], [An evaluation harness with bootstrap intervals, paired tests and a judge], [7]),
    ([3.7], [BM25, a fine-tuned embedding model, HNSW from scratch, and retrieval-augmented answers], [7]),
    ([3.8], [Constrained decoding, an agent with a calculator and search, and prompt injection], [7]),
  ),
  before: [Finish Unit 2 first, because this unit reuses its transformer, tokeniser and sampler. Run `uv run -m u3.load` once to download SmolLM2.],
  needs: [A GPU with 16 GB of memory or more, or an Apple Silicon Mac with 32 GB. The 4-bit run of Chapter 3.3 peaks at 17.5 GiB on the M2 Pro, so on a 16 GB GPU lower its `--batch-tokens` until it fits. The training runs take between half an hour and two hours each on the M2 Pro.],
)

#include "u3/ch1-open-weights.typ"
#include "u3/ch2-sft.typ"
#include "u3/ch3-lora.typ"
#include "u3/ch4-preferences.typ"
#include "u3/ch5-grpo.typ"
#include "u3/ch6-evaluation.typ"
#include "u3/ch7-retrieval.typ"
#include "u3/ch8-agents.typ"

#signoff(unit: "3",
  chapters: ("Open weights", "Supervised fine-tuning", "LoRA", "Preferences", "Reinforcement learning with verifiable rewards", "Evaluation", "Retrieval", "Tools and agents"),
  review: (
    [Explain how a chat template and loss masking turn a base model into an assistant, and what each mask hides.],
    [Derive the DPO loss from the reward-model objective and the KL-regularised policy, and explain the role of $beta$.],
    [Explain how GRPO estimates advantages without a value model, and why a group with identical rewards teaches nothing.],
    [Given two models' answers on 1,000 questions, compute a confidence interval for the difference in their accuracies and say whether it is significant.],
    [Explain how your agent's constrained decoder guarantees valid tool calls, and how you would defend it against prompt injection.],
  ),
)
