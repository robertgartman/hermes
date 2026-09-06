---
doc_type: runbook
status: draft  # draft | active | deprecated | superseded
last_updated: YYYY-MM-DD
verified_on: null  # YYYY-MM-DD — set ONLY when the procedure was actually executed
verification: >
  One line: when this procedure was last run end-to-end, and what confirmed it worked.
must_not_contain:
  - secrets
  - decision_rationale
  - functional_requirements
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `RUNBOOK-<NN>-<short-title>.md` where `NN` matches a deploy step number, else
> `RUNBOOK-<short-title>.md`.
>
> **Do not write a RUNBOOK that shadows a `deploy/NN-*.sh`.** Those scripts document their
> own prerequisites, idempotency and deliberate omissions in their headers, and the script is
> what actually gets edited — a prose copy drifts, then quietly lies. Reference the script;
> do not restate it.
>
> RUNBOOKs earn their place for procedures with **no** executable counterpart, and for
> cross-script ordering no single script contains.

# \<Procedure Name\>

## Purpose

What state this procedure reaches, and when you would run it.

## Prerequisites

(What must already be true. Credentials by **location**, never value.)

## Steps

(Ordered. Where a step maps to a script, link the script and state only what the script's
own header does not.)

| # | Action | Where | Notes |
|---|--------|-------|-------|
| 1 | | | |

## Idempotency

**Mandatory section.** State what a re-run does to existing state:

- What is **skipped** if it already exists.
- What is **merged** rather than overwritten — and therefore survives.
- What is **recreated**, and what that destroys.
- What **must** be re-run after a VPS recreate.

> Idempotency is a first-class property here, not a nicety. A procedure that cannot be
> safely re-run is a procedure nobody will re-run at the moment they most need to.

## Deliberately Not Done

(What this procedure leaves to something else, so its absence does not read as an oversight.)

## Verification

(How you know it worked. Prefer the check that would have caught the failure.)

## Recovery

(What to do when a step fails partway. What state is left behind.)

## Known Traps

(Things that cost time here. Symptom, cause, check.)

---

> No rationale (see ADR), no requirements (see SPEC), no credential values.
