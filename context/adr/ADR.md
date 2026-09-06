---
doc_type: adr
status: draft  # draft | active | deprecated | superseded
last_updated: YYYY-MM-DD
verified_on: null  # ADRs record rationale, not host behaviour — normally stays null
verification: Not applicable — records a decision and its rationale.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `ADR-NNN-<short-title>.md` — zero-padded, sequential, no gaps.
> Check the highest number in `context/adr/` **and** `context/archive/` before assigning.
> Never modify an accepted ADR: amend it, or supersede it with a new one.

# ADR-NNN: \<Title\>

## Context

(What problem or constraint forced a decision? Include the constraints that were actually
binding — the 2 GB host, EU residency, two of four users being children, one operator.)

## Decision

(What was decided. State it in one sentence before elaborating.)

## Alternatives Considered

(Options and why they were rejected.)

> **Record the dead ends that looked correct.** Several of this deployment's most expensive
> lessons are approaches that failed *silently* — a config key accepted and never resolved,
> a model name substituted without error, the wrong one of two same-named credentials. An
> ADR that documents only the winner invites the next person, or the next agent, to retry
> the loser at the same cost.
>
> For each rejected alternative worth recording: **what was tried**, **how it failed**, and
> **how the failure presented** — since the ones worth writing down are precisely the ones
> that did not announce themselves.

## Consequences

(Trade-offs and long-term impact. What does this foreclose? What now has to stay true —
and is that property captured in a SPEC? Which CONTRACTs does it fix values in?)

---

> No requirements, no procedures, no credential values.
