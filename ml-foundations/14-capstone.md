# Module 14: Capstone

**Part IV · 2 weeks · Needs: everything. Data: Online Retail II, Banking77, Telco Customer Churn, or a dataset of your own.**

## Why this module

Every Oxford assignment is a small capstone: a dataset, a question, methods chosen and
justified, results against a baseline, limitations. This is a large one, and its point is
integration. You have built every component in isolation and tested each against a
library or a benchmark; you have not yet made a segmentation feed a churn model that
feeds a targeting decision that a RAG assistant can explain, with one experiment log,
one API and one report. The seams between components are where the time goes and where
the errors live, and a fortnight is enough to find that out on something small.

The second job is the report. Thirteen write-ups of 800 words have given you fluency;
the MSc assignments and any real project need 3,000 to 4,000 words that argue rather
than narrate, with an executive summary a manager reads and an appendix a marker checks.
Write it as if it were being submitted, because the next one will be.

## The brief

Every project, whichever option, must have:

- A business question with a stated decision it informs, and a metric that matches the
  decision rather than the model.
- A data card (Module 13's datasheet, shortened): source, size, what a row is, what was
  removed and why, the time split, and the leakage you prevented.
- A baseline for every predictive component (majority class, popularity, a logistic
  regression) with its number in the same table as yours.
- At least one unsupervised component, one supervised component and one LLM component,
  each with the evaluation its module taught you.
- Experiment tracking for every number in the report; a number without a run is not a
  result.
- pytest tests on the pipeline in the Module 13 style, at least schema, golden and
  training-smoke.
- A served endpoint with a schema, a health check and a model card.
- A report of 3,000 to 4,000 words in an extended `writeup-template.md`: the six headings,
  plus an executive summary of 200 words at the top and an appendix of experiments (every
  run that informed a decision, with its config and number).
- A ten-minute recorded talk with slides, made for a technical manager.
- A repo README that lets a stranger reproduce the headline result on a clean clone in
  under an hour: `uv sync`, one data command, one run command.

## Three project options

### Option A: Retail intelligence on Online Retail II

Scope: two years of transactions from a UK gift retailer, about a million rows and 5,900
customers with IDs. Segment customers on year one with the Module 3 pipeline; predict
next-quarter churn and spend per customer with a Module 2 gradient-boosted model on RFM
and segment features, trained on rolling quarters with a strict time split; learn product
embeddings and build a Module 4 recommender from co-purchase; write a RAG assistant over
your own segment reports and product-group summaries with a Module 10 eval set; simulate
a targeting campaign in the Module 12 style; serve the churn model with drift monitoring
and a model card from Module 13.

The hard part: there is no treatment in the data. The uplift component is a simulation:
define a retention offer whose effect depends on segment and recency in a way you
specify, apply it to a random half, and show your targeting recovers most of the oracle
profit. Be explicit that this tests the method, not the retailer.

Good looks like: a segmentation stable at ARI above 0.6 year over year with segments that
differ on year-two revenue; next-quarter churn AUC above 0.78 against a recency-only
baseline near 0.70; a recommender whose hit rate at 10 beats popularity by a stated
margin on a time-split test; recall@5 above 0.85 on 50 questions; a targeting policy
capturing at least 70% of oracle profit; an endpoint answering in under 50 ms.

### Option B: Support-desk intelligence on Banking77 plus generated tickets

Scope: the 13,083 Banking77 queries, plus 5,000 longer tickets you generate with an
Ollama model from the 77 intents, timestamped over twelve weeks, with an emerging issue
(a new intent such as "app crashes after update") injected and ramping in weeks nine to
twelve. Discover topics with embeddings, UMAP and HDBSCAN (Modules 3 and 4) and compare
them to the labels with ARI and NMI; classify intents with the Module 10 encoder; detect
the emerging issue as anomaly detection over weekly topic volumes (Module 8); build a RAG
agent that drafts replies with citations from a small policy corpus you write; produce
the governance mapping for a system that drafts messages to bank customers.

The hard part: generated tickets are not real tickets. Say so in the data card, measure
how separable they are from the real queries (a classifier that tells them apart is a
measure of your synthetic data's realism), and keep every headline number on the real
test set where one exists.

Good looks like: topic discovery with NMI above 0.6 against the 77 labels; intent
accuracy above 92% on the real test set; the injected issue detected within two weeks of
onset with at most one false alarm across the eight clean weeks; drafted replies scoring
above 0.8 on citation precision and a blind rubric; a mapping that reaches a defensible
tier with Article 50 considered.

### Option C: Your own domain

Scope: a dataset from your work, if you are allowed to use it, anonymised before it
touches the repo, meeting every requirement in the brief. Choose a question someone at
work actually asked; the report is then a document you can show them.

The hard part: permission and anonymisation, then scoping. Real data is messier than any
course set, and the temptation is to spend the fortnight cleaning it. Cap cleaning at two
days and put the rest in Limitations.

Good looks like: the same structure as A or B, with baselines chosen from what the
organisation does today, so that "beats the baseline" means "beats what we do now" and
the report can say what that is worth.

## Two-week plan

Ten working days. The order is fixed; the depth of each is yours.

1. Scope. Write the business question, the decision, the metric and the three
   components on one page. Write the data card. Draft the LLM component's evaluation set
   before any LLM code, as in Lab 10.3. Set up MLflow experiments and the repo layout.
2. Baselines. Every predictive component gets its majority, popularity or logistic
   baseline, tracked, with the test split fixed for the rest of the project.
3. The unsupervised component: clustering or topic discovery, with the model-selection
   evidence from Module 3 and a stability check.
4. The supervised component: the Module 2 pipeline with honest cross-validation,
   calibration and SHAP.
5. The LLM component: retrieval and generation against the day-one evaluation set, with
   the ablation table.
6. Integration and serving: the FastAPI endpoint, schema, health check, drift monitor,
   model card and tests.
7. Evaluation and ablations: seeds, confidence intervals, the table that shows what each
   component was worth, and the targeting or detection decision with its numbers.
8. The report: executive summary last, appendix from the MLflow export.
9. The talk: ten slides, one per decision, recorded in one take.
10. Buffer. Clone the repo fresh, follow the README, and time it. Fix what broke.

If you are on day six and the LLM component is not evaluated, cut its scope, not its
evaluation.

## Rubric

Mark yourself against it before recording the talk. The last column says what separates
a distinction from a pass in a marker's eyes.

| Criterion | Weight | Distinction looks like |
|---|---|---|
| Problem framing and business value | 15 | The decision is named, the metric follows from it, and the report says what a one-point improvement is worth in money or time. |
| Data understanding and cleaning | 15 | Every cleaning rule has a row count and a reason; leakage across time is discussed and prevented; the data card would let someone else use the data. |
| Method choice and justification | 20 | Each method is chosen against a named alternative for a reason tied to the data, and the report explains the mechanism, not just the name. |
| Evaluation rigour and baselines | 20 | Baselines are in every table; intervals or seeds are reported; the ablation shows what each component contributed; the eval set for the LLM component predates the system. |
| Engineering quality and reproducibility | 10 | Tests pass, a stranger reproduces the headline number in under an hour, and every number traces to a run. |
| Communication | 15 | The executive summary stands alone; figures earn their place; the talk makes one argument in ten minutes. |
| Limitations and ethics | 5 | Limitations are specific and quantified where possible, and the governance mapping reaches a tier with its obligations. |

## Common failure modes

- No baseline, so the headline number has nothing to be better than.
- Leakage across time: features computed with data from after the prediction date, which
  is easy to do with RFM on a transaction log.
- Choosing k by eye and calling it a segmentation.
- A metric that does not match the decision: AUC when the business acts on the top 5%.
- An LLM component with a demo and no evaluation set.
- A report that narrates what you did instead of arguing what is true and why.
- Running out of time on integration because it was left until the components were
  "finished".
- Cleaning for a week and modelling for two days.

## Deliverables

- `14-capstone/` with `README.md`, `data_card.md`, `model_card.md`, `serve/`, `tests/`,
  a package per component, and `report.md` with `appendix.md`.
- The recorded talk and its slides, linked from the README.
- The MLflow store exported to `appendix.md` as a table of runs.

## Done when

- A fresh clone reproduces the headline result in under an hour following only the
  README, and you have timed it.
- `uv run pytest` passes and `uv run ruff check .` is clean.
- Every number in the report appears in the appendix with a run name.
- Each of the three components beats its baseline on the fixed test split, with the
  margin and its uncertainty stated.
- The endpoint serves a prediction and a health check, and the model card is complete.
- The report is between 3,000 and 4,000 words, the executive summary is under 200, and the
  talk is under ten minutes.
- You have marked yourself against the rubric and written one sentence per row on what
  you would change with another week.

## After the course

Keep the labs repo alive through the MSc. Each one-week course ends with an assignment on
a dataset, and the fastest start is a copy of the relevant module's pipeline with the data
swapped: Module 2 and 3 for Classical Machine Learning, Module 5 and 6 for Deep Neural
Networks and Computer Vision, Module 10 for Generative AI with LLMs, Module 4's
embeddings and the Module 10 stretch on triples for Knowledge Graphs, Module 13's
adversarial and privacy work for Security and Privacy of ML, Module 13's ONNX path for
Edge AI, and Modules 12 and 13 for the governance and decision courses. Before each
course week, re-read that module's Core ideas and re-run its headline lab; it takes an
evening and turns the week into revision.

Three suggestions for reading in the weeks before the first three ML courses. Before
Classical Machine Learning, work through James, Witten, Hastie, Tibshirani, *An
Introduction to Statistical Learning with Python*, ch. 4-6 and 8-10, doing the labs; it
is the register the course speaks in. Before Deep Neural Networks, read Prince,
*Understanding Deep Learning*, ch. 6-11 in one pass for the vocabulary of optimisation,
regularisation and architectures, and Bishop and Bishop, *Deep Learning*, ch. 12 on
transformers. Before Generative AI with LLMs, read Jurafsky and Martin's ch. 10-12 again
and Huyen's *AI Engineering* ch. 4-6, then re-run Lab 10.3 on a corpus from your own work,
because the assignment will ask for exactly that with the justification you have now
written thirteen times.
