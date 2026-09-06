---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-07-22
verification: >
  Discord verified end-to-end for Mattis on 2026-07-22 — DM → gateway → allowlist →
  Scaleway inference → reply. Other platforms' variable names verified against the pinned
  tree but not exercised live.
must_not_contain:
  - secrets
  - decision_rationale
  - behavioural_explanation
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
retrieval_priority: high
version: "1.0"
related_documents:
  - SPEC-agent-access-control
  - CONTRACT-host-layout
created: 2026-09-06
---

# Messaging Channels

## Purpose

Environment-variable names and platform settings for each messaging channel. Set per member
via [`deploy/configure-profile.sh`](../../deploy/configure-profile.sh).

Everything here is configurable from the CLI — `hermes config set/get/unset`,
`hermes setup --non-interactive`, and per-platform commands. **No web interface is required.**

## Platform Surface

Verified variable names:

| Platform | Token variables | Transport | Needs DNS / public URL? |
|---|---|---|---|
| Discord | `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS` | WebSocket, outbound | No |
| Slack | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_ALLOWED_USERS` | Socket Mode, outbound | No |
| WhatsApp (personal) | `WHATSAPP_ENABLED`, `WHATSAPP_ALLOWED_USERS` | `hermes whatsapp` — Baileys, QR pairing | No |
| WhatsApp (business) | — | `hermes whatsapp-cloud` — Meta Cloud API | **Yes** — public webhook |
| Telegram | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` | polling | No |

**The DNS requirement depends entirely on the WhatsApp backend chosen.** With Discord, Slack
and the Baileys WhatsApp bridge, no domain, no TLS, no reverse proxy and no inbound ports are
needed. (The API server in
[CONTRACT-api-server-endpoints](CONTRACT-api-server-endpoints.md) is a separate, optional
surface with its own DNS requirement.)

## Discord Settings

**One Discord application per member.** A bot token authenticates exactly one gateway, so
members cannot share one. Each member needs their own app, token and allowlist.

| Setting | Value |
|---|---|
| Privileged intents | **Server Members** + **Message Content** ON, Presence OFF |
| Permissions integer | `379904` — View Channels, Send Messages, Embed Links, Attach Files, Read Message History, Use Slash Commands. No thread permissions. |
| `DISCORD_BOT_TOKEN` | Bot page → Reset Token. Shown once. |
| `DISCORD_ALLOWED_USERS` | The numeric 18-digit snowflake user ID |
| `DISCORD_AUTO_THREAD` | `false` |

## Credential Locations

| Credential | Location | Mode |
|---|---|---|
| Per-member channel tokens | `/home/<member>/.hermes/.env` (host) | 600 |

`configure-profile.sh` accepts a literal `-` to read `KEY=VALUE` lines from **stdin**, which
keeps secrets out of the process table and shell history. It **merges** into the existing
`.env` and never truncates a configured profile.

## Compatibility

`DISCORD_ALLOWED_USERS` and its per-platform equivalents are the enforcement point for
[SPEC-agent-access-control](../spec/SPEC-agent-access-control.md). Changing the variable
name or its semantics changes a security boundary.

## Known Traps

- **`DISCORD_ALLOWED_USERS` must be the 18-digit numeric snowflake, not the username.**
  Symptom: the bot connects, shows online, and **silently ignores every message, with
  nothing in the log**. Cause: a username never matches. Check: confirm the value is all
  digits.
  *Confirmed 2026-07-22.*

- **Without the Message Content privileged intent, the bot connects, receives events, and
  sees empty text.** Symptom: it looks online and never answers — indistinguishable at a
  glance from the allowlist trap above. Both intents (Server Members **and** Message
  Content) are required.
  *Confirmed 2026-07-22.*

- **`DISCORD_AUTO_THREAD` defaults to `true`.** That makes the bot spawn a thread per
  `@mention`, which requires Create Public Threads — a permission `379904` deliberately
  omits. Set it `false` so replies land inline.
  *Confirmed 2026-07-22.*

- **A Discord server is required even for DM-only use.** Discord will not let a user open a
  DM to a bot unless they share a guild. The server is a formality; the DM is the actual
  surface.

- **Public Bot cannot be disabled.** Discord refuses to turn the toggle off, so anyone with
  the Application ID can install the bot into their own server. **This is not the security
  boundary and does not need to be** — `DISCORD_ALLOWED_USERS` is enforced in the adapter
  *before* any model call, so an unauthorised sender is dropped without consuming inference
  spend. Confirmed in `plugins/platforms/discord/adapter.py`.

- **Messaging libraries must be installed at build time.** Hermes lazy-installs platform
  dependencies on first use, but the gateway units run `ProtectSystem=full`, so
  `/usr/local/lib` is read-only to them and the lazy install can never succeed. Symptom:
  `Platform 'Discord' requirements not met`, and a gateway that starts with no platforms.
  Step 2 installs the Discord/Slack/Telegram dependencies up front, reading version pins from
  the pinned tree's own `LAZY_DEPS` table so they cannot drift from `PIN_COMMIT`.
  *Confirmed in deployment.*
