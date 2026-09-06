---
doc_type: context_guide
status: active
last_updated: 2026-09-06
verified_on: null
verification: Not applicable — this document defines routing rules, not host behaviour.
must_not_contain:
  - secrets
  - product_requirements
  - architectural_decisions
  - deployment_procedures
  - live_host_state
authoritative: true
stability: stable
audience: [ai, operator]
retrieval_priority: high
change_policy: >
  Changes require care — this document defines routing rules for every other context
  document.
created: 2026-09-06
---

# Context Documentation Guide

These subfolders hold the **authoritative, version-controlled context** for **hermes** —
four family members each running their own always-on Hermes Agent on one Scaleway VPS, with
EU-resident inference.

[README.md](../README.md) is an introduction and nothing more. **Everything authoritative
lives here.**

**A document must answer exactly one question from the Decision Matrix.** If content spans
two questions, split it and link via `related_documents`.

---

## The Rule That Makes This Repo Different

**This repository does not contain the system it describes.** There is no application source
here — only the scripts, units and prose that *produce* a running deployment on a live host.
Git can tell you what a script says. It cannot tell you what the host is doing.

Two consequences govern everything below.

**1. Observed host state beats every document.** If a document contradicts a fresh
observation from the live host, the *document* is stale. Fix the document.

**2. A claim without a verification is a guess.** Any document asserting empirical behaviour
carries `verified_on` and a re-runnable check. "It should work" is not a document — it is an
open question, and it belongs in [STATE.md](STATE.md).

This replaces the role a test suite plays in a code repository. **The host is the test
runner**, and `verified_on` is the build status.

---

## Keyword Conventions

RFC 2119 terminology: **must** / **must not** (absolute), **should** / **should not**
(recommended, may be ignored with good reason), **may** (truly optional).

---

## Secrets

**No context document may contain a credential.** Not an API key, bearer token, TSIG or HTTP
token, bot token, or password — not truncated, not expired, not "just an example".

Refer to credentials by **location and shape** instead:

> `DYNV6_API_TOKEN` — the plain **HTTP Token** from `dynv6.com/keys`, stored at
> `/etc/dynv6/api-token.env`, root:root mode 600. Not the TSIG key; that is a different
> credential.

`secrets` is therefore a mandatory entry in every document's `must_not_contain`.

---

## Frontmatter

Six required fields. Everything else is optional and used only where it earns its place —
this repository has one operator, and a schema nobody validates is a schema that rots.

### Required

| Field | Description |
|-------|-------------|
| `doc_type` | `prd`, `spec`, `adr`, `contract`, `runbook`, `ephemeral`, `state`, `context_guide` |
| `status` | `draft` (in progress), `active` (authoritative), `deprecated`, `superseded` |
| `last_updated` | `YYYY-MM-DD` |
| `verified_on` | `YYYY-MM-DD` the claims were last confirmed **against the live host**, or `null` |
| `verification` | One line: how it was confirmed, against what evidence |
| `must_not_contain` | Forbidden content categories. **Must** include `secrets` |

`verified_on` is **never omitted** — an explicit `null` is the point. PRDs, ADRs and
EPHEMERALs state intent, rationale or point-in-time analysis rather than observed host
behaviour, so `null` is their normal resting value, with `verification` saying why.

**`verified_on` may be advanced only when the check was actually re-run and passed.** If a
change invalidates a prior verification, set it back to `null` and `status: draft` rather
than leave a stale date standing. A confidently wrong date is worse than no date.

### Optional

`authoritative`, `stability` (`stable` | `evolving` | `volatile`), `decision_scope`,
`audience` (`ai` | `operator` | `product`), `created`, `related_documents`, `depends_on`,
`supersedes` / `superseded_by` (ADRs), `retrieval_priority` (`high` | `normal` | `low`,
default `normal`), `applies_to` (which deployment, e.g. `hermes-vps fr-par-1`), `pinned_to`
(upstream pin the claims depend on, e.g. `hermes-agent@<commit>`), `version` (CONTRACTs),
`ai_summary`, `semantic_tags`, `purpose`, `change_policy`.

---

## Cross-Document References

Relative markdown links: `[TYPE-identifier](relative/path/to/file.md)`

`related_documents` uses the identifier without extension:

```yaml
related_documents:
  - SPEC-profile-isolation
  - ADR-001-one-os-user-per-member
```

