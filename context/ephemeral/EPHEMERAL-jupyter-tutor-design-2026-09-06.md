---
doc_type: ephemeral
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  Nothing here has been built or tested. This is a design exploration, not a record of
  observed behaviour.
must_not_contain:
  - secrets
authoritative: false
retrieval_priority: low
related_documents:
  - PRD-jupyter-tutor
created: 2026-09-06
---

> **Design exploration, not a decision.** This document was written before anything was
> built and records one proposed architecture for a Jupyter-based tutor. It governs nothing.
>
> Product intent extracted from it lives in
> [PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md). The architecture below has **not** been
> decided — if and when it is, the load-bearing choices become ADRs and this document is
> archived.
>
> Original filename: `HERMES_JUPYTER_TUTOR.md`.

---

# Hermes + Jupyter as an Interactive School Tutor

## Goal

Build a school-focused assistant where **Jupyter is the learning workspace** and **Hermes is the orchestrator/coding agent**.

The intended audience is roughly Year 10-12, with a particular emphasis on:

- mathematics
- physics
- chemistry
- biology
- programming
- data analysis
- scientific reasoning
- interactive exercises
- textbook/photo interpretation
- generated graphs and diagrams

The core idea is that the student should not just chat with an LLM. They should work inside an **executable notebook** where explanations, code, calculations, visualizations, experiments, and follow-up questions live together.

---

## Recommended architecture

```text
JupyterLab / Notebook UI
│
├── Markdown cells
├── Python cells
├── plots / tables / outputs
├── optional Hermes sidebar
└── optional %%hermes cell magic
        │
        ▼
    Hermes agent
        │
        ├── main reasoning model
        │   └── e.g. Qwen3.5-397B via Scaleway
        │
        ├── live Jupyter kernel access
        ├── terminal / filesystem tools
        ├── web / search tools
        ├── image understanding
        ├── image generation provider
        └── sub-agents / coding tools
```

The important design choice is to keep Hermes as the **orchestrator** and let Jupyter remain the **computational workspace**.

Hermes should not merely generate code snippets. It should be able to inspect the notebook state, edit cells, execute code, read outputs, and explain results.

---

## Why Jupyter fits this use case

Jupyter is unusually well suited for school-level STEM tutoring because it combines:

- explanation
- equations
- executable code
- plots
- data
- experiments
- persistent state
- reproducible work

A normal chatbot can say:

> The maximum projectile range occurs at 45 degrees.

A Jupyter-integrated agent can instead:

1. derive the result,
2. verify it numerically,
3. plot the result,
4. let the student change assumptions,
5. ask the student to predict what happens next.

That is a much better educational loop.

---

## Live-kernel interaction

The most useful behavior is for Hermes to work against the **same live kernel** as the notebook.

That allows interactions such as:

> Use the dataframe we created earlier.

> Change only the timestep and rerun the simulation.

> Plot this using the variables already defined above.

> Explain why the result changed.

> Add an exercise beneath this cell, but hide the solution.

Because the kernel is persistent, Hermes can reason about the notebook as an evolving computational environment rather than a collection of disconnected prompts.

---

## Two good interaction models

### 1. Hermes sidebar

A persistent chat panel beside the notebook.

```text
┌──────────────────────────────┬────────────────────────────┐
│ Notebook                     │ Hermes                     │
│                              │                            │
│ code                         │ "Why does this diverge?"   │
│ plots                        │                            │
│ markdown                     │ explanation                │
│ outputs                      │ suggested fix              │
│                              │ tool actions               │
└──────────────────────────────┴────────────────────────────┘
```

This is likely the best general-purpose UX for students.

Useful actions:

- explain selected cell
- debug current notebook
- generate an exercise
- simplify explanation
- check a calculation
- create a graph
- inspect variables
- summarize the lesson
- quiz me on this notebook

### 2. `%%hermes` notebook magic

A custom notebook cell magic could provide a reproducible conversational interface.

Example:

```python
%%hermes
Explain the graph above and create a harder version of this exercise.
```

Hermes could then insert:

- a Markdown explanation,
- a new code cell,
- a generated plot,
- or a practice question below the current cell.

This is particularly attractive because the **student's question remains in the notebook**.

The notebook itself becomes a record of:

```text
lesson
→ student question
→ Hermes explanation
→ experiment
→ output
→ follow-up question
```

That is often more useful than a detached chat history.

---

## Best UX: combine both

The strongest design is probably:

- a persistent Hermes sidebar for ongoing conversation
- `%%hermes` for reproducible, notebook-native prompts

The sidebar is convenient.

The cell magic is durable and auditable.

---

## Example school workflow

A physics notebook could look like this:

