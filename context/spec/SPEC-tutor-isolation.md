---
doc_type: spec
status: draft
last_updated: 2026-09-06
verified_on: null
verification: >
  NOTHING VERIFIED. The tutor is unbuilt; every criterion below is a pre-ship gate, not a
  result. No criterion may be marked verified except by execution against a running sandbox.
must_not_contain:
  - secrets
  - capability_status
  - architectural_rationale
  - step_by_step_procedure
applies_to: unbuilt — Jupyter tutor sandbox
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

> **This is a gate, not a record.** Every criterion reads `NOT YET VERIFIED` because nothing
> is built. **No child uses the tutor until each one is executed and passes** against a
> running sandbox.
>
> A kernel is arbitrary code execution. Everything below follows from that single fact.

## Purpose

The tutor gives two children an agent that executes code on their behalf. This specifies the
boundary that makes that acceptable, and how each part of it is demonstrated rather than
assumed.

## Scope

Covers the tutor sandbox: what the kernel and orchestrator may reach, and who may reach them.
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

## Verification Criteria

Every criterion must be executed against a running sandbox. Prefer negative checks: prove the
forbidden thing is impossible, from inside the constrained context.

- **VC-1** (Verifies FR-1): When the kernel and Jupyter server are probed without credentials
  from inside the sandbox and from the host, both refuse.
  *Check:* unauthenticated request to the Jupyter server and to the kernel's port, from both
  vantage points; expect rejection, not a session.
  *Observed:* **NOT YET VERIFIED**

- **VC-2** (Verifies FR-2, FR-4): When a family member's home, an SSH key path, and a password
  store path are read from inside the kernel, each fails.
  *Check:* attempt reads from inside the kernel; expect failure for every path.
  *Observed:* **NOT YET VERIFIED**

- **VC-3** (Verifies FR-3): When a family gateway's API-server port is contacted from inside
  the kernel, the connection fails; and when the kernel's port is contacted from a member's
  gateway namespace, that fails too.
  *Check:* both directions, both negative.
  *Observed:* **NOT YET VERIFIED** — cross-member loopback reachability is currently **reasoned
  from unit configuration, not demonstrated** (OQ-8). Demonstrate or refute it before building.

- **VC-4** (Verifies INV-2): When the kernel's environment and readable filesystem are searched
  for the model credential, it is absent.
  *Check:* from inside the kernel, inspect the environment and any config the process can read.
  *Observed:* **NOT YET VERIFIED**

- **VC-5** (Verifies FR-5): When a write outside the workspace volume is attempted from inside
  the kernel, it fails.
  *Check:* attempt writes to several paths outside the workspace; expect failure for each.
  *Observed:* **NOT YET VERIFIED**

- **VC-6** (Verifies FR-6): When the sandbox is destroyed and recreated, it returns to a
  known-good state and the workspace volume survives.
  *Check:* destroy, recreate, confirm the environment works and student work persists.
  *Observed:* **NOT YET VERIFIED**

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
