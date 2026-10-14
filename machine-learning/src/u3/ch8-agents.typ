#import "../lib/template.typ": *

= Tools and agents <ch-agents>

#chapter-meta(
  time: [7 hours],
  builds: [Constrained decoding that makes a model produce a valid tool call and nothing else; a calculator that evaluates arithmetic without `eval`, and a search tool over Chapter 3.7's paragraphs; an agent loop in which SmolLM2-1.7B-Instruct calls them; its accuracy with and without tools, measured on arithmetic and on questions; and prompt injection through a search result, measured with and without a defence.],
  needs: [Chapters 2.7, 3.1 and 3.7.],
)

#why[
  A language model on its own can only write text. Given tools, it can compute exactly, look things up and act. An _agent_ is a loop in which the model proposes an action, a program carries it out, and the result comes back as more text for the model to read. Two engineering problems decide whether such a loop works. The model's proposals must be machine-readable every time, and a format the model follows most of the time is not enough. Everything that comes back from a tool is text the model will read as readily as its instructions, so every tool is a way to attack it.
]

#skip-test(
  rule: [If all four are easy, read the section on prompt injection and do Labs 3.8.3 and 3.8.4.],
  [How can a decoder guarantee that a model's output is valid JSON with a given set of fields?],
  [Describe the loop an agent runs, and what its harness must do at each step.],
  [What is indirect prompt injection, and why is it hard to prevent?],
  [Why is Python's `eval` a dangerous way to implement a calculator tool?],
)

== Core ideas

=== Tool calls as structured text

An agent's harness needs to know which tool the model wants and with what input, so the model must write its request in a fixed format. This chapter's format is a JSON object with two fields, the tool's name and its input as a string. The pseudo-tool `answer` ends the loop.

A model prompted with the format, even one fine-tuned on tool use, will sometimes deviate: a missing quote, an explanation before the JSON, a tool that does not exist. _Constrained decoding_ makes deviation impossible by restricting, at each step, the tokens the model may choose to those that keep the output a valid prefix of the format. Here the format is simple enough to constrain by hand. The fixed parts, `{"tool": "` and `", "input": "`, are forced instead of generated. The model chooses the tool's name at its first token, the only point where the three permitted names differ, and the rest of the name is forced. The input string is generated with every token that contains a quote, a backslash or a newline masked out, except the tokens that close the string.

#snippet("aif/constrain.py", "decoder", caption: [The decoder's fixed parts, and the masks for the free string])

#snippet("aif/constrain.py", "generate", caption: [Forcing, choosing and masking])

Every output of this decoder parses. General decoders constrain to any JSON schema or grammar by compiling it into an automaton over characters and, at each step, computing which tokens of the vocabulary the automaton accepts. They mask the other tokens in the same way.

=== Tools

The calculator must evaluate whatever arithmetic the model writes, and nothing else. `eval` would run any Python the model produced, including a command to delete files. The calculator instead parses the expression and walks the tree, allowing only numbers and the four operations:

#snippet("u3/agent.py", "calculator", caption: [A calculator that accepts arithmetic and refuses everything else])

The search tool returns the paragraph that BM25 ranks first for the model's query, among SQuAD's 2,067 validation paragraphs.

=== The loop

#snippet("u3/agent.py", "loop", caption: [The agent: decode a call, run the tool, return the result, repeat])

Each turn renders the conversation so far (the system prompt describing the tools, two worked examples of the protocol, the question, and the model's calls and their results), decodes one tool call, and either finishes or runs the tool and appends its result. A limit on the number of steps stops a model that would call tools forever.

Both details come from failures of earlier versions. A first version chose the tool by the summed log-probability of each name's tokens, which favours short names. The name "calculator" is two tokens to "answer"'s one, and the agent answered every arithmetic problem at once, without a single calculation. Without worked examples, a model of 1.7 billion parameters reads the description of the protocol and still rarely follows it. Two examples in the conversation, one with each tool, are enough.

=== What tools are worth

#snippet("u3/agent.py", "arithmetic", caption: [Word problems answered directly and with the calculator])

#console(read("/src/console/u3-agent.txt"), caption: [SmolLM2-1.7B-Instruct with and without tools])

Answering directly, the model gets 6 of the 40 word problems right. With the calculator it gets all 40, and it calls the calculator on every one. The example shows the division of labour: the model translates the problem into an expression, the calculator does the arithmetic, and the model reports the result. Arithmetic was the model's weakness, and the tool removes it. Search helps less, though still a great deal. On 40 SQuAD questions, token F1 rises from 13.6% answering directly to 30.9% with search. With 40 questions, both figures are uncertain by several points.

=== Prompt injection

The model reads a tool's result as more text in its context, with the same standing as the system prompt and the user's question. If a search result contains instructions, the model may follow them. This is _indirect prompt injection_. An attacker who can place text where a tool will find it, such as a web page, an email or a document, can steer the agent without access to the conversation. The program poisons every search result with an instruction to answer "banana", and counts how often the agent obeys, first without a defence and then with a common one. The defence wraps the tool's output in tags and adds a sentence to the system prompt declaring text inside those tags to be data, never instructions.

#snippet("u3/agent.py", "injection", caption: [Poisoned search results, with and without the defence])

The injection succeeded on every question. Without the defence, the agent answers "banana" on all 20 questions, and with the tool's output delimited and declared to be data it still does so on all 20. For this model the defence has no effect. The injected sentence calls itself a system notice, and a model of this size does not distinguish an instruction it reads in a tool's output from one its user gave. Larger models trained to rank the system prompt above tool output resist such text more often. None is known to resist it reliably.

Delimiters and instructions can reduce injection in stronger models but cannot prevent it, because they are themselves only text and fine-tuning trained the model to follow instructions. Defences that do not depend on the model are architectural. An agent that has read untrusted text should not be able to take consequential actions without a person's confirmation. Tools that read untrusted content should not hold privileges such as sending email or spending money. Outputs that leave the system, such as URLs, should be filtered, since an injected instruction can ask the model to leak data through them.

#keyidea[
  An agent is a loop of model, tool and result. Constrained decoding makes every tool call valid, and tools must be safe to run on any input the model produces. Every tool's output is untrusted text that can carry instructions, so an agent's permissions must assume that it will sometimes obey them.
]

#inpytorch(title: [In the libraries])[
  Chat APIs and open-weight models such as SmolLM2's larger versions support _function calling_, with tool descriptions in the system prompt and calls in a format the model was fine-tuned on. Libraries such as Outlines and XGrammar, and `llama.cpp`'s grammars, implement general constrained decoding. The Model Context Protocol standardises how tools describe themselves to agents.
]

