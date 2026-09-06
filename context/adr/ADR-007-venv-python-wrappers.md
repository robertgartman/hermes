---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: Records rationale. The post-fix check is recorded in CONTRACT-host-layout.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - CONTRACT-host-layout
  - ADR-001-one-os-user-per-member
created: 2026-09-06
---

# ADR-007: Wrap both `python` and `python3` to the Hermes venv

## Context

Bundled skills — google-workspace among them — invoke a bare `python`. Debian ships **no
`python` at all**, so those calls resolved to nothing. A `/usr/local/bin/python` wrapper
pointing at the Hermes venv fixed that on 2026-07-22.

It covered only the name `python`.

**Symptom reported 2026-07-27:** "check my calendar" over the API server succeeded roughly
**1 time in 5**. The rest either stalled mid-sentence (`finish_reason: stop`, no tool call
ever made) or hallucinated — claiming no calendar tool was installed and offering to install
`gcal` or fall back to Python's `calendar` module. Direct CLI testing was more reliable
(4/5) but not perfect, which pointed at something upstream of the API server *as well*.

**Root cause, confirmed from `journalctl -u hermes-gateway@robert`:** roughly half the time
the model reaches for **`python3`** instead of `python` — an entirely reasonable name on
Debian, just not the wrapped one. `/usr/local/bin/python3` did not exist, so the call fell
through to the system `/usr/bin/python3`, hit
`ModuleNotFoundError: No module named 'googleapiclient'`, and then burned the remainder of
the turn trying to self-heal: `pip install` (no `pip` in that interpreter),
`curl -Ls https://astral.sh/uv/install.sh | sh` (blocked on a pending security approval),
`apt-get install` (permission denied, not root), `pip3` (not found).

Every attempt is logged as a distinct failed tool call. **The agent never once tried plain
`python`, which was working the entire time.**

## Decision

Install the identical wrapper under **both** names, `python` and `python3`, each `exec`-ing
the venv's own interpreter by absolute path.

## Alternatives Considered

**Wrapping only `python`.** This *was* the prior state, and it is why the bug existed. The
lesson generalises: the model picks whichever interpreter name is idiomatic for the platform
it believes it is on, so every plausible name must resolve.

**Symlinks instead of `exec` wrappers.** Rejected — and this caveat applies to both names. A
symlink resolves through to `uv`'s interpreter shim, which then cannot see the venv's
site-packages. Only `exec`-ing the venv's own interpreter by path works.

**Routing `python`/`python3` through `uv` instead.** Prompted by a reasonable question: with
four profiles on one host, wouldn't `uv`'s shared cache save space? Checked before acting,
and rejected on three grounds:

1. **There is no duplication to eliminate.** The venv is already shared across all four
   profiles — one 235 MB tree, not four.
2. **Disk was never the binding constraint** (19 GB disk, 9.8 GB free at the time). The
   scarce resource is RAM.
3. **`uv run` would very likely reproduce the same error by a different path.** It only knows
   what to install for a script declaring dependencies via inline PEP 723 metadata or sitting
   in a `pyproject.toml` project. **None** of the 67 `.py` files across the bundled skills do
   either — confirmed by grep. They are plain `#!/usr/bin/env python3` scripts assuming a
   conventional pre-populated venv.

   A `uv` binary *does* exist on the host at `/root/.hermes/bin/uv` — almost certainly what
   Hermes' installer used to build the venv — but it is root-owned and outside the sanitized
   PATH the agent's shell tool runs with. That is very likely what sent the model down the
   failed `curl | sh` install attempt rather than finding it.

## Consequences

- Skills invoking either interpreter name now reach an interpreter that can import their
  dependencies.
- **This class of bug presents as model unreliability, not as a configuration error.** The
  visible symptom was a flaky, hallucinating agent; the cause was a missing filename. When an
  agent appears intermittently incompetent at a tool-using task, read the gateway log for
  failed tool calls before concluding anything about the model.
- Any future wrapper must `exec` the venv interpreter by path. Symlinking silently
  reintroduces the failure.
