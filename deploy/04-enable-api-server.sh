#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 04 — Enable the hermes-agent API server for all four members and put a
# lightweight Caddy reverse proxy in front of it: one FQDN per member, real
# Let's Encrypt certs via dynv6 DNS-01, no VPN needed for phone clients.
#
#   ./deploy/04-enable-api-server.sh <host-ip>
#
# Prerequisites (each is a deliberate choice, not an oversight — see the
# design discussion this script came out of):
#   - /etc/dynv6/api-token.env already placed on the host: root:root, mode
#     600, DYNV6_API_TOKEN=<HTTP Token from dynv6.com/keys — NOT the TSIG
#     key page, that's a different credential dynv6-plugin doesn't use>,
#     deliberately outside every /home/<member> tree so no
#     hermes-gateway@<member> process can read a credential that can
#     rewrite DNS + certs for everyone.
#   - dynv6 zone agent-hermes.dynv6.net exists with A records for 1..4
#     (this script's last step fills in the actual IP).
#
# What this script deliberately does NOT do: apply the host firewall
# ruleset it deploys, or touch the Scaleway security group. Both are
# printed as manual last steps — see the final output. A firewall change
# that can lock you out of the box over the same SSH session is worth doing
# by hand with a second terminal open to verify recovery, not buried inside
# an unattended script.
#
# Safe to re-run: configure-profile.sh merges .env (doesn't truncate), the
# Caddy install/config steps are idempotent, DNS record pushes are
# idempotent (delete-then-add).
# ---------------------------------------------------------------------------
set -euo pipefail

HOST="${1:-}"
[[ -n "$HOST" ]] || { echo "usage: $0 <host-ip>" >&2; exit 64; }

# 1=robert 2=sofia 3=mattis 4=love — must match Caddyfile and update-dynv6-records.sh
MEMBERS=(robert sofia mattis love)
BASE_PORT=8642

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
KEYDIR="${KEYDIR:-$HOME/.hermes-family-keys}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSHO=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY")

echo "== per-member API server credentials =="
# Mirrors the ~/.hermes-family-keys/<member>.env convention from step 01: the
# generated bearer tokens need to survive this script run, because they're
# what you'll type into each member's phone client afterwards.
mkdir -p "$KEYDIR/api-server"
chmod 700 "$KEYDIR/api-server"
for i in "${!MEMBERS[@]}"; do
  m="${MEMBERS[$i]}"
  port=$((BASE_PORT + i))
  keyfile="$KEYDIR/api-server/$m.key"
  if [[ ! -s "$keyfile" ]]; then
    ( umask 077 && openssl rand -hex 32 > "$keyfile" )
  fi
  printf 'API_SERVER_ENABLED=true\nAPI_SERVER_KEY=%s\nAPI_SERVER_PORT=%s\n' \
    "$(cat "$keyfile")" "$port" \
    | ssh "${SSHO[@]}" "root@$HOST" "/root/configure-profile.sh $m -" \
    | sed "s/^/  [$m] /"
done

echo "== dynv6 API token present? =="
ssh "${SSHO[@]}" "root@$HOST" '
  test -r /etc/dynv6/api-token.env || { echo "missing /etc/dynv6/api-token.env" >&2; exit 65; }
  grep -q "^DYNV6_API_TOKEN=" /etc/dynv6/api-token.env || { echo "/etc/dynv6/api-token.env has no DYNV6_API_TOKEN" >&2; exit 65; }
  echo "  ok"
'

echo "== building Caddy locally (dynv6 DNS-01 plugin isn't in caddyserver.com's download catalog — cross-compiling with xcaddy beats installing a Go toolchain on the 2GB VPS) =="
command -v go >/dev/null || { echo "go not found locally — required to cross-compile Caddy" >&2; exit 65; }
XCADDY="$(go env GOPATH)/bin/xcaddy"
[[ -x "$XCADDY" ]] || go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
GOOS=linux GOARCH=amd64 "$XCADDY" build --with github.com/caddy-dns/dynv6 --output "$BUILD_DIR/caddy"

