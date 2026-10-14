#import "../lib/template.typ": *

= Retrieval <ch-retrieval>

#chapter-meta(
  time: [7 hours],
  builds: [BM25, the lexical baseline that every retriever must beat; an embedding model made from SmolLM2-135M, before and after contrastive fine-tuning on question and paragraph pairs; the two combined by rank fusion; an HNSW index written from scratch and measured against exact search; and SmolLM2-360M-Instruct answering questions closed-book, with retrieved paragraphs, and with the right paragraph.],
  needs: [Chapters 1.8, 3.1 and 3.6.],
)

#why[
  A model's knowledge is frozen at training time and limited by its size, and a model of a few hundred million parameters knows little. _Retrieval-augmented generation_ gives the model documents to read: find the passages relevant to a question and put them in the prompt. It is how most deployed assistants answer questions about private, recent or specialised material, and the retrieval is usually its weakest part. This chapter builds both halves and measures each.
]

#skip-test(
  rule: [If all four are easy, read the sections on HNSW and on the end-to-end results, and do Labs 3.7.3 and 3.7.4.],
  [What does BM25 score, and why does it beat raw term counts?],
  [How does contrastive training with in-batch negatives turn a language model into an embedding model?],
  [What do HNSW's layers do, and what do the parameters `M` and `ef` trade?],
  [Why might a model answer worse when given three retrieved passages than when given the right one?],
)

== Core ideas

=== The task

SQuAD's questions were written by people about paragraphs of Wikipedia, and each question's answer is a span of its paragraph. Its validation split has 10,570 questions about 2,067 paragraphs, which make a small document collection. Given a question, the retriever must find its paragraph, and success is measured by _recall at k_, the fraction of questions whose paragraph is among the top $k$ results.

=== A lexical baseline

_BM25_ scores a document by the question's words that it contains. Each word's contribution grows with its frequency in the document but saturates, since the tenth occurrence of a word says less than the first. The contribution is normalised by the document's length relative to the average, since long documents contain more of everything. It is also weighted by the word's _inverse document frequency_, which is high for rare words and near zero for words in every document.

#snippet("u3/retrieval.py", "bm25", caption: [BM25 as a sparse matrix of weighted term frequencies])

Since SQuAD's questions were written by people looking at the paragraph, they share many words with it, and BM25 is a strong baseline on this task.

=== Embeddings, before and after training

A _dense_ retriever represents questions and paragraphs as vectors and ranks paragraphs by cosine similarity to the question. The simplest embedding from a language model averages its final hidden states over the text's tokens:

#snippet("u3/retrieval.py", "embed", caption: [A text's embedding: mean-pooled final hidden states, normalised])

A language model's hidden states are trained to predict the next token, which does not place a question near its answer, so untrained mean pooling works poorly. _Contrastive training_ with Chapter 1.8's InfoNCE loss fixes that. In a batch of 32 question and paragraph pairs from SQuAD's training split, each question's own paragraph is the positive and the other 31 paragraphs are negatives, and the loss pulls each question towards its paragraph and away from the rest.

#snippet("u3/retrieval.py", "contrastive", caption: [Contrastive fine-tuning with in-batch negatives, in both directions])

Lexical and dense retrievers fail on different questions, and _reciprocal rank fusion_ combines them using only ranks, each document scoring $1 \/ (60 + "rank")$ in each list:

#snippet("u3/retrieval.py", "fusion", caption: [Reciprocal rank fusion])

#console-part("/src/console/u3-retrieval.txt", to: 10, caption: [Four retrievers on SQuAD's validation questions])

BM25 ranks the right paragraph first for 75.4% of the questions and among the top 20 for 96.0%, the strong baseline expected from the way SQuAD was written. Untrained mean pooling ranks it first for only 11.0%. The language model's hidden states carry information about the text, but their geometry was never trained for similarity. Contrastive training on 48,000 pairs, 1,500 steps of 32, raises that to 54.8% at rank 1 and 94.1% in the top 20, still short of BM25 at the top of the list on questions that share so many words with their paragraphs. Fusion ranks the right paragraph first slightly less often than BM25 alone, 72.6% against 75.4%, and finds it more often further down, with 91.8% in the top 5 and 98.4% in the top 20 against 91.0% and 96.0%. The two retrievers miss different questions, and fusion recovers many of each one's misses at the cost of sometimes demoting BM25's correct first choice. For a system that gives the model several passages, recall a few places down matters more than recall at rank 1, and at 5 and at 20 fusion is the best of the four.

