#import "../lib/template.typ": *

= Reference library <h-library>

The course is self-contained, but it stands on a literature that you should know your way around. This part lists the books worth owning or bookmarking, the documentation the code relies on, and the papers each unit is built on. Every chapter's reading list draws on it.

== Books

- *Simon Prince, _Understanding Deep Learning_*, MIT Press, 2023. The clearest modern textbook, with excellent figures; free online. The companion text for Units 1 and 2.
- *Christopher Bishop and Hugh Bishop, _Deep Learning: Foundations and Concepts_*, Springer, 2024. More mathematical, strong on probability; free to read online.
- *Kevin Murphy, _Probabilistic Machine Learning: An Introduction_* and *_Advanced Topics_*, MIT Press, 2022 and 2023. The reference for the probabilistic view of everything; free drafts online.
- *Ian Goodfellow, Yoshua Bengio and Aaron Courville, _Deep Learning_*, MIT Press, 2016. Older, but its chapters on optimisation and regularisation remain the standard account.
- *Daniel Jurafsky and James Martin, _Speech and Language Processing_*, third edition draft. N-gram models, smoothing and tokenisation, for Chapters 2.1 and 2.2.
- *Mark Peter Deisenroth, A. Aldo Faisal and Cheng Soon Ong, _Mathematics for Machine Learning_*, Cambridge University Press, 2020. The mathematics of Part 3, at a gentle pace; free online.

== Documentation

- *The PyTorch documentation*, in particular "Autograd mechanics", "CUDA semantics", the `torch.nn` and `torch.optim` references, and the notes on numerical accuracy and reproducibility.
- *The Hugging Face documentation* for the `safetensors` format, the `tokenizers` library's model types, and the model cards of SmolLM2 and the datasets in Part 5.
- *Apple's Metal Shading Language Specification* and *the Vulkan specification*, for the two tracks of Chapter 4.4.

== Courses and talks

- *Andrej Karpathy, "Neural Networks: Zero to Hero"*, a video series that builds a scalar autograd engine and a GPT, much as Units 1 and 2 do.
- *Stanford CS336, "Language Modeling from Scratch"*, a university course on the material of Units 2 to 4, with assignments at larger scale.

== Papers by unit

*Unit 1.* Glorot and Bengio (2010) on initialisation; He and others (2015) on rectifiers; Kingma and Ba (2015), Adam; Loshchilov and Hutter (2019), AdamW; Srivastava and others (2014), dropout; Ioffe and Szegedy (2015), batch normalisation; Ba, Kiros and Hinton (2016), layer normalisation; He and others (2016), residual networks; Zhang and others (2017), rethinking generalisation; Belkin and others (2019), double descent; Chen and others (2020), SimCLR.

*Unit 2.* Sennrich, Haddow and Birch (2016), byte-pair encoding; Bengio and others (2003), a neural probabilistic language model; Vaswani and others (2017), "Attention Is All You Need"; Radford and others (2019), GPT-2; Su and others (2021), rotary position embeddings; Shazeer (2020), GLU variants; Ainslie and others (2023), grouped-query attention; Eldan and Li (2023), TinyStories; Kaplan and others (2020) and Hoffmann and others (2022), scaling laws; Holtzman and others (2020), nucleus sampling; Olsson and others (2022), induction heads.

*Unit 3.* Allal and others (2025), SmolLM2; Ouyang and others (2022), InstructGPT; Hu and others (2022), LoRA; Dettmers and others (2023), QLoRA; Rafailov and others (2023), DPO; Shao and others (2024), DeepSeekMath and GRPO; Lewis and others (2020), retrieval-augmented generation; Malkov and Yashunin (2018), HNSW; Yao and others (2023), ReAct; Zheng and others (2023), LLM-as-a-judge.

*Unit 4.* Williams, Waterman and Patterson (2009), the roofline model; Micikevicius and others (2018), mixed-precision training; Dao and others (2022), FlashAttention; Rajbhandari and others (2020), ZeRO; Shoeybi and others (2019), Megatron-LM; Huang and others (2019), GPipe; Frantar and others (2023), GPTQ; Kwon and others (2023), PagedAttention and vLLM; Leviathan, Kalman and Matias (2023), speculative decoding; Yu and others (2022), Orca and continuous batching.
