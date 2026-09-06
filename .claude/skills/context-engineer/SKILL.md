---
name: context-engineer
description: Manage the structured documentation under context/ in this repository. Use when creating, updating, validating or reviewing any PRD, SPEC, ADR, CONTRACT, RUNBOOK, EPHEMERAL or STATE document, when proposing a new document filename, when verifying frontmatter or cross-references, or when deciding which document type something belongs in. Also use after any change to deploy/ or to the live host, since those changes are what make context documents stale. Trigger phrases include "write an ADR", "draft a SPEC", "new contract", "add a runbook", "update STATE", "context engineer", "which doc type", "validate frontmatter", "check related_documents", "is this doc stale".
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

# Context Engineer — hermes

You manage the authoritative documentation under `context/`.

## Mandatory First Step

**Read `context/CONTEXT.md` before any documentation work.** It is the single source of
truth for document types, the Decision Matrix, naming, frontmatter, precedence, validation
and lifecycle rules. Do not rely on cached knowledge of it — it changes.

## The Rule That Governs Everything Here

**This repository does not contain the system it describes.** There is no application source
— only the scripts and prose that produce a running deployment on a live VPS.

1. **Observed host state beats every document.** If a document contradicts a fresh
   observation, the document is stale. Fix the document.
2. **A claim without a verification is a guess.**

### `verified_on` honesty — the rule most easily broken

`verified_on` is this repository's substitute for a test suite. Treat it as you would a
green build you did not run.

- **Advance it only when you actually re-ran the check and it passed, in this session.**
- Never date it from a plausible assumption, from a script's contents, or from the fact that
  something "should" work.
- If your change invalidates a prior verification, set `verified_on: null` and
  `status: draft`. A confidently wrong date is worse than no date.
- If you infer a property from source code rather than confirming it on the host, say so in
  `verification` and in the criterion — "source-confirmed, not host-confirmed" is a real and
  useful distinction here.
- `NOT YET VERIFIED` on a verification criterion is an acceptable, honest state. Silently
  omitting the criterion is not.

## Routing

Match the request to exactly one Decision Matrix question. The distinctions that actually
get confused:

| If the content is… | It goes in | Not |
|---|---|---|
| "X works, verified on DATE" | STATE.md row | a SPEC |
| "X must keep working under future change" | SPEC | STATE |
| "the exact key/port/path/name" | CONTRACT | SPEC or ADR |
| "why we chose this, and what we rejected" | ADR | SPEC or README |
| a procedure a `deploy/NN-*.sh` already performs | reference the script | a RUNBOOK |
| a procedure with no script (rotation, recovery) | RUNBOOK | ADR |
| analysis true on a date | EPHEMERAL | anything authoritative |

**Do not create one document per type per capability.** A capability usually needs one or
two documents plus a STATE row. Voice transcription is one ADR, some keys in an existing
CONTRACT, and a status row — not four files.

## Type-Specific Requirements

- **CONTRACT** — `## Known Traps` is **mandatory**. For this type the trap is the payload.
  Record the failures that are *silent*: accepted-but-ignored keys, values substituted
  without error, two similarly-named credentials where only one works, warnings that are
  noise, warnings that are real. For each: symptom as observed, actual cause, and the check
  that distinguishes them.
- **SPEC** — every numbered requirement needs at least one executable verification
  criterion, re-runnable unchanged after a VPS recreate. Record what was **observed**, not
  what was expected. A `200` is not verification when the log is the real evidence. Prefer
  negative checks for isolation invariants.
- **ADR** — record the dead ends that looked correct, with how they failed and how the
  failure presented. Never modify an accepted ADR; amend it, or supersede it with a new one.
  Numbers are sequential with no gaps — check `context/adr/` **and** `context/archive/`.
- **RUNBOOK** — `## Idempotency` is mandatory. Never restate a deploy script's header.
- **EPHEMERAL** — `authoritative: false`, always. Every finding must graduate somewhere.
- **STATE** — every claim carries a date. Status only; never requirements or rationale.

## Secrets

**No context document may contain a credential** — not truncated, not expired, not as an
example. Refer to credentials by **location and shape** only. `secrets` is a mandatory entry
in every `must_not_contain`.

## Workflow

**New documents or multi-file changes:**

1. Read `context/CONTEXT.md`.
2. Map the request to one Decision Matrix question.
3. Propose the filenames and scope, and confirm with the user before writing.
4. Copy the template from `context/<type>/<TYPE>.md`.
5. Write, then validate.

**Simple updates:** read CONTEXT.md, make the change, set `last_updated` to today, validate.

## Validation

**Always run this after any change under `context/`:**

```bash
./scripts/validate-context.sh
```

It checks relative links, the six required frontmatter fields, `related_documents`
resolution, and the mandatory `secrets` entry. It is the canonical implementation — the same
script lefthook and CI invoke. **Do not reimplement these checks inline**; if a rule needs to
change, change the script.

It already exempts the one deliberate broken link in `context/CONTEXT.md` (the illustrative
`relative/path/to/file.md` in the cross-reference format example).

Also run, when the change could touch credentials or scripts:

```bash
./scripts/scan-secrets.sh      # no credential may enter this repo, in any file
./scripts/lint-shell.sh        # if you touched deploy/ or scripts/
```

Then confirm by hand:

1. `last_updated` is today.
2. `verified_on` was advanced **only** for a check actually re-run.
3. Content respects `must_not_contain`, and no credential appears anywhere.
4. The file is in the right folder with the right naming pattern.
5. SPECs only: every numbered requirement is covered by a verification criterion.

## Staleness

Proactively flag documents when: the VPS was recreated or resized · the Hermes `PIN_COMMIT`
moved · a `deploy/*.sh` changed an env var, config key, port or FQDN · host behaviour
contradicts a SPEC · an open question in STATE.md was resolved without updating its
documents · `verified_on` is more than six months old on an `evolving` or `volatile` doc.

**Guessing is never an acceptable resolution to staleness. `verified_on: null` is.**
