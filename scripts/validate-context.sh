#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Validate the context/ documentation system against the rules in
# context/CONTEXT.md. No external dependencies — pure bash + coreutils.
#
#   ./scripts/validate-context.sh
#
# Checks, for every file under context/:
#   - relative markdown links resolve
#   - the six required frontmatter fields are present
#   - must_not_contain includes `secrets`
#   - every related_documents entry names a file that exists
#
# Exits non-zero on any finding. This is the canonical implementation; lefthook,
# CI and the context-engineer skill all call it rather than reimplementing it.
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# The cross-reference format example in CONTEXT.md is deliberately not a real path.
readonly ALLOWED_BROKEN_LINK='relative/path/to/file.md'
readonly REQUIRED_FIELDS=(doc_type status last_updated verified_on verification must_not_contain)

findings=0
note() { echo "  $*"; findings=$((findings + 1)); }

[[ -d context ]] || { echo "no context/ directory — nothing to validate"; exit 0; }

while IFS= read -r f; do
  dir=$(dirname "$f")

  while IFS= read -r link; do
    [[ "$link" == "$ALLOWED_BROKEN_LINK" ]] && continue
    [[ -e "$dir/$link" ]] || note "BROKEN LINK    $f -> $link"
  done < <(grep -oE '\]\([^)#][^)]*\.md\)' "$f" | sed 's/](\(.*\))/\1/')

  for key in "${REQUIRED_FIELDS[@]}"; do
    grep -qE "^${key}:" "$f" || note "MISSING FIELD  $f: $key"
  done

  awk '/^must_not_contain:/{f=1;next} f&&/^  - /{print;next} f&&!/^  - /{f=0}' "$f" \
    | grep -q 'secrets' || note "NO SECRETS RULE $f"

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    find context -name "${id}.md" | grep -q . || note "DANGLING REF   $f -> $id"
  done < <(awk '/^related_documents:/{f=1;next} f&&/^  - /{print $2;next} f&&!/^  - /{f=0}' "$f")

done < <(find context -name '*.md' | sort)

if (( findings > 0 )); then
  echo "validate-context: $findings finding(s)" >&2
  exit 1
fi
echo "validate-context: OK ($(find context -name '*.md' | wc -l | tr -d ' ') documents)"
