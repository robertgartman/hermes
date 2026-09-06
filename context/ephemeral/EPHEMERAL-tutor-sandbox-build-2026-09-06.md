---
doc_type: ephemeral
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  Point-in-time build record. Every check below was executed against the running sandbox on
  2026-09-06, but the sandbox is INCOMPLETE (no orchestrator), so no SPEC criterion is
  marked satisfied on the strength of it.
must_not_contain:
  - secrets
authoritative: false
retrieval_priority: low
related_documents:
  - SPEC-tutor-isolation
  - ADR-010-hermes-outside-the-jupyter-kernel
  - ADR-011-tutor-sandbox-isolation
  - ADR-012-deterministic-tools-for-exactness
created: 2026-09-06
---

> **Never authoritative.** Findings must graduate before they mean anything.

# Tutor sandbox — first build — 2026-09-06

## Scope

Built the kernel half of the [ADR-011](../adr/ADR-011-tutor-sandbox-isolation.md) sandbox on
the family VPS and executed the isolation checks against it. **The orchestrator half does not
exist**, so the capability is not usable and no SPEC criterion is closed here.

Host was first resized **DEV1-S → DEV1-M** (3 vCPU / 3916 MB), which ADR-011 lists as a
compatible placement. Available memory went ~877 MB → ~2922 MB.

## What exists

A Podman pod `tutor` on an `--internal` bridge network, containing one container:

| | |
|---|---|
| Image | `quay.io/jupyter/scipy-notebook`, pinned by digest `sha256:41e9176d…` |
| Verified contents | numpy 2.5.2 · scipy 1.18.0 · pandas 3.0.5 · matplotlib 3.11.1 · sympy 1.14.0 · scikit-learn 1.9.0 · networkx 3.6.1 · ipywidgets 8.1.9 · jupyterlab 4.6.3 — all nine of [ADR-012](../adr/ADR-012-deterministic-tools-for-exactness.md)'s base set |
| Caps | `--memory=1g --pids-limit=256`, following the SearXNG pattern |
| Storage | named volume `tutor-workspace` at `/home/jovyan/work`; **no host bind mounts** |
| Listener | `127.0.0.1:8888` **inside the pod netns only** — no published port |
| Token | `/etc/hermes-tutor/jupyter-token.env`, root:root 0600, outside every `/home` |

Observed cost: ~79 MB container RSS; host at ~1173 MB used, ~2742 MB available.

## Findings

### F-1 — A real FR-3 violation existed in the obvious configuration, and was caught by executing the check

**Finding:** The first build put Jupyter on the internal bridge at `10.89.0.2:8888`. That
address was **reachable from the host and from Love's gateway namespace**. `--internal`
prevents the container reaching *out*; it does nothing about the host reaching *in*, because
the host holds an interface on that bridge. Only the token stood in the way — which
[SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) INV-1 excludes from counting as the
boundary.

**Fix:** rebuild as a pod with Jupyter bound to `127.0.0.1` inside the pod network namespace,
so no listener exists on the bridge at all.

**Confidence:** **confirmed on host** — violation observed, fix observed.

### F-2 — Checks executed against the rebuilt sandbox

All run 2026-09-06 against the running pod. These map to SPEC criteria but **do not close
them**, because the sandbox lacks its orchestrator.

| Check | Result |
|---|---|
| Jupyter API, no token | `HTTP 403` |
| Jupyter API, wrong token | `HTTP 403` |
| Jupyter API, correct token | `HTTP 200` |
| host → pod `:8888` | unreachable |
| love gateway → pod `:8888` | unreachable |
| kernel → `127.0.0.1:8642` | connection refused |
| kernel → `51.15.201.4:8642` | network unreachable |
| kernel → bridge gateway `:8642` | unreachable |
| read `/home/robert`, `/home/love`, `/root/.ssh`, a member `.env`, the token file | none present |
| `OPENAI_API_KEY` in kernel env | absent |
| write `/home/jovyan/work` | succeeds (intended) |
| write `/etc`, `/usr/local`, `/` | denied |

### F-3 — The host firewall, not the container runtime, is what keeps the kernel off family services

`inet filter input` is `policy drop` with only `22`, `443`, established, `lo` and ICMP
accepted. So even once the pod is given egress, traffic from it to host ports `8642-8645` and
`8888` is dropped at INPUT. This is a **load-bearing dependency of FR-3 that is easy to
remove by accident** while editing firewall rules for an unrelated reason.

`inet filter forward` is also `policy drop`, which is why bridge containers currently have no
egress at all (DNS fails with `gaierror`). This is the same constraint that made SearXNG use
host networking ([ADR-004](../adr/ADR-004-private-searxng-backend.md)).

**Confidence:** **confirmed on host.**

## Blocked

**The orchestrator is not built**, so there is no tutor. Two things gate it:

1. **Pod egress requires a firewall change.** Additive `forward` accepts for the tutor bridge
   plus NAT masquerade. Attempted and **not applied** — the change was refused by the
   operator's tooling and needs explicit authorisation.
2. **The orchestrator needs a model credential**, and which credential is a provisioning
   decision (a new Scaleway IAM application per the existing per-member pattern, or reuse).
   Undecided. Note INV-2 holds structurally regardless: separate containers do not share
   environment or filesystem, so an orchestrator credential is not visible to the kernel —
   **but that must be demonstrated once it exists, not assumed.**

A consequence worth deciding deliberately: pod members share a network namespace, so giving
the orchestrator egress also gives the **student kernel** internet access. That is not
forbidden by the SPEC, but it is a choice about what a child's code may reach, and it should
be made on purpose rather than inherited from the pod topology.

## Graduation

| Finding | Disposition | Destination |
|---|---|---|
| F-1 | accepted | Already reflected in SPEC-tutor-isolation VC-3's evidence; the pod-loopback binding belongs in a CONTRACT once the sandbox is complete |
| F-2 | deferred | Re-run and record against the **complete** sandbox, then close the SPEC criteria |
| F-3 | accepted | Belongs in a CONTRACT as a known trap — the INPUT default-drop is silently load-bearing for FR-3 |