**Linking expectations:** SPECs reference their originating PRD where one exists · ADRs
reference affected CONTRACTs and SPECs in Consequences · RUNBOOKs reference the SPEC whose
verification criteria they satisfy · CONTRACTs reference the ADR explaining an interface
choice · EPHEMERALs list every document a finding would change.

AI agents **should** confirm referenced documents exist before processing.

---

## Summary Decision Matrix

| Question | Type |
|----------|------|
| Why does this exist, for whom, and what counts as success? | PRD |
| What property must never regress, and how do we prove it holds? | SPEC |
| Why was this approach chosen, and what does it foreclose? | ADR |
| What exact name, key, path, port or value must be spelled right? | CONTRACT |
| What do I run, in what order — where no script already says so? | RUNBOOK |
| What did this one investigation find, on this one date? | EPHEMERAL |
| What is actually true on the live host right now? | STATE (singleton) |
| How are documents classified? | Context Guide (singleton) |

**Rule of thumb:** if a document answers more than one of these, it is in the wrong place.

---

## Document Precedence

**Rule 0 — observation wins.** A verified observation of the live host beats every document.

Among documents, for what *ought* to be:

```
ADR > CONTRACT > SPEC > RUNBOOK > PRD
```

**ADRs** constrain everything downstream · **CONTRACTs** fix the exact values other things
depend on, where a typo breaks the system silently · **SPECs** define required properties
within those bounds · **RUNBOOKs** are one procedure satisfying a SPEC and may be replaced
without the requirement changing · **PRDs** express intent, which legitimately bends as
constraints are discovered.

**STATE.md sits outside this order.** It is authoritative for *what is*, never for *what
should be*. A capability specified but absent from STATE.md is not a contradiction — it is
unbuilt work.

---

## Relative Weight of the Types

These types are not equally important here, and pretending otherwise produces stub documents
that link to each other and say nothing.

| Tier | Types | Why |
|------|-------|-----|
| **Load-bearing** | CONTRACT, STATE | This deployment's characteristic failure is a wrong name accepted silently, and its truth lives on a machine rather than in git. These two carry most of the value. |
| **Narrow but real** | ADR, SPEC | ADRs for decisions that foreclose options; SPECs **only** for properties that must not regress. |
| **Occasional** | RUNBOOK, PRD, EPHEMERAL | Written when the specific trigger fires — not routinely, and never one-per-capability. |

**Do not create a document per capability across all types.** A capability typically needs
one or two documents, plus a line in STATE.md. Voice transcription, for example, is one ADR
(why a command provider, not `stt.provider: openai`), some keys in an existing CONTRACT, and
a status row in STATE — not four files.

---

## 1. PRD — Product Requirements Document

**Question:** Why does this exist, for whom, and what counts as success?

**Contains:** problem statement; goals and non-goals; who it is for — **including which
family members and their ages**, since an agent with shell access serving a child is a
different product from one serving an adult; success criteria; constraints (cost ceiling, EU
residency, the 2 GB host, operator time).

**Does NOT contain:** implementation details; config keys; procedures.

**Trigger:** a capability whose *intent* is not self-evident from the fact that it exists.

> **Low-frequency type.** "Four family members get an agent" does not need goals/non-goals
> ceremony. Reach for a PRD when there is genuine unbuilt product thinking to hold — scope,
> phasing, behavioural rules, who it is safe for.

**Folder:** `context/prd/` · **Naming:** `PRD-<capability-name>.md` · **Template:**
[PRD.md](prd/PRD.md)

---

## 2. SPEC — Non-Regression Property

**Question:** What property must never regress, and how do we prove it holds?

**Contains:** numbered requirements; invariants — above all isolation and safety boundaries;
failure modes described by **how they present**; verification criteria, each executable
against a live host with its observed evidence.

**Does NOT contain:** capability status (that is STATE); rationale (ADR); exact interface
values (CONTRACT); ordered procedure (RUNBOOK).

**Trigger:** a property that a future change could silently break, where the breakage would
matter.

> **The sharp edge of this type.** "Voice transcription works, verified 2026-07-26" is
> **not** a SPEC — it is a status row in [STATE.md](STATE.md). A SPEC is for what must
> *stay* true: that one member's gateway cannot read another's home; that an unauthorised
> sender is dropped before any model call; that no agent's API server binds a public
> interface. Expect a small number of these, all of them security-shaped.

