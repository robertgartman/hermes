---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records a decision. The mechanics it fixes were executed and observed on 2026-09-06; the
  isolation checks are recorded in EPHEMERAL-tutor-sandbox-build-2026-09-06 and remain open
  in SPEC-tutor-isolation until the sandbox is complete.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
  - reversible_decisions
audience: [ai, operator]
supersedes: null
superseded_by: null
related_documents:
  - ADR-011-tutor-sandbox-isolation
  - ADR-010-hermes-outside-the-jupyter-kernel
  - ADR-012-deterministic-tools-for-exactness
  - SPEC-tutor-isolation
  - EPHEMERAL-tutor-sandbox-build-2026-09-06
created: 2026-09-06
---

# ADR-013: Place the tutor sandbox on the family VPS, and how it is isolated

## Context

[ADR-011](ADR-011-tutor-sandbox-isolation.md) fixed the tutor's **isolation model** and
deliberately left **placement** open, noting the family VPS "without resizing" was not chosen
because JupyterLab plus a scientific stack did not obviously fit alongside four gateways on
2 GB.

Building it surfaced four mechanics that are not obvious and that the isolation depends on.
Each was observed, not reasoned:

- **A container on an `--internal` bridge is still reachable *from the host*.** `--internal`
  blocks the container reaching out; it does nothing about the host reaching in, because the
  host holds an interface on that bridge. The first build was reachable from a family
  gateway's namespace on the bridge address.
- **An `--internal` network has no default route**, so firewall rules alone cannot grant the
  orchestrator egress to the inference endpoint.
- **Podman's own DNS runs on the host bridge address**, so blocking the pod from reaching the
  host also breaks name resolution unless DNS is moved off that path.
- **The host's `input` chain is `policy drop`** with only `22`/`443` open, which is what keeps
  a routable pod off the family API-server ports.

## Decision

**Place the tutor sandbox on the family VPS, resized to DEV1-M**, and isolate it as follows.

| Element | Choice |
|---|---|
| Placement | Family VPS, resized DEV1-S → DEV1-M (3 vCPU / 4 GB) |
| Grouping | A single Podman **pod**, so members share one network namespace |
| Kernel reachability | JupyterLab binds the **pod loopback** — no listener on the bridge, so nothing outside the pod can reach it |
| Egress | A routable (non-`internal`) bridge with `forward` accepts and NAT for that subnet only |
| Pod → host | Denied at `input` for the pod subnets, so the sandbox cannot reach **any** host port |
| DNS | Podman DNS disabled for the network; explicit external resolvers |
| Orchestrator | The official upstream image, **pinned by digest to the same release the family runs** |
| Credential | Reuses an existing family Scaleway key rather than minting a new identity |

Authentication remains on the Jupyter server as well. It is **defence in depth, not the
boundary** — INV-1 is satisfied by the pod's network namespace and the host firewall.

## Alternatives Considered

**A separate host or a machine at home.** Compatible with ADR-011 and the cleanest isolation
story, since the family VPS would keep no tutor surface at all. Not chosen: it adds hardware
and an operator with no route to it from the existing tooling. **Revisit if the sandbox ever
needs to be larger than the family platform it borrows.**

**Keeping the pod on an `--internal` network.** Rejected once tested — no default route means
no inference. Worth recording because it *looks* like the strictest option and reads as safe
right up until the orchestrator cannot start.

**Publishing the kernel port onto host loopback so the host can reach it.** Rejected. Host
loopback is shared by all four family gateways — **demonstrated 2026-09-06**, see
[SPEC-tutor-isolation](../spec/SPEC-tutor-isolation.md) VC-3 — so publishing would expose the
kernel to every member's agent, with only a token in the way.

**Leaving Podman's DNS on the host bridge.** Rejected: it requires the pod to reach the host,
which is exactly what the `input` rule forbids. Containers in one pod share a namespace and
reach each other on loopback, so no name service is needed between them.

**Minting a new Scaleway IAM identity for the tutor.** Not chosen for now — reuse keeps the
change small. It does mean tutor spend is indistinguishable from that member's own, which
matters for OQ-1 and should be revisited if per-capability attribution is ever wanted.

**Running the tutor on the existing gateways as a fifth profile or via the bundled skill.**
Already rejected by [ADR-011](ADR-011-tutor-sandbox-isolation.md); restated here only so this
document is not read as reopening it.

## Consequences

**The student kernel has internet access.** Pod members share a network namespace, so the
egress the orchestrator needs is also available to the kernel. The SPEC does not forbid it,
but it governs what a child's code can reach and is now an inherited property of the topology
rather than a considered one. **If it should be constrained, that is a change of shape** —
separate containers plus firewalling the host off the bridge — not a flag.

**FR-3 depends on the host firewall's `input` default-drop.** That policy is load-bearing for
the sandbox, not merely for the family platform. A future firewall edit made for an unrelated
reason could remove it and silently reopen the pod's path to the family API servers. This
belongs in the firewall CONTRACT as a trap.

**The tutor's spend is attributed to the member whose key it reuses**, deepening OQ-1 rather
than relieving it.

**Cost rises from €6.55 to €14.74/mo**, and the scientific image consumes ~3.9 GB of a 19 GB
disk. Disk, not memory, is now the tighter resource on this host.

**The orchestrator is pinned to the family's release**, so it does not inherit the upstream
wire-protocol change recorded as OQ-9. That coupling is deliberate but must be remembered when
the family pin moves: the tutor moves with it, and inherits the same blockers.
