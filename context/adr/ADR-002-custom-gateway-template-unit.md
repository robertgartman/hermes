---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale for deviating from the upstream installer.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - ADR-001-one-os-user-per-member
  - CONTRACT-host-layout
created: 2026-09-06
---

# ADR-002: Custom systemd template unit instead of `hermes gateway install`

## Context

[ADR-001](ADR-001-one-os-user-per-member.md) requires one gateway process per family member,
each running as its own OS user. The natural approach is Hermes' own installer.

Hermes' `gateway install` writes a single, **non-templated** `hermes-gateway.service` — one
gateway per host. Running it for members 2–4 does not create additional units: it reports
"already installed" and restarts the first one. There is no upstream path to four gateways.

Two further upstream defaults are unsuitable for this deployment:

- **`StartLimitIntervalSec=0`** disables restart rate-limiting entirely. A crash-looping
  gateway retries forever, and every retry that reaches the model burns provider spend
  against a family budget with no cap (see OQ-2 in [STATE.md](../STATE.md)).
- **No memory ceiling.** Four unbounded agents share 2 GB, where the install itself already
  peaks at 1.6 GB.

## Decision

Ship a custom systemd **template unit**, `hermes-gateway@.service`, instantiated once per
member. It:

- templates on `%i` so one file serves all four members,
- restores restart rate-limiting,
- sets a per-member `MemoryMax`,
- applies the namespace directives that make [ADR-001](ADR-001-one-os-user-per-member.md)'s
  isolation real (`ProtectHome=tmpfs`, `BindPaths=/home/%i`).

## Alternatives Considered

**Run `hermes gateway install` four times.** Rejected — it does not do what the name
suggests. It reports success, and restarts the *first* member's gateway. The failure is
silent: three members simply have no gateway, and the command that was supposed to create
them exited 0.

**Patch the upstream unit in place after install.** Rejected: not reproducible across a VPS
recreate, and the patched file would be overwritten by any reinstall.

**Four hand-written unit files.** Rejected: four copies drift. A template unit is one file
with one `MemoryMax` to change.

## Consequences

- The deployment does not track upstream's unit file. If upstream changes gateway invocation
  or environment expectations, the template must be updated deliberately — this is a
  maintenance cost accepted in exchange for the multi-member capability that upstream does
  not offer.
- `MemoryMax` is set per member and is **currently unvalidated under real load** — every
  footprint figure in [STATE.md](../STATE.md) is idle with no channels connected (OQ-3).
- Unit naming becomes part of the operational surface; see
  [CONTRACT-host-layout](../contract/CONTRACT-host-layout.md).
