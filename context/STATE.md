---
doc_type: state
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  2026-09-06 — host observation plus three executed changes: ADR-009 implemented (patch
  reverted, tree verified stock, single alias confirmed by a live completion), instance
  resized DEV1-S to DEV1-M (services self-recovered, reserved IP retained), and the tutor
  Jupyter pod built and its isolation checks executed. Capability rows retain their OWN
  dates: this pass did NOT re-test STT, web search, Discord, or profile isolation.
  2026-08-08 — SearXNG listener scope, per-member web_search_tool and Tavily extraction,
  model-tier reasoning configs read back from recorded API sessions, and config read-back
  for all four profiles.
must_not_contain:
  - secrets
  - functional_requirements
  - decision_rationale
  - deployment_procedures
authoritative: true
stability: volatile
decision_scope: deployment_state
audience: [ai, operator]
retrieval_priority: high
applies_to: hermes-vps fr-par-1
related_documents:
  - PRD-family-agent-platform
  - CONTRACT-api-server-endpoints
  - CONTRACT-hermes-config-surface
  - CONTRACT-messaging-channels
  - SPEC-profile-isolation
  - SPEC-agent-access-control
  - SPEC-tutor-isolation
  - ADR-009-retire-model-tier-reasoning-patch
  - EPHEMERAL-hermes-pin-upgrade-2026-09-06
created: 2026-09-06
---

# Live Deployment State

**What is actually true on the host right now**, and when each claim was last confirmed.

> **This document is authoritative for *what is*, never for *what should be*.** A capability
> specified elsewhere but absent here is not a contradiction — it is unbuilt work.
>
> **Every claim carries a date.** An undated claim about a live machine decays into folklore
> within weeks. If you cannot date it, mark it `NOT VERIFIED` rather than assert it.

---

## Host

| | |
|---|---|
| Provider / zone | Scaleway, `fr-par-1` |
| Instance type | **DEV1-M** — 3 vCPU / 4 GB RAM / 20 GB local NVMe — *resized 2026-09-06* |
| Cost | €14.74/mo + IPv4 (was €6.55 on DEV1-S) |
| OS | Debian 13 (trixie) |
| Members | robert, sofia, mattis, love |
| Hermes version | **v0.19.0 (2026.7.20)**, pin `f13f8451`, install method `git` — *2026-09-06* |
| Python | 3.11.15 (uv-created venv, no `pip`) — *2026-09-06* |

**The install tree is now stock.** It was a git working copy carrying the model-tier patch as
uncommitted modifications; [ADR-009](adr/ADR-009-retire-model-tier-reasoning-patch.md) was
implemented on 2026-09-06 and those files were reverted. `git status --porcelain` reports no
modified files and `gateway/platforms/api_server.py` contains zero `reasoning_effort`
occurrences. The patch survives only as
[`deploy/hermes-api-model-route-reasoning.patch`](../deploy/hermes-api-model-route-reasoning.patch)
— historical record, **not to be reapplied**. `hermes update` no longer has local
modifications to stash, conflict over, and reset.

**Resized 2026-09-06** to host the tutor sandbox
([ADR-011](adr/ADR-011-tutor-sandbox-isolation.md) lists resize as a compatible placement).
Stop → `commercial-type=DEV1-M` → start; the public IP survived because it is a **reserved**
`routed_ipv4` (`dynamic=False`), not a dynamic one. All services returned on their own.
Available memory went ~877 MB → ~2922 MB. Note the literal 2 vCPU / 4 GB options
(`PLAY2-NANO`, €20.10) cost *more* than DEV1-M for less CPU.

---

## Measured Footprint

All four gateways plus SearXNG running, idle.

