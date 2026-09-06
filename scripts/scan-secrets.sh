#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Enforce this repository's hard rule: no credential ever enters the repo —
# not in a script, not in a document, not as an example.
#
#   ./scripts/scan-secrets.sh --staged    what is about to be committed (hook)
#   ./scripts/scan-secrets.sh             full: git history + working tree
#   ./scripts/scan-secrets.sh <files...>  specific files
#
# MODE MATTERS. `gitleaks git` scans COMMITTED HISTORY and therefore sees
# nothing of a staged-but-uncommitted change — a pre-commit hook wired that way
# passes cleanly while a secret walks straight through it. That exact bug was
# found here by staging a planted credential and watching the hook go green, so
# --staged is used for the hook and history is scanned separately.
#
# Uses gitleaks when available. Without it, falls back to targeted patterns for
# the credential shapes this deployment handles, so the rule still applies on a
# machine with no tooling — but see the fallback's own warning about coverage.
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

mode="full"
if [[ "${1:-}" == "--staged" ]]; then
  mode="staged"
  shift
fi

files=("$@")

if command -v gitleaks >/dev/null 2>&1; then
  echo "scan-secrets: gitleaks $(gitleaks version 2>/dev/null || echo '?') [mode: $mode]"
  rc=0
  case "$mode" in
    staged)
      # The staged diff — what is actually about to be committed.
      gitleaks git --staged --no-banner --redact --exit-code 1 . || rc=$?
      ;;
    full)
      if (( ${#files[@]} )); then
        gitleaks dir --no-banner --redact --exit-code 1 "${files[@]}" || rc=$?
      else
        # History, then the working tree — the latter also covers untracked files.
        gitleaks git --no-banner --redact --exit-code 1 . || rc=$?
        gitleaks dir --no-banner --redact --exit-code 1 . || rc=$?
      fi
      ;;
  esac
  (( rc == 0 )) && echo "scan-secrets: OK"
  exit $rc
fi

echo "scan-secrets: gitleaks not installed — using built-in fallback patterns" >&2
echo "scan-secrets: NOTE — the fallback scans FILE CONTENT ONLY. It does not read" >&2
echo "              git history, where a credential removed from HEAD still lives" >&2
echo "              in an old commit. Install gitleaks for that coverage." >&2

(( ${#files[@]} )) || mapfile -t files < <(git ls-files; git ls-files --others --exclude-standard)
(( ${#files[@]} )) || { echo "scan-secrets: no files"; exit 0; }

# Placeholders and indirection are expected in documentation and scripts:
#   $VAR   <redacted>   sk-or-...   KEY=<that member's key>
readonly PLACEHOLDER='(\$|<|\.\.\.|example|EOF|xxx|REDACTED|your-|<member>|_local_api_key)'

readonly -a PATTERNS=(
  'tvly-[A-Za-z0-9]{16,}'
  '[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '(API_KEY|_TOKEN|SECRET_KEY|PASSWORD|BOT_TOKEN)[A-Z_]*[[:space:]]*=[[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{20,}'
)

# Collect file:line locations only — never echo the matched value itself.
hits=$(
  for pattern in "${PATTERNS[@]}"; do
    grep -rnE "$pattern" "${files[@]}" 2>/dev/null \
      | grep -v '^scripts/scan-secrets\.sh:' \
      | grep -vE "$PLACEHOLDER" \
      | cut -d: -f1,2
  done | sort -u
)

findings=0
if [[ -n "$hits" ]]; then
  while IFS= read -r loc; do
    echo "  POSSIBLE SECRET  $loc"
    findings=$((findings + 1))
  done <<< "$hits"
fi

if (( findings > 0 )); then
  echo "scan-secrets: $findings possible credential(s) — see context/CONTEXT.md 'Secrets'" >&2
  exit 1
fi
echo "scan-secrets: OK (${#files[@]} files, fallback patterns)"
