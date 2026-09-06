---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records the provider commitment. Live behaviour is tracked in STATE.md.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - CONTRACT-hermes-config-surface
  - ADR-006-public-api-exposure
created: 2026-09-06
---

# ADR-003: Scaleway Generative APIs as the sole inference provider

## Context

Four agents serving a family, two of them children, need inference that is cheap, always-on,
and does not export family conversations outside the EU. Scaleway offers an EU-hosted,
OpenAI-compatible Generative APIs endpoint, and the VPS already lives in Scaleway
`fr-par-1` — so inference traffic stays inside one provider and one jurisdiction.

Measured upstream latency: **57 ms**.

## Decision

Route all inference — chat and auxiliary tasks — to Scaleway Generative APIs, configured
through Hermes' **`openai-api`** provider, with each member holding their own API key.

Auxiliary models (vision, web summarisation) are left at `provider: auto`, which routes them
to the main chat model and therefore keeps them on Scaleway too.

Exact keys, variable names and values: see
[CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md).

## Alternatives Considered

**`model.provider: custom`.** Rejected — this is the intuitive choice for "an
OpenAI-compatible endpoint that isn't OpenAI", and it is wrong. The working value is
`openai-api`. Recorded because the wrong one is the one you would reach for first.

**Leaving auxiliary models at their own defaults.** Rejected: auxiliary tasks configured
independently could route vision and web-summarisation calls to a non-EU provider, quietly
undoing the residency property that motivated the whole decision. `provider: auto` inherits
the main model and keeps them in the EU.

**A non-EU provider with better price/performance.** Not pursued. EU residency is a
constraint here, not a preference — this is family conversation data, including two
children's.

## Consequences

- **Per-member billing attribution does not currently work.** Each member has their own
  Scaleway project and a scoped key, yet all consumption records against the organisation's
  default project. Unresolved — see OQ-1 in [STATE.md](../STATE.md).
- **Scaleway has no spend caps.** Its billing API exposes no budget endpoint, so there is no
  provider-side hard limit per key. Any enforcement must be built host-side. See OQ-2.
- **API keys expire, hard-capped at 365 days.** Scaleway rejects longer requests regardless
  of organisation settings, so annual rotation is mandatory. See
  [RUNBOOK-rotate-inference-keys](../runbook/RUNBOOK-rotate-inference-keys.md).
- Model-specific limits become deployment constraints — notably the explicit output-token
  cap required by the chosen model, documented in
  [CONTRACT-api-server-endpoints](../contract/CONTRACT-api-server-endpoints.md).
- Speech-to-text also stays on Scaleway, but could not use the same provider mechanism. See
  [ADR-005](ADR-005-command-stt-provider.md).
