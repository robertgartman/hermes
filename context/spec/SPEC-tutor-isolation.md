---
doc_type: spec
status: active
last_updated: 2026-09-06
verified_on: 2026-09-06
verification: >
  2026-09-06 — executed against the rebuilt sandbox (ADR-017: kernel container only, no
  orchestrator inside). A member drove the kernel from the host; a non-member host user was
  refused at the network layer; the kernel reached no host port on 8642, 8643, 8888, 22 or
  443; the sandbox contains no Hermes and no model credential; writes stay in the workspace
  volume; and the pod was destroyed and recreated with the workspace intact.
must_not_contain:
  - secrets
  - capability_status
  - architectural_rationale
  - step_by_step_procedure
applies_to: hermes-vps fr-par-1 — tutor sandbox
audience: [ai, operator]
retrieval_priority: high
related_documents:
  - ADR-011-tutor-sandbox-isolation
  - ADR-010-hermes-outside-the-jupyter-kernel
  - PRD-jupyter-tutor
  - SPEC-profile-isolation
created: 2026-09-06
---

# Tutor Isolation

> **This was a gate; it is now also a record.** The sandbox is built and every requirement
> below was executed against it on 2026-09-06 — see **Executed Results**. The per-criterion
> entries retain the original wording and point at that section.
>
> A kernel is arbitrary code execution. Everything below follows from that single fact — and
> it is why this SPEC survives [ADR-016](../adr/ADR-016-uniform-member-capability.md)
> unchanged: the requirements never depended on anyone's age.

## Purpose

The tutor lets a family member's agent execute code on their behalf. This specifies the
boundary that makes that acceptable, and how each part is demonstrated rather than assumed.
Per [ADR-016](../adr/ADR-016-uniform-member-capability.md) all members are treated alike; these
requirements exist because a kernel is networked arbitrary code execution, not because of age.

## Scope

Covers the tutor sandbox: what the kernel may reach and who may reach it. Since
[ADR-017](../adr/ADR-017-single-hermes-host-orchestration.md) there is no orchestrator inside
the sandbox — it runs on the host as the member's own gateway.
Isolation between the four family gateways is
[SPEC-profile-isolation](SPEC-profile-isolation.md); the two meet at FR-3.

## Functional Requirements

- **FR-1** — No Jupyter kernel or server listens without authentication, on any interface
  including loopback.
- **FR-2** — The sandbox has no read access to any family member's home directory.
- **FR-3** — No process outside the sandbox can reach the kernel, and the kernel cannot reach
  a family gateway.
- **FR-4** — The sandbox has no access to host SSH credentials, browser profiles, private
  documents, unrelated source repositories, or password stores.
- **FR-5** — Writes from inside the sandbox are confined to the designated workspace volume.
- **FR-6** — The sandbox is disposable: destroying and recreating it loses no student work
  beyond the workspace volume, and restores a known-good state.

## Invariants

- **INV-1** — The boundary is enforced by the sandbox (container, namespace, host placement) —
  **never** by the agent's own approval mode, tool restrictions or system prompt. Those are
  defence in depth and may not be counted as the boundary.
- **INV-2** — Model credentials available to the orchestrator must not be readable from the
  student-facing kernel. A student can run arbitrary code in that kernel.
- **INV-3** — No requirement here may be marked satisfied by construction. Each is
  demonstrated by execution, because the failure mode is silent in every case.

## Failure Modes

- **An unauthenticated kernel on shared loopback.** Presents as *working perfectly*. Nothing
  errors, nothing is logged, and the capability functions exactly as intended for the student
  while remaining reachable by anything else on that interface. This is the concrete risk
  recorded as OQ-8 in [STATE.md](../STATE.md), and it is the reason FR-1 is first.
- **An accidental control mistaken for a deliberate one.** The bundled skill is currently
  inert because `uv` is off the member PATH and its port is taken. Both are accidents. A
  routine fix to either could enable it without anyone realising a boundary moved.
- **Credential leakage into the kernel.** An environment variable set for the orchestrator and
  inherited by the kernel hands a student's code the family's model credentials, with no
  visible symptom.
- **Workspace escape via a bind mount added for convenience.** Mounting a notebooks directory
  from a member's home to "make sharing easier" silently defeats FR-2.

## Executed Results — 2026-09-06

The sandbox was rebuilt per [ADR-017](../adr/ADR-017-single-hermes-host-orchestration.md):
JupyterLab alone in the pod, orchestrated from the host by the members' own gateways. The
criteria below were then executed rather than reasoned.

| Requirement | Result |
|---|---|
| **FR-1** kernel requires authentication | **PASS** — no token `403`, wrong token `403`, correct token `200` |
| **FR-2 / FR-4** no member home, SSH key or credential file readable from the kernel | **PASS** — every probed path absent |
| **FR-3** kernel cannot reach a family gateway | **PASS** — host `8642`, `8643`, `8888`, `22`, `443` all refused from inside |
| **FR-3** nothing outside may reach the kernel | **PASS** — a non-member host user (`caddy`) refused at the network layer; members permitted by uid |
| **INV-2** model credential unreadable from the kernel | **PASS, now structurally** — the sandbox contains no Hermes and no credential env var at all |
| **FR-5** writes confined to the workspace | **PASS** — workspace writable; `/etc`, `/usr/local`, `/` denied |
| **FR-6** disposable | **PASS** — the pod was destroyed and recreated repeatedly; `tutor-workspace` survived each time |

