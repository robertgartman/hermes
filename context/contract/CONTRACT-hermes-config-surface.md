---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-08-08
verification: >
  Config read-back for all four profiles confirmed model, web and STT keys; live
  web_search_tool and Tavily extraction calls returned real content per member.
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
  - ADR-003-scaleway-eu-inference
  - ADR-004-private-searxng-backend
  - ADR-005-command-stt-provider
created: 2026-09-06
---

# Hermes Configuration Surface

## Purpose

The `config.yaml` keys and `.env` variables each member's gateway reads. Set by
[`deploy/03-configure-profiles.sh`](../../deploy/03-configure-profiles.sh) and
[`deploy/05-enable-web-search.sh`](../../deploy/05-enable-web-search.sh).

Every value below is per member, under `/home/<member>/.hermes/`.

## Inference

| Key | Where | Value |
|---|---|---|
| `model.provider` | `config.yaml` | `openai-api` — **not** `custom` |
| `model.default` | `config.yaml` | `qwen3.5-397b-a17b` |
| `model.max_tokens` | `config.yaml` | `16384` — required, see traps |
| `OPENAI_API_KEY` | `.env` | That member's Scaleway key |
| `OPENAI_BASE_URL` | `.env` | `https://api.scaleway.ai/v1` |

Auxiliary models (vision, web summarisation) stay at `provider: auto`, which routes them to
the main chat model.

## Web

| Key | Where | Value |
|---|---|---|
| `web.search_backend` | `config.yaml` | `searxng` |
| `web.extract_backend` | `config.yaml` | `tavily` |
| `auxiliary.web_extract.reasoning_effort` | `config.yaml` | `none` |
| `SEARXNG_URL` | `.env` | `http://127.0.0.1:8888` |
| `TAVILY_API_KEY` | `.env` | Shared Tavily key |

## Speech-to-text

| Key | Where | Value |
|---|---|---|
| `stt.enabled` | `config.yaml` | `true` |
| `stt.echo_transcripts` | `config.yaml` | `true` |
| `stt.provider` | `config.yaml` | `scaleway` — the name of the entry below |
| `stt.providers.scaleway.type` | `config.yaml` | `command` |
| `stt.providers.scaleway.command` | `config.yaml` | `curl` to `$OPENAI_BASE_URL/audio/transcriptions`, model `whisper-large-v3`, piped through `jq -r .text` |
| `stt.providers.scaleway.format` | `config.yaml` | `txt` |
| `stt.providers.scaleway.timeout` | `config.yaml` | `60` |

## Credential Locations

Locations only — never values. Each source displays the secret **once**; these files are the
only copy and never enter git.

| Credential | Location | Mode |
|---|---|---|
| Per-member Scaleway inference key | `~/.hermes-family-keys/<member>` (workstation) | 600 |
| Shared Tavily key | `~/.hermes-family-keys/tavily.key` (workstation) | 600 |
| Deployed per-member secrets | `/home/<member>/.hermes/.env` (host), owned by that member | 600 |

`~/.hermes-family-keys/` is mode 700. Step 6 copies the Tavily key through **stdin, never
argv**, and is safe to re-run after rotation.

## Compatibility

Keys under `stt.providers.<name>.*` are dynamically named — the name is chosen by this
deployment, not by Hermes. `model.provider`, `web.*` and `stt.*` are upstream schema and
move with the pin.

## Known Traps

- **`model.provider: custom` looks right and is wrong.** For an OpenAI-compatible endpoint
  that is not OpenAI, the working value is `openai-api`.
  *Confirmed in deployment.*

- **`hermes config set` warns "not a recognized config key" for every `stt.providers.<name>.*`
  key.** Symptom: `Did you mean: stt.provider`. Cause: the validator does not know about
  dynamically-named provider entries. **The value is written correctly regardless.** The same
  false-positive pattern appears for `platforms.api_server.extra.model_routes.<alias>.*`.
  Note the inverse case exists too — `model_catalog` produced the same warning and *was*
  genuinely the wrong key. **Do not trust the warning in either direction**; verify against
  what actually lands in `config.yaml` and, ideally, a live request.
  *Confirmed by testing; resulting `config.yaml` matches the documented schema and
  transcription works — 2026-07-26.*

- **`$OPENAI_BASE_URL` / `$OPENAI_API_KEY` in the STT command are expanded at Hermes'
  runtime, not at config-set time.** The value must be single-quoted when passed to
  `hermes config set` — and inside `03-configure-profiles.sh`'s remote heredoc, escaped
  again so the *remote* shell executing the loop does not expand them either. The literal
  `$VAR` text must land in `config.yaml` for Hermes' own subprocess to resolve later.
  *Confirmed in deployment.*

- **Scaleway's `/v1/audio/transcriptions` ignores `response_format=text`** and always
  returns JSON (`{"text": "...", "usage": {...}}`) regardless of what is requested. Piping
  through `jq -r .text` sidesteps this — it is one of Hermes' two documented transcript
  read-back paths (stdout, when no `{output_path}` file is written). Do not try to force
  Scaleway to honour the parameter.
  *Caught by testing against a real cached voice file before trusting the config.*

- **The pinned Hermes version logs successful Tavily responses as tool errors.** Cause: its
  generic status detector matches the nested JSON field `"error": null`. This is a
  display/logging false positive only — both the direct result and the model-visible API
  response contained the extracted page.
  *Confirmed 2026-08-08.*

- **`stt.local.vad` and `stt.local.unload_after_idle_seconds` are not implemented by the
  pinned version.** Only `model` and `language` are consumed from `stt.local`. Setting the
  others has no effect and produces no error.
  *Confirmed against the pinned tree.*

- **The `voice.*` block does not apply to this deployment.** It is valid configuration, but
  it controls microphone recording in an interactive CLI/TUI on a machine with a microphone —
  not inbound voice messages on a headless VPS.

- **Hermes' API server does not proxy `/v1/audio/transcriptions`.** Messaging audio is
  transcribed inside the gateway; an API client needing a standalone transcription endpoint
  must call Scaleway directly.
