#import "../lib/template.typ": *

= Tokenisation <ch-tokens>

#chapter-meta(
  time: [5 hours],
  builds: [A byte-level BPE tokeniser, trained on all 2.2 GB of TinyStories in under a minute and checked against a naive implementation; the same encoder loading SmolLM2's vocabulary and producing exactly the tokens Hugging Face's library does; compression measured against vocabulary size on stories and on code; and the failures that tokens cause, demonstrated.],
  needs: [Unit 1. Run `uv run -m u2.prepare` once to download TinyStories.],
)

#why[
  A language model sees only a sequence of integers, _tokens_, chosen by a tokeniser that is fixed before training begins and cannot change afterwards. The tokeniser decides how long every sequence is, and so how much every step of training and generation costs. It determines which strings the model can treat as units and which it must assemble from fragments, which is why fluent models make mistakes in spelling and arithmetic. It also affects how well the model handles text unlike its training data. This chapter builds the tokeniser that every model in Unit 2 uses, and shows that it is equivalent to the one in Unit 3.
]

#skip-test(
  rule: [If all four are easy, read the sections on training efficiently and on failures, and do Labs 2.1.3 and 2.1.4.],
  [Why do modern tokenisers start from bytes rather than characters or words?],
  [Given the corpus "low low lower lowest", what is the first merge byte-pair encoding makes, and why?],
  [Why do many recent tokenisers split numbers into single digits?],
  [A tokeniser trained on stories encodes Python code at two bytes per token. Why, and what does that cost a model?],
)

== Core ideas

=== From text to integers

A model needs a finite vocabulary of symbols, each with its own embedding vector. There are three obvious choices. _Words_ give short sequences but an unbounded vocabulary: every name, typo and new word would need an entry, and those missing from the vocabulary could not be represented at all. _Characters_ give a manageable vocabulary for one alphabet but long sequences, and Unicode has over 150,000 of them. _Bytes_ give a vocabulary of exactly 256, can represent any text in UTF-8, and make sequences long: one byte per letter in English, two or three per character in most other scripts.

_Subword_ tokenisation is a compromise between these. Frequent strings, such as common words and common pieces of words, get single tokens, and rare strings are spelled out from smaller pieces, down to single bytes if need be. The vocabulary stays fixed, typically between 8,000 and 250,000 tokens, every input can be encoded, and common text is short.

=== Byte-pair encoding

_Byte-pair encoding_ (BPE) learns the subwords from a corpus. Start with the corpus as bytes and a vocabulary of the 256 byte values. Count every adjacent pair of symbols; replace the most frequent pair everywhere with a new symbol, and add it to the vocabulary; repeat until the vocabulary has the size you want. Each step records a _merge_, a rule that two symbols combine into a third, and the merges, in the order they were learned, are the tokeniser.

Merges never cross the boundaries of _chunks_, the pieces a regular expression splits text into before BPE sees it. GPT-2's expression, which this course uses, keeps a word together with the space before it, separates punctuation and runs of whitespace, and recognises English contractions. SmolLM2 and many recent tokenisers also split every digit into its own chunk:

#snippet("aif/bpe.py", "pattern", caption: [GPT-2's pre-tokenisation pattern, and a pattern that isolates digits])

#snippet("aif/bpe.py", "chunks", caption: [Splitting text into chunks, with digits isolated])

=== Training efficiently

The naive algorithm recounts every pair in the corpus after each merge, which is fast enough for a page of text and far too slow for 2.2 GB. Two observations make it fast. First, merges never cross chunks, so the corpus reduces to its distinct chunks and their counts: the 530 million chunks of TinyStories are only 59,732 distinct strings, mostly words. Second, a merge only changes pair counts in the words that contain it, so the counts can be updated in place, and a heap finds the most frequent pair without scanning them all.

#snippet("aif/bpe.py", "count", caption: [Counting chunks, the only pass over the full corpus])

#snippet("aif/bpe.py", "merge-word", caption: [Replacing every occurrence of a pair in one word])

#snippet("aif/bpe.py", "train", caption: [Training: pair counts kept up to date, a heap to find the most frequent pair, stale heap entries skipped])

`aif.corpus` counts chunks in parallel across processes, splitting the file at document boundaries, and `u2.prepare` trains the course's 8,192-token vocabulary and encodes the whole corpus to a file of 16-bit token ids:

#snippet("u2/prepare.py", "prepare", caption: [Training the tokeniser and encoding the corpus])

#console(read("/src/console/u2-prepare.txt"), caption: [All of TinyStories, tokenised, on the M2 Pro's twelve cores])

`u2/bpe_check.py` checks the fast trainer against the plain algorithm. It trains the first 200 merges both ways, on three million characters, and checks that every merge agrees. It then checks that every text decodes back to itself, and that the encoder below reproduces a production tokeniser exactly:

#snippet("u2/bpe_check.py", "naive", caption: [The textbook algorithm, recounting everything after each merge])

