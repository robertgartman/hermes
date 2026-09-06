---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  Every name, port, path and image digest below was read back from the running host on
  2026-09-06, and the traps were each hit during the build rather than anticipated.
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
  - ADR-013-tutor-sandbox-on-the-family-vps
  - ADR-011-tutor-sandbox-isolation
  - SPEC-tutor-isolation
created: 2026-09-06
---

# Tutor Sandbox Surface

## Purpose

The exact names, ports, images, paths and credential locations of the tutor sandbox. Managed
with `podman` as root; there is no deploy script for this yet.

## Podman Objects

| Object | Name | Notes |
|---|---|---|
| Pod | `tutor` | Members share one network namespace |
| Kernel container | `tutor-jupyter` | JupyterLab + the ADR-012 stack |
| Orchestrator container | `tutor-hermes` | Hermes gateway, external client of the kernel |
| Network | `tutor-net-egress` | Routable bridge, **DNS disabled** |
| Workspace volume | `tutor-workspace` | Mounted at `/home/jovyan/work` |
| Orchestrator volume | `tutor-hermes-data` | Mounted at `/opt/data` (`HERMES_HOME`) |

The earlier `tutor-net` (`--internal`) network is superseded — see Known Traps.

## Images — pinned by digest

| Role | Image |
|---|---|
| Kernel | `quay.io/jupyter/scipy-notebook@sha256:41e9176dc64072976c43c037f853ae9a95ca34aeb0170c58a1b304d62fbde486` |
| Orchestrator | `docker.io/nousresearch/hermes-agent@sha256:a6ce64e2038867885c2c90f6602425e6e70293d5e6d952a0e603a99265e01c40` (tag `v2026.7.20`) |

The orchestrator tag **deliberately matches the family pin**. Moving one moves the other.

## Ports — all pod-internal, none published

| Port | Service |
|---|---|
| `8888` | JupyterLab, bound to pod loopback |
| `8650` | Orchestrator API server |
| `9119` | Hermes dashboard (upstream default) |

**Nothing is published to the host.** Host `8888` belongs to SearXNG and is unrelated.

## Orchestrator Configuration

| Key | Value |
|---|---|
| `model.provider` | `openai-api` |
| `model.default` | `qwen3.5-397b-a17b` |
| `model.base_url` | `https://api.scaleway.ai/v1` — **must be set explicitly**, see traps |
| `model.max_tokens` | `16384` |
| container command | `gateway run` — **required**, see traps |

## Credential Locations

Locations only, never values.

| Credential | Location | Mode |
|---|---|---|
| Jupyter server token | `/etc/hermes-tutor/jupyter-token.env` (host), root:root | 600 |
| Orchestrator env (reused member inference key, Jupyter token, API-server key) | `/etc/hermes-tutor/orchestrator.env` (host), root:root | 600 |

Both live **outside every `/home`**, following the dynv6 token pattern.

## Known Traps

- **`hermes config set model.provider openai-api` writes `base_url: https://openrouter.ai/api/v1`.**
  It is not left empty and it does not follow `OPENAI_BASE_URL`. If `model.base_url` is not
  then set explicitly, the orchestrator points at OpenRouter with a Scaleway key. Symptom:
  auth failures against a provider you never configured.
  *Hit during the 2026-09-06 build; corrected by setting `model.base_url` explicitly.*

- **The image's default entrypoint runs the interactive UI and exits immediately without a
  TTY.** With `--restart`, the container loops forever while `podman ps` briefly shows "Up".
  Symptom in logs: `Warning: Input is not a terminal (fd=0).` then `Goodbye!`. **Pass
  `gateway run` as the command** — upstream's compose does exactly this.
  *Hit during the build.*

- **`podman exec <ctr> sh -c hermes` fails with `hermes: not found`.** The venv is put on
  `PATH` by the entrypoint wrapper, which `exec` bypasses. Use the absolute path
  `/opt/hermes/.venv/bin/hermes`, or set `PATH=/opt/hermes/bin:/opt/hermes/.venv/bin:...`
  and `HOME=/opt/data`.

- **A container on an `--internal` podman network is still reachable from the host**, and
  therefore from every family gateway, because the host holds an interface on that bridge.
  `--internal` only stops the container reaching out. **Bind the service to the pod loopback
  instead** — that is what makes it unreachable.
  *Observed as a live FR-3 violation on 2026-09-06 before the rebuild.*

- **An `--internal` network has no default route**, so no firewall rule can grant egress.
  Symptom: DNS fails and every outbound connection is `Network is unreachable`.

- **Podman's DNS server listens on the host bridge address**, so denying the pod access to the
  host also breaks name resolution. Symptom: raw-IP connections succeed while every hostname
  fails with `gaierror`. **Create the network with `--disable-dns` and set explicit external
  resolvers**; pod members reach each other on loopback and need no name service.

- **`inet filter input` `policy drop` is load-bearing for the sandbox, not just for the family
  platform.** It is what keeps the routable pod off host ports `8642-8645` and `8888`. A
  firewall edit made for an unrelated reason can remove it and silently reopen that path.
  Re-run the VC-3 check in [SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) after any
  firewall change.

- **Creating a kernel session over the REST API requires the XSRF exemption or a token
  header.** With the `Authorization: token …` header it works; a bare `POST /api/sessions`
  returns an XSRF complaint rather than an auth error, which reads like the wrong problem.
