# Scaleway Generative APIs as the Hermes inference provider (verified)

Everything below was verified end-to-end on a live DEV1-S host, not taken from docs.

## Provider wiring

Hermes has **no native Scaleway provider**. Use the OpenAI-compatible path
(confirmed by <https://hermes-agent.nousresearch.com/docs/integrations/providers>:
"OpenAI API (direct) — `OPENAI_API_KEY` in `~/.hermes/.env` (provider: `openai-api`,
optional `OPENAI_BASE_URL`)").

`~/.hermes/.env` (mode 600, owned by the family member):

```bash
OPENAI_API_KEY=<that person's Scaleway secret key>
OPENAI_BASE_URL=https://api.scaleway.ai/v1
```

`~/.hermes/config.yaml`:

```yaml
model:
  provider: openai-api
  default: mistral-small-3.2-24b-instruct-2506
```

### Do NOT use `provider: custom`

The obvious-looking `custom` provider with `CUSTOM_BASE_URL`/`CUSTOM_API_KEY` **does not
work against Scaleway**. Captured on the wire, Hermes rewrites the base URL into
OpenRouter's convention and sends the discovery request unauthenticated:

```
GET /api/v1/models HTTP/1.1        <- note /api/ prefix
User-Agent: python-httpx/0.28.1
(no Authorization header)
```

Scaleway answers `HTTP 403 insufficient permissions`, which looks like an IAM problem
and is not one. `provider: openai-api` sends the correct authenticated request.

Config keys are nested under `model:` — top-level `provider:` is silently accepted but
never read (`hermes config set` warns "not a recognized config key").

## IAM: permissions must be organization-scoped

`GenerativeApisModelAccess` **only takes effect at organization scope**. A policy scoped
to a single project yields `HTTP 403 insufficient permissions` indefinitely — verified
across all four keys over ~15 minutes, and by reverting a working key back to project
scope and watching it break.

Consequence: an inference key cannot be confined to one project. The permission is still
narrow (model invocation only — no infrastructure access), but it is org-wide.

## Cost attribution — UNRESOLVED

The design goal was one project per family member so `scw billing consumption list`
would break spend down per person.

Observed so far: **all Generative APIs consumption is recorded against the organization's
default project**, not against each key's `default_project_id`, despite deliberately
asymmetric per-key load (1/2/3/4 calls). Re-check before relying on R6:

```bash
scw billing consumption list -o json | jq -r '.[]|select(.category_name=="AI")|"\(.product_name) \(.project_id) \(.value)"'
```

If this does not resolve, per-user attribution on Scaleway is not achievable and the
requirement needs either a different provider (OpenRouter has real per-key attribution
*and* per-key spend caps) or client-side accounting from token counts.

## No spend caps exist

Scaleway's billing API offers only `consumption`, `discount`, `invoice` — there is **no
budget or spend-cap API**. R7 ("enforce ongoing cost control", "disable only the
over-budget key") cannot be enforced provider-side. The only enforcement available is a
timer on the host polling consumption and stopping a gateway past a threshold.

## API keys

The organization enforces mandatory expiry, capped at **365 days**
(`max_api_key_expiration_duration=31536000`). Attempting to raise the cap to 3 years is
rejected by Scaleway regardless of the org setting, so annual rotation is unavoidable.

## Gotchas that cost real time

- **SSH keys are project-scoped.** A key registered in one project is not injected into
  instances in another; the instance boots with no authorized key and cannot be
  recovered by rebooting. Register the key in the target project *before* creating.
- **Resources cannot move between projects.** Putting the VPS in a different project
  means recreating it.
- `MaxAuthTries 3` (set in our SSH hardening) collides with an ssh-agent holding several
  keys — connect with `-o IdentitiesOnly=yes`.
- Scaleway does **not** return `usage.cost` in completion responses (OpenRouter does),
  so per-request cost accounting must be derived from token counts.
