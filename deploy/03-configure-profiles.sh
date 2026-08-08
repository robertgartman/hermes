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
# Keep the deployment default aligned with the API's "default" tier. The
# qwen3.5 output-token limit is handled by model.max_tokens below.
MODEL="${MODEL:-qwen3.5-397b-a17b}"

# Model tier aliases exposed to family clients (Chatbox etc.) via the API
# server's /v1/models — see README § Mobile / API access. The ALIAS NAMES are
# the stable contract: family members use aliases, not model IDs. Swap the
# model or reasoning effort behind a tier here; nobody using the alias needs
# to know or care. All tiers deliberately share one model and vary only the
# Scaleway reasoning_effort request field.
ALIAS_MODEL="${ALIAS_MODEL:-qwen3.5-397b-a17b}"
EFFORT_QUICK="${EFFORT_QUICK:-none}"
EFFORT_DEFAULT="${EFFORT_DEFAULT:-medium}"
EFFORT_SMART="${EFFORT_SMART:-high}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PATCH="$SCRIPT_DIR/hermes-api-model-route-reasoning.patch"
SSHO=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY")

[[ -f "$HERMES_PATCH" ]] || { echo "missing deployment patch: $HERMES_PATCH" >&2; exit 66; }

for effort in "$EFFORT_QUICK" "$EFFORT_DEFAULT" "$EFFORT_SMART"; do
  case "$effort" in
    none|low|medium|high) ;;
    *) echo "unsupported qwen3.5 reasoning effort: $effort" >&2; exit 66 ;;
  esac
done

for m in "${MEMBERS[@]}"; do
  [[ -s "$KEYDIR/$m.env" ]] || { echo "missing $KEYDIR/$m.env — run 01 first" >&2; exit 65; }
done

echo "== deploying unit + configurator =="
scp "${SSHO[@]}" "$SCRIPT_DIR/hermes-gateway@.service" "$SCRIPT_DIR/configure-profile.sh" "$HERMES_PATCH" "root@$HOST:/root/" >/dev/null
ssh "${SSHO[@]}" "root@$HOST" '
  PATCH=/root/hermes-api-model-route-reasoning.patch
  HERMES_SRC=/usr/local/lib/hermes-agent
  if git -C "$HERMES_SRC" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "  Hermes model-route reasoning patch already applied"
  else
    git -C "$HERMES_SRC" apply --check "$PATCH"
    git -C "$HERMES_SRC" apply "$PATCH"
    echo "  applied Hermes model-route reasoning patch"
  fi
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
ssh "${SSHO[@]}" "root@$HOST" \
  "MODEL='$MODEL' ALIAS_MODEL='$ALIAS_MODEL' EFFORT_QUICK='$EFFORT_QUICK' EFFORT_DEFAULT='$EFFORT_DEFAULT' EFFORT_SMART='$EFFORT_SMART' bash -s" <<'REMOTE'