```text
# Projectile motion

[Markdown]
Basic theory and equations

[Python]
Initial parameters

[Python]
Simulation

[Plot]
Trajectory

[Hermes interaction]
"Why is the trajectory no longer symmetric when I add air resistance?"

[Python generated/edited by Hermes]
Air-resistance model

[Plot]
Comparison

[Exercise generated by Hermes]
Predict what happens if mass doubles.

[Student response]

[Hermes]
Feedback and explanation
```

This turns the notebook into an **interactive computational textbook**.

---

## Recommended model/tool split

Do not force one model to perform every task.

A better architecture is:

| Responsibility | Suggested component |
|---|---|
| Reasoning and tutoring | Qwen3.5-397B or another strong LLM |
| Textbook/photo understanding | multimodal vision-capable model |
| Exact arithmetic | Python |
| Algebra/calculus verification | SymPy |
| Numerical simulation | NumPy / SciPy |
| Graphs | Matplotlib / Plotly |
| Tabular work | pandas |
| Image generation | dedicated image-generation model |
| Web research | Hermes web/search tools |
| Files and codebase work | Hermes filesystem/terminal tools |

The LLM decides **what should be done**.

Deterministic tools should handle tasks where exactness matters.

---

## Why this matters for educational reliability

LLMs are good at explanations and pattern recognition, but they can still:

- make algebra mistakes
- misread diagrams
- hallucinate constants
- invent references
- produce plausible-looking but wrong graphs
- skip steps

Jupyter gives Hermes the ability to **verify** rather than merely answer.

For example, instead of simply asserting a result, Hermes can run:

```python
import sympy as sp

x = sp.symbols("x")
expr = x**2 - 4*x + 3

sp.solve(expr, x)
```

and then explain the result.

This greatly improves trustworthiness.

---

## Preferred STEM toolchain

A useful base environment could contain:

```text
python
numpy
scipy
pandas
matplotlib
sympy
scikit-learn
networkx
jupyterlab
ipywidgets
```

Optional additions:

```text
plotly
rdkit
statsmodels
pint
astropy
```

depending on subjects.

---

## Scientific visualization

For exact scientific graphs, prefer deterministic plotting over generative images.

Examples:

- functions
- trajectories
- distributions
- vectors
- waveforms
- scatter plots
- phase diagrams
- statistical graphs

Use Matplotlib, Plotly, or similar.

Image generation is more appropriate for:

- conceptual illustrations
- labeled educational scenes
- simplified biological diagrams
- visual metaphors
- historical illustrations

---

## Notebook organization

Instead of one giant tutor conversation, create notebooks by topic.

Example:

```text
physics/
    mechanics.ipynb
    waves.ipynb
    electricity.ipynb

math/
    algebra.ipynb
    calculus.ipynb
    statistics.ipynb
    vectors.ipynb

chemistry/
    stoichiometry.ipynb
    acids_bases.ipynb
    organic_intro.ipynb
```

Each notebook becomes both:

- a lesson
- an experiment
- a revision resource
- a history of student questions

---

## Educational behavior rules

Hermes should be configured to act more like a tutor than an answer engine.

Good defaults:

1. Prefer hints before full solutions.
2. Ask the student to predict outcomes before executing experiments.
3. Explain reasoning step by step when appropriate.
4. Verify arithmetic and algebra with tools.
5. Distinguish assumptions from facts.
6. State when an image or problem is ambiguous.
7. Avoid confidently inventing facts.
8. Generate practice problems at an appropriate difficulty level.
9. Adapt explanations to the student's current level.
10. Encourage the student to explain results back in their own words.

For assessed homework, it may be useful to support a mode such as:

```text
Tutor mode:
- do not immediately give the final answer
- guide with progressively stronger hints
- reveal the complete solution only when explicitly requested
```

---

## Hermes should remain outside the kernel

A clean architecture is:

```text
Browser
│
├── JupyterLab
│   └── Python kernel
│
└── Hermes UI/service
    ├── model provider
    ├── Jupyter integration
    ├── terminal
    ├── files
    └── external tools
```

or:

```text
JupyterLab
│
├── normal notebook
└── Hermes sidebar
    │
    ▼
local Hermes service
    ├── Scaleway API
    ├── Jupyter kernel
    ├── filesystem
    └── tools
```

This keeps the notebook environment replaceable and the orchestration layer independent.

The model provider can later be swapped without changing notebooks.

---

## Sandboxing and security

For children, avoid giving the agent unrestricted access to the host machine.

A safer setup is:

```text
Docker container
├── JupyterLab
├── Python environment
├── lesson notebooks
├── selected datasets
└── controlled writable workspace
```

Hermes operates inside that environment.

The host machine should not expose:

- SSH credentials
- browser profiles
- private documents
- unrelated source repositories
- password stores
- arbitrary host filesystem access

