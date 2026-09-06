---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a decision and its rationale. The measurements cited were run on 2026-09-06 —
  Scaleway reasoning-token comparison against the live endpoint, and source inspection of
  the installed tree — but this document asserts no standing host behaviour.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents:
  - ADR-003-scaleway-eu-inference
  - ADR-006-public-api-exposure
  - CONTRACT-api-server-endpoints
  - EPHEMERAL-hermes-pin-upgrade-2026-09-06
created: 2026-09-06
---

# ADR-009: Retire the model-tier reasoning patch and expose a single model alias

## Context

The API server exposed three aliases — `quick`, `default`, `smart` — backed by one model
(`qwen3.5-397b-a17b`) and differing only in `reasoning_effort` (`none` / `medium` / `high`).
Upstream `model_routes` accepts only `{model, provider, api_key, base_url}`, so this required
a local patch to `gateway/platforms/api_server.py`, carried as **uncommitted working-tree
state** on the host.

Three findings on 2026-09-06 made that arrangement untenable.

**The patch no longer applies.** Against the current stable release the file has grown
5729 → 7937 lines and the anchors moved; `git apply --check` fails. Every future upgrade
re-incurs this cost, and the upstream installer's update path would stash the patch, fail to
re-apply it, and `git reset --hard` — leaving the tiers silently collapsed while still
returning `200`s.

**No configuration-only replacement exists.** Investigated and rejected below.

**The patch was doing more work than it appeared to.** `run_agent.py` gates the reasoning
field behind `_supports_reasoning_extra_body()`, whose final clause is
`if "openrouter" not in base_url: return False`. `api.scaleway.ai` is not OpenRouter, so
Hermes' ordinary configuration path **never sends a reasoning field to Scaleway at all**. The
patch's `request_overrides` was the only mechanism placing `reasoning_effort` on a Scaleway
request. Any global reasoning setting is therefore inert for this deployment.

Two constraints shaped the choice. **There is no usage telemetry** — `log_level` is unset,
the route-application log line is `logger.debug`, and Caddy has no access log, so whether the
family ever switched tiers is unknown and unknowable from existing evidence. And **there are
no spend caps** (OQ-2) with no per-member attribution (OQ-1), so reasoning spend is
unbounded and unattributable.

A measurement against the live endpoint (single prompt; indicative, not a benchmark):

| `reasoning_effort` | completion tokens |
|---|---|
| omitted | 499 |
| `none` | 5 |
| `high` | 597 |

Scaleway reasons substantially by default — omitting the field yields roughly 84% of
`high`'s output-token spend.

## Decision

**Retire the patch, expose one public model alias, and accept Scaleway's default reasoning
effort.**

The deployment carries no local modification to Hermes source. The API server advertises a
single alias rather than three, and no `reasoning_effort` is configured anywhere.

This is implementable immediately on the current pin; it does **not** depend on the upgrade,
which remains blocked for unrelated reasons
([EPHEMERAL-hermes-pin-upgrade-2026-09-06](../ephemeral/EPHEMERAL-hermes-pin-upgrade-2026-09-06.md)).
Retiring the patch removes one of that upgrade's obstacles.

The operator selected `high` when choosing a single level. **`high` is not reachable without
the patch** — see Context — so accepting the provider default is the faithful reading of the
intent behind that choice: maximise answer quality without retaining custom source.

## Alternatives Considered

**Rebase the patch against the new release.** Rejected. It would be smaller than the original
70 lines, because upstream now ships a `_REASONING_EFFORTS` frozenset identical to the
patch's hand-rolled allow-list. But it reinstates exactly the recurring cost this decision
exists to eliminate, and it has already broken once. Worth revisiting only as an upstream
contribution, where the maintenance burden moves off this deployment.

**Configure the tiers via `custom_providers` + `extra_body`.** Rejected after investigation —
and recorded in detail because it **looks correct and fails silently**, the failure class this
deployment is most prone to. Three independent defects, any one fatal:

1. `gateway/platforms/api_server.py` at the target release contains **zero** occurrences of
   `request_overrides` and **zero** of `extra_body` across 7937 lines. The API-server route
   path cannot carry either.
2. The extra-body matcher returns `None` unless the provider is literally `custom` or
   `custom:*`. This deployment uses `openai-api`.
3. Named entries resolve to bare `provider: "custom"`, so matching falls back to base_url
   plus model. All three tiers **deliberately** share one base_url and one model, so all
   three would match the first entry — every alias silently serving one configuration while
   still returning `200`.

**Keep three aliases mapped to identical configuration.** Rejected. Nothing would break for
any client, but `smart` would do nothing beyond `quick` while continuing to advertise that it
does. This deployment's characteristic failure is a wrong thing accepted without error; three
names for one behaviour institutionalises exactly that.

**Differentiate the tiers by model rather than by reasoning effort.** Not adopted, though it
is technically sound and patch-free: `model_routes.<alias>.model` is an upstream field, and
Scaleway offers smaller models (`qwen3.6-35b-a3b`, `mistral-small-3.2-24b-instruct-2506`,
`deepseek-v4-flash-0731`, among others). It was declined in favour of the simplest possible
surface. **It remains the obvious first move if a cost lever is later needed** — see
Consequences.

**Retain a minimal patch solely to force `high`.** Rejected. It would preserve custom source
in order to buy roughly a 20% increase in reasoning tokens over the provider default, while
reintroducing the full upgrade-friction cost.

## Consequences

**Every family member must reconfigure their client.** `quick` and `smart` cease to exist as
selectable models. This affects four people across an unknown number of devices, two of them
children. This is the principal cost of the decision and it is one-time.

**A real cost lever is lost.** The measurement shows `none` produced 5 completion tokens
against 499 for the default — roughly two orders of magnitude on a simple question. Any
member who used `quick` for routine questions will now spend meaningfully more. With no spend
caps and no per-member attribution, that increase is neither bounded nor visible. **If spend
becomes a concern, reintroduce tiers by model, not by reasoning effort** — that path needs no
patch.

**Effective reasoning behaviour becomes an upstream/provider detail.** Scaleway may change
the default for `qwen3.5-397b-a17b` without notice, and nothing in this deployment would
record or resist it. This is accepted deliberately: the alternative is custom source.

**The install tree becomes clean.** `/usr/local/lib/hermes-agent` stops being a modified git
working copy, so `hermes update` and the installer's update path no longer stash, conflict
and reset. One of the four upgrade blockers is removed.

**[CONTRACT-api-server-endpoints](../contract/CONTRACT-api-server-endpoints.md) must change:**
its `pinned_to` no longer references the patch; the Model Tier Aliases table and the
`model_routes.<alias>.reasoning_effort` row are removed; and its `verified_on` reverts to
`null` until the new surface is confirmed on the host. The alias-name stability promise now
covers a single name.

**No SPEC is required.** Nothing here is a property that must not regress — it is a
configuration choice, and STATE.md carries the live status.

**`deploy/03-configure-profiles.sh` becomes the sole definition** of the public model
surface; `ALIAS_MODEL` / `EFFORT_QUICK` / `EFFORT_DEFAULT` / `EFFORT_SMART` are superseded.
[`deploy/hermes-api-model-route-reasoning.patch`](../../deploy/hermes-api-model-route-reasoning.patch)
is retained as historical record only, and must not be reapplied.