**Folder:** `context/spec/` · **Naming:** `SPEC-<capability-name>.md` · **Template:**
[SPEC.md](spec/SPEC.md)

### Verification Criteria — the local adaptation

There is no test suite here, so a SPEC's verification criteria are the closest thing this
repository has, and they carry a stricter burden than acceptance criteria elsewhere:

- Every numbered requirement **must** have at least one criterion.
- Each criterion **must** be **executable** — a command, a log assertion, an observation —
  precise enough to re-run unchanged after a VPS recreate.
- Each criterion **should** record **what was actually observed**, not what was expected.
- A criterion never run against a live host **must** read `NOT YET VERIFIED`. It is a plan,
  not a result.
- **A 200 response is not verification** when the log is the real evidence. Choose the check
  that would have caught the failure.
- For isolation invariants, prefer **negative checks**: prove the forbidden thing is
  impossible, from inside the constrained context.

---

## 3. ADR — Architecture Decision Record

**Question:** Why was this approach chosen, and what does it foreclose?

**Contains:** the decision; context and constraints; alternatives considered **and why they
were rejected** — especially the ones tried on the host and found broken; consequences.

**Does NOT contain:** requirements; procedures; reversible or trivial choices.

**Trigger:** a decision that forecloses options — a security boundary, a provider
commitment, a pin policy, a deliberate deviation from upstream.

> **An ADR is the right home for a rejected approach that looked correct.** Several of this
> deployment's most expensive lessons are dead ends that failed *silently*. Recording only
> the winner invites the next person — or the next agent — to retry the loser.

**Folder:** `context/adr/` · **Naming:** `ADR-NNN-<short-title>.md`, zero-padded sequential,
no gaps · **Template:** [ADR.md](adr/ADR.md)

Before assigning a number, check the highest in `context/adr/` **and** `context/archive/`,
plus any unmerged branch. Never modify an accepted ADR — amend, or supersede it with a new
one.

---

## 4. CONTRACT — Interface & Configuration Surface

**Question:** What exact name, key, path, port or value must be spelled right?

**Contains:** environment variable names; `config.yaml` key paths; filesystem paths with
required mode and ownership; port assignments; systemd unit names; FQDNs; model alias names;
externally-visible API shapes; compatibility rules; **known traps**.

**Does NOT contain:** rationale (ADR); behaviour (SPEC); procedure (RUNBOOK); **credential
values** — locations only.

**Trigger:** getting the name wrong breaks the system — especially when it breaks it
*silently*.

> **The highest-value type in this repository.** Nearly every expensive failure here was a
> wrong name accepted without error: an allowlist entry that was a username instead of a
> numeric ID; a model name silently substituted for a different one; config keys "recognized"
> by the setter and resolving to nothing.
>
> **`## Known Traps` is mandatory in a CONTRACT.** For this type the trap is the payload,
> not an appendix. A name that fails loudly needs no documentation; a name that fails
> silently needs exactly this.

**Folder:** `context/contract/` · **Naming:** `CONTRACT-<interface-name>.md` ·
**Template:** [CONTRACT.md](contract/CONTRACT.md)

---

## 5. RUNBOOK — Procedure With No Script

**Question:** What do I run, in what order — where no script already says so?

**Contains:** prerequisites; ordered steps; **idempotency behaviour** — what a re-run skips,
merges or recreates; what the procedure deliberately does *not* do; verification; recovery.

**Does NOT contain:** rationale (ADR); the requirement (SPEC); credential values.

**Trigger:** a procedure that is **not already an executable script**.

> **Do not write a RUNBOOK that shadows a `deploy/NN-*.sh`.** Those scripts document their
> own prerequisites, idempotency and deliberate omissions in their headers, and the script
> is what actually gets edited — a prose copy drifts, and then quietly lies. Reference the
> script; do not restate it.
>
> RUNBOOKs earn their place for procedures with **no** executable counterpart: annual key
> rotation, recovery after a VPS recreate, onboarding a member to a new channel — and for
> the **cross-script ordering** that no single script contains.

**Folder:** `context/runbook/` · **Naming:** `RUNBOOK-<NN>-<short-title>.md` where `NN`
matches a deploy step number, else `RUNBOOK-<short-title>.md` · **Template:**
[RUNBOOK.md](runbook/RUNBOOK.md)

---

## 6. EPHEMERAL — Time-boxed Investigation

**Question:** What did this one investigation find, on this one date?

**Contains:** scope and date; findings; recommendations; a graduation path per finding.

