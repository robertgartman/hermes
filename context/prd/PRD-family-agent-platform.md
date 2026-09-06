---
doc_type: prd
status: active
last_updated: 2026-09-06
verified_on: null
verification: States product intent. Delivery status per requirement lives in STATE.md.
must_not_contain:
  - secrets
  - implementation_details
  - config_keys
  - deployment_procedures
audience: [ai, operator, product]
related_documents:
  - PRD-jupyter-tutor
  - ADR-001-one-os-user-per-member
  - ADR-003-scaleway-eu-inference
  - ADR-005-command-stt-provider
  - ADR-012-deterministic-tools-for-exactness
created: 2026-09-06
---

# Family Agent Platform

## Purpose

Four family members — Robert, Sofia, Mattis, Love — each with their own always-on agent,
reachable from the tools they already use, on infrastructure a household can afford and one
person can maintain.

## Problem Statement

Useful personal agents are either hosted services that see everything a family says, or
self-hosted setups that assume one technical user on one machine. Neither fits a household
of four where two members are children and one person maintains everything.

## Goals

The requirements this platform exists to satisfy. **Current delivery status for each lives in
[STATE.md](../STATE.md)** — this document says what they are, not how far along they are.

| ID | Requirement |
|---|---|
| R1 | Run Hermes on a cheap Scaleway VPS |
| R2 | Run four profiles continuously |
| R3 | Keep family profiles separate |
| R4 | Maintain an internet-safe security baseline |
| R5 | Clarify whether DNS is required |
| R6 | Track inference spend per profile |
| R7 | Enforce cost control per profile |
| R8 | Support mixed messaging channels per member |
| R9 | Accept non-text input — speech, images, documents — on every channel a member actually uses |
| R10 | Produce non-text output — computed charts, generated images, spoken replies |
| R11 | Handle each modality with whatever is best at it, rather than with the chat model by default |

## Non-Goals

- Not a product for anyone outside this household.
- Not a high-availability service. A gateway that needs a restart is acceptable.
- Not a platform requiring a web UI to operate — everything is configurable from the CLI.
- Not live, real-time voice conversation. Turn-based speech in and out is the whole ambition.
- Not a media production tool. Non-text output exists to answer a question, not to make assets.
- Not a host for local model weights. RAM is the binding constraint and every modality is
  served remotely or not at all.

## Who This Is For

Four people with different needs and very different threat models:

| Member | Notes |
|---|---|
| Robert | Operator. Also the only person who can fix anything. |
| Sofia | Adult user. |
| Mattis | **Child.** |
| Love | **Child.** |

**Two of four users are children, and every agent can execute shell commands.** This single
fact drives the platform's most consequential decision — OS-level rather than
application-level isolation ([ADR-001](../adr/ADR-001-one-os-user-per-member.md)) — and it
is the reason the largest remaining gap is child-safety controls (OQ-4 in
[STATE.md](../STATE.md)) rather than any missing feature.

## Multimodality

Text-only is where this platform happens to be, not something it decided. Two of the
modalities below are already partly present and undescribed; the rest are absent. R9–R11
exist to make the intent explicit before more is built on the assumption of text.

| Modality | Direction | Where it stands | Intent |
|---|---|---|---|
| Speech | in | Live on messaging channels; **absent from the web/API surface**, where a member has no way to send a voice message at all | Works the same on every channel a member uses |
| Images — photos, screenshots, a page of a textbook | in | The capability is claimed by configuration but **has never been exercised**, so it is unknown rather than working | First-class. This is the modality a household actually reaches for |
| Documents — PDFs and similar | in | Nothing | Later. Wanted, not urgent |
| Charts and graphs | out | Nothing outside the tutor's notebook | **Computed from real numbers**, never drawn by a model |
| Generated images and diagrams | out | No backend | All four members, no distinction between adults and children |
| Speech | out | No backend | Optional, and the least valuable of these |

### The chat model decides; something else does the work

The organising principle for R11: **the chat model's job is to work out which handler a
request needs, not to be that handler.** A modality goes to a purpose-built model, or to
deterministic code, and the result the member sees is that component's output rather than
the chat model's description of it.

