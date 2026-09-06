---
doc_type: runbook
status: active
last_updated: 2026-09-06
verified_on: 2026-08-08
verification: >
  Steps 1–3 rebuild the deployment from nothing and have been executed on a live host;
  steps 4–6 were run and verified individually. Latest full-stack verification 2026-08-08.
must_not_contain:
  - secrets
  - decision_rationale
  - functional_requirements
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - CONTRACT-host-layout
  - CONTRACT-api-server-endpoints
  - SPEC-profile-isolation
created: 2026-09-06
---

# Deployment Sequence

## Purpose

The **order** in which the deploy scripts run, and what has to be re-run after a VPS
recreate. Each script documents its own prerequisites, idempotency and deliberate omissions
in its header — **read the script for step detail; this document covers only what no single
script can know.**

## Steps

| # | Script | Where | Purpose |
|---|---|---|---|
| 0 | `scw init` | workstation | Authenticate the Scaleway CLI. **Interactive — needs a real TTY**, so run it in a normal terminal. |
| 1 | [`01-provision-scaleway.sh`](../../deploy/01-provision-scaleway.sh) | workstation | Projects, SSH key, per-member IAM application + scoped policy + API key, and the VPS itself via [`cloud-init-hermes-base.yaml`](../../deploy/cloud-init-hermes-base.yaml). |
| 2 | [`02-install-hermes.sh <ip>`](../../deploy/02-install-hermes.sh) | workstation → host | Installs Hermes once, system-wide, checksum-verified, pinned to a commit. **~6 min.** |
| 3 | [`03-configure-profiles.sh <ip>`](../../deploy/03-configure-profiles.sh) | workstation → host | Gateway template unit, per-member `.env`, Scaleway wiring, starts all four gateways. |
| 4 | [`configure-profile.sh <user> -`](../../deploy/configure-profile.sh) | host, per member | Adds messaging channels by piping `KEY=VALUE` lines in. |
| 5 | [`04-enable-api-server.sh <ip>`](../../deploy/04-enable-api-server.sh) | workstation → host | Optional. API server per member, Caddy build + install, DNS. |
| 6 | [`05-enable-web-search.sh <ip>`](../../deploy/05-enable-web-search.sh) | workstation → host | Shared SearXNG, plus Tavily when a key is present. |

**Steps 1–3 rebuild the entire deployment from nothing.** Steps 4–6 are additive.

## Idempotency

| Step | Re-run behaviour |
|---|---|
| 1 | Skips anything that already exists — **except API keys**, which are minted fresh only when a member has none saved locally. |
| 2 | Reinstalls at the pinned commit. Aborts if upstream's `install.sh` checksum changed. |
| 3 | **Merges** `.env` values rather than overwriting, so channel tokens added later survive. Also removes superseded model routes (`medium`, `ultra`) from existing profiles. |
| 4 | Merges into the existing `.env`; never truncates a configured profile. |
| 5 | Fully idempotent — safe to re-run after a VPS recreate. |
| 6 | Deploys and verifies SearXNG with or without a Tavily key. Re-run with a key later to enable Tavily. |

## After a VPS Recreate

**Scaleway resources cannot move between projects, so relocating the VPS means recreating
it.** This is a recurring procedure, not a one-off.

1. Re-run steps 1–3. Step 1 will **not** mint new inference keys if
   `~/.hermes-family-keys/` still holds them — those files are the only copy.
2. Re-run step 5. It is idempotent and rebuilds the API server and Caddy configuration.
3. **Repoint DNS at the new IP** with
   [`update-dynv6-records.sh <ip>`](../../deploy/update-dynv6-records.sh). Hand-editing
   records in the dynv6 UI is the thing this script exists to replace.
4. Re-run step 6.
5. Re-add messaging channels per member (step 4) — tokens live in each member's `.env`,
   which is gone with the host.

**Verify SSH reachability before assuming a step failed.** SSH keys are project-scoped in
Scaleway: a key registered in another project is not injected, and the instance boots
unreachable. A reboot does not fix it.

## Deliberately Not Done

- **Step 5 does not apply the host firewall.** That is separate, and deliberately so.
- **No step configures child-safety controls.** Approval mode, tool restrictions and skill
  pruning are unset — see OQ-4 in [STATE.md](../STATE.md).
- **No step rotates credentials.** See
  [RUNBOOK-rotate-inference-keys](RUNBOOK-rotate-inference-keys.md).

## Verification

After a full rebuild, confirm in this order — each check is cheap and localises the failure:

1. Four gateways running and boot-enabled: `systemctl list-units 'hermes-gateway@*'`
2. Isolation intact: the negative check in
   [SPEC-profile-isolation](../spec/SPEC-profile-isolation.md) VC-1.
3. Inference live per member — one completion each.
4. Endpoints returning `200` with **production** certificates (not staging — see the Caddy
   trap in [CONTRACT-api-server-endpoints](../contract/CONTRACT-api-server-endpoints.md)).
5. Model tiers resolving — confirm from the **agent log**, not the response code.
6. Search and extraction returning real content per member.

## Known Traps

- **Step 0 needs a real TTY.** `scw init` is interactive and will not work through a
  non-interactive agent session.
- **The install peaks at 1.6 GB** on a 2 GB host — the tightest moment in the whole
  sequence. Do not run step 2 alongside other memory-hungry work.
- **Firewall changes must be applied in the safe order** — explicit allows first, default
  policy flipped second — and verified from a **fresh** connection immediately, before
  trusting the change. The existing connection will keep working either way and tells you
  nothing.
- **Connect with `-o IdentitiesOnly=yes`.** `MaxAuthTries 3` is exhausted by an agent
  offering several keys before the right one.