**INV-1 is now satisfied where it previously could not be.** Access to the kernel is decided
by uid in the host packet filter — an OS control. In the superseded two-container design,
student code shared a network namespace with a credentialled orchestrator and was separated
from it only by a bearer token, which INV-1 excludes and **which no host firewall rule could
have fixed**, because netfilter hooks are per-namespace.

**Not yet executed:** a *second* member's kernel isolation, because all members currently share
one notebook path and therefore one kernel — see the trap in
[CONTRACT-tutor-sandbox](../contract/CONTRACT-tutor-sandbox.md).


## Verification Criteria

Every criterion must be executed against a running sandbox. Prefer negative checks: prove the
forbidden thing is impossible, from inside the constrained context.

- **VC-1** (Verifies FR-1): When the kernel and Jupyter server are probed without credentials
  from inside the sandbox and from the host, both refuse.
  *Check:* unauthenticated request to the Jupyter server and to the kernel's port, from both
  vantage points; expect rejection, not a session.
  *Observed:* **PASS 2026-09-06** — see Executed Results (no token `403`, wrong token `403`,
  correct token `200`).

- **VC-2** (Verifies FR-2, FR-4): When a family member's home, an SSH key path, and a password
  store path are read from inside the kernel, each fails.
  *Check:* attempt reads from inside the kernel; expect failure for every path.
  *Observed:* **PASS 2026-09-06** — see Executed Results (every probed path absent).

- **VC-3** (Verifies FR-3): When a family gateway's API-server port is contacted from inside
  the kernel, the connection fails; and when the kernel's port is contacted from a member's
  gateway namespace, that fails too.
  *Check:* both directions, both negative.
  *Observed:* **PASS 2026-09-06** — the kernel reached no host port (`8642`, `8643`, `8888`,
  `22`, `443` all refused), and a non-member host user was refused at the network layer while
  members are permitted by uid. See Executed Results.

  The **precondition this criterion originally demanded** was also settled: cross-member loopback reachability was **demonstrated on
  2026-09-06**, not merely reasoned, closing OQ-8.

  `hermes-gateway@.service` carries no network-isolation directive and
  `PrivateNetwork=no`. From Love's gateway namespace — and as the `love` UNIX user — a request
  to Robert's API server on `127.0.0.1:8642` **connects and is answered**, returning `401`. A
  control request to the deliberately shared SearXNG on `127.0.0.1:8888` returns `200`.

  The TCP path across members is therefore **open**; only the bearer token refuses it, which is
  an application-level control and explicitly not the boundary under INV-1. An unauthenticated
  kernel on this interface would return `200` to any member's agent, with nothing in the way.
  This is the evidence behind FR-1 and behind the rejection of the on-host skill in
  [ADR-011](../adr/ADR-011-tutor-sandbox-isolation.md).

  *Re-runnable check:*
  ```bash
  nsenter -t "$(systemctl show hermes-gateway@love -p MainPID --value)" -n -m -- \
    curl -sS -m 8 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8642/v1/models
  # 000/refused = isolated (desired end state); any HTTP response = reachable
  ```

- **VC-4** (Verifies INV-2): When the kernel's environment and readable filesystem are searched
  for the model credential, it is absent.
  *Check:* from inside the kernel, inspect the environment and any config the process can read.
  *Observed:* **PASS 2026-09-06 — now structurally.** The sandbox contains no Hermes and no
  credential environment variable at all; since
  [ADR-017](../adr/ADR-017-single-hermes-host-orchestration.md) nothing carrying a model
  credential runs inside it.

- **VC-5** (Verifies FR-5): When a write outside the workspace volume is attempted from inside
  the kernel, it fails.
  *Check:* attempt writes to several paths outside the workspace; expect failure for each.
  *Observed:* **PASS 2026-09-06** — the workspace volume is writable; writes to `/etc`,
  `/usr/local` and `/` were each denied.

- **VC-6** (Verifies FR-6): When the sandbox is destroyed and recreated, it returns to a
  known-good state and the workspace volume survives.
  *Check:* destroy, recreate, confirm the environment works and student work persists.
  *Observed:* **PASS 2026-09-06** — the pod was destroyed and recreated several times during
  the rebuild; `tutor-workspace` survived intact each time.

### Coverage

| Requirement | Covered by | Status |
|---|---|---|
| FR-1 | VC-1 | not yet |
| FR-2 | VC-2 | not yet |
| FR-3 | VC-3 | not yet |
| FR-4 | VC-2 | not yet |
| FR-5 | VC-5 | not yet |
| FR-6 | VC-6 | not yet |
| INV-1 | VC-1, VC-3, VC-5 | not yet |
| INV-2 | VC-4 | not yet |
| INV-3 | — | procedural; applies to every row above |

> **Coverage is 0/9.** That is the correct state for an unbuilt capability, and it is recorded
> this way deliberately: the temptation with a design this well-argued is to treat the
> reasoning as the assurance. It is not. Nine checks stand between this document and a child
> using the tutor.