The sharpest case is charts. A language model asked for a graph produces a picture that
looks like a graph — plausible, unlabelled against real data, and wrong in ways nobody
notices. A chart is a computation over numbers, so it must be computed, and the numbers must
be inspectable. The tutor already decides exactly this for its own scope in
[ADR-012](../adr/ADR-012-deterministic-tools-for-exactness.md); R11 is the same principle
stated for the platform, where it is **intent and not yet a decision**.

The same split applies elsewhere: speech in already goes to a transcription service rather
than the chat model ([ADR-005](../adr/ADR-005-command-stt-provider.md)), and it is the
working precedent that this shape is achievable here rather than aspirational.

### Configure or build — the question that sizes all of this

Hermes appears to expose a per-task handler surface: separate slots for transcription,
speech, image generation and browsing, distinct model roles for auxiliary work such as
vision, and a general escape hatch that hands a task to an arbitrary command. If that is
what it is, most of R9–R11 is configuration and the work is choosing backends. If it is not,
this is orchestration to be built.

**Nobody has checked, and the difference is the entire size of the work.** It is recorded as
a risk below rather than assumed in either direction. The interface detail, once known,
belongs in
[CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md).

## Success Criteria

- Each member can reach their own agent from a tool they already use, without the operator
  present.
- No member's agent can read another member's data, including when asked to directly.
- The whole thing is rebuildable from this repository after a total loss of the host.
- Monthly cost stays in single-digit euros.
- A member can send a photograph of something and get a useful answer about that thing.
- A member asking for a chart gets one computed from real numbers, with the numbers available
  to check — not a picture of a chart.
- A voice message behaves the same way on every channel a member uses.

## Constraints

- **Cost ceiling:** single-digit euros per month. Currently €6.55/mo plus IPv4.
- **EU data residency.** This is family conversation data, including two children's. Not a
  preference — a constraint, and the reason inference is committed to an EU provider
  ([ADR-003](../adr/ADR-003-scaleway-eu-inference.md)).
- **2 GB of RAM**, shared by four always-on agents plus supporting services. RAM, not disk or
  CPU, is the binding resource in every capacity decision.
- **One part-time operator.** Anything requiring routine manual attention will eventually not
  get it — which is why annual key rotation with no automation is a live risk (OQ-5).
- **EU residency binds every modality, not only chat.** A child's homework photograph and a
  family voice message are the content that constraint exists for. A modality with no EU
  backend does not ship; it does not quietly route elsewhere
  ([ADR-003](../adr/ADR-003-scaleway-eu-inference.md)).
- **Non-text work is metered differently.** Generated images and synthesised speech are priced
  per unit rather than per token, and are the first thing here capable of moving spend
  non-linearly — on a platform with neither attribution nor a cap (OQ-1, OQ-2).

## Risks & Open Questions

Everything currently unresolved on the live host is tracked in
[STATE.md](../STATE.md). The two with product-level consequences:

- **Child-safety controls are unset** (OQ-4). The platform currently gives two children
  shell-capable agents with 78 bundled skills seeded by default. This is the gap that most
  affects whether the product is *appropriate*, as distinct from whether it works.
- **Spend is neither attributable nor capped** (OQ-1, OQ-2), so R6 and R7 are unmet with no
  provider-side path to meeting them.
- **Whether Hermes orchestrates modalities out of the box is unverified.** It determines
  whether R9–R11 are a configuration exercise or a build, and it is answerable by reading the
  pinned tree on the host. Until someone does, every estimate here is a guess.
- **The EU constraint may not survive contact with R10.** Image generation and speech
  synthesis are the two modalities least likely to have an EU-resident backend on the current
  provider. If none exists, R10 and
  [ADR-003](../adr/ADR-003-scaleway-eu-inference.md) collide, and the resolution is an ADR
  rather than a quiet exception.
- **Image understanding has never been tested** and is recorded as unknown in
  [STATE.md](../STATE.md), not as working. The most-wanted input modality is also the one
  with the least evidence behind it.
- **Non-text output widens OQ-4.** Generated images go to all four members by decision,
  including two children, on a platform whose child-safety controls are still unset. This
  does not gate the requirement — it enlarges a gap that was already the platform's most
  significant.
