---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records a decision about scope and policy. Nothing here asserts host behaviour.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator, product]
supersedes: null
superseded_by: null
related_documents:
  - ADR-015-two-tier-security-model
  - ADR-001-one-os-user-per-member
  - SPEC-tutor-isolation
  - PRD-jupyter-tutor
created: 2026-09-06
---

# ADR-016: All family members are treated alike; no age-based capability restrictions

## Context

This repository has consistently described two of the four members as "children" and treated
that as grounds for reduced capability. [STATE.md](../STATE.md) carried the absence of such
restrictions as **OQ-4, "the most significant open gap"**, and successive analyses proposed
approval modes, restricted toolsets, skill pruning and removal of their public endpoints.

Two facts settle it. **Mattis and Love are 16 and 17** — near-adults, not small children. And
the operator, who is their parent, has decided they are to be treated **no differently from
the adults**, with no bespoke per-member setup.

That is a parenting decision, not a technical one, and it belongs to the operator. The
repository's job is to record it and stop re-proposing the alternative.

## Decision

**All four members receive identical capability. No restriction is applied to any member on
the basis of age, and no member gets a bespoke configuration.**

Concretely, and explicitly **not** to be built:

- No per-member approval mode, toolset allowlist or skill pruning aimed at Mattis or Love.
- No removal of their API-server endpoints or messaging channels.
- No per-member systemd drop-ins, capability caps or filesystem restrictions beyond the
  uniform posture every member already has.

**OQ-4 is closed as decided, not deferred.** It was never an unknown awaiting research; it was
a question whose answer was the operator's to give.

Whatever [ADR-015](ADR-015-two-tier-security-model.md) Tier 2 achieves is applied **uniformly
to all four members**, or not at all.

## Alternatives Considered

**Age-tiered capability.** Rejected by the operator. Worth recording that the technical
analysis behind it was sound but answered the wrong question: it established what *could* be
restricted, never whether it *should* be. Several rounds of work optimised a constraint nobody
had asked for.

**Keep OQ-4 open pending "child-safety controls".** Rejected. Leaving it open would invite the
next contributor — or the next agent — to re-derive the same proposals and re-propose them.
That is precisely the waste ADRs exist to prevent.

**Restrict capability for everyone instead.** Not chosen. It would be uniform, but nobody
asked for a less capable platform; the four agents exist to be useful.

## Consequences

**The sandbox isolation requirements are unaffected, and must not be relaxed by
misreading this.** [SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) requires that no
Jupyter kernel listens without authentication and that the sandbox cannot reach a family
gateway. Those exist because **a kernel is arbitrary code execution reachable over a network**,
not because of anyone's age. They apply identically for a 45-year-old.

**Cross-member measures already built stay**, because they were never age-based: the per-uid
network rules make each member's endpoint private to that member — symmetric, and as true for
Robert as for Love.

**Prose describing members as "children" needing protection is now misleading** wherever it
implies differential treatment. Accepted ADRs are not edited; this document supersedes that
framing. STATE and the PRD should describe the audience by school year rather than by an
implied capability tier.

**Any future per-member restriction requires its own ADR** explaining why it is not uniform.
The default is now equality, and departures must be argued.
