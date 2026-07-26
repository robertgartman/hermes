#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# update-dynv6-records.sh <ip>
#
# Points all four family members' subdomains at <ip> via dynv6's REST API v2
# (Bearer-token auth — see 04-enable-api-server.sh for the TSIG-vs-HTTP-
# Token mixup that preceded this and how it got sorted out: the credential
# is an HTTP Token from dynv6.com/keys, NOT a TSIG key, and this script does
# NOT use nsupdate/RFC2136 despite an earlier version assuming it would).
# Run once during initial setup, and again any time the VPS is recreated —
# per the main README, "Resources cannot move between projects... Relocating
# the VPS means recreating it." This script is the fix for that: re-run it
# with the new IP instead of hand-editing DNS records in the dynv6 UI.
#
# Verified against the live API (the OpenAPI spec at dynv6.github.io/api-spec
# didn't load cleanly through available tooling, so this was confirmed with
# real requests instead of trusted from docs):
#   GET   /api/v2/zones                          -> [{name, id, ...}]
#   GET   /api/v2/zones/{zoneID}/records          -> [{type, name, data, id, ...}]
#   PATCH /api/v2/zones/{zoneID}/records/{id}     body: {"data": "<ip>"}
#
# Record IDs are looked up by name on every run rather than hardcoded —
# they're specific to this zone and wouldn't survive a zone recreate.
#
# Reads the shared dynv6 API token from /etc/dynv6/api-token.env
# (root-owned, mode 600, outside every /home/<member> tree — see
# caddy.service for why).
# ---------------------------------------------------------------------------
set -euo pipefail

ZONE="agent-hermes.dynv6.net"
ENV_FILE="/etc/dynv6/api-token.env"
API="https://dynv6.com/api/v2"
IP="${1:?usage: $0 <ip>}"

# 1=robert 2=sofia 3=mattis 4=love — must match 04-enable-api-server.sh and Caddyfile
MEMBERS=(robert sofia mattis love)

[[ $EUID -eq 0 ]] || { echo "must run as root (reads ${ENV_FILE})" >&2; exit 77; }
[[ -r "$ENV_FILE" ]] || { echo "missing ${ENV_FILE} — see the dynv6 API token setup step in the README discussion" >&2; exit 65; }
command -v jq >/dev/null || { echo "jq not found — apt install jq" >&2; exit 65; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${DYNV6_API_TOKEN:?DYNV6_API_TOKEN not set in ${ENV_FILE}}"

AUTH=(-H "Authorization: Bearer ${DYNV6_API_TOKEN}")

zone_id="$(curl -sS "${AUTH[@]}" "${API}/zones" | jq -r --arg z "$ZONE" '.[] | select(.name==$z) | .id')"
[[ -n "$zone_id" ]] || { echo "zone ${ZONE} not found under this API token" >&2; exit 65; }

records_json="$(curl -sS "${AUTH[@]}" "${API}/zones/${zone_id}/records")"

for i in "${!MEMBERS[@]}"; do
  n=$((i + 1))
  record_id="$(echo "$records_json" | jq -r --arg n "$n" '.[] | select(.type=="A" and .name==$n) | .id')"
  [[ -n "$record_id" ]] || { echo "no A record named '${n}' in zone ${ZONE} — create it in the dynv6 UI first" >&2; exit 65; }

  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"${IP}\"}" \
    "${API}/zones/${zone_id}/records/${record_id}")"
  [[ "$code" == "200" ]] || { echo "PATCH failed for ${n}.${ZONE} (HTTP ${code})" >&2; exit 1; }
  echo "  ${n}.${ZONE} (${MEMBERS[$i]}) -> ${IP}"
done
