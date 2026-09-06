---
doc_type: ephemeral
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a documentation migration. No claim about the live host was re-verified during it —
  every verified_on date was carried across from the README's existing evidence.
must_not_contain:
  - secrets
authoritative: false
retrieval_priority: low
related_documents:
  - PRD-jupyter-tutor
  - PRD-family-agent-platform
created: 2026-09-06
---

# README Migration — 2026-09-06

## Scope

Established the `context/` documentation system and migrated the 35 KB `README.md` into it,
leaving the README as an introduction. Adapted from the context system in the `otelq`
repository — **structure and concept only**, none of its content.

**No live-host verification was performed.** Every `verified_on` date in the new documents
was carried forward from evidence already recorded in the README. Nothing was re-tested, and
nothing was upgraded from "unverified" to "verified" during the migration.

## Taxonomy Decisions

The source system used PRD / SPEC / ADR / CONTRACT / EPHEMERAL. Adapted as follows.

### F-1 — Added STATE as a singleton type

The source repository's truth is readable from its source code. This repository's truth lives
on a machine no document can read. Roughly 40% of the README was live-host state — requirement
status, open questions, measured footprint, endpoint inventory, and every "verified on DATE"
claim — with no type to hold it.

**Accepted.** `context/STATE.md`, `stability: volatile`, authoritative for *what is* and never
for *what should be*.

### F-2 — Redefined SPEC as non-regression properties only

The source SPEC type covers "what the system must do", verified by a test suite. This
repository has no test suite, and most of its capability claims ("voice transcription works,
verified 2026-07-26") are **status**, not specification — they belong in STATE.

**Accepted.** SPEC is reserved for properties a future change could silently break, verified by
executable checks against the live host. Two exist; both are security-shaped. Acceptance
criteria became **Verification Criteria** carrying an executable check and its observed result.

### F-3 — Constrained RUNBOOK to script-less procedures

A RUNBOOK per `deploy/NN-*.sh` would duplicate script headers that already document
prerequisites, idempotency and deliberate omissions — and the script is what gets edited, so
the prose copy would drift and then quietly lie.

**Accepted with a rule:** a RUNBOOK that shadows a deploy script is banned. Two exist: the
cross-script ordering no single script contains, and key rotation, which has no script at all.

### F-4 — Rejected a dedicated TRAP type

This repository's most valuable content is dead ends that failed *silently*. They were
considered for their own type.

**Rejected.** A trap is always *about* something — a key, a credential, a procedure — and
piling them separately makes them unfindable at the moment of impact. Instead `## Known Traps`
is **mandatory** in CONTRACT, where the trap is the payload rather than an appendix.

### F-5 — Trimmed frontmatter from 9 required fields to 6

The source schema has ~20 fields, 9 required. With one operator and ~15 documents, a schema
nobody validates rots.

**Accepted.** Required: `doc_type`, `status`, `last_updated`, `verified_on`, `verification`,
`must_not_contain`. All else optional. `verified_on` is never omitted — an explicit `null` is
the point.

### F-6 — Made `secrets` a mandatory `must_not_contain` entry

Not present in the source system, which handles no credentials. This deployment handles four
inference keys, four bearer tokens, a Tavily key and a DNS token.

**Accepted.** Documents name credentials by **location and shape**, never value.

## Content Mapping

| README section | Destination |
|---|---|
| Title, architecture summary, step table | `README.md` (kept, condensed) |
| One Linux user per member | ADR-001, SPEC-profile-isolation |
| Why a custom unit | ADR-002 |
| Measured footprint | STATE.md |
| Inference: Scaleway | ADR-003, CONTRACT-hermes-config-surface |
| Web queries: SearXNG + Tavily | ADR-004, CONTRACT-hermes-config-surface |
| Messaging channels, Discord | CONTRACT-messaging-channels, SPEC-agent-access-control |
| Voice transcription | ADR-005, CONTRACT-hermes-config-surface |
| `python3` wrapper | ADR-007, CONTRACT-host-layout |
| Mobile / API access, model tiers, dynv6 + Caddy | ADR-006, CONTRACT-api-server-endpoints |
| Requirements status R1–R8 | PRD-family-agent-platform (the requirements), STATE.md (their status) |
| Open questions | STATE.md |
| Operational notes | AGENTS.md §4, CONTRACT-host-layout |
| `HERMES_JUPYTER_TUTOR.md` | PRD-jupyter-tutor (intent) + EPHEMERAL-jupyter-tutor-design (proposed architecture) |

## Findings Requiring Attention

### F-7 — `idea.md` is a chat transcript, not a document

`idea.md` is a pasted assistant reply that wraps a heredoc writing
`HERMES_JUPYTER_TUTOR.md`. Its first line is *"Since the file link isn't usable in your
client…"*. It is scratch, duplicating content now held properly.

**Recommendation: delete.** Left in place — deleting an author's file is the author's call.

### F-8 — Verification coverage is asymmetric on the security boundary

Surfaced by writing the verification criteria, not by testing. Everything verified to date
confirms that **authorised access works**. Nothing confirms that **unauthorised access
fails**:

- **VC-2** (bearer token required) — every recorded test used a *valid* token. The negative
  case has never been run.
- **VC-3** (unauthorised Discord sender dropped before any model call) — confirmed by reading
  `plugins/platforms/discord/adapter.py`. Never confirmed against a live rejection.
- **VC-4** (dynv6 token unreadable from a gateway namespace) — true by construction
  (root:root, 600), never asserted from inside a namespace.

For shell-capable endpoints serving two children, this is the most consequential gap in the
repository. Recorded honestly in
[SPEC-agent-access-control](../spec/SPEC-agent-access-control.md) rather than smoothed over.

### F-9 — Several isolation properties are true by construction, not by assertion

[SPEC-profile-isolation](../spec/SPEC-profile-isolation.md) VC-1 — the load-bearing negative
check — is genuinely verified. VC-2 through VC-5 are marked `NOT YET VERIFIED`: established at
provisioning but never re-asserted as re-runnable checks. A VPS recreate currently
**re-assumes** them rather than re-proving them.

**Recommendation:** add these as explicit assertions in the deploy scripts.

### F-10 — `RUNBOOK-rotate-inference-keys` has never been executed

Written because Scaleway's 365-day cap makes the deadline real and unannounced, not because
the steps are proven. Marked `status: draft`, `verified_on: null`, with the warning in the
document body.

## Graduation

| Finding | Disposition | Destination |
|---|---|---|
| F-1 – F-6 | Accepted | `context/CONTEXT.md` |
| F-7 | Recommendation | Awaiting operator decision |
| F-8 | Accepted | SPEC-agent-access-control; tracked here until closed |
| F-9 | Accepted | SPEC-profile-isolation; needs deploy-script assertions |
| F-10 | Accepted | RUNBOOK-rotate-inference-keys, `status: draft` |

## Open Questions

- Should the deploy scripts assert the isolation and access-control criteria on every run,
  turning a VPS recreate into a re-proof rather than a re-assumption? (F-8, F-9)

The `context-engineer` skill is installed at `.claude/skills/context-engineer/SKILL.md`,
self-contained rather than split across a canonical copy. It carries the routing table, the
`verified_on` honesty rule, and a runnable validation block. `AGENTS.md` §5 keeps the same
rules inline for agents that do not load skills.