**Never authoritative** — `authoritative: false`, always. Each accepted finding **must**
graduate into a SPEC, ADR, CONTRACT, RUNBOOK or STATE entry; rejected findings **should** be
marked rejected in place, with a reason.

**Trigger:** analysis that is true *on a date* rather than true ongoing — a review, an
audit, a debugging session, a design proposal not yet decided.

**Folder:** `context/ephemeral/` · **Naming:** `EPHEMERAL-<topic>-<YYYY-MM-DD>.md` ·
**Template:** [EPHEMERAL.md](ephemeral/EPHEMERAL.md)

---

## 7. STATE — Live Deployment Baseline (singleton)

**Question:** What is actually true on the live host right now?

**Contains:** host identity and size; per-capability live status, each with its own
`verified_on`; measured footprint; endpoint inventory; requirement status; **open questions
and known-broken things**.

**Does NOT contain:** requirements; rationale; procedure; credential values.

**Trigger:** the answer would change when someone reboots, resizes or reconfigures the VPS —
without any document being *wrong*.

> **This type has no equivalent in a code repository, and it is the reason this system is
> not simply copied from one.** In a code repo, "what is true" is readable from source. Here
> it is readable only from a machine — so it must be written down with a date attached, or
> every claim silently decays into folklore.

**Folder:** `context/` · **Naming:** `STATE.md` (singleton)

---

## Validation

Run `./scripts/validate-context.sh` after any change here. It is the canonical
implementation of the mechanical rules below — the same script lefthook and CI invoke — so
change the script rather than reimplementing its checks anywhere else.

Before creating or updating any document:

1. **References resolve** — every `related_documents` and `depends_on` entry exists.
2. **Content boundaries hold** — nothing from `must_not_contain`, and **never a credential**.
3. **`last_updated` is today.**
4. **`verified_on` is honest** — advanced only on a check actually re-run this session;
   otherwise `null`.
5. **Required frontmatter present** with valid values.
6. **SPECs only:** every numbered requirement is covered by at least one VC.

---

## Staleness Signals

| Signal | Affected |
|--------|----------|
| The VPS was recreated or resized | STATE, CONTRACT, RUNBOOK |
| The upstream Hermes pin (`PIN_COMMIT`) moved | SPEC, CONTRACT, ADR |
| A `deploy/*.sh` changed an env var, config key, port or FQDN | CONTRACT |
| Host behaviour contradicts a SPEC | SPEC |
| A new ADR supersedes constraints assumed elsewhere | CONTRACT, SPEC, RUNBOOK |
| `verified_on` older than 6 months on an `evolving` or `volatile` doc | Any |
| An open question in STATE.md was resolved, docs not updated | Any |

When staleness is found, re-verify against the host and update, or flag for review.
**Guessing is never an acceptable resolution — `verified_on: null` is.**

---

## Lifecycle

**Create:** new capability → SPEC if it has a property that must not regress, plus a STATE
row · decision that forecloses options → ADR · names something else depends on → CONTRACT ·
script-less procedure → RUNBOOK · time-boxed analysis → EPHEMERAL.

**Update:** clarifying scope → PRD, SPEC · traps found while deploying → CONTRACT, RUNBOOK ·
re-verifying after a host change → bump `verified_on` · anything about the live host →
STATE.md.

**Never update:** accepted ADRs (amend, or supersede with a new one) · deprecated documents
(archive instead).

**Deprecate:** set `status`, add `superseded_by` where one exists, move to
`context/archive/`, preserve the original filename and `doc_type`.

---

## Folder and Naming Quick Reference

| Type | Folder | Pattern |
|------|--------|---------|
| PRD | `context/prd/` | `PRD-<capability-name>.md` |
| SPEC | `context/spec/` | `SPEC-<capability-name>.md` |
| ADR | `context/adr/` | `ADR-NNN-<short-title>.md` (sequential, no gaps) |
| Contract | `context/contract/` | `CONTRACT-<interface-name>.md` |
| Runbook | `context/runbook/` | `RUNBOOK-<NN>-<short-title>.md` |
| Ephemeral | `context/ephemeral/` | `EPHEMERAL-<topic>-<YYYY-MM-DD>.md` |
| State | `context/` | `STATE.md` (singleton) |
| Context Guide | `context/` | `CONTEXT.md` (singleton) |
| Archived | `context/archive/` | original filename preserved |
