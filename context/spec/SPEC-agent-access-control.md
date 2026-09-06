---
doc_type: spec
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  2026-09-06 — external-boundary audit EXECUTED against the live host under the Tier-1
  standard of ADR-015: socket enumeration, firewall inbound policy, SSH posture,
  unauthenticated probes of every published endpoint including a path sweep, and an
  authenticated control. One issue found and fixed (/health disclosed the version
  unauthenticated). VC-3 and VC-5 remain unexecuted and say so.
must_not_contain:
  - secrets
  - capability_status
  - architectural_rationale
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - ADR-006-public-api-exposure
  - CONTRACT-api-server-endpoints
  - CONTRACT-messaging-channels
created: 2026-09-06
---

# Agent Access Control

## Purpose

Only the intended person may reach a given member's agent, and unauthorised requests must be
rejected **before** they cost anything.

Every agent behind these boundaries can execute shell commands. Two of the four belong to
children. A regression here is not a degraded feature — it is an open shell.

## Scope

Covers who may reach an agent, over messaging channels and the public API surface. Isolation
*between* members once inside the host is [SPEC-profile-isolation](SPEC-profile-isolation.md).

## Functional Requirements

- **FR-1** — Every hermes-agent API server binds `127.0.0.1` only.
- **FR-2** — Caddy is the only process with a public listener.
- **FR-3** — Every API request requires that member's bearer token, regardless of origin.
- **FR-4** — An unauthorised messaging sender is rejected in the platform adapter **before
  any model call**.
- **FR-5** — Both firewall layers default-drop inbound, with explicit allows for TCP 22 and
  443 only.
- **FR-6** — Port 80 is closed on both layers.

## Invariants

- **INV-1** — The security boundary is the bearer token plus the loopback binding — **never
  obscurity**. Numeric subdomain labels reduce information disclosure in Certificate
  Transparency logs; they are not access control.
- **INV-2** — CORS configuration must never be treated as an authentication control.
  `API_SERVER_CORS_ORIGINS=*` is deliberate: CORS and bearer-token auth are orthogonal, and
  every endpoint requires the token regardless of origin.
- **INV-3** — Rejection of an unauthorised sender must not consume inference spend.

## Failure Modes

- **An API server bound to a public interface.** The shell-capable endpoint becomes its own
  front door, with nothing able to enforce anything ahead of it. Presents as working
  normally.
- **Allowlist entry in the wrong format.** A Discord username instead of a numeric snowflake
  never matches — but the failure is *closed*, not open: the bot ignores everyone silently.
  Dangerous in the opposite direction, since it is indistinguishable from a broken bot and
  invites loosening the allowlist to "fix" it.
- **Firewall change applied in the wrong order.** Flipping the default policy before adding
  explicit allows locks the operator out of a host that must then be recreated.

## Verification Criteria

- **VC-1** (Verifies FR-1, FR-2): Given the running host, when listening sockets are
  enumerated, then ports 8642–8645 appear on `127.0.0.1` only, and the sole public listener
  is Caddy on 443.

  *Check:* `ss -tlnp` on the host; confirm bind addresses.
  *Observed:* **EXECUTED 2026-09-06.** Socket enumeration returned exactly four public-interface
  listeners: `sshd` on `22`, `caddy` on `80` and `443`, and `systemd-resolved` (LLMNR) on
  `5355`. All four API servers were on `127.0.0.1` only (`8642-8645`), as were SearXNG
  (`8888`) and the dashboard (`9121`). The tutor sandbox publishes **no** ports at all.

  **This contradicts FR-2 as written.** Caddy is *not* the only process with a public
  listener — `sshd` is (intentionally), and `systemd-resolved` binds `5355` on `0.0.0.0`
  without anyone intending it. Neither is reachable: the firewall's inbound policy is `drop`
  with allows for `22` and `443` only, so `5355` is unreachable from outside. FR-2 should be
  restated as "Caddy is the only process serving application traffic publicly", with the
  firewall — not the absence of listeners — as the control. Recorded rather than silently
  reinterpreted.