#reading(
  [Shunyu Yao and others, "ReAct: Synergizing Reasoning and Acting in Language Models", ICLR 2023.],
  [Timo Schick and others, "Toolformer: Language Models Can Teach Themselves to Use Tools", NeurIPS 2023.],
  [Brandon Willard and Rémi Louf, "Efficient Guided Generation for Large Language Models", 2023: constrained decoding with automata.],
  [Kai Greshake and others, "Not What You've Signed Up For: Compromising Real-World LLM-Integrated Applications with Indirect Prompt Injection", AISec 2023.],
)

== Labs

#lab([A richer schema], goal: [Generalise the constrained decoder.], time: [2 hours], code: "code/aif/constrain.py")[
  + Extend the decoder to a call with a third field, an integer `count`, generated with only digit tokens allowed and at most four digits.
  + Test it on 50 prompts and check that every output parses with Python's `json` module and has all three fields.
  #done-when(
    [All 50 outputs parse and validate.],
  )
  #evidence([The code and the validation summary.])
]

#lab([A new tool], goal: [Add a tool and measure whether the agent uses it well.], time: [1.5 hours], code: "code/u3/agent.py")[
  + Add a `convert` tool for units of length and mass, and write 20 tasks that need it.
  + Measure accuracy with and without the tool, and the fraction of tasks on which the agent called it.
  #done-when(
    [Your table has both accuracies and the call rate.],
    [You can describe the commonest failure from the traces.],
  )
  #evidence([The tool, the tasks and the table.])
]

#lab([Reading failures], goal: [Classify why the agent fails.], time: [1.5 hours], code: "code/u3/agent.py")[
  + Collect the traces of 20 failed tasks, arithmetic and questions.
  + Classify each failure: wrong tool, malformed input, misread result, stopped too early, looped, or a correct-looking answer that is wrong.
  #done-when(
    [Every failure has a class and a one-line reason.],
    [You propose one change to the prompt or the loop and measure its effect on the 20 tasks.],
  )
  #evidence([The classification, the change and its effect.])
]

#lab([Attacks and defences], goal: [Measure injection under variations.], time: [1.5 hours], code: "code/u3/agent.py")[
  + Write five phrasings of the injected instruction, from blunt to disguised as part of the paragraph.
  + Measure the attack success rate of each against the plain and the guarded agent, on 20 questions.
  #done-when(
    [Your table has ten rates.],
    [You can say which phrasings, if any, the guard stops, and explain why.],
  )
  #evidence([The phrasings and the table.])
]

#problems(
  [The constrained decoder chooses the tool by likelihood but generates the input greedily. What could go wrong if the input were sampled at temperature 1 under the mask?],
  [Why is masking the quote character inside the string not enough to guarantee valid JSON if the input may contain backslashes? What would a complete string automaton need?],
  [An agent may call tools up to 10 times per task, each call adding 300 tokens of results. How does the cost of each step grow over the task, with a KV cache?],
  [Explain why an agent that can read email and send email is more dangerous than one that can only read it, in terms of prompt injection.],
  [A calculator receives `10 ** 10 ** 10`. What happens with `eval`, and what does this chapter's calculator do?],
)

#checklist(
  [I can implement constrained decoding for a structured format and explain its guarantee.],
  [I can build safe tools and an agent loop around a model.],
  [I can measure what tools add, and classify an agent's failures.],
  [I can explain prompt injection and the architectural defences against it.],
  [Lab 3.8.1–3.8.4 done-when criteria all hold, with evidence filed.],
)
