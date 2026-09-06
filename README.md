# Hermes family setup on Scaleway

Four family members — Robert, Sofia, Mattis, Love — each running their own always-on
[Hermes Agent](https://hermes-agent.nousresearch.com) on one cheap EU VPS, with EU-resident
inference via Scaleway Generative APIs.

**€6.55/mo. One 2 GB host. Four isolated agents. No web UI required.**

---

## What this repository is

A **deployment repository**, not an application. It holds the scripts, systemd units and
documentation that build the deployment — the running system itself lives on a VPS.

That distinction shapes everything: this repo can tell you what a script does, but only the
live host can tell you what is true. So every claim about the deployment is dated, and
carries the check that proves it.

**Everything authoritative lives in [`context/`](context/CONTEXT.md). This README is an
introduction and nothing more.**

---

## How it works

**One Linux user per family member — not one Hermes profile per member.**

Hermes profiles isolate Hermes state but run as the same OS user, so any member's agent could
read every other member's secrets and memory. The agent executes shell commands, and two of
the four users are children. That is not an acceptable boundary.

Instead: four unprivileged Linux users, `0700` homes, no sudo, one shared system-wide Hermes
install, and one systemd instance per user with `ProtectHome=tmpfs` + `BindPaths=/home/%i`.

Verified on the live host: from inside Love's gateway namespace, `ls /home/` returns only
`love` — Robert's home does not merely deny access, **it does not exist**.

```
/usr/local/lib/hermes-agent      2.2 GB, shared by all four
/usr/local/bin/hermes
/home/<member>/.hermes/          per-member: .env, config.yaml, state.db, sessions, memories
hermes-gateway@<member>.service  per-member unit, MemoryMax=320M
```

Inference runs on Scaleway Generative APIs — EU-hosted, OpenAI-compatible, 57 ms measured
upstream latency. Web search uses one private SearXNG shared by all four profiles; page
extraction uses Tavily; speech-to-text runs on Scaleway. Each member is also reachable from a
phone over HTTPS through a Caddy reverse proxy, with their own bearer token.

→ [ADR-001: one OS user per member](context/adr/ADR-001-one-os-user-per-member.md)
· [SPEC-profile-isolation](context/spec/SPEC-profile-isolation.md)

---

## Deploying

Steps 1–3 rebuild the entire deployment from nothing. Steps 4–6 are additive.

| # | Script | Where |
|---|---|---|
| 0 | `scw init` | workstation — interactive, needs a real TTY |
| 1 | [`01-provision-scaleway.sh`](deploy/01-provision-scaleway.sh) | workstation |
| 2 | [`02-install-hermes.sh <ip>`](deploy/02-install-hermes.sh) | workstation → host |
| 3 | [`03-configure-profiles.sh <ip>`](deploy/03-configure-profiles.sh) | workstation → host |
| 4 | [`configure-profile.sh <user> -`](deploy/configure-profile.sh) | host, per member |
| 5 | [`04-enable-api-server.sh <ip>`](deploy/04-enable-api-server.sh) | workstation → host |
| 6 | [`05-enable-web-search.sh <ip>`](deploy/05-enable-web-search.sh) | workstation → host |

Each script documents its own prerequisites, idempotency and deliberate omissions in its
header. **Read the script for step detail.**

→ [RUNBOOK-00-deployment-sequence](context/runbook/RUNBOOK-00-deployment-sequence.md) for
ordering, and what must be re-run after a VPS recreate.

Step 1 writes the four inference keys to `~/.hermes-family-keys/` (mode 600). Scaleway shows
a secret key **once**; those files are the only copy. **They never enter git.**

---

## Where everything lives

| I want to know… | Read |
|---|---|
| What is live right now, and what is broken | [context/STATE.md](context/STATE.md) |
| How documents are organised | [context/CONTEXT.md](context/CONTEXT.md) |
| The exact env var / config key / port / path | [`context/contract/`](context/contract/) |
| Why something was done this way | [`context/adr/`](context/adr/) |
| What must never regress, and how it is proven | [`context/spec/`](context/spec/) |
| How to run a procedure with no script | [`context/runbook/`](context/runbook/) |
| What we are trying to build, and for whom | [`context/prd/`](context/prd/) |
| How to work in this repo as an agent | [AGENTS.md](AGENTS.md) |

**Start with [context/STATE.md](context/STATE.md)** if you want the current picture, or
[context/CONTEXT.md](context/CONTEXT.md) if you are about to write something.

---

## Status at a glance

Live and verified: four gateways, profile isolation, EU inference, both firewall layers,
Discord for Mattis, voice transcription, web search and extraction, public API endpoints with
real certificates, and model tier aliases.

Not done: per-member spend attribution (no provider path), spend caps (Scaleway has no budget
API), child-safety controls, and messaging channels for members other than Mattis.

**The most significant open gap is child safety.** Mattis and Love have agents that can
execute shell commands, with approval mode, tool restrictions and skill pruning unset.

→ [context/STATE.md](context/STATE.md) for dated status, measured footprint, and every open
question.

---

## Conventions

- **No credential ever enters this repository** — not in a script, not in a document, not as
  an example. Secrets pass through stdin, never argv.
- **Every claim about the live host is dated.** An undated claim about a machine decays into
  folklore; `verified_on: null` is the honest alternative.
- **Verify from the log, not the status code.** A `200` proves a request was accepted, not
  that a setting took effect.
