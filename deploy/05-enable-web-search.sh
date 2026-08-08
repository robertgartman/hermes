#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 05 — Add web query support for every Hermes profile.
#
#   ./deploy/05-enable-web-search.sh <host-ip>
#
# Search uses one private, loopback-only SearXNG container shared by all four
# profiles. Page extraction uses Tavily when a key is supplied through either:
#
#   TAVILY_API_KEY=tvly-... ./deploy/05-enable-web-search.sh <host-ip>
#   ~/.hermes-family-keys/tavily.key
#
# Without a Tavily credential the script still deploys and verifies SearXNG;
# it deliberately leaves web.extract_backend unset instead of advertising a
# broken extractor. Re-run with a key later to enable Tavily idempotently.
# ---------------------------------------------------------------------------
set -euo pipefail

HOST="${1:-}"
[[ -n "$HOST" ]] || { echo "usage: $0 <host-ip>" >&2; exit 64; }

MEMBERS=(robert sofia mattis love)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
KEYDIR="${KEYDIR:-$HOME/.hermes-family-keys}"
TAVILY_KEY_FILE="${TAVILY_KEY_FILE:-$KEYDIR/tavily.key}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSHO=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY")

for required in searxng-settings.yml hermes-searxng.service; do
  [[ -f "$SCRIPT_DIR/$required" ]] || {
    echo "missing deployment asset: $SCRIPT_DIR/$required" >&2
    exit 66
  }
done

tavily_key="${TAVILY_API_KEY:-}"
if [[ -z "$tavily_key" && -s "$TAVILY_KEY_FILE" ]]; then
  tavily_key="$(<"$TAVILY_KEY_FILE")"
fi

echo "== installing daemonless container runtime =="
ssh "${SSHO[@]}" "root@$HOST" '
  set -e
  if ! command -v podman >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman
  fi
  podman --version
'

echo "== deploying private SearXNG =="
scp "${SSHO[@]}" \
  "$SCRIPT_DIR/searxng-settings.yml" "$SCRIPT_DIR/hermes-searxng.service" \
  "root@$HOST:/root/" >/dev/null
ssh "${SSHO[@]}" "root@$HOST" '
  set -euo pipefail
  install -d -m 755 /etc/hermes-searxng
  install -m 644 /root/searxng-settings.yml /etc/hermes-searxng/settings.yml
  rm -f /root/searxng-settings.yml

  if [[ -s /etc/hermes-searxng.env ]]; then
    secret="$(sed -n "s/^SEARXNG_SECRET=//p" /etc/hermes-searxng.env | head -1)"
  else
    secret=""
  fi
  [[ -n "$secret" ]] || secret="$(openssl rand -hex 32)"
  env_tmp="$(mktemp /etc/hermes-searxng.env.XXXXXX)"
  umask 077
  printf "SEARXNG_SECRET=%s\nSEARXNG_BASE_URL=http://127.0.0.1:8888/\nSEARXNG_PORT=8888\nGRANIAN_HOST=127.0.0.1\nGRANIAN_WORKERS=1\nSEARXNG_LIMITER=false\nSEARXNG_PUBLIC_INSTANCE=false\nSEARXNG_IMAGE_PROXY=false\n" \
    "$secret" > "$env_tmp"
  chown root:root "$env_tmp"
  chmod 600 "$env_tmp"
  mv -f "$env_tmp" /etc/hermes-searxng.env

  install -m 644 /root/hermes-searxng.service /etc/systemd/system/hermes-searxng.service
  rm -f /root/hermes-searxng.service

  image="docker.io/searxng/searxng@sha256:5d6d903ab82afa56ee32792d477f36bc63d3e5ca04fcb6947e28a5cfd987fad3"
  podman pull "$image"
  systemctl daemon-reload
  systemctl enable hermes-searxng.service
  systemctl restart hermes-searxng.service

  ready=false
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 15 "http://127.0.0.1:8888/search?q=official+SearXNG+documentation&format=json" \
      | jq -e ".results | (type == \"array\" and length > 0)" >/dev/null; then
      ready=true
      break
    fi
    sleep 1
  done
  [[ "$ready" == true ]] || {
    journalctl -u hermes-searxng.service --no-pager -n 80 >&2
    exit 1
  }

  systemctl is-active hermes-searxng.service
  ss -ltn | grep -Eq "127\\.0\\.0\\.1:8888[[:space:]]" || {
    echo "SearXNG is not bound to loopback:8888" >&2
    exit 1
  }
  if ss -ltn | grep -Eq "(^|[[:space:]])(0\\.0\\.0\\.0|\\[::\\]):8888[[:space:]]"; then
    echo "SearXNG unexpectedly has a wildcard listener" >&2
    exit 1
  fi
