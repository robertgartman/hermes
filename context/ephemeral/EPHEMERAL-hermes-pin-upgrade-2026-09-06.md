---
doc_type: ephemeral
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  Point-in-time analysis. Host observations were taken live on 2026-09-06; upstream findings
  were read from source at the target commit but NOT executed, and are labelled per finding.
must_not_contain:
  - secrets
authoritative: false
retrieval_priority: low
related_documents:
  - CONTRACT-api-server-endpoints
  - CONTRACT-hermes-config-surface
  - ADR-003-scaleway-eu-inference
  - ADR-005-command-stt-provider
  - PRD-jupyter-tutor
created: 2026-09-06
---

> **Never authoritative.** This document governs nothing. Every accepted finding must
> graduate into a SPEC, ADR, CONTRACT, RUNBOOK or STATE entry.

# Hermes pin upgrade to v2026.8.31 — 2026-09-06

## Scope

Assessed whether the deployment can move from its pinned Hermes commit `f13f8451` to the
latest stable release, tag **`v2026.8.31`** (commit `29112bef`, published 2026-08-31), and
whether the local reasoning-effort patch could be retired in favour of upstream
configuration.

Three evidence sources, and the distinction matters for how much each finding is worth:

- **Live host** (`hermes-family`, 2026-09-06) — read-only observation over SSH.
- **Upstream source at both commits** — files fetched and read directly. **Not executed.**
- **This repository** — `deploy/` scripts and `context/` documents.

**Outcome: NO-GO.** Four blockers, detailed below. The upgrade remains desirable — the pin is
**9750 commits behind** on a shell-capable, publicly reachable host — but it cannot be run as
scoped.

## Findings

### F-1 — Current inference works because of an upstream bug that the target commit fixes

**Finding:** On upgrade, all four members' agents would very likely stop reaching Scaleway
entirely — not degraded, but total inference failure.

`hermes_cli/providers.py:68` declares the `openai-api` provider with
`transport="codex_responses"`. At the current pin nothing consults that declaration: api_mode
comes from URL detection alone, `api.scaleway.ai` is not a recognised host, so resolution
falls to `chat_completions` — which is what this deployment needs and silently gets.

The target commit adds `_fallback_api_mode()` (`hermes_cli/runtime_provider.py:187`, wired at
`:614`, `:1863`, `:2526`), **absent from the installed tree**. It consults the overlay
whenever URL detection has no opinion. `_detect_api_mode_for_url()` returns `None` for
`api.scaleway.ai`; `determine_api_mode()` then resolves the declared transport to
`codex_responses`. Requests would go to `/v1/responses`, which Scaleway does not serve.

Upstream's own docstring names this configuration as the defect being repaired:

> *"Before this helper the runtime paths consulted URL detection ONLY and silently landed
> reasoning providers on `chat_completions` whenever the hostname wasn't literally
> recognized."*

**This is a standing fragility, not merely an upgrade problem.** The deployment depends on a
bug that upstream has already closed; some future upgrade will surface it regardless.

**Candidate mitigation (untested):** set `model.api_mode: chat_completions` on all four
profiles *before* any gateway starts on new code. `_provider_supports_explicit_api_mode()`
should honour it because `model.provider` matches the runtime provider.

**Evidence:** `hermes_cli/providers.py:68-72`, `hermes_cli/runtime_provider.py:187-208`,
`_detect_api_mode_for_url` returning `None`, `determine_api_mode` resolution order (step 3,
transport map). Absence of `_fallback_api_mode` in `/usr/local/lib/hermes-agent` confirmed on
host.
**Confidence:** inferred from source — high, but **the failure was not reproduced and the
mitigation was not tested**.

### F-2 — Route-level `reasoning_effort` has no upstream mechanism; the config-only replacement does not work

**Finding:** The `quick`/`default`/`smart` tiers cannot be expressed in configuration alone at
the target commit. A proposed replacement using `custom_providers` + `extra_body` was
**investigated and rejected**.

Upstream `_parse_model_routes` still has
`allowed_keys = ("model", "provider", "api_key", "base_url")` — no `reasoning_effort`. The
`custom_providers` route fails on three independent grounds:

1. `gateway/platforms/api_server.py` at the target commit contains **zero** occurrences of
   `request_overrides` and **zero** of `extra_body` across 7937 lines — the API-server route
   path cannot carry either.
2. `_custom_provider_extra_body_for_agent` returns `None` unless the provider is `custom` or
   `custom:*`. This deployment uses `openai-api`.
3. Named entries resolve to bare `provider: "custom"`, so matching falls back to base_url +
   model. All three tiers **deliberately** share one base_url and one model, so all three
   would match the first entry — failing **silently**, the failure class this deployment is
   most prone to.

