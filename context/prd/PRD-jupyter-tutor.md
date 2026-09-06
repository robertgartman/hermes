---
doc_type: prd
status: draft
last_updated: 2026-09-06
verified_on: null
verification: Product intent for an unbuilt capability. Nothing here has been implemented.
must_not_contain:
  - secrets
  - implementation_details
  - config_keys
  - deployment_procedures
audience: [ai, operator, product]
related_documents:
  - PRD-family-agent-platform
created: 2026-09-06
---

# Jupyter School Tutor

> **Nothing here is built.** This records product intent for a possible second capability on
> the existing family platform. The proposed architecture — sidebar, cell magic, container
> layout, model split — is a separate exploration and is **not decided**: see
> [EPHEMERAL-jupyter-tutor-design-2026-09-06](../ephemeral/EPHEMERAL-jupyter-tutor-design-2026-09-06.md).

## Purpose

A school-focused assistant where **Jupyter is the learning workspace** and **Hermes is the
orchestrator**.

## Problem Statement

A student chatting with an LLM gets answers. A student working in an executable notebook gets
a place where explanation, code, calculation, visualisation, experiment and follow-up
question live together — and where every claim can be checked by running it.

The distinction is the entire point of the capability:

```
not:  student → chatbot → answer
but:  student → notebook → executed, inspectable result
```

## Goals

- The student works **inside** an executable notebook, not in a chat window beside one.
- Hermes can inspect notebook state, edit cells, execute code and read outputs — not merely
  emit code snippets.
- Arithmetic and algebra are **verified with tools**, not asserted by the model.
- Explanations adapt to the student's current level.

## Non-Goals

- Not a homework-answering service. For assessed work the default posture is hints before
  solutions, with the full solution revealed only on explicit request.
- Not a replacement for the messaging-based agents the family already has.
- Not a general programming environment — the subject scope is school STEM.

## Who This Is For

Roughly **Year 10–12**. Within this family that means **Mattis and Love**.

**Both are children, and the platform they would run on gives agents shell access.** The
child-safety controls that this capability would need are the same ones currently unset on
the existing deployment — OQ-4 in [STATE.md](../STATE.md). That gap is a **prerequisite**,
not a parallel workstream: shipping a tutor for children on top of unrestricted
shell-capable agents would make an already-open question materially worse.

Subject emphasis: mathematics, physics, chemistry, biology, programming, data analysis,
scientific reasoning, textbook/photo interpretation, generated graphs and diagrams.

## Behavioural Requirements

The tutor is configured to behave like a tutor rather than an answer engine:

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

## Parent/Teacher Controls

Four axes, intended as a later layer rather than a first deliverable:

| Control | Values |
|---|---|
| Difficulty | Year 10 · Year 11 · Year 12 · First-year university |
| Assistance level | Socratic · Hints · Guided solution · Full solution |
| Subject mode | Math · Physics · Chemistry · Biology · Programming · General |
| Verification mode | Normal · Strict |

**Strict verification** requires numeric answers checked in Python, symbolic algebra checked
in SymPy, citations for external factual claims, and explicit uncertainty for ambiguous
images.

## Success Criteria

Phase 1 succeeds if Hermes can reliably inspect notebooks, execute code, inspect variables,
edit cells and create plots. Everything after that is UX.

Judge the concept on **real lessons** in proof-of-concept notebooks before investing in
interface work.

## Constraints

- **Host capacity.** The existing VPS runs at ~860 MB available with four gateways and
  SearXNG (see [STATE.md](../STATE.md)), and real-load memory is unmeasured (OQ-3). A
  JupyterLab instance plus a scientific Python stack does not obviously fit; this capability
  may require the `DEV1-M` resize or a separate host.
- **Child safety is a blocker, not a caveat** — see *Who This Is For*.
- **Cost.** No per-member spend attribution or cap exists today (OQ-1, OQ-2). A tutor
  encourages sustained, iterative use — exactly the usage pattern those unresolved questions
  are about.
- **Operator time.** One operator, part time.

## Phasing

| Phase | Scope |
|---|---|
| 1 | Basic stack: Hermes + Scaleway model + JupyterLab + shared notebook directory + scientific Python environment |
| 2 | Student-friendly behaviour: tutor prompt, hint mode, strict verification, grade setting, exercise generation |
| 3 | Notebook-native UX: cell magic, sidebar, selected-cell context, insert/run controls |
| 4 | Multimodal: textbook photos, diagrams, image generation, document ingestion |

Avoid building the ideal interface first. Simplicity is worth more early than saving small
amounts of inference cost.

## Risks & Open Questions

- **Does it fit on the host at all?** Unmeasured, and the most likely reason this stalls.
- **Does keeping Hermes outside the kernel hold up in practice?** The design exploration
  argues it should; nothing has tested it.
- **Does hint-first behaviour survive a motivated teenager?** A tutor whose solution mode is
  one request away may be indistinguishable from an answer engine in practice.
