---
doc_type: adr
status: active
last_updated: 2026-09-06
verified_on: null
verification: >
  Records the decision. The checks themselves were run locally on 2026-09-06 —
  shellcheck and yamllint clean, validator and secrets scanner passing, the secrets
  fallback confirmed against planted credentials.
must_not_contain:
  - secrets
  - feature_requirements
  - step_by_step_procedure
audience: [ai, operator]
related_documents:
  - ADR-001-one-os-user-per-member
created: 2026-09-06
---

# ADR-008: Enforce sanity checks at commit time

## Context

This repository had **no** tooling: no hooks, no CI, no linter configuration. Discipline was
maintained entirely by hand — and maintained well, in fairness. All seven deploy scripts use
`set -euo pipefail`, and no credential has ever been committed.

Two things made that unsustainable.

**The repository now states rules in writing that nothing checks.** `context/CONTEXT.md`
declares that no document may contain a credential, that every document carries six
frontmatter fields, and that `related_documents` must resolve. A written rule with no
enforcement decays exactly like an undated claim about the host.

**The failure modes here are silent and expensive.** These scripts run as root against a live
host, handle four inference keys and four bearer tokens, and boot a machine that becomes
unreachable if `cloud-init` is malformed. Nearly every costly incident recorded in this
repository was something accepted without error.

Ruff, pyright and the rest of the source system's Python toolchain are irrelevant: there are
**zero `.py` files** here. The lintable surface is 7 bash scripts, 4 YAML files, 3 systemd
units and ~30 markdown documents.

## Decision

Adopt **lefthook** for commit-time checks with **GitHub Actions as the backstop**, running
four checks:

| Check | Covers | Tool |
|---|---|---|
| `lint-shell` | `*.sh` | `bash -n`, then shellcheck at `--severity=warning` |
| `lint-yaml` | `*.yml`, `*.yaml` | yamllint, config tuned to machine-shaped YAML |
| `validate-context` | `context/**` | repo-local script, no dependencies |
| `scan-secrets` | everything | gitleaks, with a built-in pattern fallback |

**Each check is a script under `scripts/`, not inline configuration.** lefthook, CI and the
`context-engineer` skill all invoke the same executable rather than reimplementing the logic
— the same rule this repository applies to RUNBOOKs and deploy scripts.

**Locally, a missing tool degrades loudly and does not block.** In CI, a missing tool fails
the build. A developer without shellcheck installed should not be unable to commit; a green
CI run that silently checked nothing is intolerable.

## Alternatives Considered

**No tooling, continue by hand.** Rejected. It worked while the repository was seven scripts
and one operator holding the whole thing in memory. It does not extend to ~30 documents with
cross-references and a written no-credentials rule.

**pre-commit (the Python framework).** Rejected: it would introduce a Python toolchain into a
repository with no Python, to manage hooks for bash and YAML.

**Blocking locally when a tool is missing.** Rejected. It makes a fresh clone uncommittable
until four tools are installed, and the predictable outcome is `--no-verify` becoming habit —
which disables the credential scan too.

**Gating shellcheck at `--severity=info`.** Rejected after measuring it. These scripts
deliberately expand variables client-side when building remote heredocs, producing five
SC2029 info hits that are all correct code. Gating there would train everyone to ignore the
output.

**Formatting the cloud-init file to satisfy yamllint.** Rejected. The findings were
`- [ sh, -c, "..." ]` runcmd spacing and the mandatory `#cloud-config` first line — which
*cannot* carry a starting space without breaking the boot, and cannot be waived per-line
because nothing may precede line 1. The linter was configured to the file's legitimate
idioms instead. A genuine trailing-blank-line in `searxng-settings.yml` was fixed rather than
excepted.

## Consequences

- **Hooks install per clone, not per worktree.** `lefthook install` writes to the
  repository's common git dir, so one install covers every worktree. Two failure modes stay
  silent: hooks never installed (commits run nothing, no message), and no staged file
  matching a command's glob (skipped silently). The globs in `lefthook.yml` are therefore
  broader than the obvious extension — `*.md` rather than `context/**`, because `AGENTS.md`
  and `README.md` link into `context/` too.
- **`scan-secrets` is deliberately not globbed.** A credential can land in any file type, and
  the rule it enforces has no exceptions.
- **The secrets fallback keeps the rule enforced without gitleaks installed**, using patterns
  for the credential shapes this deployment actually handles, with placeholders
  (`$VAR`, `<...>`, `sk-or-...`) excluded. It reports locations only and never echoes a
  matched value.
- **The fallback and gitleaks do not cover the same ground.** gitleaks scans **git history**;
  the fallback scans the **working tree only**. A credential removed from `HEAD` still lives
  in an old commit, and only gitleaks will find it. The fallback says so when it runs.
- **The first full run surfaced four history findings, all false positives.** Documentation
  placeholders of the form `hermes_<member>_local_api_key`, inside `Authorization: Bearer`
  example commands in the original README (commit `74bc846`, removed in `3a18e6e`), matched by
  gitleaks' `curl-auth-header` rule. Allowlisted in `.gitleaks.toml` **by that exact string
  shape rather than by commit**, so the initial commit stays fully scanned for anything else.
  Rewriting history is not the remedy for a false positive.
- **One deliberate shellcheck suppression now exists**, at
  [`deploy/02-install-hermes.sh`](../../deploy/02-install-hermes.sh) — SC2087, where the
  unquoted heredoc is load-bearing: it bakes `INSTALLER_SHA` and `PIN_COMMIT` in at send
  time. Quoting it would silently defeat both the checksum gate and the version pin. Any
  future suppression must carry the same kind of reason.
- **These checks cover the repository, not the deployment.** They cannot tell you whether the
  host is healthy — that is what `verified_on` and [STATE.md](../STATE.md) are for. Passing
  CI means the repository is internally consistent, nothing more.
