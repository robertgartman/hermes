---
doc_type: prd
status: draft  # draft | active | deprecated | superseded
last_updated: YYYY-MM-DD
verified_on: null  # PRDs state intent, not observed behaviour — normally stays null
verification: Not applicable — states product intent, not host behaviour.
must_not_contain:
  - secrets
  - implementation_details
  - config_keys
  - deployment_procedures
audience: [ai, operator, product]
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `PRD-<capability-name>.md` — e.g. `PRD-jupyter-tutor.md`
>
> **Low-frequency type.** Reach for a PRD only when there is genuine unbuilt product
> thinking to hold: scope, phasing, behavioural rules, who it is safe for. A capability that
> is obviously worth having does not need one.

# Product Requirements Document

## Purpose

Why this capability exists and how success is measured. High-level; a north star.

## Problem Statement

(What problem is being solved, for this family specifically?)

## Goals

## Non-Goals

(Be generous here — this is a household, not a platform team.)

## Who This Is For

(Which family members. **Name ages and capability where they change the safety posture** —
an agent with shell access serving a child is a different product from one serving an
adult.)

## Success Criteria

(Prefer observable outcomes over metrics. There is no analytics stack here.)

## Constraints

(Cost ceiling, EU data residency, the 2 GB host budget, child safety, operator time. State
the number where one exists.)

## Risks & Open Questions

(Anything currently unresolved *on the live host* belongs in [STATE.md](../STATE.md) — link,
don't duplicate.)

---

> No implementation details, config keys or procedures. Minimize code examples.
> **Be less prescriptive and more declarative.**