#console(read("/src/console/u2-bpe-check.txt"), caption: [The fast trainer, the round trip and SmolLM2's tokeniser, checked])

The first merges are the most common pairs in English children's stories: "he", then " t", " a", " s", " w", "nd", and by the seventh merge " the" is a single token.

=== Encoding

To encode a chunk, start from its bytes and apply merges in the order they were learned: among the adjacent pairs that have a merge, pick the one learned earliest, merge every occurrence, and repeat until no pair has a merge. Applying them in this order, rather than greedily by length, reproduces exactly the segmentation that training produced.

#snippet("aif/bpe.py", "encode-chunk", caption: [Encoding one chunk: always the earliest-learned merge first])

#snippet("aif/bpe.py", "encode", caption: [Encoding text: special tokens, chunks, a cache, and decoding])

The cache matters because most chunks are common words seen thousands of times, so after the first few megabytes almost every chunk is a dictionary lookup. _Special tokens_, such as `<|endoftext|>` which separates documents, are matched before chunking and never produced by merges. Because they are matched in the input, text that contains the string `<|endoftext|>` is encoded as the special token itself, as it is by default in Hugging Face's tokenisers. A system that places untrusted text in a prompt, such as a web page, should strip or escape special-token strings first, or a document could end the conversation it was placed in.

=== Loading someone else's tokeniser

Hugging Face's `tokenizer.json` stores a byte-level BPE vocabulary as strings, mapping each byte to a printable character so that tokens are readable in the file. GPT-2's table maps the printable ASCII and Latin-1 bytes to themselves and the rest to characters from U+0100 onwards, so a space is stored as "Ġ".

#snippet("aif/bpe.py", "byte-map", caption: [GPT-2's byte-to-character table])

With the table inverted, `BPE.from_huggingface` reads SmolLM2's 49,152 tokens and 48,900 merges into the same class, and the check above shows it producing exactly the tokens of the reference implementation on stories, code, chat markup and random Unicode. The check also found that SmolLM2's vocabulary has no token for 21 of the 256 byte values, mostly control characters and bytes that never occur in valid UTF-8, and that the reference implementation silently drops them. `aif.bpe` does the same, and Unit 3 relies on the two agreeing.

=== Compression

How many bytes a token covers on average measures how well a tokeniser compresses text, and so how long the sequences a model must process are. `u2/bpe_train.py` trains vocabularies from 512 to 16,384 tokens on TinyStories and measures each on its own domain, stories, and on another, the source code of PyTorch's neural-network modules:

#snippet("u2/bpe_train.py", "sweep", caption: [One count of the corpus, then a vocabulary of each size])

#console(read("/src/console/u2-bpe-sweep.txt"), caption: [Bytes per token against vocabulary size])

#fig("u2-compression", caption: [Compression against vocabulary size. On its own domain the tokeniser saturates once most words have tokens of their own. On code its compression stays low at every size.]) <fig-compression>

On stories, compression rises quickly and then saturates near 4.1 bytes per token, because TinyStories has only 60,000 distinct words and by 8,192 tokens nearly every common word has its own. On code the same vocabularies manage 1.3 to 2.3 bytes per token, because merges learned from stories rarely occur in code. SmolLM2's tokeniser, trained on web text and code, compresses stories as well as the specialised one and code almost twice as well. The domain of the training corpus decides what a tokeniser compresses well, more than the vocabulary's size does. A poorly matched tokeniser makes every sequence longer, which costs more steps per document and more memory for attention.

=== What tokens hide

A model that sees tokens does not see the letters inside them directly. `u2/tokens.py` shows both tokenisers' pieces for a few strings, with spaces drawn as dots:

#snippet("u2/tokens.py", "pieces", caption: [Tokens as text, with undecodable fragments shown as hex bytes])

#console(read("/src/console/u2-tokens.txt"), caption: [How two tokenisers split ten strings])

"hello", "Hello" and "HELLO" share nothing at the token level, so the model must learn their relationship from data. "strawberry" arrives as three or four pieces, `st|raw|berry` or `st|ra|w|berry`, so the model never sees its r's one at a time, which is why counting them is hard for a language model. Numbers become sequences of digits, which helps arithmetic, since every number is spelled the same way wherever it appears. Tokenisers that merge digit groups write 1234567 as arbitrary chunks such as "123" and "4567". The TinyStories tokeniser, which saw almost no Japanese and no emoji, breaks them into raw bytes, three tokens for each Japanese character and four for the emoji. SmolLM2's does better, keeping 本 whole and spending two tokens on the emoji, but with both tokenisers the same sentence costs several times more tokens in Japanese than in English. Finally, a trailing space is its own token, so a prompt ending in a space puts the model in an unusual position, since in training text a space almost always arrives attached to the following word.

#keyidea[
  A tokeniser is a compression scheme learned from a corpus and fixed for the life of the model. It determines sequence lengths, and therefore cost. It also determines what the model can see directly, and the model must learn from data how the pieces it splits apart fit together.
]

