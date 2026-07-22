# Hermes family setup on Scaleway

Four family members — Robert, Sofia, Mattis, Love — each running their own always-on
[Hermes Agent](https://hermes-agent.nousresearch.com) on one cheap EU VPS, with
EU/GDPR-resident inference via Scaleway Generative APIs.

Everything below has been executed and verified on a live host. Where something is
unverified or known-broken it says so explicitly.

## Deployment runbook

Run in order. Steps 1–3 rebuild the entire deployment from nothing.

| # | Script | Where | What it does |
|---|---|---|---|
| 0 | `scw init` | workstation | Authenticate the Scaleway CLI. Interactive — needs a real TTY, so run it in a normal terminal. |
| 1 | [`deploy/01-provision-scaleway.sh`](deploy/01-provision-scaleway.sh) | workstation | Creates 5 projects, registers your SSH key, creates one IAM application + scoped policy + API key per member, and boots the VPS with [`cloud-init-hermes-base.yaml`](deploy/cloud-init-hermes-base.yaml). |
| 2 | [`deploy/02-install-hermes.sh <ip>`](deploy/02-install-hermes.sh) | workstation → host | Installs Hermes once, system-wide, checksum-verified and pinned to a commit. ~6 min. |
| 3 | [`deploy/03-configure-profiles.sh <ip>`](deploy/03-configure-profiles.sh) | workstation → host | Installs the [gateway unit](deploy/hermes-gateway@.service), writes each member's `.env` via [`configure-profile.sh`](deploy/configure-profile.sh), points Hermes at Scaleway, starts all four gateways. |
| 4 | `hermes whatsapp` / `hermes gateway setup` | host, per member | Add messaging channels. Interactive over SSH — **no web UI required**. |

Step 1 writes the four inference keys to `~/.hermes-family-keys/` (mode 600). Scaleway
shows a secret key **once**; those files are the only copy. They never enter git.

Supporting files: [`deploy/scaleway-provider.md`](deploy/scaleway-provider.md) documents
the verified provider wiring and the traps that cost the most time.

## Architecture

**One Linux user per family member, not one Hermes profile per family member.**

Hermes profiles isolate Hermes state but run as the same OS user, so any member's agent
could read every other member's secrets and memory. Since the agent can execute shell
commands and two of the four users are children, that is not an acceptable boundary.

Instead: four unprivileged Linux users, `0700` homes, no sudo, one shared system-wide
Hermes install, and one systemd instance per user with `ProtectHome=tmpfs` +
`BindPaths=/home/%i`.

Verified on the live host: from inside Love's gateway namespace, `ls /home/` returns only
`love` — Robert's home does not merely deny access, it does not exist.

```
/usr/local/lib/hermes-agent      2.2 GB, shared by all four
/usr/local/bin/hermes
/home/<member>/.hermes/          per-member: .env, config.yaml, state.db, sessions, memories
hermes-gateway@<member>.service  per-member unit, MemoryMax=320M
```

### Why a custom unit instead of `hermes gateway install`

Hermes' own installer writes a single, non-templated `hermes-gateway.service` — **one
gateway per host**. Installing it for members 2–4 just reports "already installed" and
restarts the first one. Our [template unit](deploy/hermes-gateway@.service) also restores
restart rate-limiting (upstream ships `StartLimitIntervalSec=0`, letting a crash loop
retry forever and burn provider spend) and adds per-member memory caps.

## Measured footprint

Scaleway **DEV1-S** — 2 vCPU / 2 GB / 20 GB local NVMe, **€6.55/mo** + IPv4, `fr-par-1`,
Debian 13.

| | Idle, all four gateways running |
|---|---|
| Per gateway RSS | 133–152 MB |
| Total used | 845 MB / 1968 MB |
| Available | ~1.1 GB |
| Swap used | ~0 (2 GB swapfile configured) |
| Disk | 7.4 GB / 19 GB |

DEV1-S is sufficient. Two caveats: this is **idle with no messaging platforms connected**,
and the install itself peaks at **1.6 GB** — the tightest moment on the box. `DEV1-M`
(3 vCPU / 4 GB, €14.74/mo) is a stop/resize/start away if real usage demands it.

Note the README's original "2 vCPU / 4 GB starter" spec matches no cheap x64 SKU:
`DEV1-M` gives 3 vCPU / 4 GB for **less** (€14.74) than the literal 2/4 options
(`PLAY2-NANO`, €20.10).

## Inference: Scaleway Generative APIs

EU-hosted, OpenAI-compatible, verified end-to-end through Hermes for all four members.
Measured upstream latency: **57 ms**. 18 models available.

```yaml
# ~/.hermes/config.yaml
model:
  provider: openai-api        # NOT "custom" — see scaleway-provider.md
  default: mistral-small-3.2-24b-instruct-2506
```
```bash
# ~/.hermes/.env  (mode 600, owned by that member)
OPENAI_API_KEY=<that member's Scaleway key>
OPENAI_BASE_URL=https://api.scaleway.ai/v1
```

Auxiliary models (vision, web summarisation) default to `provider: auto`, which routes
them to the main chat model — so they stay on Scaleway too, rather than leaking to a
non-EU provider.

## Messaging channels — no web interface needed

Everything is configurable from the CLI: `hermes config set/get/unset`,
`hermes setup --non-interactive`, and per-platform commands. Verified env var names:

| Platform | Token vars | Transport | Needs DNS/public URL? |
|---|---|---|---|
| Discord | `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS` | WebSocket, outbound | No |
| Slack | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_ALLOWED_USERS` | Socket Mode, outbound | No |
| WhatsApp (personal) | `WHATSAPP_ENABLED`, `WHATSAPP_ALLOWED_USERS` | `hermes whatsapp` — Baileys, QR pairing | No |
| WhatsApp (business) | — | `hermes whatsapp-cloud` — Meta Cloud API | **Yes** — public webhook |
| Telegram | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` | polling | No |

So the DNS answer depends entirely on which WhatsApp backend you pick. With Discord,
Slack and the Baileys WhatsApp bridge, **no domain, no TLS, no reverse proxy, no inbound
ports** are required.

## Requirements status

| ID | Requirement | Status |
|---|---|---|
| R1 | Run Hermes on a cheap Scaleway VPS | **Done** — DEV1-S, €6.55/mo, verified |
| R2 | Run 4 profiles continuously | **Done** — 4 systemd units, boot-enabled |
| R3 | Keep family profiles separate | **Done** — OS-user + mount-namespace isolation, verified |
| R4 | Internet-safe security baseline | **Partly** — SSH key-only, no sudo, hardened units, unattended upgrades. No host firewall configured yet. |
| R5 | Clarify DNS need | **Done** — not needed unless using WhatsApp Cloud API |
| R6 | Track inference spend per profile | **Open** — see below |
| R7 | Enforce cost control per profile | **Blocked** — see below |
| R8 | Mixed messaging channels per member | **Ready** — env vars verified, tokens not yet added |

## Open questions

1. **Per-member billing attribution is unresolved (R6).** The design gives each member
   their own Scaleway project and a key whose `default_project_id` points at it. But so
   far *all* Generative APIs consumption is recorded against the organisation's default
   project, with zero against the four `hermes-*` projects — even after deliberately
   asymmetric per-key load. Billing may settle daily; **re-check after 24h** with:
   ```bash
   scw billing consumption list -o json | jq -r '.[]|select(.category_name=="AI")|"\(.product_name) \(.project_id)"'
   ```
   If it does not resolve, per-member attribution is not achievable on Scaleway and R6
   needs either a different provider or client-side token accounting.

2. **Scaleway has no spend caps (R7).** Its billing API exposes only `consumption`,
   `discount`, `invoice` — no budget API. There is no provider-side equivalent of
   OpenRouter's per-key hard limit, and no way to "disable only the over-budget key"
   automatically. Enforcement would have to be a timer on the host that polls consumption
   and stops a gateway past a threshold. Not yet built.

3. **Host firewall not configured.** No inbound ports are needed beyond SSH, but no
   nftables ruleset or Scaleway security group has been applied yet.

4. **Real-load memory is unmeasured.** All figures are idle with no channels connected.
   `MemoryMax=320M` per member is comfortable now but untested against live Slack/Discord/
   WhatsApp clients and concurrent conversations.

5. **Child-safety controls not configured.** Mattis and Love get agents that can execute
   shell commands. Approval mode, tool restrictions and skill pruning have not been set.
   78 bundled skills are seeded per member by default, most irrelevant for a family.

6. **Key rotation.** Scaleway enforces API key expiry, hard-capped at **365 days** — a
   3-year request is rejected regardless of the org setting. Keys expire and must be
   rotated annually; no automation exists yet.

## Operational notes

- **Connect with `-o IdentitiesOnly=yes`.** Our SSH hardening sets `MaxAuthTries 3`; an
  agent holding several keys exhausts that before offering the right one.
- **SSH keys are project-scoped in Scaleway.** A key registered in another project is not
  injected, and the instance boots unreachable — a reboot does not fix it.
- **Resources cannot move between projects.** Relocating the VPS means recreating it.
