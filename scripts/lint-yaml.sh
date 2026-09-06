#!/usr/bin/env bash
# Run yamllint over the given YAML files (default: all tracked YAML).
# A missing yamllint is reported LOUDLY and skipped — never silently passed.
#
# A malformed cloud-init file fails at first boot, on a host you then cannot
# reach — which is why this check exists at all.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

files=("$@")
(( ${#files[@]} )) || mapfile -t files < <(find . -path ./.git -prune -o \( -name '*.yml' -o -name '*.yaml' \) -print)
(( ${#files[@]} )) || { echo "lint-yaml: no YAML files"; exit 0; }

if ! command -v yamllint >/dev/null 2>&1; then
  echo "lint-yaml: SKIPPED — yamllint not installed (brew install yamllint)" >&2
  echo "lint-yaml: ${#files[@]} file(s) went UNCHECKED locally; CI is the backstop" >&2
  exit 0
fi

echo "lint-yaml: checking ${#files[@]} file(s)"
yamllint --strict "${files[@]}"