echo "== installing Caddy on the host =="
scp "${SSHO[@]}" "$BUILD_DIR/caddy" "root@$HOST:/root/caddy" >/dev/null
ssh "${SSHO[@]}" "root@$HOST" '
  set -e
  install -m 755 /root/caddy /usr/local/bin/caddy
  rm -f /root/caddy
  id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin caddy
  mkdir -p /etc/caddy /var/lib/caddy
  chown caddy:caddy /var/lib/caddy
  # jq: used by update-dynv6-records.sh to parse the REST API responses
  # (not nsupdate/dnsutils — that was the earlier, confirmed-wrong TSIG
  # approach; the API this actually uses is plain HTTPS+JSON)
  command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq; }
'

echo "== deploying Caddyfile, unit, DNS-update script, firewall ruleset =="
scp "${SSHO[@]}" \
  "$SCRIPT_DIR/Caddyfile" "$SCRIPT_DIR/caddy.service" \
  "$SCRIPT_DIR/update-dynv6-records.sh" "$SCRIPT_DIR/nftables-hermes.conf" \
  "root@$HOST:/root/" >/dev/null
ssh "${SSHO[@]}" "root@$HOST" '
  set -e
  mv /root/Caddyfile /etc/caddy/Caddyfile
  chown -R caddy:caddy /etc/caddy
  mv /root/caddy.service /etc/systemd/system/caddy.service
  install -m 755 /root/update-dynv6-records.sh /usr/local/sbin/update-dynv6-records.sh
  install -d -m 755 /etc/nftables-hermes
  mv /root/nftables-hermes.conf /etc/nftables-hermes/hermes.conf
  systemctl daemon-reload
'

echo "== pushing DNS A records (dynv6 REST API) =="
ssh "${SSHO[@]}" "root@$HOST" "/usr/local/sbin/update-dynv6-records.sh '$HOST'"

echo "== starting Caddy =="
ssh "${SSHO[@]}" "root@$HOST" '
  systemctl enable --now caddy
  sleep 2
  systemctl is-active caddy
'

cat <<EOF

== done ==

Per-member API server URLs (certs may take a few seconds to a couple of
minutes to issue on first request — Caddy does it lazily, on first connect):

  robert  https://1.agent-hermes.dynv6.net
  sofia   https://2.agent-hermes.dynv6.net
  mattis  https://3.agent-hermes.dynv6.net
  love    https://4.agent-hermes.dynv6.net

Bearer tokens for each member's client app (Chatbox etc. — Authorization:
Bearer <token>) live at, on THIS machine, not the host:
  $KEYDIR/api-server/<member>.key

Verify one member end-to-end before configuring phones:
  curl https://1.agent-hermes.dynv6.net/v1/chat/completions \\
    -H "Authorization: Bearer \$(cat $KEYDIR/api-server/robert.key)" \\
    -H "Content-Type: application/json" \\
    -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello!"}]}'

Two things intentionally left for you to do by hand, not this script:

1. Host firewall (closes README open item #3). The ruleset is already on
   the host at /etc/nftables-hermes/hermes.conf. Apply it yourself, with a
   SECOND terminal open on a fresh SSH connection before you close this one:
     ssh root@$HOST 'nft -c -f /etc/nftables-hermes/hermes.conf'   # syntax check
     ssh root@$HOST 'nft -f /etc/nftables-hermes/hermes.conf'      # apply
     ssh -o IdentitiesOnly=yes -i $SSH_KEY root@$HOST 'echo still alive'  # verify from a NEW connection
     ssh root@$HOST 'apt-get install -y nftables && systemctl enable nftables'  # persist across reboot

2. Scaleway security group — the cloud-level firewall in front of the host,
   separate from the above. Only 443 needs to be open (not 80 — DNS-01
   doesn't use it); 22 should already be open since you can SSH in today.
   Check current rules and add 443 if missing:
     scw instance security-group-rule list security-group-id=<id-from-scw-instance-server-list>
   The exact create-rule subcommand wasn't independently verified against
   your installed scw version — run --help before trusting any example
   syntax here.
EOF
