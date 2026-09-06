---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records a design decision for an unbuilt capability. Nothing implemented.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - PRD-jupyter-tutor
  - ADR-010-hermes-outside-the-jupyter-kernel
created: 2026-09-06
---

# ADR-012: The model decides what to do; deterministic tools do the exact work

> **Decided, not built.** Constrains the Jupyter tutor
> ([PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md)).

## Context

A tutor that states a wrong answer confidently is worse than no tutor. A student cannot
distinguish a fluent wrong derivation from a correct one — that is precisely the skill they
are still acquiring — so ordinary model fallibility lands differently here than in an adult's
coding assistant, where the user is the check.

The notebook makes a better option available. Anything that can be computed can be computed
*in the notebook*, in front of the student, where the result is inspectable and re-runnable.

## Decision

**The model decides what should be done. Deterministic tools do anything where exactness
matters**, and their output is what the student sees.

| Responsibility | Component |
|---|---|
| Reasoning and tutoring | the main chat model |
| Textbook / photo understanding | a vision-capable model |
| Exact arithmetic | Python |
| Algebra and calculus verification | SymPy |
| Numerical simulation | NumPy / SciPy |
| Graphs | Matplotlib / Plotly |
| Tabular work | pandas |
| Web research | Hermes web/search tools |
| Files and code | Hermes filesystem/terminal tools |

Base environment: `numpy`, `scipy`, `pandas`, `matplotlib`, `sympy`, `scikit-learn`,
`networkx`, `jupyterlab`, `ipywidgets` — with `plotly`, `rdkit`, `statsmodels`, `pint` and
`astropy` added per subject as needed.

This is what makes the PRD's **strict verification mode** implementable rather than
aspirational: numeric answers checked in Python, symbolic algebra checked in SymPy.

## Alternatives Considered

**Let the model compute directly and state results.** Rejected. It fails silently and
plausibly, which is the worst possible failure mode for a learner, and it forfeits the one
advantage a notebook has over a chat window.

**Ask the model to compute, then verify with tools afterwards.** Rejected as the default. It
doubles cost and latency, and creates a contradiction the student must adjudicate when the two
disagree — the wrong person to arbitrate.

**Start with one model doing everything, split later if quality demands.** Rejected *for
exactness specifically*, and accepted everywhere else: the PRD deliberately favours simplicity
over premature optimisation, and model **routing** can come later. But arithmetic and algebra
are not a tuning problem to revisit — they are the thing the tutor exists to get right.

**A cheaper model for routine work.** Deferred, not rejected. A plausible later addition once
usage patterns are known; simplicity is worth more than small inference savings at the start,
and per-member spend is neither attributable nor capped today (OQ-1, OQ-2 in
[STATE.md](../STATE.md)).

## Consequences

- **The scientific Python stack becomes a hard dependency**, not an optional extra, which
  raises the sandbox's footprint and makes host placement a real constraint — see
  [ADR-011](ADR-011-tutor-sandbox-isolation.md).
- **Auxiliary tasks must stay on the EU provider.** A vision-capable model for textbook photos
  must not silently route outside the EU; the existing deployment holds this by keeping
  auxiliary models at `provider: auto`
  ([ADR-003](ADR-003-scaleway-eu-inference.md)), and photographs of a child's homework are
  exactly the content that rule exists for.
- **Image generation has no backend today** (STATE.md), so any tutor feature depending on
  generated diagrams is blocked until one exists.
- Tool output the student can re-run is the deliverable. A correct answer the student cannot
  check is a failure of this ADR even when the answer is right.