=== Approximate search with HNSW

Exact dense search compares the question with every paragraph, which is fast enough for two thousand paragraphs and too slow for a billion. _Hierarchical navigable small-world graphs_ find near neighbours in roughly logarithmic time. Each vector is a node, linked to some of its nearest neighbours. Search is greedy. It starts at an entry point, moves to whichever neighbour is closest to the query, and stops when no neighbour is closer, keeping a list of the `ef` best candidates seen so that it does not stall in a local minimum. The hierarchy makes long jumps possible. Each node is also placed in higher layers with geometrically falling probability, and the sparse graphs of the higher layers carry a search across the collection before the dense bottom layer refines it.

#snippet("aif/hnsw.py", "levels", caption: [Each node's top layer, drawn geometrically])

#snippet("aif/hnsw.py", "search-layer", caption: [Best-first search within one layer, keeping the `ef` closest candidates])

#snippet("aif/hnsw.py", "insert", caption: [Inserting a node: descend greedily, then link to its nearest neighbours in each of its layers])

#snippet("aif/hnsw.py", "search", caption: [Search: greedy through the upper layers, wide at the bottom])

#console-part("/src/console/u3-retrieval.txt", from: 10, to: 14, command: false, caption: [HNSW over 21,000 paragraph embeddings])

The program indexes the paragraphs of SQuAD's training and validation splits together, 20,958 of them, to give the index more to search, and builds the graph in 19 seconds. With `ef` at 10, a search finds 86.8% of the exact top 10 while computing 210 distances per query, a hundredth of the 20,958 that exact search computes. At 32 it finds 95.3% for 365 distances, and at 100 it finds 99.0% for 780, still under 4% of the exhaustive count. Recall rises quickly with `ef` while the cost grows slowly, and `ef` is chosen per query at search time, without rebuilding the index.

A Python implementation is slower per query than NumPy's exact search at this size, because each step of the search is interpreted while the exact search is one matrix multiplication. The count of distances computed does not depend on the language, and it shows the algorithm's advantage. In compiled implementations such as FAISS and hnswlib, that advantage in distances becomes a speed advantage at a few hundred thousand vectors and an overwhelming one at a billion.

=== Retrieval-augmented answers

#snippet("u3/retrieval.py", "rag", caption: [Answering with passages in the prompt])

#console-part("/src/console/u3-retrieval.txt", from: 14, command: false, caption: [SmolLM2-360M-Instruct with and without passages, by token F1 against SQuAD's answers])

Without passages, SmolLM2-360M-Instruct's answers score 10.7% token F1, because a model this small holds little of what Wikipedia holds. Given the top three passages from the fused retriever it scores 25.2%, more than double, and given the right paragraph alone, 32.3%. Retrieval supplies 14.5 points of the 21.6 between no passages and the right one, most of the attainable gain. Even with the right paragraph in hand, the model scores only 32.3%, so at this size reading limits the system as much as retrieval does.

The gap between the right paragraph and the retrieved ones has two parts: questions whose paragraph was not retrieved, and questions whose paragraph was retrieved among distractors that the model was misled by. Lab 3.7.4 separates them.

#keyidea[
  Retrieval puts knowledge the model lacks into its prompt. A lexical baseline is strong when questions share words with documents, and contrastive training makes a language model a good dense retriever. Approximate indexes such as HNSW trade a little recall for search time that grows only logarithmically. The answers are limited by the retrieval and, in a small model, by its reading as well.
]

#inpytorch(title: [In the libraries])[
  `sentence-transformers` trains and runs embedding models with the losses of this chapter, FAISS and hnswlib provide HNSW and other indexes in C++, and vector databases wrap them with storage and filtering. Most practical systems combine a lexical and a dense retriever, often with a third, slower model to rerank the top results.
]