'

echo "== configuring Hermes profiles =="
for m in "${MEMBERS[@]}"; do
  if [[ -n "$tavily_key" ]]; then
    printf 'SEARXNG_URL=http://127.0.0.1:8888\nTAVILY_API_KEY=%s\n' "$tavily_key"
  else
    printf 'SEARXNG_URL=http://127.0.0.1:8888\n'
  fi \
    | ssh "${SSHO[@]}" "root@$HOST" "/root/configure-profile.sh $m -" \
    | sed "s/^/  [$m] /"
done

ssh "${SSHO[@]}" "root@$HOST" '
  set -euo pipefail
  for u in robert sofia mattis love; do
    R="sudo -u $u -H env PATH=/usr/local/bin:/usr/bin:/bin HERMES_HOME=/home/$u/.hermes"
    $R hermes config set web.search_backend searxng >/dev/null 2>&1
    $R hermes config set auxiliary.web_extract.reasoning_effort none >/dev/null 2>&1
    if grep -q "^TAVILY_API_KEY=." "/home/$u/.hermes/.env"; then
      $R hermes config set web.extract_backend tavily >/dev/null 2>&1
      extract=tavily
    else
      $R hermes config unset web.extract_backend >/dev/null 2>&1 || true
      extract=unconfigured
    fi
    systemctl restart "hermes-gateway@$u.service"
    sleep 3
    systemctl is-active --quiet "hermes-gateway@$u.service"
    echo "  $u -> search:searxng extract:$extract web_extract_reasoning:none"
  done
'

if ssh "${SSHO[@]}" "root@$HOST" '
  for u in robert sofia mattis love; do
    grep -q "^TAVILY_API_KEY=." "/home/$u/.hermes/.env" || exit 1
  done
'; then
  tavily_configured=true
else
  tavily_configured=false
fi

echo "== direct provider verification =="
ssh "${SSHO[@]}" "root@$HOST" '
  set -euo pipefail
  for u in robert sofia mattis love; do
    result="$(sudo -u "$u" -H env \
      PATH=/usr/local/lib/hermes-agent/venv/bin:/usr/local/bin:/usr/bin:/bin \
      HERMES_HOME="/home/$u/.hermes" \
      /usr/local/lib/hermes-agent/venv/bin/python -c \
      "from tools.web_tools import web_search_tool; print(web_search_tool(\"official SearXNG documentation\", 3))")"
    if ! printf "%s" "$result" | jq -e ".success == true and (.data.web | length > 0)" >/dev/null; then
      echo "  $u: failed: $result" >&2
      exit 1
    fi
    count="$(printf "%s" "$result" | jq ".data.web | length")"
    echo "  $u: $count results"
  done

  if grep -q "^TAVILY_API_KEY=." /home/robert/.hermes/.env; then
    extract_result="$(sudo -u robert -H env \
      PATH=/usr/local/lib/hermes-agent/venv/bin:/usr/local/bin:/usr/bin:/bin \
      HERMES_HOME=/home/robert/.hermes \
      /usr/local/lib/hermes-agent/venv/bin/python -c \
      "import asyncio; from tools.web_tools import web_extract_tool; print(asyncio.run(web_extract_tool([\"https://example.com/\"])))")"
    if ! printf "%s" "$extract_result" \
      | jq -e ".results[0] | (.error == null and (.content | length > 0))" >/dev/null; then
      echo "  Tavily extraction failed: $extract_result" >&2
      exit 1
    fi
    echo "  tavily: example.com extracted successfully"
  fi
  podman stats --no-stream --format "  memory={{.MemUsage}} cpu={{.CPU}} pids={{.PIDs}}" hermes-searxng
'

if [[ "$tavily_configured" == true ]]; then
  echo "Tavily extraction is active and verified."
else
  cat <<EOF
SearXNG search is active and verified. Tavily extraction remains intentionally
disabled because no credential was found. Save a key at:
  $TAVILY_KEY_FILE
then re-run this script.
EOF
fi
