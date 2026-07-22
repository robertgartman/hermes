#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 03 — Configure the four profiles and start their gateways.
#
#   ./deploy/03-configure-profiles.sh <host-ip>
#
# Reads each member's inference key from KEYDIR (written by step 01), installs
# it into that member's own ~/.hermes/.env at mode 600, points Hermes at
# Scaleway, then enables one gateway service per member.
#
# Safe to re-run: .env values are merged, not overwritten, so channel tokens
# added later by `hermes setup` survive.
# ---------------------------------------------------------------------------
set -euo pipefail

HOST="${1:-}"
[[ -n "$HOST" ]] || { echo "usage: $0 <host-ip>" >&2; exit 64; }

MEMBERS=(robert sofia mattis love)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
KEYDIR="${KEYDIR:-$HOME/.hermes-family-keys}"
MODEL="${MODEL:-mistral-small-3.2-24b-instruct-2506}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSHO=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY")

for m in "${MEMBERS[@]}"; do
  [[ -s "$KEYDIR/$m.env" ]] || { echo "missing $KEYDIR/$m.env — run 01 first" >&2; exit 65; }
done

echo "== deploying unit + configurator =="
scp "${SSHO[@]}" "$SCRIPT_DIR/hermes-gateway@.service" "$SCRIPT_DIR/configure-profile.sh" "root@$HOST:/root/" >/dev/null
ssh "${SSHO[@]}" "root@$HOST" '
  mv /root/hermes-gateway@.service /etc/systemd/system/
  chmod +x /root/configure-profile.sh
  systemctl daemon-reload
  # Hermes own installer writes a single non-templated hermes-gateway.service
  # supporting only ONE gateway per host; remove it if present.
  systemctl disable --now hermes-gateway.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/hermes-gateway.service
  systemctl daemon-reload
  echo "  done"
'

echo "== per-member credentials =="
# Piped separately from any heredoc: a single ssh cannot take both a stdin pipe
# and a heredoc, and the heredoc silently wins.
for m in "${MEMBERS[@]}"; do
  grep -E '^(OPENAI_API_KEY|OPENAI_BASE_URL)=' "$KEYDIR/$m.env" \
    | ssh "${SSHO[@]}" "root@$HOST" "/root/configure-profile.sh $m -" \
    | sed 's/^/  /'
done

echo "== provider config =="
ssh "${SSHO[@]}" "root@$HOST" "MODEL='$MODEL' bash -s" <<'REMOTE'
for u in robert sofia mattis love; do
  R="sudo -u $u -H env PATH=/usr/local/bin:/usr/bin:/bin HERMES_HOME=/home/$u/.hermes"
  # Scaleway is reached through the OpenAI-compatible provider. `provider: custom`
  # does NOT work: Hermes rewrites the base URL to OpenRouter's /api/v1/models and
  # sends it unauthenticated, which Scaleway rejects as 403.
  # Keys are nested under `model:` — a top-level `provider:` is never read.
  $R hermes config set model.provider openai-api >/dev/null 2>&1
  $R hermes config set model.default "$MODEL" >/dev/null 2>&1
  echo "  $u -> openai-api / $MODEL"
done
REMOTE

echo "== starting gateways =="
ssh "${SSHO[@]}" "root@$HOST" '
  for u in robert sofia mattis love; do
    systemctl reset-failed hermes-gateway@$u 2>/dev/null || true
    systemctl enable --now hermes-gateway@$u >/dev/null 2>&1
  done
  sleep 25
  for u in robert sofia mattis love; do
    MC=$(systemctl show hermes-gateway@$u -p MemoryCurrent --value 2>/dev/null)
    case "$MC" in ""|*[!0-9]*) M="n/a";; *) M="$((MC/1048576))MB";; esac
    printf "  %-7s %-9s mem=%-7s restarts=%s\n" "$u" "$(systemctl is-active hermes-gateway@$u)" "$M" "$(systemctl show hermes-gateway@$u -p NRestarts --value)"
  done
  echo
  free -m | head -2 | tail -1
'

cat <<EOF

Configured. Verify inference per member with:
  ssh -o IdentitiesOnly=yes root@$HOST \\
    "sudo -u robert -H sh -c 'cd /home/robert && HERMES_HOME=/home/robert/.hermes /usr/local/bin/hermes -z \"say ok\"'"

Then add messaging channels per member (interactive, over SSH — no web UI needed):
  hermes whatsapp        # Baileys bridge, personal account, QR pairing
  hermes whatsapp-cloud  # official Meta Business Cloud API (needs public webhook)
  hermes gateway setup   # Discord / Slack / Telegram tokens
EOF
