# hermes — working instructions

**hermes** is a deployment repository, not an application. It contains the scripts, systemd
units and documentation that produce four always-on Hermes agents — one per family member —
on a single Scaleway VPS. There is no application source here.

## 1. This repo does not contain the system it describes

The truth about this deployment lives on a **live host**. Git can tell you what a script
says; it cannot tell you what the machine is doing.

- **Observed host state beats every document.** When they disagree, the document is stale.
- **A claim without a verification is a guess.** Every empirical document carries
  `verified_on` and a re-runnable check. `verified_on: null` is an honest answer;
  a confidently wrong date is not.
- **Never advance a `verified_on` date for a check you did not actually run.**

## 2. Find the canonical truth

All authoritative context lives in [`context/`](./context/CONTEXT.md). Read
[CONTEXT.md](./context/CONTEXT.md) **first** — it routes you to the right document by task
type.

- **What is live right now, and what is broken:** [context/STATE.md](./context/STATE.md)
- **Exact names, keys, paths and ports:** `context/contract/`
- **Why something is the way it is:** `context/adr/`
- **Security properties that must not regress:** `context/spec/`

Document precedence in conflict: **ADR > CONTRACT > SPEC > RUNBOOK > PRD**, with observed
host state above all of them.

[README.md](./README.md) is an introduction. It is not authoritative for anything.

## 3. Non-negotiables (deviations require an ADR)

- **The isolation boundary is the operating system, never Hermes configuration.** Four
  unprivileged users, `0700` homes, no sudo, one systemd instance each with
  `ProtectHome=tmpfs` + `BindPaths=/home/%i`. Hermes profiles share a UID and are not a
  security boundary — two of four users are children and the agent runs shell commands. See
  [ADR-001](./context/adr/ADR-001-one-os-user-per-member.md) and
  [SPEC-profile-isolation](./context/spec/SPEC-profile-isolation.md).
- **No credential ever enters this repository.** Not in a script, not in a document, not as
  an example. Keys live in `~/.hermes-family-keys/` (workstation) and each member's
  `.env` (host). Pass secrets through **stdin, never argv**.
- **Inference stays in the EU.** All chat and auxiliary models route to Scaleway. Auxiliary
  tasks stay at `provider: auto` so they inherit the main model rather than leaking to a
  non-EU provider.
- **RAM is the binding constraint**, not disk or CPU. 2 GB shared by four always-on agents;
  the install alone peaks at 1.6 GB.
- **Every deploy script must stay idempotent and safe to re-run after a VPS recreate.**
  Scaleway resources cannot move between projects, so recreation is a routine event.
- **Verify from the log, not the status code.** A `200` proves a request was accepted, not
  that the setting took effect.

## 4. Common pitfalls

These have each cost real time.

- **Connect with `-o IdentitiesOnly=yes`.** SSH hardening sets `MaxAuthTries 3`; an agent
  offering several keys exhausts that before reaching the right one.
- **SSH keys are project-scoped in Scaleway.** A key registered in another project is not
  injected and the instance boots **unreachable**. A reboot does not fix it.
- **The venv has no `pip`.** It is uv-created, so a bare `pip list` fails — which makes "is
  package X installed?" silently return nothing rather than an error. Use
  `/root/.hermes/bin/uv pip install --python /usr/local/lib/hermes-agent/venv/bin/python`.
- **`/usr/local/lib` is read-only to gateways** (`ProtectSystem=full`), so Hermes' lazy
  install of platform dependencies can never succeed at runtime. Install at build time.
- **`hermes config set` warns "not a recognized config key" for dynamically-named keys, and
  writes them correctly anyway.** The same warning also appears for keys that genuinely do
  nothing. **Do not trust it in either direction** — verify what lands in `config.yaml`, and
  ideally test live.
- **`scw init` needs a real TTY.** It cannot be completed from a non-interactive session.
- **Firewall changes: explicit allows first, default policy second**, then verify from a
  **fresh** connection immediately. Your existing connection keeps working either way and
  tells you nothing.

Full trap inventories live in the CONTRACTs — that is what that document type is for.

## 5. Writing or updating context documents

Use the `context-engineer` skill, or follow
[context/CONTEXT.md](./context/CONTEXT.md) directly. Key rules:

- One document answers exactly one question from the Decision Matrix.
- A capability usually needs **one or two** documents plus a row in STATE.md — not one of
  each type.
- **A SPEC is for properties that must not regress**, not for "X works". That is a STATE row.
- **`## Known Traps` is mandatory in a CONTRACT.** For that type, the trap is the payload.
- Never write a RUNBOOK that restates a `deploy/NN-*.sh` header. Reference the script.
- Never modify an accepted ADR — amend it, or supersede it with a new one.

## 6. Checks

Four checks run at commit time via lefthook, with GitHub Actions as the backstop. See
[ADR-008](./context/adr/ADR-008-commit-time-sanity-checks.md).

```bash
lefthook install                        # ONCE PER CLONE — writes to the common git dir
lefthook run pre-commit --all-files     # run on demand, without committing
```

Each check is a script, callable directly:

| Script | Checks |
|---|---|
| `./scripts/lint-shell.sh` | `bash -n`, then shellcheck at `--severity=warning` |
| `./scripts/lint-yaml.sh` | yamllint, tuned to cloud-init and Actions idioms |
| `./scripts/validate-context.sh` | links, required frontmatter, `related_documents`, `secrets` rule |
| `./scripts/scan-secrets.sh` | gitleaks, with a pattern fallback when it is absent |

**Three silent failure modes to check rather than assume:**

- **Hooks never installed.** `git commit` then runs nothing and says nothing. `lefthook
  install` is per clone, not per worktree.
- **No staged file matched a glob**, so the command was skipped silently.
- **A tool is missing.** Locally that degrades loudly and does **not** block — read the
  output, since "PARTIAL" and "SKIPPED" mean the check did not really run. CI fails on a
  missing tool, and is the real gate.

Optional local tooling: `brew install lefthook shellcheck gitleaks yamllint`. None is
required to work in the repo.

**Suppressions need a reason.** There is exactly one — SC2087 in
[`deploy/02-install-hermes.sh`](./deploy/02-install-hermes.sh), where the unquoted heredoc
is load-bearing. Match that standard.

**These checks cover the repository, not the deployment.** A green run says nothing about
whether the host is healthy; that is what `verified_on` and
[STATE.md](./context/STATE.md) are for.

## 7. Code intelligence

Serena is configured (`.serena/project.yml`, `bash` language server). Its index is
per-directory and a linked worktree inherits none of it — an un-indexed worktree returns
*plausible but incomplete* results rather than an error. Treat "no results" from an
unverified index as unknown, not as evidence.
