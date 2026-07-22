#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# configure-profile.sh <user> KEY=VALUE [KEY=VALUE ...]
#
# Non-interactively configure one family member's Hermes gateway. No web UI,
# no setup wizard. Run as root on the host.
#
#   ./configure-profile.sh sofia \
#       OPENROUTER_API_KEY=sk-or-... \
#       WHATSAPP_ENABLED=true \
#       WHATSAPP_ALLOWED_USERS=46701234567
#
# Pass a literal `-` to read KEY=VALUE lines from stdin instead, which keeps
# secrets out of the process table and shell history:
#
#   ./configure-profile.sh sofia - < sofia-secrets.env
#
# MERGES into the existing .env. It never truncates a profile that has already
# been configured — re-running to change one key preserves the rest.
# ---------------------------------------------------------------------------
set -euo pipefail

usage() { echo "usage: $0 <user> [KEY=VALUE ...]   (or pipe KEY=VALUE lines on stdin)" >&2; exit 64; }

[[ $# -ge 1 ]] || usage
USER_NAME="$1"; shift

id -u "$USER_NAME" >/dev/null 2>&1 || { echo "no such user: $USER_NAME" >&2; exit 65; }
[[ $EUID -eq 0 ]] || { echo "must run as root (writes into another user's home)" >&2; exit 77; }

HERMES_HOME="/home/${USER_NAME}/.hermes"
ENV_FILE="${HERMES_HOME}/.env"
UNIT="hermes-gateway@${USER_NAME}"

# Secrets must never touch disk world-readable, not even for an instant.
umask 077
install -d -o "$USER_NAME" -g "$USER_NAME" -m 700 "$HERMES_HOME"

# Collect assignments from argv, and from stdin only when asked explicitly.
# Auto-detecting `[[ ! -t 0 ]]` here would make this script silently consume
# the stdin of whatever called it — including the remaining lines of a parent
# heredoc — so stdin is opt-in via a literal `-` argument.
declare -a PAIRS=()
READ_STDIN=false
for arg in "$@"; do
  if [[ "$arg" == "-" ]]; then READ_STDIN=true; else PAIRS+=("$arg"); fi
done
if [[ "$READ_STDIN" == true ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    PAIRS+=("$line")
  done
fi
[[ ${#PAIRS[@]} -gt 0 ]] || { echo "nothing to set" >&2; exit 64; }

TMP="$(mktemp "${ENV_FILE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
[[ -f "$ENV_FILE" ]] && cat "$ENV_FILE" > "$TMP"

for pair in "${PAIRS[@]}"; do
  key="${pair%%=*}"
  [[ "$key" == "$pair" ]] && { echo "malformed (expected KEY=VALUE): $pair" >&2; exit 64; }
  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "invalid key: $key" >&2; exit 64; }

  # Replace an existing assignment in place, else append. Value goes through a
  # temp file so it is never an argv element and never re-parsed by the shell.
  if grep -qE "^${key}=" "$TMP" 2>/dev/null; then
    grep -vE "^${key}=" "$TMP" > "${TMP}.n" && mv "${TMP}.n" "$TMP"
  fi
  printf '%s\n' "$pair" >> "$TMP"
  echo "  set ${key}"
done

chown "$USER_NAME:$USER_NAME" "$TMP"
chmod 600 "$TMP"
mv -f "$TMP" "$ENV_FILE"
trap - EXIT

echo "wrote ${ENV_FILE} ($(stat -c '%U:%G %a' "$ENV_FILE"))"

# `systemctl list-unit-files hermes-gateway@mattis` exits 1 — there is no unit
# *file* by that name, only the template hermes-gateway@.service. So the old
# guard skipped the restart on every single run, leaving the gateway alive with
# a stale environment while this script still printed "wrote ...". A new channel
# token appeared in .env and was never loaded.
# LoadState resolves template instances: "loaded" if the template is installed,
# "not-found" if it is not.
if [[ "$(systemctl show -p LoadState --value "$UNIT" 2>/dev/null)" == "loaded" ]]; then
  systemctl restart "$UNIT"
  sleep 3
  echo "${UNIT}: $(systemctl is-active "$UNIT")"
fi
