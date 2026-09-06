---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale. Endpoint values and live status live elsewhere.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - CONTRACT-api-server-endpoints
  - SPEC-agent-access-control
  - ADR-001-one-os-user-per-member
created: 2026-09-06
---

# ADR-006: Public API access via Caddy, DNS-01 certificates, and opaque subdomains

## Context

Family members want to reach their agents from a phone, using an ordinary
OpenAI-compatible client. Hermes ships an API server that provides exactly that interface.

By its own documentation, that API server "gives full access to hermes-agent's toolset,
**including terminal commands**". Exposing it publicly is therefore exposing a shell — for
four people, two of them children, on a host where the OS-user boundary
([ADR-001](ADR-001-one-os-user-per-member.md)) is the only thing separating them.

## Decision

Expose one FQDN per member through a **Caddy reverse proxy** holding real Let's Encrypt
certificates issued via **DNS-01**, with each member's API server bound to `127.0.0.1`.
Caddy is the only process with a public listener. Every request requires that member's
bearer token.

Four supporting choices, each load-bearing:

**Opaque subdomain labels (`1`–`4`, never member names).** Let's Encrypt issuance is
permanently and publicly logged in Certificate Transparency. A `mattis-…` certificate would
forever tie a child's name to a host documented — by Hermes' own docs — as running an agent
with terminal access. The label is the one part of this design that can never be retracted.

**DNS-01, not HTTP-01.** Chosen so port 80 never needs to be open. Only 443 is.

**`API_SERVER_CORS_ORIGINS` is required, not optional.** `*` is used deliberately: CORS and
bearer-token auth are orthogonal. Every endpoint still requires the token regardless of
origin; this setting only controls which origins receive the headers a browser or proxy
needs in order not to discard an otherwise-successful response.

**The dynv6 credential lives outside every `/home/<member>` tree** — `/etc/dynv6/`,
root:root, mode 600. A `hermes-gateway@<member>` process can read its own home by design;
this token can rewrite DNS and certificates for the entire family, so it must not be
reachable from any agent.

## Alternatives Considered

**A VPN instead of public HTTPS.** Rejected on usability: it puts a client and a connection
step between a child and their agent, on a phone.

**Binding the API server directly to a public interface.** Rejected outright — it would make
the shell-capable endpoint its own TLS terminator and its own front door, with no layer able
to enforce anything ahead of it.

**HTTP-01 certificate issuance.** Rejected: it requires port 80 open on both firewall layers
permanently, to serve challenges for a service that otherwise needs only 443.

**Descriptive subdomains (`mattis-hermes.…`).** Rejected — see Certificate Transparency
above. This is irreversible in a way no other naming choice here is.

**Omitting `API_SERVER_CORS_ORIGINS`.** This was the prior state, and it failed in a way
worth recording because `curl` testing **never catches it**: `curl` is not subject to CORS
at all, so the endpoint tested clean all session. Chatbox routes some calls — at least its
`/v1/models` fetch — through its own `cors-proxy.chatboxai.app` backend, which emulates
browser CORS enforcement even though that hop is server-to-server and CORS strictly does not
apply. With the setting absent, `OPTIONS /v1/models` returned `403` with **no**
`Access-Control-Allow-*` headers at all. Chatbox read that as a failed preflight and aborted
before sending the real request.

The symptom presented as **two apparently unrelated problems** — a network error, and model
tiers appearing not to work — that shared one cause: the model list never refreshed past its
original single-model cache because the listing call kept failing the same preflight. Nothing
reached the access log to debug from.

**A TSIG key for dynv6.** Tried and rejected: dynv6 has **two unrelated token types**, and
the TSIG key (for RFC2136 `nsupdate`) is not what Caddy's `caddy-dns/dynv6` plugin uses. The
plugin authenticates with a Bearer token against dynv6's REST API v2 — confirmed by reading
the plugin's Go source after a TSIG key returned a clean `401`.

## Consequences

- **The security boundary is the bearer token plus the loopback binding**, not obscurity.
  These properties must not regress; they are specified with executable checks in
  [SPEC-agent-access-control](../spec/SPEC-agent-access-control.md).
- Caddy must be a **custom build**. `caddyserver.com`'s prebuilt-binary download API does not
  carry every `caddy-dns/*` plugin — `dynv6` is absent from its catalog (`400: not a
  registered Caddy module package path`) despite the module being real. The binary is built
  with `xcaddy` on the workstation and shipped by `scp`, which also avoids installing a Go
  toolchain on the 2 GB VPS.
- **DNS records must be repointed whenever the VPS is recreated.** Scaleway resources cannot
  move between projects, so relocation means recreation. See
  [RUNBOOK-00-deployment-sequence](../runbook/RUNBOOK-00-deployment-sequence.md).
- Caddy's staging-CA fallback behaviour is a recurring operational trap; see
  [CONTRACT-api-server-endpoints](../contract/CONTRACT-api-server-endpoints.md).