#reading(
  [Pranav Rajpurkar, Jian Zhang, Konstantin Lopyrev and Percy Liang, "SQuAD: 100,000+ Questions for Machine Comprehension of Text", EMNLP 2016.],
  [Stephen Robertson and Hugo Zaragoza, "The Probabilistic Relevance Framework: BM25 and Beyond", _Foundations and Trends in Information Retrieval_ 3(4), 2009.],
  [Vladimir Karpukhin and others, "Dense Passage Retrieval for Open-Domain Question Answering", EMNLP 2020.],
  [Yury Malkov and Dmitry Yashunin, "Efficient and Robust Approximate Nearest Neighbor Search Using Hierarchical Navigable Small World Graphs", _IEEE TPAMI_ 42(4), 2020.],
  [Patrick Lewis and others, "Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks", NeurIPS 2020.],
)

== Labs

#lab([BM25's parameters], goal: [Tune the lexical baseline on one half of the questions and test it on the other.], time: [1 hour], code: "code/u3/retrieval.py")[
  + Sweep $k_1$ over 0.5, 1.2 and 2.0 and $b$ over 0.25, 0.75 and 1.0 on the first half of the validation questions.
  + Evaluate the best setting on the second half.
  #done-when(
    [Your table has nine recall\@5 values, and you report one held-out result.],
  )
  #evidence([The table and the held-out result.])
]

#lab([Harder negatives], goal: [Improve the embedding model with negatives chosen by BM25.], time: [2 hours], code: "code/u3/retrieval.py")[
  + For each training question, take BM25's highest-ranked wrong paragraph as a hard negative, and add it to the batch alongside the in-batch negatives.
  + Train for the same number of steps and compare recall at 1, 5 and 20 with the original.
  #done-when(
    [You have both models' recalls.],
    [You can explain the change from examples of questions that moved.],
  )
  #evidence([The recalls and three examples.])
]

#lab([HNSW's trade-offs], goal: [Map recall against work for HNSW's parameters.], time: [1.5 hours], code: "code/aif/hnsw.py")[
  + Build indexes with `M` of 8, 16 and 32 over the 21,000 embeddings, recording build time.
  + For each, measure recall at 10 and distances per query for `ef` from 10 to 200, and plot recall against distances.
  #done-when(
    [Your plot has three curves.],
    [You can choose the setting that reaches 95% recall with the fewest distances.],
  )
  #evidence([The plot and the choice.])
]

#lab([Where answers are lost], goal: [Separate retrieval failures from reading failures.], time: [1.5 hours], code: "code/u3/retrieval.py")[
  + For the 300 questions, record whether the right paragraph was among the three retrieved, and the F1 with retrieved passages and with the right one.
  + Split the gap between the right paragraph's F1 and the retrieved passages' F1 into the part from retrieval misses and the part from distraction.
  #done-when(
    [Your two parts add up to the gap.],
    [You can show two questions where distractors misled the model.],
  )
  #evidence([The decomposition and the examples.])
]

#problems(
  [In BM25, what happens to a term that occurs in every document? What does $b = 0$ mean, and when might it be right?],
  [Contrastive training with batches of 32 has 31 negatives per question. Why might larger batches help, and what do they cost?],
  [Why do HNSW's layers use a geometric distribution of levels with ratio $1 \/ M$? How many layers does a graph of a million nodes with $M = 16$ have on average?],
  [Cosine similarity of normalised embeddings is a dot product. Why does that make exact search a matrix multiplication, and what is its arithmetic intensity?],
  [Retrieval puts three paragraphs of 150 tokens in the prompt. How does that change the cost of generating a 20-token answer with Chapter 2.7's KV cache?],
)

#checklist(
  [I can implement BM25 and explain its terms.],
  [I can turn a language model into an embedding model with contrastive training.],
  [I can implement HNSW and measure its recall against its cost.],
  [I can build a retrieval-augmented system and diagnose where it loses answers.],
  [Lab 3.7.1–3.7.4 done-when criteria all hold, with evidence filed.],
)