**Evidence:** `gateway/platforms/api_server.py` (0/0 grep counts, 7937 lines), `allowed_keys`
at `:2460`, `agent/agent_init.py` extra-body matcher, `hermes_cli/runtime_provider.py:1327`.
**Confidence:** inferred from source — high.

### F-3 — Tavily extraction is deleted upstream

**Finding:** `web.extract_backend: tavily` has no implementation at the target commit.
`tools/web_tools.py` contains **0** occurrences of `tavily` (the installed file has **26**),
and `_LEGACY_WEB_BACKENDS` is
`{parallel, firecrawl, exa, searxng, brave-free, ddgs, xai, keenable}`. SearXNG **search** is
unaffected; page **extraction** breaks.

**Evidence:** `tools/web_tools.py:163-165` at the target commit; grep counts at both commits.
**Confidence:** inferred from source — high.

### F-4 — Command-STT loses its credentials to an environment scrub

**Finding:** Voice transcription would return empty transcripts, with no error.
`tools/transcription_tools.py:727` (and `:2131`) now spawn the command child via
`hermes_subprocess_env(inherit_credentials=False)` — a call **absent** from the installed
file. The helper strips provider credentials by default via
`_HERMES_PROVIDER_ENV_BLOCKLIST`, which covers the `OPENAI_BASE_URL` / `OPENAI_API_KEY`
variables the transcription command interpolates at runtime.

This affects a child's voice messages (Discord, Mattis) — see
[ADR-005](../adr/ADR-005-command-stt-provider.md).

**Evidence:** `tools/transcription_tools.py:725-727`, `tools/environments/local.py:834+`,
blocklist construction at `:447`. Installed file has no such call.
**Confidence:** inferred from source — high. **The exact blocklist membership was not
enumerated**, and no transcription was attempted on new code.

### F-5 — The deployment patch exists only as uncommitted working-tree state on the host

**Finding:** `/usr/local/lib/hermes-agent` is a git working copy carrying uncommitted
modifications to `gateway/platforms/api_server.py` and `tests/gateway/test_api_server.py`
(+70/−5) — that dirty state *is* the live patch.

The upstream installer's update path stashes a dirty tree
(`git stash push --include-untracked`), updates, then attempts `git stash apply`; on conflict
it warns and may `git reset --hard HEAD`, leaving the work only in a stash. Given the file
grew 5729 → 7937 lines, that re-apply would conflict.

**Reassuring corollary, confirmed:** the live diff is **byte-identical** (6854 bytes) to
[`deploy/hermes-api-model-route-reasoning.patch`](../../deploy/hermes-api-model-route-reasoning.patch),
so nothing exists solely on the host and deliberately cleaning the tree loses nothing.

**Evidence:** `git status --porcelain` and `git diff` on host; byte-for-byte comparison
against the committed patch, ignoring `index` lines.
**Confidence:** **confirmed on host.**

### F-6 — The existing patch no longer applies, but a rebase is materially smaller

**Finding:** `git apply --check` of the committed patch against the target file fails:
`error: patch failed: gateway/platforms/api_server.py:1847`. The anchors moved (model_routes
parsing ~1775 → ~2460).

However, every dependency survives: `request_overrides` remains an accepted kwarg
(`run_agent.py:499`, `:592`), `parse_reasoning_effort` still exists
(`hermes_constants.py:1312`), and upstream now ships a `_REASONING_EFFORTS` frozenset whose
values are identical to the patch's hand-rolled allow-list. A rebased patch is therefore
**substantially smaller** than the current 70 lines, since much of the original merely
reimplemented what upstream now provides.

**Non-obvious trap for any rebase:** with `provider: openai-api` there is no registered
provider profile, so `reasoning_config` alone emits nothing on the wire.
`request_overrides["reasoning_effort"]` is what actually places the field on a Scaleway
request. Both halves are required; dropping either yields three tiers, three `200`s and one
behaviour.

**Evidence:** `git apply --check` executed on host against the fetched target file; symbol
lookups at the target commit.
**Confidence:** **patch-does-not-apply confirmed on host**; the rebase sketch is **inferred
and unwritten**.

### F-7 — The Jupyter skill is already seeded to all four members, including both children, and its prerequisites are unmet

**Finding:** `skills/data-science/jupyter-live-kernel/` is a **bundled** skill at the current
pin and is present in all four member homes — Mattis and Love included. Seeded skills are
**copies, not symlinks**, so an upgrade would not remove them even though the skill moves to
`optional-skills/data-science/jupyter-notebook/` upstream (bundled `SKILL.md` count drops
78 → 60).

It cannot currently function, and two of the reasons are security-relevant:

- **`uv` is not on the member PATH** (root-owned at `/root/.hermes/bin/uv`), so the skill
  fails at its first prerequisite.
