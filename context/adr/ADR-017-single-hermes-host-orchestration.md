---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a decision. The architecture it describes was built and its isolation properties
  executed on 2026-09-06; results are in SPEC-tutor-isolation.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents:
  - ADR-001-one-os-user-per-member
  - ADR-010-hermes-outside-the-jupyter-kernel
  - ADR-011-tutor-sandbox-isolation
  - ADR-013-tutor-sandbox-on-the-family-vps
  - SPEC-tutor-isolation
created: 2026-09-06
---

# ADR-017: One Hermes. The kernel is containerised; orchestration stays on the host

## Context

The tutor was first built as a Podman pod containing **two** things: JupyterLab *and a second,
complete Hermes installation* acting as orchestrator. An audit on 2026-09-06 found that design
indefensible, on evidence from this repository's own documents.

**No document ever argued for the second Hermes.**
[ADR-010](ADR-010-hermes-outside-the-jupyter-kernel.md) requires only that Hermes reach the
kernel *"as an external client"* — the words container, image and sandbox do not appear in it.
[ADR-011](ADR-011-tutor-sandbox-isolation.md) placed the orchestrator inside the sandbox in a
single sentence and a diagram, while its entire Context argues about **the kernel**. Neither
ADR-011's four alternatives nor [ADR-013](ADR-013-tutor-sandbox-on-the-family-vps.md)'s six
ever evaluate *"the orchestrator stays on the host"*.

**[ADR-001](ADR-001-one-os-user-per-member.md) had already rejected this exact shape**: *"One
Hermes install per user. Rejected: 4 × 2.2 GB of identical code on a 20 GB disk, for no
isolation benefit."* A second install was added anyway, and both disk accountings written
afterwards omitted it.

**The one recorded objection to host-side orchestration was falsified the same afternoon.**
ADR-013 rejected reaching the kernel from the host because *"host loopback is shared by all
four family gateways… with only a token in the way"*. Per-uid `nftables` rules were added
1h45m later and verified — twelve of twelve cross-member combinations refused at the network
layer. The decision resting on that objection was never reopened.

**And colocation made the security property *worse*.** Sharing a pod network namespace, student
code could reach the orchestrator's API server on pod loopback, gated only by a bearer token —
the control class [SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) INV-1 excludes. **No
host firewall rule can reach inside a pod's namespace**, so that gap was unclosable by design.

## Decision

**One Hermes installation. Only JupyterLab is containerised. The members' existing gateways
orchestrate it from the host over Jupyter's API.**

| Element | Choice |
|---|---|
| Orchestrator | The members' existing host gateways — **no Hermes in the sandbox** |
| Sandbox contents | JupyterLab and the scientific stack, nothing else |
| Kernel address | A **static** pod address, so configuration does not chase a changing IP |
| Who may reach the kernel | root and the four member uids, enforced by `nftables` `meta skuid` — the same shape already guarding the API servers and dashboards |
| Kernel → host | Denied at `input` for the sandbox subnet: the kernel reaches **no** host port |
| Credentials | Stay on the host. **Nothing carrying a model credential runs inside the sandbox** |

## Alternatives Considered

**Keep the two-container pod (status quo).** Rejected on the evidence above: unargued,
already excluded by ADR-001, ~2.7 GB of duplicate code on a disk that had blocked three
pieces of work in one day, a version-coupling requirement that broke within hours, and a
weaker isolation property than the simpler design.

**Publish the kernel port to host loopback via Podman.** Attempted and abandoned: the
`conmon` forwarder did not pass traffic — root itself could not reach the published port while
the pod address answered `200` directly. Using the pod address removes a moving part rather
than debugging one.

**JupyterLab on the host with no container.** Not chosen. The container is the one piece of
this system that genuinely earns its isolation, because it is where arbitrary student code
runs. That was never the disputed part.

**No Jupyter at all — use Hermes' own `execute_code`.** Rejected: it is stateless, and
persistent kernel state between calls is the pedagogical point
([PRD-jupyter-tutor](../prd/PRD-jupyter-tutor.md)).

## Consequences

**Roughly 2.7 GB returned** and the duplicate-install class of problem is gone: there is one
Hermes to upgrade, so host and sandbox versions **cannot** drift. The coupling requirement in
[CONTRACT-tutor-sandbox](../contract/CONTRACT-tutor-sandbox.md) becomes unnecessary rather
than merely satisfied.

**The isolation properties improve.** The model credential never enters the sandbox at all,
which is strictly stronger than protecting it with a token inside the same namespace as the
student's kernel. Access to the kernel is decided by uid in the kernel's own packet filter —
an OS control, satisfying INV-1 where the previous design could not.

**All four members currently share one kernel**, so one member's variables are visible to
another. That is a consequence of a single notebook path, not of this decision, and is
changed by giving each member their own path. Recorded because it is a privacy surprise if
nobody chose it.

**ADR-011 and ADR-013 are superseded in part.** Their isolation *requirements* stand; their
placement of the orchestrator **inside** the sandbox does not. Accepted ADRs are not edited,
so this document supersedes those two clauses and nothing else.

**A general lesson, recorded because it caused this.** The ADRs mandating the two-container
design were written the same day, largely before a working system existed, and were then
treated as requirements rather than as claims to test. This repository's own rule —
*observation beats every document* — was available the whole time and was not applied.
