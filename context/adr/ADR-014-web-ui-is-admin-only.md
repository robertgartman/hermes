---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a decision. The behaviour it rests on was executed on 2026-09-06 — the route
  inventory was read from the shipped web source, and the cross-member loopback access was
  measured before the mitigating rule existed.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents:
  - ADR-006-public-api-exposure
  - ADR-001-one-os-user-per-member
  - CONTRACT-api-server-endpoints
  - SPEC-profile-isolation
created: 2026-09-06
---

# ADR-014: The Hermes web UI is an operator surface; family chat stays on the API servers

## Context

The platform gained memory headroom after the DEV1-M resize, which made running Hermes' own
web UI practical. The intent was a nicer interface for **all four family members**, guarded by
a username and password.

Two findings changed the shape of that.

**The web UI is one application, not a chat app plus an admin app.** Its shipped routes
include `/chat` alongside `/env`, `/config`, `/files`, `/models`, `/plugins`, `/skills`,
`/logs` and `/system`. `/env` is the profile's environment variables — the Scaleway
credential among them. Upstream describes the surface as "managing config, API keys, and
sessions".

**Restricting it by path at the reverse proxy does not work.** The routes are client-side
views over a shared `/api/*`. Blocking `/env` at the proxy hides a page while leaving the
endpoint behind it reachable, so anyone granted `/chat` can call the configuration and
environment APIs directly. A path allowlist here would look like a control and not be one.

Separately, and measured before any mitigation existed: with a dashboard bound to loopback,
**a child's gateway user reached another member's dashboard and received `HTTP 200`** with no
credential. Loopback is shared by all four gateways — see
[SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) VC-3. Authentication at the reverse
proxy does not touch that path at all; it guards only the public door.

## Decision

**The Hermes web UI is exposed to the adult operator only. Family chat remains on the
per-member API servers.**

- One dashboard instance, for the operator, bound to loopback and published only through
  Caddy on a **numeric** subdomain, consistent with
  [ADR-006](ADR-006-public-api-exposure.md).
- **Two controls, because there are two doors.** Username and password at Caddy for the
  public door; an `nftables` rule restricting the dashboard ports to `root` and the Caddy uid
  for the loopback door. Neither alone is sufficient.
- Every family member's chat interface stays the **per-member API server** behind its own
  bearer token, driven by any OpenAI-compatible client. That surface exposes conversation and
  nothing else — no environment, no filesystem, no configuration.
- For the two children specifically, the richer interactive surface is the tutor's JupyterLab
  inside the sandbox, which carries none of this exposure.

## Alternatives Considered

**Give every member their own dashboard.** This was the original intent and is rejected on
what the UI actually contains: it would hand a child the family's model credential, the
profile's filesystem and its configuration, through a supported button rather than an
exploit. It also compounds [OQ-4](../STATE.md) — child-safety controls are the largest open
gap on this deployment, and this would widen it rather than narrow it.

**Expose only `/chat` through the proxy.** Rejected as a **control that does not control
anything** — see Context. Worth recording precisely because it is the obvious design and it
looks sufficient right up until someone calls `/api/*` directly.

**Rely on username and password alone.** Rejected on measurement, not principle. The
credential guards the public door; the loopback door returned `200` to a child's agent while
that credential was in place.

**Build a chat-only front end against the API servers.** Not chosen now — it is a real
project, not a configuration change. **It remains the correct answer if the family wants a
nicer interface than a third-party client**, because it is the only option that separates
conversation from administration.

## Consequences

**Family members' interface is unchanged**: their own API endpoint plus a client of their
choosing. The "nicer UI" goal is met for the operator only, and deferred for everyone else.

**A new firewall rule is load-bearing.** The dashboard-port restriction in
[`deploy/nftables-hermes.conf`](../../deploy/nftables-hermes.conf) is a security boundary, not
tuning. Removing it silently restores cross-member access to an admin console holding
credentials.

**The dashboard must never be bound to a public interface.** It enforces DNS-rebinding
protection, so a reverse proxy has to rewrite the `Host` header; the tempting shortcut is to
bind it publicly instead, which would defeat ADR-006's rule that Caddy holds the only public
listener.

**One more credential to rotate**, stored outside the repository and outside every `/home`,
following the dynv6 token pattern.
