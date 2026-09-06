---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  2026-09-06 — after implementing ADR-009: /v1/models returns only hermes-agent and default,
  a live completion through default returned 200, and the web dashboard endpoint was checked
  end to end (401 without credentials, 401 on a wrong password, 200 with the correct one,
  real Let's Encrypt issuer). Cross-member loopback access to the dashboard was confirmed
  blocked. Endpoint certs for 1-4 verified 2026-07-26.
must_not_contain:
  - secrets
  - decision_rationale
  - behavioural_explanation
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
pinned_to: hermes-agent (stock; no local patch as of 2026-09-06)
audience: [ai, operator]
retrieval_priority: high
version: "1.0"
related_documents:
  - ADR-006-public-api-exposure
  - ADR-009-retire-model-tier-reasoning-patch
  - SPEC-agent-access-control
created: 2026-09-06
---

# API Server Endpoints

## Purpose

The public surface of each member's agent: FQDNs, loopback ports, bearer-token locations and
model alias names. Set by
[`deploy/04-enable-api-server.sh`](../../deploy/04-enable-api-server.sh).

## Endpoints

| Member | URL | Loopback port |
|---|---|---|
| Robert | `https://1.agent-hermes.dynv6.net` | 8642 |
| Sofia | `https://2.agent-hermes.dynv6.net` | 8643 |
| Mattis | `https://3.agent-hermes.dynv6.net` | 8644 |
| Love | `https://4.agent-hermes.dynv6.net` | 8645 |
| Robert — **web dashboard (admin)** | `https://5.agent-hermes.dynv6.net` | 9121 |

The `5` endpoint is the Hermes web UI and is **not** a chat endpoint for the family — it is an
admin surface serving `/env`, `/config` and `/files` from the same application as `/chat`. See
[ADR-014](../adr/ADR-014-web-ui-is-admin-only.md). It is guarded by **two** controls: basic
auth at Caddy, and an `nftables` rule restricting ports `9121-9124` to `root` and the Caddy
uid, because loopback is shared by every member gateway.

**Subdomain labels are numeric by design and must stay that way** — see
[ADR-006](../adr/ADR-006-public-api-exposure.md). Certificate Transparency logs are
permanent and public.

Each hermes-agent API server binds `127.0.0.1` only. Caddy holds the sole public listener.

Verify any endpoint:

```bash
curl https://1.agent-hermes.dynv6.net/v1/chat/completions \
  -H "Authorization: Bearer $(cat ~/.hermes-family-keys/api-server/robert.key)" \
  -H "Content-Type: application/json" \
  -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello!"}]}'
```

## Model Surface

`GET /v1/models` returns exactly two entries:

| Name | Backing model |
|---|---|
| `hermes-agent` | the native root name |
| `default` | `qwen3.5-397b-a17b` |

**`default` is the stable contract** — clients select by name. The `quick` and `smart` tiers
were retired on 2026-09-06 by
[ADR-009](../adr/ADR-009-retire-model-tier-reasoning-patch.md); they no longer resolve.

**No reasoning effort is configured anywhere**, and none can be sent to Scaleway from Hermes'
ordinary configuration path — see the trap in
[CONTRACT-hermes-config-surface](CONTRACT-hermes-config-surface.md). Scaleway's own default
applies. If differentiated tiers are ever wanted again, vary
`model_routes.<alias>.model` — an upstream field needing no patch.

## Configuration Keys

| Key | Value |
|---|---|
| `platforms.api_server.extra.model_routes.default.model` | `qwen3.5-397b-a17b` |
| `platforms.api_server.extra.model_routes.default.provider` | `openai-api` |
| `model.max_tokens` | `16384` — global |
| `API_SERVER_CORS_ORIGINS` | `*` — required, not optional |
| `DASHBOARD_PORT` | `/etc/hermes-dashboard/<member>.env`, read by `hermes-dashboard@.service` |

There is **no** route-level `reasoning_effort` key any more. It never existed upstream; it
came from a local patch that has been retired and must not be reapplied.

## Credential Locations

| Credential | Location | Mode |
|---|---|---|
| Per-member bearer tokens | `~/.hermes-family-keys/api-server/<member>.key` — **workstation only, never on the host** | 600 |
| dynv6 API token | `/etc/dynv6/api-token.env` (host), root:root — deliberately outside every `/home/<member>` | 600 |
| Dashboard basic-auth credential | `/etc/hermes-dashboard/robert-webui.cred` (host), root:root | 600 |
| Dashboard bcrypt hash for Caddy | `/etc/hermes-dashboard/caddy.env` (host), root:root, read by `caddy.service` | 600 |

## Known Traps

- **The dashboard rejects proxied requests with `400 {"detail":"Invalid Host header..."}`.**
  It enforces DNS-rebinding protection and accepts only the address it bound to. This reads
  exactly like a broken reverse-proxy config but is the backend refusing deliberately. Fix it
  in Caddy with `header_up Host {upstream_hostport}` — **not** by binding the dashboard to a
  public interface, which would break ADR-006's rule that Caddy holds the only public
  listener.
  *Hit 2026-09-06: auth succeeded and the request still 400'd, which misdirects toward the
  credential.*

- **`basic_auth` is the Caddy 2.8+ spelling.** Older documentation says `basicauth`; this host
  runs v2.11.4 and the old name fails validation.

- **Basic auth at Caddy does not protect the loopback path.** A dashboard bound to
  `127.0.0.1` is reachable by every member gateway — measured `HTTP 200` from a child's user
  before the firewall rule existed. The `nftables` uid restriction is the control for that
  door; the password guards only the public one.

- **The host install ships no built web UI.** `hermes dashboard` exits with "Web UI frontend
  not built and npm is not available" because the installer never builds it and `npm` is not
  reachable as a member user. Build once as root in `web/`, then run with **both**
  `--skip-build` and `HERMES_WEB_DIST` — either alone still fails.

- **`API_SERVER_CORS_ORIGINS` is required for browser-like clients, and `curl` will never
  catch its absence** — `curl` is not subject to CORS at all, so the endpoint tests clean
  from that angle indefinitely. Chatbox routes some calls (at least `/v1/models`) through
  `cors-proxy.chatboxai.app`, which emulates browser CORS enforcement. Without the setting,
  `OPTIONS /v1/models` returns `403` with **no** `Access-Control-Allow-*` headers, the
  preflight fails, and the real request is never sent — nothing reaches the access log.
  Symptom presents as **two unrelated-looking problems**: `Network Error: Failed to fetch
  (cors-proxy.chatboxai.app)`, and model tiers appearing not to work (the model list never
  refreshed past its original single-model cache).
  *Discovered 2026-07-27; fixed in `04-enable-api-server.sh`.*

- **`qwen3.5-397b-a17b` requires an explicit output-token cap.** Without it:
  `HTTP 400: payload validation: max_completion_tokens is limited to 16384 for
  qwen3.5-397b-a17b`. Hermes otherwise falls back to a per-provider default above Scaleway's
  hard cap. Confirmed from source (`gateway/run.py`) that `model.max_tokens` is checked
  before that fallback, and that `model_routes` has **no** per-alias token-limit override —
  so the cap must be global.
  *Verified live 2026-08-08.*

- **`model_catalog.<name>.*` and `model_aliases.<name>.*` are dead ends.** Both were tried
  first. Both are "recognized" by `hermes config set` with no warning, and **neither resolves
  as a callable model** via `model.default` or the `-m` flag — `HTTP 422: model 'x' not
  found`, confirmed on the live host rather than assumed. They may govern something else
  entirely, or nothing yet; they are not the API-server model-tier mechanism regardless.

- **`hermes config set` warns "not a recognized config key" for
  `platforms.api_server.extra.model_routes.<alias>.*`.** Noise — the validator does not know
  about dynamically-named entries, and the value is written correctly. Same pattern as the
  STT provider keys. Verify against what is written, not the warning.

- **Verify tiers from the agent log, not the response code.** A `200` proves the alias
  resolved to *something*. Confirm the log shows
  `model=qwen3.5-397b-a17b reasoning_effort=none` for a `"model": "quick"` request:

  ```bash
  curl https://1.agent-hermes.dynv6.net/v1/models -H "Authorization: Bearer $(cat ~/.hermes-family-keys/api-server/robert.key)"
  ```

- **Caddy silently falls back to the Let's Encrypt *staging* CA** after a couple of failed
  issuance attempts on one domain — a built-in rate-limit safety net. The resulting
  certificate is real but untrusted by every client. A full `systemctl restart caddy` (not
  `reload`) resets that state and forces a fresh attempt against production.
  *Confirmed 2026-07-26.*

- **dynv6 has two unrelated token types.** The TSIG key (`dynv6.com/keys/tsig/new`, for
  RFC2136 `nsupdate`) is **not** what `caddy-dns/dynv6` uses — that plugin authenticates via
  Bearer token against dynv6's REST API v2. Symptom of using the wrong one: a clean `401`.
  The correct credential is the plain **HTTP Token** from the general `dynv6.com/keys` page.
  *Confirmed by reading the plugin's Go source, 2026-07-26.*

- **`caddyserver.com`'s prebuilt-binary API does not carry `caddy-dns/dynv6`** — `400: not a
  registered Caddy module package path`, despite the module being real. Build locally
  instead: `GOOS=linux GOARCH=amd64 xcaddy build --with github.com/caddy-dns/dynv6`, then
  `scp` it. This also avoids installing a Go toolchain on the 2 GB VPS.