- Its documented launch uses **port 8888**, which SearXNG already holds on loopback.
- Its documented launch **disables authentication entirely** (empty identity token and
  password; the target commit additionally suggests disabling XSRF checks). Because the
  isolation boundary here is the OS user and mount namespace — **not** the network namespace —
  loopback is shared across all four members. An unauthenticated kernel on loopback would be
  reachable by every member's gateway, letting one member execute code inside another's
  kernel. That would defeat the property
  [SPEC-profile-isolation](../spec/SPEC-profile-isolation.md) exists to protect.

Nothing has been built; see [PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md).

**Evidence:** per-member `find … -name SKILL.md` counts (78 seeded; Robert 79) and content
comparison against the bundled copy on host; `ss -lntp` showing `searxng` on
`127.0.0.1:8888`; `sudo -u robert … command -v uv` finding nothing; SKILL.md text at both
commits.
**Confidence:** **confirmed on host**, except the cross-member kernel reachability, which is
**reasoned from the unit configuration and not demonstrated**.

### F-8 — Configuration keys that DO survive the jump

**Finding:** Checked against the target commit, these remain present and consumed:
`web.search_backend` / `web.extract_backend` key names (`agent/web_search_provider.py`),
`API_SERVER_CORS_ORIGINS` (`gateway/platforms/api_server.py`), the STT command-provider
schema (`gateway/run.py:3227` reads `command`), and `model.max_tokens`
(`gateway/run.py:3191-3203`, global still winning over per-provider `max_output_tokens`).

Note this is about **key names**, not behaviour: `extract_backend` survives as a key while
its `tavily` **value** does not (F-3).

**Confidence:** inferred from source — high.

### F-9 — Host baseline, 2026-09-06

Measured live; supersedes the 2026-08-08 figures for these fields only.

| | |
|---|---|
| Hermes | v0.19.0 (2026.7.20), commit `f13f8451`, install method `git` |
| Python | 3.11.15 |
| Uptime | 45 days, load 0.01 |
| Memory | 1968 MB total · ~783 MB available · swap 2047 MB, ~34 MB used |
| Per-gateway | ~185 MB each (~655 MB reclaimable across four) |
| SearXNG | `MemoryCurrent` ~14 MB (well under the 2026-08-08 warmed figure) |
| Disk | 8.4 GB used of 19 GB · 9.0 GB available |
| Install tree | 2.2 GB |
| Loopback listeners | 8642/8643/8644/8645 API servers · 8888 SearXNG |

**Upgrade headroom arithmetic:** ~783 MB available, plus ~655 MB from stopping four
gateways, gives ~1.44 GB against a documented **1.6 GB install peak** — short, and reliant on
swap. Not a blocker on its own, but not comfortable.

**Confidence:** **confirmed on host.**

## Graduation

| Finding | Disposition | Destination |
|---|---|---|
| F-1 | accepted | New ADR (next free number is **009**) on the wire-protocol pin; open question in [STATE.md](../STATE.md) |
| F-2 | accepted | Same ADR — records `custom_providers` as a **rejected** alternative so it is not retried |
| F-3 | accepted | [CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md) trap + STATE open question |
| F-4 | accepted | [CONTRACT-hermes-config-surface](../contract/CONTRACT-hermes-config-surface.md) trap; affects [ADR-005](../adr/ADR-005-command-stt-provider.md) |
| F-5 | accepted | [CONTRACT-host-layout](../contract/CONTRACT-host-layout.md) — the install tree is deliberately dirty; STATE note |
| F-6 | deferred | Blocked on the tier-mechanism decision; revisit with the ADR |
| F-7 | accepted | STATE rows; the isolation concern is a candidate requirement for [SPEC-profile-isolation](../spec/SPEC-profile-isolation.md) |
| F-8 | accepted | Confirms existing CONTRACT entries; no change beyond F-3's value correction |
| F-9 | accepted | [STATE.md](../STATE.md) measured footprint |

**Nothing here is authoritative until it graduates.** The ADR and CONTRACT edits are not yet
written.

## Open Questions

- **The tier mechanism is undecided.** Rebase the patch (F-6), accept a single reasoning
  level, or pursue an upstream contribution. This must be settled **before** the pin moves.
- **F-1's mitigation is untested.** `model.api_mode: chat_completions` is a candidate, not a
  verified fix. It should be proven from the outgoing request body, not from a `200`.
- **No breaking-change review of the 9750-commit range was completed.** Release notes were
  not enumerated; the four blockers were found by targeted inspection, so **there may be
  more**. Absence of further findings here is not evidence of their absence.
- **Config-schema migration on first start is unexamined.** Upstream source references a
  `v11 → v12` migration writing `api_mode` under a new `transport` field. Whether an upgraded
  gateway rewrites each member's `config.yaml` — and whether that could clobber hand-set keys
  across four live profiles — was **not** determined.
