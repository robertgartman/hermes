---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records a design decision for an unbuilt capability. Nothing implemented.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - PRD-jupyter-tutor
  - ADR-011-tutor-sandbox-isolation
  - ADR-012-deterministic-tools-for-exactness
created: 2026-09-06
---

# ADR-010: Hermes orchestrates the notebook from outside the kernel

> **Decided, not built.** This constrains the Jupyter tutor
> ([PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md)) whenever it is implemented.

## Context

The tutor puts a student in an executable notebook with an agent alongside. The obvious
shortcut is to run the agent *inside* the Python kernel — a cell magic that calls a model in
process, sharing the kernel's namespace.

That collapses two things that need to stay separate. The kernel is the student's
computational workspace: it holds their variables, their partial work, their mistakes. The
agent is an orchestrator that inspects and manipulates that workspace. Merging them makes the
agent's failures indistinguishable from the student's.

## Decision

**Hermes runs as a service outside the Jupyter kernel** and reaches the notebook through
Jupyter's API — inspecting notebook state, editing cells, executing code and reading outputs
as an external client.

```
JupyterLab                    Hermes service
├── normal notebook           ├── model provider
└── Hermes sidebar   ───────► ├── Jupyter kernel access
                              ├── filesystem
                              └── external tools
```

The student-facing surface may be a sidebar, a cell magic, or both. That is a UI choice above
this boundary and does not change it — a cell magic is permitted only as a *client* of the
external service, never as an in-kernel model call.

## Alternatives Considered

**Run the agent inside the kernel.** Rejected. An agent sharing the student's namespace can
clobber their variables, and a crash takes the student's session with it. It also makes the
model provider a kernel dependency — changing providers would mean rebuilding the notebook
environment.

**Drive the notebook by generating code for the student to paste.** Rejected: it makes the
agent unable to read outputs, so it cannot verify its own suggestions — which is the whole
point of putting a tutor in an executable environment rather than a chat window.

**Couple Hermes to JupyterLab specifically.** Not chosen. Going through the Jupyter API keeps
the notebook environment replaceable; a different frontend over the same kernel protocol
should not require touching the orchestration layer.

## Consequences

- **The notebook environment stays replaceable, and the model provider stays swappable**
  without touching notebooks. Given that inference is already committed to one provider
  ([ADR-003](ADR-003-scaleway-eu-inference.md)) with an unresolved provider-level fragility
  (OQ-9 in [STATE.md](../STATE.md)), keeping that seam clean is worth more here than usual.
- **The agent needs authenticated access to a kernel.** That access is the tutor's primary
  attack surface, and the bundled `jupyter-live-kernel` skill's documented launch disables
  authentication entirely (OQ-8). The boundary this ADR creates must therefore be secured
  explicitly, not assumed — see
  [SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md).
- Agent failures stay attributable. A stalled orchestrator does not present as a broken
  kernel, which matters because this deployment has already been burned once by a tooling
  fault that looked like model incompetence
  ([ADR-007](ADR-007-venv-python-wrappers.md)).
- Two processes must be run and supervised rather than one, on a host where RAM is the
  binding constraint.
