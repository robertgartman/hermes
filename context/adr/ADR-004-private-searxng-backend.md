---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale. Live status and verification are in STATE.md.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - CONTRACT-hermes-config-surface
  - ADR-001-one-os-user-per-member
created: 2026-09-06
---

# ADR-004: One shared private SearXNG for search; Tavily for extraction

## Context

All four agents need web search. Two constraints shape the answer: RAM is the binding
resource on a 2 GB host (see [STATE.md](../STATE.md)), and four separate search backends
would mean four sets of credentials and four processes for an identical, stateless workload.

Page *extraction* is a separate need. Asking the main chat model to browse and summarise a
page spends reasoning tokens on work that a purpose-built extractor does better and cheaper.

## Decision

Run **one** private SearXNG instance, shared by all four profiles, reachable only on
loopback. Use **Tavily** independently for page extraction, so Hermes can fetch page content
without routing it through the chat model.

Deployment specifics:

- Official SearXNG image, **pinned by digest**, managed by systemd through **rootful
  Podman**. Podman is chosen because it has no resident daemon — on this host, a daemon is
  pure overhead.
- One Granian worker, JSON-only output, no image proxy, no public-instance mode.
- `server.limiter: false`, which makes Valkey unnecessary for a loopback-only service.
- **Host networking is deliberate**, not laziness. The host's default-drop forwarding
  firewall blocks a container bridge's DNS and egress; binding the host-networked process to
  loopback keeps it private *without* adding forwarding exceptions to the firewall.
- Container memory **and** total swap both capped at 256 MiB — equal caps mean no container
  swap. PID count capped at 128.

## Alternatives Considered

**A hosted search API per member.** Rejected: four credentials and four billing surfaces for
a stateless query workload, plus every family search leaving the host attributed to an
individual.

**A container bridge network instead of host networking.** Tried and rejected: the host
firewall's default-drop forwarding policy blocks the bridge's DNS and egress. Making it work
would mean punching forwarding exceptions through a firewall that was deliberately closed —
trading a real security property for a cosmetic networking one.

**Docker instead of Podman.** Rejected: a resident daemon costs memory continuously on the
host's scarcest resource, for no benefit to a single pinned container.

**Enabling SearXNG's limiter.** Rejected: the limiter requires Valkey, which is a second
process and more RAM, to rate-limit a service reachable only from loopback by four local
processes.

**Letting the chat model browse and summarise pages itself.** Rejected on cost and quality —
this is what a dedicated extractor is for, and it lets the extraction task run at
`reasoning_effort: none`.

## Consequences

- One shared instance means **no per-member search attribution or isolation**. Accepted: the
  queries are stateless and the service holds no per-member state, so this does not weaken
  [ADR-001](ADR-001-one-os-user-per-member.md)'s boundary.
- The digest pin must be updated deliberately; an unpinned image would change under the
  deployment silently.
- Tavily is a **non-EU dependency for page-extraction traffic**, unlike inference
  ([ADR-003](ADR-003-scaleway-eu-inference.md)). What leaves the host is a URL and the
  fetched public page, not conversation content.
- The pinned Hermes version **logs successful Tavily responses as tool errors**. This is a
  display false positive with a known cause; see the trap in
  [CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md).
