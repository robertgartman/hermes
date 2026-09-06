---
doc_type: spec
status: active
last_updated: 2026-09-06
verified_on: 2026-08-08
verification: >
  Negative check executed inside Love's gateway namespace on the live host — `ls /home/`
  returned only `love`.
must_not_contain:
  - secrets
  - capability_status
  - architectural_rationale
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - ADR-001-one-os-user-per-member
  - ADR-002-custom-gateway-template-unit
  - CONTRACT-host-layout
created: 2026-09-06
---

# Profile Isolation

## Purpose

No family member's agent may read another member's secrets, memories or conversations.

This property is the reason the deployment does not use Hermes' native profiles
([ADR-001](../adr/ADR-001-one-os-user-per-member.md)). It could be silently broken by a
future change to the gateway unit, a relaxed home permission, or a shared path introduced
for convenience — and the breakage would produce **no error and no log line**. That is what
makes it a specification rather than a status row.

Two of the four users are children, and the agent can execute shell commands.

## Scope

Covers isolation between the four member gateways on one host. Does not cover the public API
surface — see [SPEC-agent-access-control](SPEC-agent-access-control.md).

## Functional Requirements

- **FR-1** — Each member runs as a distinct unprivileged Linux user with no sudo.
- **FR-2** — Each member's home is mode `0700`, owned by that member.
- **FR-3** — Each member's gateway runs as its own systemd instance under that member's user.
- **FR-4** — A gateway process must not be able to observe the existence of any other
  member's home directory.
- **FR-5** — Per-member Hermes state (`.env`, `config.yaml`, `state.db`, sessions, memories)
  resides only under that member's home.
- **FR-6** — A member's gateway must not be able to reach another member's API server. The
  four servers bind loopback, which is **shared** by every gateway, so this cannot be left to
  the bearer token.


## Invariants

- **INV-1** — The isolation boundary is the operating system, never Hermes application
  configuration. No Hermes-level setting may be relied upon to enforce it.
- **INV-2** — Credentials whose scope exceeds one member must live **outside** every
  `/home/<member>` tree. The dynv6 token is the current instance: it can rewrite DNS and
  certificates for the whole family.
- **INV-3** — The shared Hermes tree at `/usr/local/lib/hermes-agent` is read-only to every
  gateway.

## Failure Modes

- **Silent cross-read.** With profiles sharing a UID, one child's agent can read a parent's
  credentials on request. Nothing errors; the agent simply complies. This is the failure this
  document exists to prevent.
- **Namespace directive dropped from the unit.** Removing `ProtectHome=tmpfs` or
  `BindPaths=/home/%i` restores full visibility of `/home`. The gateway starts normally and
  logs nothing unusual.
- **Home permission loosened.** A `chmod` to `0755` during troubleshooting silently makes
  every member's state world-readable.

## Verification Criteria

- **VC-1** (Verifies FR-4, INV-1): Given a running gateway, when `/home/` is listed from
  inside that gateway's namespace, then only that member's own directory exists — not merely
  denied, **absent**.

  *Check:* list `/home/` from within the target member's gateway namespace.
  *Observed:* from inside Love's gateway namespace, `ls /home/` returned only `love`.
  Robert's home did not merely deny access — it did not exist. — **2026-08-08**

- **VC-2** (Verifies FR-1, FR-2): Given each member account, when ownership and mode are
  inspected, then the home is `0700` and owned by that member, and the account has no sudo
  rights.

  *Check:* `stat -c '%a %U' /home/*` and confirm no member appears in sudo group membership.
  *Observed:* **NOT YET VERIFIED** as a standing re-runnable check — the property was
  established at provisioning by
  [`cloud-init-hermes-base.yaml`](../../deploy/cloud-init-hermes-base.yaml) but has not been
  re-asserted as an explicit post-deploy assertion.

- **VC-3** (Verifies FR-3): Given the host, when gateway units are listed, then exactly one
  `hermes-gateway@<member>.service` instance exists per member and each runs as that member.

  *Check:* `systemctl list-units 'hermes-gateway@*'` and confirm the `User=` of each instance.
  *Observed:* four instances running and boot-enabled — **2026-08-08**. Per-instance `User=`
  assertion **NOT YET VERIFIED** as an explicit check.

- **VC-4** (Verifies INV-2): Given a member's gateway namespace, when the dynv6 credential
  path is read, then it is unreadable.

  *Check:* attempt to read `/etc/dynv6/api-token.env` from inside a member's gateway
  namespace; expect failure.
  *Observed:* **NOT YET VERIFIED.** The file is root:root mode 600 by construction, but the
  negative check has not been executed from inside a gateway namespace.

- **VC-5** (Verifies INV-3): Given a running gateway, when a write to
  `/usr/local/lib/hermes-agent` is attempted, then it fails read-only.

  *Check:* attempt a write from inside a gateway namespace.
  *Observed:* confirmed indirectly — Hermes' lazy dependency install fails under
  `ProtectSystem=full`, which is why dependencies are installed at build time. Not asserted
  as a direct check.

### Coverage

| Requirement | Covered by | Last verified |
|---|---|---|
| FR-1 | VC-2 | not yet |
| FR-2 | VC-2 | not yet |
| FR-3 | VC-3 | 2026-08-08 (partial) |
| FR-4 | VC-1 | 2026-08-08 |
| FR-5 | VC-1, VC-2 | 2026-08-08 (partial) |
| INV-1 | VC-1 | 2026-08-08 |
| INV-2 | VC-4 | not yet |
| INV-3 | VC-5 | indirect |

> **VC-1 is the load-bearing check** and is genuinely verified. The remainder are honest
> gaps: properties true by construction, not yet asserted as re-runnable checks. They should
> become explicit assertions in the deploy scripts so a VPS recreate re-proves them rather
> than re-assuming them.

- **VC-6** (Verifies FR-6, INV-1): Given all four gateways running, when each member's user
  attempts to reach every member's API-server port on loopback, then only its own answers and
  the other three refuse at the network layer.
  *Check:* for each member user, connect to `127.0.0.1:8642-8645`; expect an HTTP status from
  its own port only, and no connection to the other three.
  ```bash
  for u in robert sofia mattis love; do
    for p in 8642 8643 8644 8645; do
      printf '%s -> %s : ' "$u" "$p"
      sudo -u "$u" curl -sS -m 5 -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$p/v1/models"
    done
  done
  ```
  *Observed:* **PASS, 2026-09-06.** A full 4x4 matrix: each member's own port returned `401`
  (reachable, auth-challenged) and **all twelve cross-member combinations returned `000`** —
  refused before any HTTP exchange. Caddy continued to proxy all five public endpoints, so
  the rule discriminates by uid rather than blocking the port outright.

  **Before this rule the same matrix returned `401` in every cell** — that is, every member's
  agent could reach every other member's server, and only a bearer token refused it. INV-1
  excludes an application-level check from counting as the boundary, so this was a genuine
  gap, not a theoretical one. Enforced in
  [`deploy/nftables-hermes.conf`](../../deploy/nftables-hermes.conf); re-run this check after
  any firewall edit.
