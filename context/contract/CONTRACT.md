---
doc_type: contract
status: draft  # draft | active | deprecated | superseded
last_updated: YYYY-MM-DD
verified_on: null  # YYYY-MM-DD — set ONLY when the values were read back off the host
verification: >
  One line: how these values were confirmed on the host, and against what evidence.
must_not_contain:
  - secrets
  - decision_rationale
  - behavioural_explanation
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
pinned_to: null  # e.g. hermes-agent@<commit>, where the schema depends on the pin
audience: [ai, operator]
retrieval_priority: high
version: "1.0"
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `CONTRACT-<interface-name>.md` — e.g. `CONTRACT-hermes-config-surface.md`
>
> **The highest-value type in this repository.** Nearly every expensive failure here was a
> wrong name accepted without error. If getting a name wrong breaks the system *silently*,
> it belongs in a CONTRACT.

# \<Interface Name\> Contract

## Purpose

The boundary this fixes, and who depends on it being spelled exactly this way.

## Surface

(The authoritative table of names and values. Include type, where it is set, and whether it
is required.)

| Name | Where set | Required | Value / shape |
|------|-----------|----------|---------------|
| | | | |

## Credential Locations

(**Locations and shapes only — never values.** Where each credential lives on the host or
workstation, its mode and owner, and whether the source shows it only once.)

| Credential | Location | Mode | Notes |
|------------|----------|------|-------|
| | | | |

## Compatibility

(What may change without breaking consumers, and what may not. For anything an external
client depends on — a model alias, an FQDN, a port — say plainly that the name is the stable
part.)

## Known Traps

**Mandatory section.** For this document type the trap *is* the payload.

A name that fails loudly needs no documentation. Record the ones that fail **silently**:
accepted-but-ignored keys, values substituted without error, two credentials with similar
names where only one works, warnings that are noise, warnings that are real.

For each: **the symptom as observed**, **the actual cause**, and **the check that
distinguishes them**.

> - **\<Trap\>** — Symptom: … Cause: … Check: `<command>`
>   *Confirmed YYYY-MM-DD* | `NOT YET VERIFIED`

---

> No rationale (see ADR), no behaviour (see SPEC), no procedure (see RUNBOOK).
> **Never a credential value.**