#inpytorch(title: [In the libraries])[
  Production tokenisers are written in fast languages: OpenAI's `tiktoken` and Hugging Face's `tokenizers` in Rust, Google's SentencePiece in C++. They implement the algorithms of this chapter, with SentencePiece also offering a probabilistic alternative, the unigram model. `tokenizers` reads and writes the `tokenizer.json` format that this chapter's loader understands, and `AutoTokenizer.from_pretrained` wraps it with a model's chat template.
]

#reading(
  [Rico Sennrich, Barry Haddow and Alexandra Birch, "Neural Machine Translation of Rare Words with Subword Units", ACL 2016: BPE for language.],
  [Alec Radford and others, "Language Models are Unsupervised Multitask Learners", OpenAI, 2019, section 2.2: byte-level BPE.],
  [Taku Kudo and John Richardson, "SentencePiece: A Simple and Language Independent Subword Tokenizer", EMNLP 2018.],
  [Aleksandar Petrov and others, "Language Model Tokenizers Introduce Unfairness Between Languages", NeurIPS 2023.],
)

== Labs

#lab([BPE by hand], goal: [Learn the algorithm by running it on paper.], time: [1 hour], code: "code/aif/bpe.py")[
  + Take the corpus "low low low lower lower newest newest newest widest", split into words with the space attached to the word that follows.
  + Perform the first six merges by hand, recording the pair counts before each.
  + Check your merges with `bpe.count_chunks` and `bpe.train`, then encode "lowest" by hand and with the tokeniser.
  #done-when(
    [Your six merges and the encoding of "lowest" match the program's.],
    [You can explain any tie and how the program breaks it.],
  )
  #evidence([The pair counts after each merge, and the program's output.])
]

#lab([Choosing a vocabulary size], goal: [Weigh compression against the cost of a larger vocabulary.], time: [1 hour], code: "code/u2/bpe_train.py")[
  + For vocabularies of 1,024, 4,096 and 16,384, compute how many tokens TinyStories' validation set becomes.
  + For the Chapter 2.5 model, compute how the parameters of the embedding and the FLOPs of the output layer change with the vocabulary.
  + Estimate the total training FLOPs for the same number of _bytes_ of text with each vocabulary.
  #done-when(
    [Your table has the tokens, the embedding parameters and the FLOPs per byte for each size.],
    [You can say which vocabulary minimises training cost per byte for this model, and why it is not the largest.],
  )
  #evidence([The table and the argument.])
]

#lab([A tokeniser for code], goal: [See how the training corpus shapes a tokeniser.], time: [1.5 hours], code: "code/u2/bpe_train.py")[
  + Train an 8,192-token tokeniser on the Python files of PyTorch's installation, using `bpe.count_chunks` over their text.
  + Measure its compression on code it did not see, such as the course's `aif` package, and on TinyStories, and compare with the story tokeniser and SmolLM2's.
  + Look at its 100 longest tokens and say what they are.
  #done-when(
    [You have a 3 by 2 table of compression for three tokenisers on two domains.],
    [You can describe what kinds of string your code tokeniser learned to keep whole.],
  )
  #evidence([The table and the list of long tokens.])
]

#lab([Tokens and letters], goal: [Measure how tokenisation hides characters.], time: [1.5 hours], code: "code/u2/tokens.py")[
  + For the 1,000 most common words in TinyStories, record how many tokens each takes in both tokenisers, and how many words are a single token.
  + For the same words with their first letter capitalised, and in capitals, repeat the count.
  + Encode one sentence translated into English, French, Greek and Japanese, and compare tokens per character.
  #done-when(
    [You have both counts, and the fraction of words whose capitalised forms share no token with their lower-case form.],
    [Your table shows the cost of the four languages in tokens per character.],
  )
  #evidence([The counts, the table, and a paragraph on what each implies for a model.])
]

#problems(
  [Show that BPE training is deterministic given a tie-breaking rule, and give a corpus where two different tie-breaking rules produce different tokenisers.],
  [Why must a tokeniser encode with the merges in the order they were learned, rather than taking the longest token that matches at each position? Give a string where the two disagree.],
  [A model's context holds 2,048 tokens. With 4.1 bytes per token on English and 1.3 on Japanese, how many characters of each fit?],
  [Why is it important that ordinary text can never produce the token `<|endoftext|>`? What could happen if it could?],
  [SmolLM2's vocabulary lacks the byte 0x04. What does the model see if a document contains it? Is silently dropping it the right behaviour?],
)

#checklist(
  [I can explain byte-level BPE, train it by hand, and encode with its merges.],
  [I can explain pre-tokenisation and why digits are often split.],
  [I can load a Hugging Face tokeniser into my own encoder and show that they agree.],
  [I can measure compression and explain how vocabulary size and training domain affect it.],
  [Lab 2.1.1–2.1.4 done-when criteria all hold, with evidence filed.],
)
