---
doc_type: contract
status: active
last_updated: 2026-09-06
verified_on: 2026-08-08
verification: >
  Paths and units confirmed on the live host across deployment stages; python3 wrapper
  verified post-fix 2026-07-27 via an explicit import check as an unprivileged member.
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
  - ADR-001-one-os-user-per-member
  - ADR-002-custom-gateway-template-unit
  - ADR-007-venv-python-wrappers
  - SPEC-profile-isolation
created: 2026-09-06
---

# Host Layout

## Purpose

Filesystem paths, systemd units, ports and interpreter names on the VPS. Anything that
another script, unit or agent resolves by exact name.

## Filesystem

| Path | Owner / mode | Contents |
|---|---|---|
| `/usr/local/lib/hermes-agent` | root | Shared 2.2 GB Hermes tree, all four members |
| `/usr/local/lib/hermes-agent/venv` | root | Shared 235 MB venv — **one tree, not four** |
| `/usr/local/bin/hermes` | root | Hermes command |
| `/usr/local/bin/python` | root, 755 | Wrapper → venv interpreter |
| `/usr/local/bin/python3` | root, 755 | Identical wrapper — **both names required** |
| `/home/<member>/` | `<member>`, 0700 | Per-member home, no sudo |
| `/home/<member>/.hermes/` | `<member>` | `.env`, `config.yaml`, `state.db`, sessions, memories |
| `/etc/dynv6/api-token.env` | root:root, 600 | dynv6 HTTP token — outside every member home |
| `/root/.hermes/bin/uv` | root | Present, but outside the agent's sanitized PATH |

## Systemd Units

| Unit | Purpose |
|---|---|
| `hermes-gateway@<member>.service` | One instance per member. `MemoryMax=320M`, `ProtectHome=tmpfs`, `BindPaths=/home/%i`, `ProtectSystem=full`, restart rate-limiting restored |
| `hermes-searxng.service` | Shared SearXNG via rootful Podman, digest-pinned |
| `caddy.service` | Custom build with the dynv6 plugin; sole public listener |
| `nftables.service` | Host firewall, persisted from `/etc/nftables.conf` |

## Ports

| Port | Bound to | Service |
|---|---|---|
| 22 | public | SSH — key-only |
| 443 | public | Caddy |
| 80 | **closed on both layers** | Not needed; DNS-01 never uses it |
| 8888 | `127.0.0.1` | SearXNG (`GRANIAN_HOST=127.0.0.1`, `SEARXNG_PORT=8888`) |
| 8642–8645 | `127.0.0.1` | Per-member API servers |

Both firewall layers — host nftables and the Scaleway security group — default-drop inbound
with explicit `accept` for TCP 22 and 443 only.

## Interpreter Wrapper

Both names install the identical wrapper:

```sh
#!/bin/sh
exec /usr/local/lib/hermes-agent/venv/bin/python "$@"
```

Post-fix check:

```bash
sudo -u robert env PATH=/usr/local/bin:/usr/bin:/bin python3 -c "import googleapiclient"
```

## Known Traps

- **The wrapper must `exec` the venv interpreter by path — never a symlink.** A symlink
  resolves through to `uv`'s interpreter shim, which then cannot see the venv's
  site-packages. Applies to both `python` and `python3`.
  *Confirmed 2026-07-27.*

- **Wrapping only `python` is not enough.** The model reaches for `python3` roughly half the
  time — a reasonable name on Debian. Symptom is not a config error but **apparent model
  incompetence**: stalled turns (`finish_reason: stop`, no tool call) or hallucinated claims
  that no tool is installed. Read `journalctl -u hermes-gateway@<member>` for failed tool
  calls before concluding anything about the model.
  *Root-caused 2026-07-27.*

- **The venv has no `pip`.** It is uv-created. A bare `pip list` fails, which makes "is
  package X installed?" checks silently return nothing rather than an error. Use:

  ```bash
  /root/.hermes/bin/uv pip install --python /usr/local/lib/hermes-agent/venv/bin/python
  ```

- **`/usr/local/lib` is read-only to gateways** (`ProtectSystem=full`), so Hermes' lazy
  install of platform dependencies can never succeed at runtime. Install at build time. See
  [CONTRACT-messaging-channels](CONTRACT-messaging-channels.md).

- **Connect with `-o IdentitiesOnly=yes`.** SSH hardening sets `MaxAuthTries 3`; an agent
  holding several keys exhausts that before offering the right one.

- **SSH keys are project-scoped in Scaleway.** A key registered in another project is not
  injected, and the instance boots **unreachable**. A reboot does not fix it.

- **Resources cannot move between projects.** Relocating the VPS means recreating it — which
  makes DNS repointing a recurring procedure, not a one-off. See
  [RUNBOOK-00-deployment-sequence](../runbook/RUNBOOK-00-deployment-sequence.md).
