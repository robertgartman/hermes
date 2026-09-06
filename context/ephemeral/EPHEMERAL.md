---
doc_type: ephemeral
status: draft
last_updated: YYYY-MM-DD
verified_on: null
verification: Not applicable — point-in-time analysis, not a standing claim.
must_not_contain:
  - secrets
authoritative: false  # ALWAYS false. An ephemeral governs nothing.
retrieval_priority: low
related_documents: []
created: YYYY-MM-DD
---

> **Naming:** `EPHEMERAL-<topic>-<YYYY-MM-DD>.md`
>
> **Never authoritative.** This document type governs nothing. Every accepted finding must
> graduate into a SPEC, ADR, CONTRACT, RUNBOOK or STATE entry; rejected findings are marked
> rejected in place, with a reason.

# \<Topic\> — \<YYYY-MM-DD\>

## Scope

(What was examined, on what date, against what — the live host, the repo, an upstream
source. Say which, because it determines how much the findings are worth.)

## Findings

(Ordered by significance. For each: what was found, what evidence supports it, and how
confident you are.)

### F-1 — \<title\>

**Finding:** …
**Evidence:** …
**Confidence:** confirmed on host | inferred from source | unverified

## Graduation

Every finding lands somewhere. Nothing stays here.

| Finding | Disposition | Destination |
|---------|-------------|-------------|
| F-1 | accepted / rejected / deferred | `context/…` or "rejected: \<reason\>" |

## Open Questions

(What this investigation could not settle. Anything still open about the **live host**
should also be reflected in [STATE.md](../STATE.md).)
