---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale. The resulting property is verified in SPEC-profile-isolation.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - SPEC-profile-isolation
  - ADR-002-custom-gateway-template-unit
created: 2026-09-06
---

# ADR-001: One Linux user per family member, not one Hermes profile per member

## Context

Four family members each need an always-on agent on a single VPS. Hermes has a native
profile mechanism, which is the obvious first answer.

Two facts make the obvious answer unacceptable:

1. **The agent can execute shell commands.** This is a core feature, not an edge case.
2. **Two of the four users are children.**

Hermes profiles isolate Hermes *state* — sessions, memories, config — but every profile runs
as the **same OS user**. Any member's agent could therefore read every other member's
secrets and memories by simply asking its own shell to do so. No Hermes-level setting
changes that; the boundary is below Hermes.

## Decision

Give each member their **own unprivileged Linux user** with a `0700` home and no sudo. Share
a single system-wide Hermes install between them, and run **one systemd instance per user**
with `ProtectHome=tmpfs` plus `BindPaths=/home/%i`.

The isolation boundary is the operating system, not the application.

```
/usr/local/lib/hermes-agent      2.2 GB, shared by all four
/usr/local/bin/hermes
/home/<member>/.hermes/          per-member: .env, config.yaml, state.db, sessions, memories
hermes-gateway@<member>.service  per-member unit
```

## Alternatives Considered

**Hermes profiles (`hermes --profile <name>`).** Rejected: profiles isolate application
state but share a UID. With shell execution available, that is not a security boundary at
all — it is a filing convention. The failure mode is silent and total: nothing errors, one
child's agent simply *can* read a parent's credentials on request.

**Four separate VPS instances.** Rejected on cost and footprint. Four DEV1-S instances is
4×€6.55/mo for a workload that fits comfortably in one, and each would carry its own 2.2 GB
Hermes tree.

**Containers per member.** Not pursued. The OS-user boundary plus systemd's namespace
directives achieves the required property with no additional runtime, on a host where RAM is
the binding constraint.

**One Hermes install per user.** Rejected: 4 × 2.2 GB of identical code on a 20 GB disk, for
no isolation benefit — the code tree is read-only to the gateways anyway
(`ProtectSystem=full`).

## Consequences

- **The `ProtectSystem=full` mount is read-only to gateways**, so Hermes' lazy install of
  platform dependencies can never succeed at runtime. Dependencies must be installed at
  build time. See [CONTRACT-host-layout](../contract/CONTRACT-host-layout.md).
- Anything a member's agent must reach has to live inside that member's home, or be a
  service on loopback. Credentials that must *not* be reachable — such as the dynv6 token,
  which can rewrite DNS and certificates for the whole family — are placed deliberately
  outside every `/home/<member>` tree. See
  [ADR-006](ADR-006-public-api-exposure.md).
- Upstream's single-gateway installer becomes unusable, forcing a custom template unit. See
  [ADR-002](ADR-002-custom-gateway-template-unit.md).
- The resulting isolation property is the repository's most important non-regression
  requirement and is specified with executable checks in
  [SPEC-profile-isolation](../spec/SPEC-profile-isolation.md).