| | 2026-09-06 **after resize** | 2026-09-06 pre-resize | 2026-08-08 |
|---|---|---|---|
| Instance | DEV1-M, 3 vCPU | DEV1-S, 2 vCPU | DEV1-S |
| Per-gateway RSS | ~185 MB each | ~185 MB each (~655 MB across four) | 133–191 MB |
| SearXNG | ~132 MB (podman stats) | `MemoryCurrent` ~14 MB | ~140 MB warmed |
| Tutor Jupyter pod | **~79 MB** (cap 1 GB) | n/a | n/a |
| Total used | **1173 MB / 3916 MB** | 1171 MB / 1968 MB | 1.1 GB / 1968 MB |
| Available | **~2742 MB** | ~783 MB | ~860 MB |
| Swap used | **0** of 2047 MB | ~34 MB of 2047 MB | 0 |
| Disk | **~13.8 GB / 19 GB** (5.2 GB free) | 8.4 GB / 19 GB (9.0 free) | ~8 GB / 19 GB |
| Install tree | 2.2 GB | 2.2 GB | 2.2 GB |

The disk drop is the **3.87 GB** digest-pinned `scipy-notebook` image. The two SearXNG figures
measure different things (`podman stats` RSS vs systemd `MemoryCurrent`); neither indicates the
service changed.

**Loopback listeners** (2026-09-06): `8642`/`8643`/`8644`/`8645` per-member API servers ·
`8888` SearXNG. Caddy holds the only public listeners (`80`, `443`); `sshd` on `22`.

**Per-member skills** (2026-09-06): 78 bundled `SKILL.md` in the install tree, 78 seeded per
member (Robert 79 — one self-made). Seeded skills are **copies, not symlinks**, so they do
not track the install tree.

**Two caveats on these numbers.** They are **idle, with no messaging platforms connected** —
see open question OQ-3. And the *install itself* peaks at **1.6 GB**, which is the tightest
moment on the box; capacity planning should use that figure, not the steady state.

**Upgrade headroom — resolved by the resize.** On DEV1-S this was ~1.44 GB against a 1.6 GB
install peak, i.e. dependent on swap. On DEV1-M it is **~2742 MB available against the same
1.6 GB peak**, with the tutor pod already running. Memory is no longer the binding constraint
on a reinstall. See OQ-7.

---

## Capability Status

| Capability | Status | Verified | Notes |
|---|---|---|---|
| Four gateways, boot-enabled | **Live** | 2026-08-08 | One systemd instance per member |
| Profile isolation (OS user + mount namespace) | **Live** | 2026-08-08 | See [SPEC-profile-isolation](spec/SPEC-profile-isolation.md) |
| Scaleway EU inference | **Live** | 2026-08-08 | 57 ms measured upstream latency |
| Firewall, both layers default-drop | **Live** | 2026-07-26 | Host nftables + Scaleway security group; `22`/`443` only |
| Discord — Mattis | **Live** | 2026-07-22 | DM → gateway → allowlist → inference → reply |
| Discord — other members | **Not configured** | — | |
| Slack / Telegram / WhatsApp | **Not configured** | — | Deps preinstalled; no tokens set |
| Voice transcription (STT) | **Live — messaging path only** | 2026-08-08 | Scaleway command provider; reverified after the Qwen tier update. Per [ADR-005](adr/ADR-005-command-stt-provider.md) the API server proxies no transcription route, so the web/API surface has no voice input |
| Web search (SearXNG) | **Live** | 2026-08-08 | All four profiles, three real results each |
| Page extraction (Tavily) | **Live** | 2026-08-08 | See trap in [CONTRACT-hermes-config-surface](contract/CONTRACT-hermes-config-surface.md) |
| API server + Caddy + real certs | **Live** | 2026-08-08 | Four FQDNs, production Let's Encrypt |
| Model alias (single `default`) | **Live** | 2026-09-06 | [ADR-009](adr/ADR-009-retire-model-tier-reasoning-patch.md) implemented. `/v1/models` returns `hermes-agent` and `default` only; `quick`/`smart` retired. Live completion through `default` returned `200`. No reasoning effort configured — Scaleway's default applies |
| Hermes web UI — Robert only | **Live** | 2026-09-06 | Built on host (`web_dist`); `hermes-dashboard@robert` on 9121; `https://5.agent-hermes.dynv6.net` behind basic auth + an nftables uid rule. Admin surface — see [ADR-014](adr/ADR-014-web-ui-is-admin-only.md) |
| `python`/`python3` venv wrappers | **Live** | 2026-07-27 | Fixes google-workspace skill reliability |
| Image understanding (vision input) | **Unknown — never tested** | — | No image has been sent to any member's agent on any channel. Unmeasured, **not** known-absent — see OQ-6 |
| Browser automation | **No backend** | — | |
| Image generation | **No backend** | — | |
| TTS | **No backend** | — | |
| Per-member spend tracking | **Unresolved** | — | See OQ-1 |
| Child-safety controls | **Not configured** | — | See OQ-4 — **the most significant open gap** |
| Jupyter live-kernel skill (on family gateways) | **Seeded, inert, and must stay so** | 2026-09-06 | Present in all four homes incl. both children; prerequisites unmet. [ADR-011](adr/ADR-011-tutor-sandbox-isolation.md) **rejects** enabling it here — see OQ-8 |
| Tutor sandbox — kernel half | **Running, incomplete** | 2026-09-06 | Podman pod `tutor`: digest-pinned JupyterLab + the ADR-012 stack, token-authenticated, bound to pod loopback, unreachable from host and from every family gateway. **No orchestrator, so not usable** — see OQ-10 |
| Tutor sandbox — orchestrator | **Not built** | — | Blocked on pod egress (firewall change) and a model credential — see OQ-10 |

