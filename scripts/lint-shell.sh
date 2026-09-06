#!/usr/bin/env bash
# Run shellcheck over the given shell scripts (default: deploy/*.sh).
# A missing shellcheck is reported LOUDLY and skipped — never silently passed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

files=("$@")
(( ${#files[@]} )) || mapfile -t files < <(find . -path ./.git -prune -o -name '*.sh' -print)
(( ${#files[@]} )) || { echo "lint-shell: no shell scripts"; exit 0; }

# Always available, and catches the worst class outright: a script that cannot
# parse. Runs whether or not shellcheck is installed.
syntax_failed=0
for f in "${files[@]}"; do
  bash -n "$f" || { echo "  SYNTAX ERROR   $f" >&2; syntax_failed=1; }
done
(( syntax_failed )) && { echo "lint-shell: syntax errors" >&2; exit 1; }

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint-shell: ${#files[@]} script(s) parse OK" >&2
  echo "lint-shell: PARTIAL — shellcheck not installed (brew install shellcheck)," >&2
  echo "            so only syntax was checked locally. CI is the backstop." >&2
  exit 0
fi

# Gate at `warning`, not `info`. These scripts deliberately expand variables
# client-side when building remote heredocs (SC2029/SC2087), which is correct
# here and annotated where it matters — see deploy/02-install-hermes.sh.
echo "lint-shell: checking ${#files[@]} script(s)"
shellcheck --severity=warning --external-sources "${files[@]}"
