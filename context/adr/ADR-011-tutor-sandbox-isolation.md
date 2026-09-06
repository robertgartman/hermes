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
retrieval_priority: high
related_documents:
  - PRD-jupyter-tutor
  - ADR-010-hermes-outside-the-jupyter-kernel
  - ADR-001-one-os-user-per-member
  - SPEC-tutor-isolation
created: 2026-09-06
---

# ADR-011: The tutor runs in a dedicated sandbox, not on a family gateway

> **Decided, not built.** This is a precondition for shipping the tutor, not a later
> hardening step.

## Context

The tutor's users are Mattis and Love — both children. The capability's entire value comes
from an agent that can execute code on their behalf, which means the question is not *whether*
it runs code but *where*.

The existing platform cannot simply host it. Its isolation boundary is the OS user plus a
mount namespace ([ADR-001](ADR-001-one-os-user-per-member.md)) — deliberately **not** a
network namespace. Loopback is therefore shared by all four members.

That distinction is already load-bearing. A `jupyter-live-kernel` skill is bundled at the
current pin and seeded into all four member homes, **including both children's**, and its
documented launch **disables authentication entirely** (OQ-8 in [STATE.md](../STATE.md)). An
unauthenticated kernel on shared loopback would be reachable by every member's gateway — a
kernel is arbitrary code execution, so that is a cross-member shell, reached without a
credential.

The skill is currently non-functional by accident, not by design: `uv` is not on the member
PATH, and its documented port is already held by SearXNG.

## Decision

**The tutor runs in its own sandboxed container stack** — JupyterLab plus the scientific
Python environment plus the Hermes orchestrator — with a controlled writable workspace, and
**no path to the host or to any family member's home**.

```
sandbox
├── jupyter        JupyterLab + scientific Python stack + notebooks volume
└── hermes         orchestrator, Jupyter API access, model credentials
     shared: ./workspace
```

The sandbox must not expose SSH credentials, browser profiles, private documents, unrelated
source repositories, password stores, or arbitrary host filesystem access. It should be
disposable — cheap to destroy and restore.

**No kernel may listen without authentication**, on loopback or anywhere else. The properties
this creates are specified with checks in
[SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md), every one of which must pass before
a child uses the tutor.

## Alternatives Considered

**Enable the bundled `jupyter-live-kernel` skill on the existing gateways.** Rejected, and
this is the alternative most likely to be attempted, because the skill is *already sitting in
both children's homes* and looks like a switch waiting to be flipped. Its documented launch
disables authentication on a loopback interface shared by all four members. What currently
prevents it is two unrelated accidents — a PATH gap and a port collision — neither of which is
a security control, and both of which a future fix could remove without anyone noticing what
else changed.

**Run the tutor as a fifth OS user on the existing host.** Rejected. It inherits exactly the
gap above: the OS-user boundary does not isolate the network, so a kernel bound to loopback
remains reachable across members. It also adds the tutor's memory footprint to a host with
~783 MB available against a 1.6 GB install peak.

**Run it on the family VPS in a container without resizing.** Not chosen. The isolation model
is right, but the capacity is not — JupyterLab plus a scientific Python stack on top of four
gateways and SearXNG does not obviously fit. **Placement is deliberately left open**: this ADR
fixes the isolation model, not the host. Resize, separate host, or a machine at home are all
compatible with it.

**Rely on the agent's own approval mode and tool restrictions.** Rejected as the *primary*
boundary — it is application-level configuration, the same class of control that
[ADR-001](ADR-001-one-os-user-per-member.md) already rejected for the family platform. Useful
in depth; not sufficient alone.

## Consequences

- **The tutor cannot ship on the current host as configured.** That is the intended
  consequence. The gating question moves from "does the notebook work?" to "is the sandbox
  demonstrated?"
- **A prerequisite exists that predates the tutor**: the bundled skill is seeded to both
  children now. Whether its cross-member reachability warrants a requirement in
  [SPEC-profile-isolation](../spec/SPEC-profile-isolation.md) is undecided, and the
  reachability was **reasoned from unit configuration, not demonstrated** (OQ-8). It should be
  demonstrated or refuted before the tutor is built, since the answer changes what the sandbox
  must defend against.
- **Placement and capacity become explicit open questions** rather than assumptions —
  carried in [PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md) and STATE.md.
- The container stack is one more thing to build, pin and maintain, for one operator who
  already maintains four gateways, a search backend and a reverse proxy.