A disposable or easily restorable environment is ideal.

---

## Suggested Docker-level architecture

```text
docker compose
│
├── jupyter
│   ├── JupyterLab
│   ├── scientific Python stack
│   └── notebooks volume
│
└── hermes
    ├── Hermes agent
    ├── access to Jupyter API
    ├── selected shared workspace
    └── external model/API credentials
```

Possible shared volume:

```text
./workspace:/workspace
```

The notebook service and Hermes can both operate on that directory.

---

## `%%hermes` concept

A simple implementation could expose Hermes as a local HTTP service.

Pseudo-interface:

```text
POST /chat
POST /notebook/edit
POST /notebook/run
GET  /notebook/state
```

Then define a Jupyter magic:

```python
from IPython.core.magic import register_cell_magic

@register_cell_magic
def hermes(line, cell):
    response = send_to_hermes(
        notebook=current_notebook(),
        prompt=cell,
    )
    display_response(response)
```

A more advanced version could let Hermes return structured notebook actions:

```json
{
  "message": "I added a numerical comparison below.",
  "actions": [
    {
      "type": "insert_code_cell",
      "source": "..."
    },
    {
      "type": "run_cell"
    }
  ]
}
```

This is preferable to letting arbitrary generated text mutate the notebook directly.

---

## Useful Hermes commands for a student

Potential UX shortcuts:

```text
/explain
/check
/hint
/solve
/quiz
/simplify
/visualize
/derive
/debug
/summarize
/practice
```

Examples:

```text
/check
Verify my derivation above.
```

```text
/hint
Give me one hint without revealing the answer.
```

```text
/quiz
Create five questions based only on this notebook.
```

```text
/visualize
Show what this equation means geometrically.
```

---

## Parent/teacher controls

A useful future layer could include:

### Difficulty

```text
Year 10
Year 11
Year 12
First-year university
```

### Assistance level

```text
Socratic
Hints
Guided solution
Full solution
```

### Subject mode

```text
Math
Physics
Chemistry
Biology
Programming
General
```

### Verification mode

```text
Normal
Strict
```

Strict mode could require:

- numeric answers checked in Python
- symbolic algebra checked in SymPy
- citations for external factual claims
- explicit uncertainty for ambiguous images

---

## Why Hermes is a good fit

Hermes is most useful here as an **agent**, not merely a chat model wrapper.

The orchestration layer can decide that a task requires:

- reasoning
- notebook inspection
- code generation
- execution
- graph generation
- image understanding
- file editing
- external research

That is exactly what a notebook-based tutor needs.

The model should be the planner and explainer.

The tools should perform the work.

---

## Suggested initial implementation

Avoid trying to build the entire ideal interface immediately.

### Phase 1

Get the basic stack working:

```text
Hermes
+ Scaleway model
+ JupyterLab
+ shared notebook directory
+ scientific Python environment
```

Test whether Hermes can reliably:

- inspect notebooks
- execute code
- inspect variables
- edit cells
- create plots

### Phase 2

Add student-friendly behavior:

- tutor system prompt
- hint mode
- strict verification
- age/grade setting
- exercise generation

### Phase 3

Add notebook-native UX:

- `%%hermes`
- sidebar
- selected-cell context
- insert/run controls

### Phase 4

Add multimodal features:

- textbook photos
- diagrams
- image generation
- document ingestion

---

## Suggested proof-of-concept notebooks

Before investing heavily in UI, test the concept with several real lessons.

### Mathematics

- quadratic functions
- systems of equations
- derivatives
- probability

### Physics

- projectile motion
- harmonic motion
- circuits
- waves

### Chemistry

- stoichiometry
- pH
- equilibrium
- reaction rates

For each notebook, test whether the agent can:

1. understand the lesson,
2. answer correctly,
3. manipulate the live notebook,
4. create useful visualizations,
5. generate exercises,
6. verify its own results,
7. teach rather than merely answer.

---

## Model strategy

A reasonable starting point is:

```text
Primary:
Qwen3.5-397B via Scaleway

Routine/cheap tasks:
Qwen3.6-35B-A3B

Exact work:
Python / SymPy / SciPy

Image generation:
separate dedicated provider
```

Model routing can be added later.

Initially, simplicity is probably more valuable than saving small amounts of inference cost.

---

## Key design principle

The best version of this system is not:

```text
student → chatbot → answer
```

It is:

```text
student
   ↓
Hermes
   ↓
reason → inspect → calculate → experiment → verify → explain
   ↓
living Jupyter notebook
```

The notebook becomes an **interactive, executable textbook** and Hermes becomes the tutor, laboratory assistant, and coding agent around it.

That is likely a substantially better learning environment than a conventional standalone AI chat interface.
