---
doc_type: spec
status: draft  # draft | active | deprecated | superseded
last_updated: YYYY-MM-DD
verified_on: null  # YYYY-MM-DD — set ONLY when the criteria below were actually re-run
verification: >
  One line: how these criteria were confirmed, and against what evidence.
must_not_contain:
  - secrets
  - capability_status
  - architectural_rationale
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
pinned_to: null  # e.g. hermes-agent@<commit>, where behaviour depends on the pin
audience: [ai, operator]
retrieval_priority: high
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `SPEC-<capability-name>.md` — e.g. `SPEC-profile-isolation.md`
>
> **Reserved for properties that must not regress.** "X works, verified on DATE" is a status
> row in [STATE.md](../STATE.md), not a SPEC. A SPEC is for what must *stay* true under
> future change — in this repository, almost always a security or isolation boundary.

# Non-Regression Specification

## Purpose

The property this document protects, and why a future change could plausibly break it.

## Scope

(What this covers, and what it leaves to other documents.)

## Functional Requirements

- **FR-1** — …
- **FR-2** — …

## Invariants

(Rules that hold at all times. Isolation and safety boundaries belong here, and deserve the
most aggressive verification criteria.)

- **INV-1** — …

## Failure Modes

(What goes wrong and **how it presents**. "The bot stays online and silently ignores every
message, with nothing in the log" is worth more than "authorization fails".)

## Verification Criteria

Every numbered requirement **must** be covered by at least one criterion, executable against
a live host and re-runnable unchanged after a VPS recreate.

> - **VC-1** (Verifies FR-1): Given \<precondition\>, when \<action\>, then \<observable
>   outcome\>.
>   *Check:* `<command, log assertion, or observation>`
>   *Observed:* \<what actually came back\> — `YYYY-MM-DD` | `NOT YET VERIFIED`

Rules:

- Record **what was observed**, not what was expected.
- Never run against a live host ⇒ `NOT YET VERIFIED`. It is a plan, not a result.
- **A 200 response is not verification** when the log is the real evidence.
- For isolation invariants, prefer **negative checks** — prove the forbidden thing is
  impossible, from inside the constrained context.

### Coverage

| Requirement | Covered by | Last verified |
|-------------|-----------|---------------|
| FR-1 | VC-1 | YYYY-MM-DD |

---

> No rationale (see ADR), no exact interface values (see CONTRACT), no procedure (see
> RUNBOOK). A criteria section that does not cover every numbered requirement is invalid.