for u in robert sofia mattis love; do
  R="sudo -u $u -H env PATH=/usr/local/bin:/usr/bin:/bin HERMES_HOME=/home/$u/.hermes"
  # Scaleway is reached through the OpenAI-compatible provider. `provider: custom`
  # does NOT work: Hermes rewrites the base URL to OpenRouter's /api/v1/models and
  # sends it unauthenticated, which Scaleway rejects as 403.
  # Keys are nested under `model:` — a top-level `provider:` is never read.
  $R hermes config set model.provider openai-api >/dev/null 2>&1
  $R hermes config set model.default "$MODEL" >/dev/null 2>&1

  # Without this, qwen3.5-397b-a17b (the deployment default and all three tier
  # backends) 400s on every request, tool use or not.
  # model.max_tokens is unset by default, so Hermes falls back to a
  # per-provider default that exceeds Scaleway's hard 16384-token cap for
  # this model: "HTTP 400: payload validation: max_completion_tokens is
  # limited to 16384 for qwen3.5-397b-a17b". model.max_tokens is a GLOBAL
  # setting — model_routes has no per-alias override for it (checked the
  # patched source: reasoning_effort is supported, but max_tokens is not) —
  # so this caps all three tiers. 16384 output tokens remains generous in
  # practice.
  $R hermes config set model.max_tokens 16384 >/dev/null 2>&1

  # Model tier aliases for API-server clients (Chatbox etc.) — a SEPARATE
  # mechanism from model.default above, found by reading
  # gateway/platforms/api_server.py directly (not reliably documented):
  # platforms.api_server.extra.model_routes.<alias>.{model,provider,
  # reasoning_effort}. Upstream supports the first two fields; the deployment
  # patch applied above adds the existing Hermes reasoning knob to model_routes
  # and forwards it as Scaleway's top-level reasoning_effort request field.
  # This is NOT the same as model_catalog/model_aliases (tried first, both dead
  # ends for CLI-side switching — see README). Verified end-to-end: listed
  # correctly via GET /v1/models AND confirmed to route to the right backend
  # model via a live /v1/chat/completions call, not just cosmetic.
  # Remove aliases from the previous four-tier definition so a re-run updates
  # existing profiles as well as clean installs.
  $R hermes config unset platforms.api_server.extra.model_routes.medium >/dev/null 2>&1 || true
  $R hermes config unset platforms.api_server.extra.model_routes.ultra >/dev/null 2>&1 || true

  for route in "quick:$EFFORT_QUICK" "default:$EFFORT_DEFAULT" "smart:$EFFORT_SMART"; do
    alias_name="${route%%:*}"; alias_effort="${route#*:}"
    $R hermes config set "platforms.api_server.extra.model_routes.$alias_name.model" "$ALIAS_MODEL" >/dev/null 2>&1
    $R hermes config set "platforms.api_server.extra.model_routes.$alias_name.provider" openai-api >/dev/null 2>&1
    $R hermes config set "platforms.api_server.extra.model_routes.$alias_name.reasoning_effort" "$alias_effort" >/dev/null 2>&1
  done

  # Voice transcription via Scaleway's whisper-large-v3, NOT the built-in
  # stt.provider=openai path — that path validates the model name against
  # OpenAI's own catalog, silently substitutes the unrecognized
  # "whisper-large-v3" with "whisper-1", and Scaleway then 422s because it has
  # no model by that name. The command-provider registry
  # (stt.providers.<name>: type: command) has no such whitelist — it just runs
  # the shell command — so it's the working path. Also: Scaleway ignores
  # response_format=text and always returns JSON regardless, hence `| jq -r
  # .text` rather than writing curl's body straight to {output_path}. See the
  # README's "Configured: voice transcription via Scaleway" section for the
  # full incident (verified against real Discord voice messages, not
  # synthesized audio).
  $R hermes config set stt.enabled true >/dev/null 2>&1
  $R hermes config set stt.echo_transcripts true >/dev/null 2>&1
  $R hermes config set stt.provider scaleway >/dev/null 2>&1
  $R hermes config set stt.providers.scaleway.type command >/dev/null 2>&1
  $R hermes config set "stt.providers.scaleway.command" "curl -sS -X POST \$OPENAI_BASE_URL/audio/transcriptions -H \"Authorization: Bearer \$OPENAI_API_KEY\" -F \"file=@{input_path}\" -F \"model=whisper-large-v3\" | jq -r .text" >/dev/null 2>&1
  $R hermes config set stt.providers.scaleway.format txt >/dev/null 2>&1
  $R hermes config set stt.providers.scaleway.timeout 60 >/dev/null 2>&1

  echo "  $u -> openai-api / $MODEL, stt -> scaleway/whisper-large-v3, aliases -> quick:$EFFORT_QUICK/default:$EFFORT_DEFAULT/smart:$EFFORT_SMART"
done
REMOTE

echo "== starting gateways =="
# `restart`, not `enable --now`: the latter only starts a stopped unit, so a
# re-run against an already-running deployment (e.g. after changing the alias
# model or efforts above) would silently leave the old config loaded. Safe to
# re-run — that's the whole point of aliases being editable here.
ssh "${SSHO[@]}" "root@$HOST" '
  for u in robert sofia mattis love; do
    systemctl reset-failed hermes-gateway@$u 2>/dev/null || true
    systemctl enable hermes-gateway@$u >/dev/null 2>&1
    systemctl restart hermes-gateway@$u
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