---

## Endpoints

One FQDN per member, fronted by Caddy. Exact values, ports and token locations:
[CONTRACT-api-server-endpoints](contract/CONTRACT-api-server-endpoints.md).

Verified 2026-07-26: all four endpoints return `200` with real production Let's Encrypt
certs. Re-verified 2026-08-08 for model-tier behaviour.

---

## Requirement Status

| ID | Requirement | Status |
|---|---|---|
| R1 | Run Hermes on a cheap Scaleway VPS | **Done** — DEV1-S, €6.55/mo, verified |
| R2 | Run 4 profiles continuously | **Done** — 4 systemd units, boot-enabled |
| R3 | Keep family profiles separate | **Done** — OS-user + mount-namespace isolation, verified |
| R4 | Internet-safe security baseline | **Done** — SSH key-only, no sudo, hardened units, unattended upgrades, both firewall layers default-drop inbound with explicit `22`/`443` allows, each verified from a fresh connection before trusting the change |
| R5 | Clarify DNS need | **Done** — not needed unless using the WhatsApp Cloud API |
| R6 | Track inference spend per profile | **Open** — see OQ-1 |
| R7 | Enforce cost control per profile | **Blocked** — see OQ-2 |
| R8 | Mixed messaging channels per member | **Partly** — Discord live for Mattis only |

---

## Open Questions

### OQ-1 — Per-member billing attribution is unresolved (R6)

Each member has their own Scaleway project and a key whose `default_project_id` points at
it. Despite that, **all** Generative APIs consumption is recorded against the organisation's
default project, with zero against the four `hermes-*` projects — even after deliberately
asymmetric per-key load.

Billing may settle daily. **Re-check after 24h:**

```bash
scw billing consumption list -o json | jq -r '.[]|select(.category_name=="AI")|"\(.product_name) \(.project_id)"'
```

If it does not resolve, per-member attribution is not achievable on Scaleway, and R6 needs
either a different provider or client-side token accounting.

### OQ-2 — Scaleway has no spend caps (R7)

The billing API exposes only `consumption`, `discount` and `invoice` — no budget API. There
is no provider-side equivalent of a per-key hard limit, and no way to automatically disable
only the over-budget key. Enforcement would have to be a host timer polling consumption and
stopping a gateway past a threshold. **Not built.**

### OQ-3 — Real-load memory is unmeasured

