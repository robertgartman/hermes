---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale and the dead ends. Live status is in STATE.md.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - ADR-003-scaleway-eu-inference
  - CONTRACT-hermes-config-surface
created: 2026-09-06
---

# ADR-005: Speech-to-text via a `command` provider, not `stt.provider: openai`

## Context

Discord voice messages arrived and were never transcribed. Root cause, confirmed in the
gateway log: `stt.provider` defaulted to `local`, which requires either `faster-whisper`
installed or a `HERMES_LOCAL_STT_COMMAND` — neither existed on this host.
`STT provider 'local' configured but unavailable`.

This was a **setting, not a missing skill**.

Since inference already runs on Scaleway via an OpenAI-compatible endpoint
([ADR-003](ADR-003-scaleway-eu-inference.md)), pointing STT at the same endpoint looks like
the same trick applied twice. It is not.

## Decision

Configure a **`stt.providers.<name>` entry of `type: command`**, invoking Scaleway's
transcription endpoint via `curl` and reading the transcript from stdout through `jq`.

A command provider has **no model-name whitelist** — Hermes simply runs the shell command —
which is precisely the property the built-in OpenAI path lacks.

Exact keys and the quoting rules: see
[CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md).

## Alternatives Considered

**`stt.provider: openai` pointed at Scaleway.** Tried first; fails **silently in a way worth
recording**, because it is the obvious move:

1. `stt.openai.model: whisper-large-v3` is validated against Hermes' hardcoded list of
   *known OpenAI* model names. `whisper-large-v3` is not on that list, so Hermes logs
   `Model whisper-large-v3 not available on OpenAI, using whisper-1` and **substitutes it**.
   The configured model name is discarded, not passed through.
2. Scaleway then correctly rejects `whisper-1`, which it does not have:
   `HTTP 422 MODEL NOT FOUND`.
3. The `STT_OPENAI_BASE_URL` redirect itself **worked** — confirmed by the error arriving as
   a clean Scaleway-shaped 422 rather than a connection failure. Only the model-name
   substitution broke it.

**`stt.provider: local` with `faster-whisper`.** Rejected on memory. The local model is
cached for the life of each gateway process, so four gateways would hold four model
instances on a 2 GB host whose services are capped at 320 MB each. Additionally, the
proposed `stt.local.vad` and `stt.local.unload_after_idle_seconds` settings **are not
implemented by the pinned Hermes version** — only `model` and `language` are consumed from
`stt.local`.

**`HERMES_LOCAL_STT_COMMAND`.** Superseded. `stt.providers.<name>.type: command` is the
newer, documented-as-recommended mechanism.

**The `voice.*` block.** Valid configuration, but irrelevant here: it controls microphone
recording in an interactive Hermes CLI/TUI on a machine that has a microphone. This is a
headless VPS handling *inbound* voice messages.

## Consequences

- STT stays on Scaleway, so voice data does not leave the EU and no model weights sit on the
  VPS.
- **The schema was found by grepping the installed package's own source and bundled docs**,
  not from the hosted documentation site or web search, which did not reliably surface it.
  Future STT changes should assume the same: read the pinned tree.
- Hermes' API server **does not proxy** an OpenAI-compatible `/v1/audio/transcriptions`
  route. Messaging audio is transcribed inside the gateway; an API client needing a
  standalone transcription endpoint must call Scaleway directly.
- Two behaviours of this setup are traps rather than decisions — Scaleway ignoring
  `response_format=text`, and `$OPENAI_BASE_URL` expansion timing. Both are recorded in
  [CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md).
