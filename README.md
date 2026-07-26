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
| 4 | [`deploy/configure-profile.sh <user> -`](deploy/configure-profile.sh) | host, per member | Add messaging channels by piping `KEY=VALUE` lines in — non-interactive, secrets never enter argv or shell history. See [Configured: Discord for Mattis](#configured-discord-for-mattis). `hermes whatsapp` / `hermes gateway setup` remain available for interactive setup over SSH — **no web UI required**. |
| 5 | [`deploy/04-enable-api-server.sh <ip>`](deploy/04-enable-api-server.sh) | workstation → host | Optional. Enables hermes-agent's API server per member, builds and installs a Caddy reverse proxy (real Let's Encrypt certs via dynv6 DNS-01), points DNS at the host. See [Mobile / API access](#mobile--api-access). Idempotent — safe to re-run after a VPS recreate. |

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

### Configured: Discord for Mattis

Verified end-to-end on 2026-07-22: DM → gateway → allowlist → Scaleway inference → reply.

**One Discord application per member.** A bot token authenticates exactly one gateway, so
members cannot share one. Each member gets their own app, token and allowlist.

| Setting | Value | Why |
|---|---|---|
| Privileged intents | **Server Members** + **Message Content** ON, Presence OFF | Both are required. Without Message Content the bot connects, receives events, and sees empty text — it looks online and never answers. |
| Permissions integer | `379904` | View Channels, Send Messages, Embed Links, Attach Files, Read Message History, Use Slash Commands. No thread permissions. |
| `DISCORD_BOT_TOKEN` | Bot page → Reset Token | Shown once. Not the Application ID, Public Key or Client Secret. |
| `DISCORD_ALLOWED_USERS` | Numeric user ID | **Must be the 18-digit snowflake, not the username.** A username silently never matches: the bot stays online and ignores every message, with nothing in the log. |
| `DISCORD_AUTO_THREAD` | `false` | Defaults to `true`, which makes the bot spawn a thread per `@mention` — needing Create Public Threads, which `379904` deliberately omits. Set false so replies land inline. |

**A server is required even for DM-only use.** Discord will not let a user open a DM to a
bot unless they share a guild. The server is a formality; the DM is the actual surface.

**Public Bot cannot be disabled.** Discord refuses to turn the toggle off, so anyone with
the Application ID can install the bot into their own server. This is not the security
boundary and does not need to be. `DISCORD_ALLOWED_USERS` is enforced in the adapter
*before* any model call, so an unauthorised sender is dropped without consuming inference
spend. Confirmed in `plugins/platforms/discord/adapter.py`.

~~**Voice messages do not work.**~~ **RESOLVED 2026-07-26** — see
[Configured: voice transcription via Scaleway](#configured-voice-transcription-via-scaleway)
below.

### Configured: voice transcription via Scaleway

Verified end-to-end on 2026-07-26 against real Discord voice messages from Mattis (not
synthesized test audio) — transcript came back correct both times ("Hello.").

**Root cause of the original failure:** `stt.provider` defaulted to `local`, which needs
`faster-whisper` installed or a `HERMES_LOCAL_STT_COMMAND` — neither existed on this host.
Confirmed in the gateway log: `STT provider 'local' configured but unavailable`. This is a
**setting, not a skill** — unrelated to the 78 bundled skills in open question #5.

**Why not just point `stt.provider: openai` at Scaleway (same trick as the chat model)?**
Tried it first — it silently fails in a way worth documenting so nobody repeats it:

1. `stt.openai.model: whisper-large-v3` gets validated against Hermes's hardcoded list of
   *known OpenAI* model names. `whisper-large-v3` isn't on that list, so Hermes logs
   `Model whisper-large-v3 not available on OpenAI, using whisper-1` and silently
   substitutes it — your configured model name is discarded, not passed through.
2. Scaleway then correctly rejects `whisper-1` (it doesn't have a model by that name):
   `HTTP 422 MODEL NOT FOUND`.
3. The `STT_OPENAI_BASE_URL` redirect itself worked mechanically — confirmed by the error
   coming back as a clean Scaleway-shaped 422, not a connection failure. Only the
   model-name substitution broke it.

**The fix — `stt.providers.<name>: type: command`**, not `HERMES_LOCAL_STT_COMMAND`. This
is a newer, documented-as-recommended mechanism (found by grepping the installed
package's own source and docs at `/usr/local/lib/hermes-agent/website/docs/user-guide/
features/tts.md` — this specific schema was not reliably surfaced by web search or the
hosted docs site). Unlike `stt.provider: openai`, a command provider has no whitelist —
Hermes just runs the shell command:

```yaml
# ~/.hermes/config.yaml, set via `hermes config set` (see 03-configure-profiles.sh)
stt:
  provider: scaleway
  providers:
    scaleway:
      type: command
      command: >-
        curl -sS -X POST $OPENAI_BASE_URL/audio/transcriptions
        -H "Authorization: Bearer $OPENAI_API_KEY"
        -F "file=@{input_path}" -F "model=whisper-large-v3"
        | jq -r .text
      format: txt
      timeout: 60
```

**A second gotcha, caught by testing against a real cached voice file before trusting the
config:** Scaleway's `/v1/audio/transcriptions` endpoint ignores `response_format=text` and
always returns JSON (`{"text": "...", "usage": {...}}`) regardless of what you ask for.
Piping through `jq -r .text` — one of Hermes's two documented "how the transcript is read
back" paths (stdout, when no `{output_path}` file is written) — sidesteps this rather than
trying to force Scaleway to honor a parameter it doesn't respect.

**`$OPENAI_BASE_URL` / `$OPENAI_API_KEY` are expanded at Hermes's runtime, not at
config-set time** — the value must be single-quoted when passed to `hermes config set`
(and, inside `03-configure-profiles.sh`'s remote heredoc, escaped so the *remote* shell
executing the loop doesn't expand them either) so the literal `$VAR` text lands in
`config.yaml` for Hermes's own subprocess call to resolve later, using the same credentials
already configured for chat.

**`hermes config set`'s "not a recognized config key" warning is noise for this schema.**
Every key under `stt.providers.<name>.*` triggers it (`Did you mean: stt.provider`) because
the validator doesn't know about dynamically-named provider entries — the value is still
written correctly. Confirmed by testing: the resulting `config.yaml` matches the documented
schema exactly, and transcription works. (The same false-positive pattern showed up earlier
for `model_catalog` — that one, unlike this one, actually *was* the wrong key. Don't trust
the warning either way; verify against what actually gets written and, ideally, a live test.)

## Mobile / API access

Each member's agent is also reachable directly over HTTPS via hermes-agent's built-in
OpenAI-compatible API server, fronted by a lightweight Caddy reverse proxy — one FQDN per
member, real Let's Encrypt certs via dynv6 DNS-01. Point any OpenAI-compatible client
(e.g. [Chatbox](https://github.com/chatboxai/chatbox)) at the URL below with the member's
bearer token.

| Member | URL | Loopback port | Bearer token (local only, never on the host) |
|---|---|---|---|
| Robert | `https://1.agent-hermes.dynv6.net` | 8642 | `~/.hermes-family-keys/api-server/robert.key` |
| Sofia  | `https://2.agent-hermes.dynv6.net` | 8643 | `~/.hermes-family-keys/api-server/sofia.key` |
| Mattis | `https://3.agent-hermes.dynv6.net` | 8644 | `~/.hermes-family-keys/api-server/mattis.key` |
| Love   | `https://4.agent-hermes.dynv6.net` | 8645 | `~/.hermes-family-keys/api-server/love.key` |

Verify any endpoint:

```bash
curl https://1.agent-hermes.dynv6.net/v1/chat/completions \
  -H "Authorization: Bearer $(cat ~/.hermes-family-keys/api-server/robert.key)" \
  -H "Content-Type: application/json" \
  -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello!"}]}'
```

Deliberately opaque subdomain labels (`1`–`4`, not member names): Let's Encrypt certificate
issuance is permanently, publicly logged in Certificate Transparency (crt.sh etc.) — a
`mattis-hermes.example.com` cert would forever tie a child's name to a host known (from
hermes-agent's own docs) to run an agent with terminal access.

Each hermes-agent API server stays bound to `127.0.0.1` — Caddy is the only thing with a
public listener, since the API server "gives full access to hermes-agent's toolset,
including terminal commands" (its own docs' words).

### Configured: dynv6 + Caddy reverse proxy

Verified end-to-end on 2026-07-26: all four member endpoints return `200` with real
production Let's Encrypt certs. Traps that cost time getting here:

- **dynv6 has two unrelated token types.** The TSIG key (`dynv6.com/keys/tsig/new`, for
  RFC2136 `nsupdate`) is NOT what Caddy's `caddy-dns/dynv6` plugin needs — that plugin
  authenticates via Bearer token against dynv6's REST API v2
  (`https://dynv6.com/api/v2/...`). Confirmed by reading the plugin's Go source after a
  TSIG key got a clean `401`. The right credential is the plain **HTTP Token** from the
  general `dynv6.com/keys` page. Stored at `/etc/dynv6/api-token.env`
  (`DYNV6_API_TOKEN=...`), root:root mode 600, deliberately outside every
  `/home/<member>` tree — a `hermes-gateway@<member>` process can read its own home, and
  this credential can rewrite DNS + certs for the whole family.
- **`caddyserver.com`'s prebuilt-binary download API doesn't carry every `caddy-dns/*`
  plugin** — `dynv6` isn't in its catalog (400: "not a registered Caddy module package
  path"), even though the module itself is real. Built a custom binary locally instead
  with `xcaddy` (`GOOS=linux GOARCH=amd64 xcaddy build --with github.com/caddy-dns/dynv6`)
  and shipped it via `scp` — avoids installing a Go toolchain on the 2 GB VPS entirely.
- **Caddy silently falls back to the Let's Encrypt *staging* CA** after a couple of failed
  issuance attempts on one domain (a built-in rate-limit safety net) — the resulting cert
  is real but untrusted by any client. A full `systemctl restart caddy` (not just
  `reload`) resets that state and forces a fresh attempt against production.
- **DNS-01, not HTTP-01** — chosen specifically so port 80 never needs to be open, only
  443.

## Requirements status

| ID | Requirement | Status |
|---|---|---|
| R1 | Run Hermes on a cheap Scaleway VPS | **Done** — DEV1-S, €6.55/mo, verified |
| R2 | Run 4 profiles continuously | **Done** — 4 systemd units, boot-enabled |
| R3 | Keep family profiles separate | **Done** — OS-user + mount-namespace isolation, verified |
| R4 | Internet-safe security baseline | **Done** — SSH key-only, no sudo, hardened units, unattended upgrades, host nftables + Scaleway security group both default-drop inbound with explicit `22`/`443`-only allow rules, verified from a fresh connection before trusting either change. |
| R5 | Clarify DNS need | **Done** — not needed unless using WhatsApp Cloud API |
| R6 | Track inference spend per profile | **Open** — see below |
| R7 | Enforce cost control per profile | **Blocked** — see below |
| R8 | Mixed messaging channels per member | **Partly** — Discord live for Mattis, verified end-to-end. Other members and platforms not yet added. |

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

3. ~~Host firewall not configured.~~ **RESOLVED 2026-07-26.** Both layers now default-drop
   inbound with explicit allow rules for `22`/`443` only, applied in the safe order
   (explicit allows added first, default policy flipped second) and verified from a fresh
   connection immediately after each change:
   - Host: [`deploy/nftables-hermes.conf`](deploy/nftables-hermes.conf), persisted via the
     standard `nftables.service` (`/etc/nftables.conf`).
   - Cloud: Scaleway security group `Default security group`
     (`inbound-default-policy=drop`, explicit `accept` rules for TCP 22 and 443).
   `80` is deliberately not open on either layer — see [Mobile / API access](#mobile--api-access)
   for why DNS-01 never needs it.

4. **Real-load memory is unmeasured.** All figures are idle with no channels connected.
   `MemoryMax=320M` per member is comfortable now but untested against live Slack/Discord/
   WhatsApp clients and concurrent conversations.

5. **Child-safety controls not configured.** Mattis and Love get agents that can execute
   shell commands. Approval mode, tool restrictions and skill pruning have not been set.
   78 bundled skills are seeded per member by default, most irrelevant for a family.

6. **Key rotation.** Scaleway enforces API key expiry, hard-capped at **365 days** — a
   3-year request is rejected regardless of the org setting. Keys expire and must be
   rotated annually; no automation exists yet.

7. **No tool backend configured (web search, browser, image gen, TTS) — for any member,
   on any channel, not just the API server.** Chat works because it only needs the model
   provider (Scaleway, already configured). Confirmed by grepping all four `.env`/
   `config.yaml`: no `FIRECRAWL_API_KEY`, `BROWSERBASE_API_KEY`, `FAL_KEY`,
   `ELEVENLABS_API_KEY`, no Nous Portal setup. This is the same root cause as the
   already-documented "voice messages do not work" gap. Two paths, needs a decision:
   a [Nous Portal](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server)
   subscription (bundles 300+ models + web/image/TTS/browser via one Tool Gateway — but
   check whether it can supply *only* tools while `model.provider` stays pinned to
   Scaleway, since Portal's own models would undermine the EU-residency goal this
   deployment is built around), or per-tool bring-your-own-key (Firecrawl for web
   search/scraping, Browserbase for browser automation, FAL for image gen, ElevenLabs or
   OpenAI/Mistral for TTS — each independent, no Portal required).

## Operational notes

- **Connect with `-o IdentitiesOnly=yes`.** Our SSH hardening sets `MaxAuthTries 3`; an
  agent holding several keys exhausts that before offering the right one.
- **SSH keys are project-scoped in Scaleway.** A key registered in another project is not
  injected, and the instance boots unreachable — a reboot does not fix it.
- **Resources cannot move between projects.** Relocating the VPS means recreating it.
- **Messaging libraries must be installed at build time.** Hermes lazy-installs platform
  deps on first use, but the gateway units run `ProtectSystem=full`, so `/usr/local/lib`
  is read-only to them and the lazy install can never succeed. Step 2 installs the
  Discord/Slack/Telegram deps up front, reading the version pins from the pinned tree's
  own `LAZY_DEPS` table so they cannot drift from `PIN_COMMIT`. Symptom when missing:
  `Platform 'Discord' requirements not met` and a gateway that starts with no platforms.
- **The venv has no `pip`.** It is uv-created; use
  `/root/.hermes/bin/uv pip install --python /usr/local/lib/hermes-agent/venv/bin/python`.
  A bare `pip list` fails, which makes "is package X installed?" checks silently return
  nothing rather than an error.