Every figure above is idle with no channels connected. `MemoryMax=320M` per member is
comfortable now but untested against live Slack/Discord/WhatsApp clients and concurrent
conversations.

### OQ-4 — Child-safety controls not configured

**The most significant open gap.** Mattis and Love get agents that can execute shell
commands. Approval mode, tool restrictions and skill pruning have not been set. 78 bundled
skills are seeded per member by default, most irrelevant for a family.

### OQ-5 — Key rotation

Scaleway enforces API key expiry, hard-capped at **365 days** — a 3-year request is rejected
regardless of the org setting. Keys expire and must be rotated annually. **No automation
exists**; see [RUNBOOK-rotate-inference-keys](runbook/RUNBOOK-rotate-inference-keys.md).

### OQ-6 — Multimodal backends: three absent, one merely untested

Browser automation, image generation and TTS have no backend. Web search, extraction and STT
are configured and live.

**Image understanding does not belong in that list.** Nothing has ever sent an image to any
member's agent, so there is no evidence in either direction — unmeasured, not known-absent.
Two questions are open, and the second is the larger one:

1. **Does an image reach the model at all?** Untested end to end, on every channel.
2. **Does Hermes hand per-modality work to separate handlers out of the box?** Readable from
   the pinned tree at `/usr/local/lib/hermes-agent`; not yet read. It decides whether R9–R11
   in [PRD-family-agent-platform](prd/PRD-family-agent-platform.md) are a configuration
   exercise or new work.

Neither question needs a host change to answer — one is a message, the other is a `grep`.

### OQ-7 — The pin is 9750 commits behind and the upgrade is blocked

Assessed 2026-09-06 against latest stable **`v2026.8.31`** (commit `29112bef`). **NO-GO** —
four blockers, none yet resolved. Full analysis and evidence:
[EPHEMERAL-hermes-pin-upgrade-2026-09-06](ephemeral/EPHEMERAL-hermes-pin-upgrade-2026-09-06.md).

1. **Wire protocol flips** — would break inference for all four members. See OQ-9.
2. **Route-level `reasoning_effort` has no upstream mechanism**, and the config-only
   replacement via `custom_providers` + `extra_body` was investigated and **does not work**.
   The `quick`/`default`/`smart` tiers depend on the local patch, which no longer applies.
3. **Tavily extraction is deleted upstream** — `web.extract_backend: tavily` would have no
   implementation. SearXNG *search* is unaffected.
4. **Command-STT loses its credentials** to a new subprocess environment scrub — voice
   transcription would return empty transcripts with no error.

Two of those have since moved. The live patch is **gone** — ADR-009 was implemented on
2026-09-06 and the install tree is now stock, removing blocker 2's dirty-tree complication.
And the install-headroom concern is **resolved by the resize**: ~2922 MB available against a
1.6 GB peak, rather than the ~1.44 GB it was on DEV1-S.

**The tier mechanism must be decided before the pin moves.** No breaking-change review of the
full 9750-commit range was performed, so **further blockers may exist** — the four above were
found by targeted inspection, not by exhaustive review.

### OQ-8 — The Jupyter skill is seeded to both children but cannot run

`skills/data-science/jupyter-live-kernel/` is bundled at the current pin and present in all
four member homes, **including Mattis's and Love's**. It is non-functional: `uv` is not on the
member PATH (root-owned at `/root/.hermes/bin/uv`), and its documented launch uses port
`8888`, already held by SearXNG.

**The security question is the important one.** That skill's documented launch disables
authentication entirely. The isolation boundary here is the OS user and mount namespace —
**not** the network namespace — so loopback is shared across all four members. An
unauthenticated kernel on loopback would be reachable by every member's gateway.

This is captured as **FR-1** of
[SPEC-tutor-isolation](spec/SPEC-tutor-isolation.md) — *no Jupyter kernel or server listens
without authentication, on any interface including loopback*. Nothing has been built — see
[PRD-jupyter-tutor](prd/PRD-jupyter-tutor.md) and
[ADR-011](adr/ADR-011-tutor-sandbox-isolation.md).

