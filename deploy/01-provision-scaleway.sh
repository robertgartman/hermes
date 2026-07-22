#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 01 — Provision Scaleway: projects, IAM, SSH key, VPS.
#
# Run on your workstation. Requires `scw` configured (`scw init`) and `jq`.
# Idempotent: re-running skips anything that already exists, EXCEPT API keys,
# which are minted fresh only when a member has none saved locally.
#
#   ./deploy/01-provision-scaleway.sh
#
# Writes each member's inference key to KEYDIR (default ~/.hermes-family-keys,
# mode 700, files 600). Those files are the ONLY copy — Scaleway shows a secret
# key exactly once. They are consumed by 03-configure-profiles.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

MEMBERS=(robert sofia mattis love)
ZONE="${ZONE:-fr-par-1}"
TYPE="${TYPE:-DEV1-S}"
IMAGE="${IMAGE:-debian_trixie}"
SERVER_NAME="${SERVER_NAME:-hermes-family}"
INFRA_PROJECT="${INFRA_PROJECT:-hermes-agent}"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_rsa.pub}"
KEYDIR="${KEYDIR:-$HOME/.hermes-family-keys}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v scw >/dev/null || { echo "scw not installed" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq not installed" >&2; exit 1; }
[[ -f "$SSH_PUBKEY" ]] || { echo "no public key at $SSH_PUBKEY" >&2; exit 1; }
scw account project list -o json >/dev/null 2>&1 || { echo "scw not authenticated — run 'scw init'" >&2; exit 1; }

umask 077
mkdir -p "$KEYDIR"

project_id() { scw account project list -o json | jq -r --arg n "$1" '.[]|select(.name==$n)|.id'; }

ensure_project() {
  local name="$1" id
  id="$(project_id "$name")"
  if [[ -z "$id" ]]; then
    id="$(scw account project create name="$name" description="Hermes family setup" -o json | jq -r '.id')"
    echo "  created project $name" >&2
  fi
  printf '%s' "$id"
}

echo "== projects =="
INFRA_ID="$(ensure_project "$INFRA_PROJECT")"
declare -A MEMBER_PROJECT
for m in "${MEMBERS[@]}"; do MEMBER_PROJECT[$m]="$(ensure_project "hermes-$m")"; done
echo "  infra=$INFRA_ID"

# SSH keys are PROJECT-scoped. A key registered elsewhere is not injected into
# instances in this project, and the instance then boots with no way in — a
# reboot does not fix it, because injection happens once at first boot.
echo "== ssh key in $INFRA_PROJECT =="
FINGERPRINT="$(awk '{print $2}' "$SSH_PUBKEY")"
if scw iam ssh-key list -o json | jq -e --arg p "$INFRA_ID" --arg k "$FINGERPRINT" \
     '.[]|select(.project_id==$p and (.public_key|contains($k)))' >/dev/null 2>&1; then
  echo "  already registered"
else
  scw iam ssh-key create name="${INFRA_PROJECT}-key" public-key="$(cat "$SSH_PUBKEY")" \
      project-id="$INFRA_ID" -o json | jq -r '"  registered \(.name)"'
fi

# One IAM application + API key per member, so each gateway carries only its own
# credential. NOTE: the permission set is granted at ORGANIZATION scope, because
# Scaleway's GenerativeApisModelAccess has no effect when scoped to a project —
# a project-scoped grant returns 403 forever. See scaleway-provider.md.
echo "== iam applications, policies, keys =="
ORG_ID="$(scw account project list -o json | jq -r '.[0].organization_id')"
EXPIRY="$(date -u -v+364d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+364 days' +%Y-%m-%dT%H:%M:%SZ)"

for m in "${MEMBERS[@]}"; do
  app_id="$(scw iam application list -o json | jq -r --arg n "hermes-$m" '.[]|select(.name==$n)|.id')"
  if [[ -z "$app_id" ]]; then
    app_id="$(scw iam application create name="hermes-$m" description="Hermes inference for $m" -o json | jq -r '.id')"
  fi

  pol_id="$(scw iam policy list -o json | jq -r --arg n "hermes-$m-inference" '.[]|select(.name==$n)|.id')"
  if [[ -z "$pol_id" ]]; then
    pol_id="$(scw iam policy create name="hermes-$m-inference" \
        description="Generative APIs model access for $m" \
        application-id="$app_id" -o json | jq -r '.id')"
  fi
  scw iam rule update "$pol_id" \
      rules.0.permission-set-names.0=GenerativeApisModelAccess \
      rules.0.organization-id="$ORG_ID" -o json >/dev/null

  if [[ -s "$KEYDIR/$m.env" ]]; then
    echo "  $m: key already saved in $KEYDIR/$m.env (delete it to mint a new one)"
  else
    scw iam api-key create application-id="$app_id" description="hermes-$m gateway" \
        expires-at="$EXPIRY" default-project-id="${MEMBER_PROJECT[$m]}" -o json \
      | jq -r '"OPENAI_API_KEY=\(.secret_key)\nOPENAI_BASE_URL=https://api.scaleway.ai/v1\n# access_key=\(.access_key) expires=\(.expires_at)"' \
      > "$KEYDIR/$m.env"
    chmod 600 "$KEYDIR/$m.env"
    echo "  $m: key minted -> $KEYDIR/$m.env (expires $EXPIRY)"
  fi
done

echo "== instance =="
if scw instance server list zone="$ZONE" -o json | jq -e --arg n "$SERVER_NAME" '.[]|select(.name==$n)' >/dev/null 2>&1; then
  IP="$(scw instance server list zone="$ZONE" -o json | jq -r --arg n "$SERVER_NAME" '.[]|select(.name==$n)|.public_ip.address')"
  echo "  $SERVER_NAME already exists at $IP"
else
  IP="$(scw instance server create zone="$ZONE" project-id="$INFRA_ID" \
      type="$TYPE" image="$IMAGE" name="$SERVER_NAME" ip=new root-volume=l:20GB \
      cloud-init=@"$SCRIPT_DIR/cloud-init-hermes-base.yaml" \
      tags.0=hermes tags.1=family -w -o json | jq -r '.public_ip.address')"
  echo "  created $SERVER_NAME at $IP"
fi

cat <<EOF

Provisioned. Host: $IP

Next:
  ssh -o IdentitiesOnly=yes root@$IP 'cloud-init status --wait'
  ./deploy/02-install-hermes.sh $IP
  ./deploy/03-configure-profiles.sh $IP

Note: our SSH hardening sets MaxAuthTries 3. If your agent holds several keys,
always connect with -o IdentitiesOnly=yes or you will be locked out mid-handshake.
EOF
