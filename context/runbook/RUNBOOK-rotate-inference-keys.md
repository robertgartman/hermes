---
doc_type: runbook
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  NEVER EXECUTED. Derived from the provisioning and configuration scripts' documented
  behaviour, not from a performed rotation. Treat every step as unproven.
must_not_contain:
  - secrets
  - decision_rationale
  - functional_requirements
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
related_documents:
  - ADR-003-scaleway-eu-inference
  - CONTRACT-hermes-config-surface
  - RUNBOOK-00-deployment-sequence
created: 2026-09-06
---

# Rotate Inference Keys

> **This procedure has never been run.** It is written because the deadline is real and
> arrives without warning, not because the steps are proven. Verify each step as you go, and
> set `verified_on` once a rotation has actually been completed.

## Purpose

Replace each member's Scaleway inference key before it expires.

**Scaleway hard-caps API key expiry at 365 days.** A 3-year request is rejected regardless of
the organisation setting, so this is an annual obligation with no automation behind it —
tracked as OQ-5 in [STATE.md](../STATE.md).

**Failure mode if missed:** all four agents stop being able to reach inference. There is no
warning in the deployment, and the symptom will present as four simultaneously broken
agents.

## Prerequisites

- `scw` authenticated on the workstation (`scw init` — interactive, needs a real TTY).
- Write access to `~/.hermes-family-keys/` (mode 700).
- SSH access to the host.
- Awareness that **Scaleway shows a secret key exactly once.** The files in
  `~/.hermes-family-keys/` are the only copy — losing one means minting another.

## Steps

| # | Action | Where |
|---|---|---|
| 1 | Mint a new API key for each member's IAM application, keeping `default_project_id` pointed at that member's project | workstation |
| 2 | Write each new secret to `~/.hermes-family-keys/<member>`, mode 600, replacing the old value | workstation |
| 3 | Push the new keys into each member's `.env` | workstation → host |
| 4 | Restart each gateway so it picks up the new credential | host |
| 5 | Verify one completion per member | workstation |
| 6 | Delete the superseded keys in Scaleway **only after** step 5 passes for all four | workstation |

For step 3, `configure-profile.sh` merges rather than overwrites, and reads `KEY=VALUE` lines
from **stdin** when passed a literal `-` — which keeps the secret out of argv and shell
history:

```
./configure-profile.sh <member> - < <(printf 'OPENAI_API_KEY=%s\n' "$NEW_KEY")
```

## Idempotency

- **Steps 1–2 are not idempotent.** Re-running mints an additional key. Scaleway allows
  multiple live keys per application, so a partial rotation leaves orphans that must be
  cleaned up by hand.
- **Steps 3–4 are idempotent** — `.env` values merge, and a restart is repeatable.
- **Step 6 is destructive and irreversible.** Do not run it before step 5 passes for every
  member.

## Deliberately Not Done

- **No expiry monitoring.** Nothing on the host or workstation warns that a key is
  approaching its 365-day limit. Until something does, this procedure depends on the
  operator remembering.
- **No automated rotation.** See OQ-5.

## Verification

One completion per member, confirmed from the gateway log rather than from a bare `200`:

```bash
journalctl -u hermes-gateway@<member> -n 50
```

A stale key presents as an authentication failure from Scaleway, not as a Hermes error.

## Recovery

- **New key written but gateway not restarted:** the member keeps using the old credential
  until restart. Harmless until the old key is deleted — which is why step 6 comes last.
- **Old key deleted before verification:** that member's agent is down. Mint a fresh key and
  repeat from step 2. There is no way to recover a deleted secret.
- **Partial rotation across members:** members are independent. A failure for one does not
  affect the other three.

## Known Traps

- **The 365-day cap is enforced regardless of organisation settings.** Requesting a longer
  expiry does not produce a longer key; the request is rejected.
- **Per-member billing attribution does not currently work** (OQ-1), so rotation cannot be
  validated by watching consumption move between projects. All AI consumption records against
  the organisation's default project.
- **Do not pass a secret in argv.** Use the stdin form. Both `configure-profile.sh` and step
  6 of the deployment sequence exist in their current shape for this reason.