- **VC-2** (Verifies FR-3): Given a member endpoint, when a request is made without a valid
  bearer token, then it is rejected.

  *Check:* request `/v1/chat/completions` with no `Authorization` header and with a wrong
  token; expect rejection in both cases.
  *Observed:* **EXECUTED 2026-09-06 — PASS, with one issue found and fixed.**

  Unauthenticated `GET /v1/models` returned `401` on all four member endpoints, and `401` on
  the dashboard endpoint. A request carrying a valid token returned `200`. Probing for
  commonly-exposed unauthenticated paths (`/`, `/healthz`, `/metrics`, `/docs`,
  `/openapi.json`, `/api/config`) returned `404`.

  **`/health` returned `200` unauthenticated**, disclosing
  `{"status":"ok","platform":"hermes-agent","version":"0.19.0"}` — the exact version, to
  anyone on the internet, on all four family endpoints. That is reconnaissance rather than
  access, so it did not breach the Tier-1 requirement in
  [ADR-015](../adr/ADR-015-two-tier-security-model.md), but it is the wrong side of a strict
  line and is now blocked at Caddy (`404`). Re-verified after the change: all four return
  `404`, and an authenticated call still returns `200`.

  Bearer tokens are 64 characters. SSH posture confirmed alongside: `passwordauthentication
  no`, `kbdinteractiveauthentication no`, `permitemptypasswords no`, `pubkeyauthentication
  yes`, `permitrootlogin without-password`, `maxauthtries 3`.

- **VC-3** (Verifies FR-4, INV-3): Given a configured Discord bot, when a sender not in
  `DISCORD_ALLOWED_USERS` messages it, then the message is dropped before any model call and
  no inference spend is consumed.

  *Check:* message a member's bot from an unlisted account; confirm no completion appears in
  `journalctl -u hermes-gateway@<member>`.
  *Observed:* enforcement ordering **confirmed by reading `plugins/platforms/discord/adapter.py`**
  — the allowlist is checked before any model call. A **live rejection test has not been
  run**; this is source-confirmed, not host-confirmed.

- **VC-4** (Verifies FR-5, FR-6): Given a host outside the deployment, when TCP ports other
  than 22 and 443 are probed, then they are dropped at both layers.

  *Check:* external port probe; and inspect `/etc/nftables.conf` plus the Scaleway security
  group's `inbound-default-policy`.
  *Observed:* both layers default-drop with explicit `accept` for TCP 22 and 443 only,
  applied in the safe order — explicit allows added first, default policy flipped second —
  and **verified from a fresh connection immediately after each change** — **2026-07-26**.
  Port 80 deliberately closed on both.

- **VC-5** (Verifies INV-1): Given the public DNS names, when certificates are inspected in
  Certificate Transparency logs, then no label discloses a family member's name.

  *Check:* search crt.sh for the zone; confirm labels are `1`–`4`.
  *Observed:* labels are numeric by construction — **2026-07-26**. CT-log inspection
  **NOT YET VERIFIED** as an executed check.

### Coverage

| Requirement | Covered by | Last verified |
|---|---|---|
| FR-1 | VC-1 | 2026-07-26 (indirect) |
| FR-2 | VC-1 | 2026-07-26 |
| FR-3 | VC-2 | not yet — **negative case never run** |
| FR-4 | VC-3 | source-confirmed only |
| FR-5 | VC-4 | 2026-07-26 |
| FR-6 | VC-4 | 2026-07-26 |
| INV-1 | VC-5 | 2026-07-26 (partial) |
| INV-2 | — | by construction; see CONTRACT |
| INV-3 | VC-3 | source-confirmed only |

> **The two weakest criteria are VC-2 and VC-3, and both are negative tests.** Everything
> verified so far confirms that authorised access *works*; nothing yet confirms that
> unauthorised access *fails*. For a shell-capable endpoint serving children, that asymmetry
> is the most important gap in this repository's verification coverage.
