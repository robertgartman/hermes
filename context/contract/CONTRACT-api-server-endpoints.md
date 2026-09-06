---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-08-08
verification: >
  All four public model lists contained only quick/default/smart; live calls succeeded for
  every profile; Robert's recorded API sessions confirmed effective reasoning configs as
  disabled, medium and high. Endpoint certs verified 2026-07-26.
must_not_contain:
  - secrets
  - decision_rationale
  - behavioural_explanation
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
pinned_to: hermes-agent + deploy/hermes-api-model-route-reasoning.patch
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

## Model Tier Aliases

> **Superseded in principle, still live in practice.**
> [ADR-009](../adr/ADR-009-retire-model-tier-reasoning-patch.md) retires the three-tier
> surface in favour of a single alias with no configured reasoning effort. **That decision is
> not yet implemented** — everything in this section remains accurate on the host as of
> 2026-09-06. When the cutover happens, this section collapses to one alias, the
> `reasoning_effort` row disappears from Configuration Keys, `pinned_to` drops the patch
> reference, and `verified_on` reverts to `null` until reconfirmed.

Exposed via `GET /v1/models` by the **API server only**. All three use the same model and
vary only reasoning effort.

| Alias | Model | `reasoning_effort` |
|---|---|---|
| `quick` | `qwen3.5-397b-a17b` | `none` |
| `default` | `qwen3.5-397b-a17b` | `medium` |
| `smart` | `qwen3.5-397b-a17b` | `high` |

**The alias names are the stable contract** — clients like Chatbox select by name. The
backing model and effort levels live in `03-configure-profiles.sh` (`ALIAS_MODEL`,
`EFFORT_QUICK`, `EFFORT_DEFAULT`, `EFFORT_SMART`). Re-running that script also removes the
superseded `medium` and `ultra` routes from existing profiles.

Scaleway accepts `none`, `low`, `medium` and `high` for this model.

## Configuration Keys

| Key | Value |
|---|---|
| `platforms.api_server.extra.model_routes.<alias>.model` | `qwen3.5-397b-a17b` |
| `platforms.api_server.extra.model_routes.<alias>.provider` | upstream field |
| `platforms.api_server.extra.model_routes.<alias>.reasoning_effort` | supplied by the deployment patch |
| `model.max_tokens` | `16384` — global, used by all three tiers |
| `API_SERVER_CORS_ORIGINS` | `*` — required, not optional |

`reasoning_effort` at route level is **not** upstream. It comes from
[`deploy/hermes-api-model-route-reasoning.patch`](../../deploy/hermes-api-model-route-reasoning.patch),
a narrow extension that accepts the field, validates it, updates Hermes' internal reasoning
config, and forwards it as Scaleway's top-level request field. It does not alter auxiliary
tasks or MoA.

## Credential Locations

| Credential | Location | Mode |
|---|---|---|
| Per-member bearer tokens | `~/.hermes-family-keys/api-server/<member>.key` — **workstation only, never on the host** | 600 |
| dynv6 API token | `/etc/dynv6/api-token.env` (host), root:root — deliberately outside every `/home/<member>` | 600 |

## Known Traps

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