**Cross-member loopback reachability is no longer a supposition — it was demonstrated
2026-09-06.** `hermes-gateway@.service` has no network-isolation directive
(`PrivateNetwork=no`), and from Love's gateway namespace a request to Robert's API server on
`127.0.0.1:8642` connects and is answered (`401`); the shared SearXNG on `8888` returns `200`
as a control. The TCP path between members is open, and only a bearer token refuses it. An
unauthenticated kernel on that interface would answer `200` to any member's agent. See
SPEC-tutor-isolation VC-3 for the re-runnable check.

**What remains open here is the present state, not the future design:** the skill is seeded
and inert today, and the two host-level obstacles (`uv` absent from the member PATH, port
`8888` already held) are unaddressed.

### OQ-9 — Inference works because of an upstream bug, and that bug is now fixed upstream

`hermes_cli/providers.py` declares the `openai-api` provider with
`transport="codex_responses"`. The pinned version never consults that declaration — api_mode
comes from URL detection alone, `api.scaleway.ai` is unrecognised, and resolution falls to
`chat_completions`, which is what this deployment needs.

Upstream has since added a fallback that **does** consult the declaration. On any version
carrying it, this deployment's requests would target `/v1/responses`, which Scaleway does not
serve.

**This is a standing fragility, not merely an upgrade problem** — it will surface on some
future upgrade regardless of when one is attempted. A candidate mitigation exists
(`model.api_mode: chat_completions`, set on all four profiles before any gateway starts on new
code) but is **untested**, and must be proven from the outgoing request body rather than a
`200`.

### OQ-10 — The tutor sandbox has a kernel but no orchestrator

The kernel half is built and its isolation checks pass
([EPHEMERAL-tutor-sandbox-build-2026-09-06](ephemeral/EPHEMERAL-tutor-sandbox-build-2026-09-06.md)).
**There is no tutor**, because [ADR-010](adr/ADR-010-hermes-outside-the-jupyter-kernel.md)
puts Hermes outside the kernel as an API client and that service does not exist. Two things
gate it:

1. **Pod egress needs a firewall change.** `inet filter forward` is `policy drop`, so bridge
   containers have no egress; the orchestrator cannot reach Scaleway. Additive `forward`
   accepts plus NAT masquerade were prepared but **not applied** — the change was refused by
   operator tooling and needs explicit authorisation.
2. **The orchestrator needs a model credential**, which is a provisioning decision — a new
   Scaleway IAM application per the existing per-member pattern, or reuse of an existing key.
   Undecided.

**A consequence to decide deliberately, not inherit:** pod members share a network namespace,
so giving the orchestrator egress also gives the **student kernel** internet access. The SPEC
does not forbid it, but it governs what a child's code may reach.

**Also load-bearing and easy to break by accident:** `inet filter input` is `policy drop` with
only `22`/`443` open, and that is what keeps the pod off host ports `8642-8645`/`8888` once
egress exists. FR-3 depends on it. A future firewall edit for an unrelated reason could remove
it silently.


---

## Resolved

| Was | Resolved | How |
|---|---|---|
| Host firewall not configured | 2026-07-26 | Both layers default-drop with explicit `22`/`443` allows, applied in safe order and verified from a fresh connection after each change |
| Discord voice messages did not work | 2026-07-26 | Scaleway command STT provider — see [ADR-005](adr/ADR-005-command-stt-provider.md) |
| No web-query backends configured | 2026-08-08 | Shared private SearXNG for search, Tavily for extraction, all four profiles |
| `check my calendar` failed ~4 times in 5 | 2026-07-27 | `python3` wrapper — see [ADR-007](adr/ADR-007-venv-python-wrappers.md) |
| Chatbox "Network Error", tiers appeared broken | 2026-07-27 | `API_SERVER_CORS_ORIGINS` — see [ADR-006](adr/ADR-006-public-api-exposure.md) |
