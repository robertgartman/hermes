---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  Every name, address, port and path below was read back from the running host on 2026-09-06,
  and the access-control behaviour was executed: a member drove the kernel from the host, a
  non-member host user was refused, and the kernel could reach no host port.
must_not_contain:
  - secrets
  - decision_rationale
  - behavioural_explanation
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1
audience: [ai, operator]
retrieval_priority: high
version: "2.0"
related_documents:
  - ADR-017-single-hermes-host-orchestration
  - ADR-011-tutor-sandbox-isolation
  - SPEC-tutor-isolation
created: 2026-09-06
---

# Tutor Sandbox Surface

## Purpose

Exact names, addresses, ports and paths for the tutor. Managed with `podman` as root; there is
no deploy script for this yet.

**There is no Hermes inside the sandbox.** The members' existing host gateways orchestrate the
kernel over Jupyter's API — see
[ADR-017](../adr/ADR-017-single-hermes-host-orchestration.md).

## Podman Objects

| Object | Name |
|---|---|
| Pod | `tutor` — **static address `10.89.1.10`** |
| Kernel container | `tutor-jupyter` (the only container in the pod) |
| Network | `tutor-net-egress` — routable bridge, **DNS disabled**, subnet `10.89.1.0/24` |
| Workspace volume | `tutor-workspace` → `/home/jovyan/work` |

The address is static **by design**: members' configuration points at it, and a pod recreate
would otherwise hand out a new address and silently break every caller.

## Image — pinned by digest

`quay.io/jupyter/scipy-notebook@sha256:41e9176dc64072976c43c037f853ae9a95ca34aeb0170c58a1b304d62fbde486`

Carries the [ADR-012](../adr/ADR-012-deterministic-tools-for-exactness.md) base set: numpy,
scipy, pandas, matplotlib, sympy, scikit-learn, networkx, ipywidgets, jupyterlab.

## Addresses and Access

| | |
|---|---|
| Kernel API | `http://10.89.1.10:8888` — bound `0.0.0.0` **inside the pod only** |
| Published to host | **Nothing.** No port publishing |
| Who may reach it | root and uids `1001-1004` (the four members), enforced by `nftables` `meta skuid` |
| Kernel → host | Denied at `input` for `10.89.0.0/16`: **no** host port is reachable |

## Orchestration

| | |
|---|---|
| Driver | `/opt/hermes-tutor/jupyter_exec.py`, root-owned `0644`, vendored from `deploy/tutor/` |
| Interpreter | `/usr/local/lib/hermes-agent/venv/bin/python` — needs `websockets`, already a Hermes dependency |
| Per-member config | `JUPYTER_TOKEN` and `JUPYTER_TUTOR_URL` in each member's own `.env` (mode 600, owned by that member) |

## Credential Locations

| Credential | Location | Mode |
|---|---|---|
| Jupyter server token | `/etc/hermes-tutor/jupyter-token.env` (host), root:root | 600 |
| Same token, per member | `/home/<member>/.hermes/.env`, owned by that member | 600 |

**No model credential exists anywhere in the sandbox**, and nothing inside it runs Hermes.

## Known Traps

- **Podman's published-port path did not work here.** With `-p 127.0.0.1:8890:8888`, `conmon`
  listened but passed no traffic — **root itself** got no response while the pod address
  answered `200` directly. Symptom is a connect timeout that looks exactly like a firewall
  drop, which sends you to the wrong place. Use the pod address; do not reintroduce publishing
  without testing it end to end.

- **Guarding only one path to the kernel guards nothing.** The published port and the pod's
  bridge address are different destinations. A `meta skuid` rule on one is silently bypassed
  via the other. The current design removes the ambiguity by having only one path.

- **`--internal` networks cannot reach the inference endpoint** (no default route) and are
  **still reachable from the host** — `--internal` blocks the container reaching out, not the
  host reaching in. Neither is what it sounds like.

- **Podman's DNS lives on the host bridge address**, so denying the pod access to the host
  breaks name resolution. Symptom: raw IPs connect while every hostname fails with `gaierror`.
  The network is created `--disable-dns` with explicit external resolvers.

- **`inet filter input`'s `policy drop` is load-bearing for the sandbox.** It is what keeps the
  kernel off host ports. Re-run SPEC-tutor-isolation VC-3 after any firewall change.

- **All members currently share one notebook path**, so kernel state is shared between them.
  Give each member a distinct `--path` if that is not wanted.
