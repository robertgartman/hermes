---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a decision and the priority behind it. The external-boundary audit that accompanied
  it was executed on 2026-09-06 and its results live in SPEC-agent-access-control.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents:
  - ADR-001-one-os-user-per-member
  - ADR-006-public-api-exposure
  - SPEC-agent-access-control
  - SPEC-profile-isolation
created: 2026-09-06
---

# ADR-015: External access is a strict requirement; inter-member isolation is best effort

## Context

Until now this deployment treated its two security concerns as though they carried equal
weight: keeping outsiders out, and keeping the four family members apart. That produced a
recurring deadlock.

Cross-member isolation cannot be made absolute here. The agents share one host and one
loopback interface, and every constraint Hermes itself offers is read from a config file the
member owns and their own shell can edit. Work kept stalling on the question "is this a real
boundary?" when applied to a **family**, where the honest answer is that best achievable
separation between four people who trust each other is a different goal from keeping the
internet out.

Meanwhile the genuinely absolute requirement — that **no external person reaches the system or
its data** — was being verified less rigorously than the internal one. One of its criteria,
the negative authentication test in
[SPEC-agent-access-control](../spec/SPEC-agent-access-control.md), had **never been executed**
against the live host.

## Decision

**Two tiers, with different standards of proof.**

**Tier 1 — External access. Strict, absolute, non-negotiable.**
No person outside the family may reach the solution or any of its data. Every criterion is
executable, and any gap is a defect to be fixed immediately rather than recorded as an open
question. This tier owns: the host firewall's inbound policy, the SSH posture, the TLS
termination and its certificates, the authentication on every published endpoint, and **what
an unauthenticated request can learn** — including metadata.

**Tier 2 — Between family members. Best effort.**
Strive for the strongest separation the architecture affords, and prefer OS-enforced controls
where they are available and cheap. But application-level measures — approval modes, tool
allowlists, skill pruning — are **legitimate and useful here**, provided they are labelled as
defence in depth and never described as boundaries. A shortfall in this tier is a tracked
limitation, not a defect.

The distinction that matters: **Tier 1 failures are breaches, Tier 2 shortfalls are
trade-offs.**

## Alternatives Considered

**Hold both tiers to the same absolute standard.** Rejected — it is what created the deadlock.
It also produced a false equivalence in which a version string disclosed to the entire
internet and a sibling reading another sibling's session were weighed alike. They are not
alike.

**Treat inter-member isolation as out of scope entirely.** Rejected. Two of the four members
are children, one adult holds the credentials and the billing, and the agents execute shell
commands. "Best effort" is a real obligation — it forecloses nothing already achieved, and the
per-uid network rules added on 2026-09-06 stay.

**Rely on the OS boundary alone and drop application-level controls.** Rejected under Tier 2:
once such controls are correctly labelled as defence in depth, they are worth having. The
error was never using them — it was calling them a boundary.

## Consequences

**Verification effort shifts to the external boundary**, where every criterion must be
executed rather than reasoned. The audit run alongside this decision found and closed one
issue: `/health` disclosed the exact Hermes version, unauthenticated, on all four family
endpoints — reconnaissance rather than access, but the wrong side of a strict line.

**OQ-4 changes character.** Child-safety controls become a Tier-2 objective: pursue the best
available, label honestly, accept that a determined child with shell access can edit their own
config. They no longer block on the impossible standard of an in-application boundary.

**Application-level controls become usable again**, which unblocks concrete work — approval
modes, restricted toolsets, skill pruning for the children — provided STATE and the SPECs call
them defence in depth.

**A Tier-1 regression is an incident.** Any change touching the firewall's inbound policy, the
SSH configuration, Caddy's published surface, or endpoint authentication must re-run the
external criteria before it is considered done. That is a higher bar than this repository
applies anywhere else, and deliberately so.
