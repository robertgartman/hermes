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

# --- ADR numbering ---------------------------------------------------------
# CONTEXT.md requires ADR numbers to be sequential, zero-padded and gap-free
# across BOTH context/adr/ and context/archive/. Concurrent sessions each pick
# "the next number" from the same starting point and collide, which is silent
# until someone reads the directory listing — so check it here instead.
mapfile -t adr_files < <(find context/adr context/archive -name 'ADR-[0-9][0-9][0-9]-*.md' 2>/dev/null | sort)

if (( ${#adr_files[@]} > 0 )); then
  nums=()
  for f in "${adr_files[@]}"; do
    n=$(basename "$f" | sed -E 's/^ADR-([0-9]{3}).*/\1/')
    nums+=("$n")
    # The heading must agree with the filename — they drift apart precisely when
    # a file is renamed to resolve a collision.
    grep -qE "^# ADR-${n}[:[:space:]]" "$f" \
      || note "ADR HEADING    $f: filename says ADR-${n}, heading does not match"
  done

  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    owners=$(find context/adr context/archive -name "ADR-${d}-*.md" -exec basename {} \; | tr '\n' ' ')
    note "ADR DUPLICATE  ADR-${d} claimed by: ${owners}"
    note "               resolve: the ADR already referenced by another document keeps"
    note "               the number; the unreferenced one renumbers (see CONTEXT.md)"
  done < <(printf '%s\n' "${nums[@]}" | sort | uniq -d)

  # Gap detection: the sorted unique set must be exactly 001..N.
  mapfile -t uniq_nums < <(printf '%s\n' "${nums[@]}" | sort -u)
  expected=1
  for n in "${uniq_nums[@]}"; do
    want=$(printf '%03d' "$expected")
    [[ "$n" == "$want" ]] || note "ADR GAP        expected ADR-${want}, found ADR-${n}"
    expected=$((expected + 1))
  done
fi

# supersedes / superseded_by must name a document that exists.
while IFS= read -r f; do
  while IFS= read -r ref; do
    [[ -n "$ref" && "$ref" != "null" ]] || continue
    find context -name "${ref}.md" | grep -q . \
      || note "DANGLING REF   $f -> ${ref} (supersedes/superseded_by)"
  done < <(grep -hE '^(supersedes|superseded_by):' "$f" | sed -E 's/^[a-z_]+:[[:space:]]*//')
done < <(find context -name '*.md')

if (( findings > 0 )); then
  echo "validate-context: $findings finding(s)" >&2
  exit 1
fi
echo "validate-context: OK ($(find context -name '*.md' | wc -l | tr -d ' ') documents)"
