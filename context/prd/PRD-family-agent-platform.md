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

## Non-Goals

- Not a product for anyone outside this household.
- Not a high-availability service. A gateway that needs a restart is acceptable.
- Not a platform requiring a web UI to operate — everything is configurable from the CLI.

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

## Success Criteria

- Each member can reach their own agent from a tool they already use, without the operator
  present.
- No member's agent can read another member's data, including when asked to directly.
- The whole thing is rebuildable from this repository after a total loss of the host.
- Monthly cost stays in single-digit euros.

## Constraints

- **Cost ceiling:** single-digit euros per month. Currently €6.55/mo plus IPv4.
- **EU data residency.** This is family conversation data, including two children's. Not a
  preference — a constraint, and the reason inference is committed to an EU provider
  ([ADR-003](../adr/ADR-003-scaleway-eu-inference.md)).
- **2 GB of RAM**, shared by four always-on agents plus supporting services. RAM, not disk or
  CPU, is the binding resource in every capacity decision.
- **One part-time operator.** Anything requiring routine manual attention will eventually not
  get it — which is why annual key rotation with no automation is a live risk (OQ-5).

## Risks & Open Questions

Everything currently unresolved on the live host is tracked in
[STATE.md](../STATE.md). The two with product-level consequences:

- **Child-safety controls are unset** (OQ-4). The platform currently gives two children
  shell-capable agents with 78 bundled skills seeded by default. This is the gap that most
  affects whether the product is *appropriate*, as distinct from whether it works.
- **Spend is neither attributable nor capped** (OQ-1, OQ-2), so R6 and R7 are unmet with no
  provider-side path to meeting them.
