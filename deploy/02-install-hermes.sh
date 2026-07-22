#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 02 — Install Hermes on the host, once, system-wide.
#
#   ./deploy/02-install-hermes.sh <host-ip>
#
# Installs as root so Hermes uses its FHS layout: code in
# /usr/local/lib/hermes-agent, command at /usr/local/bin/hermes. Each family
# member then gets their own HERMES_HOME under their own home directory, so a
# single 2.2 GB code tree is shared by all four instead of copied per user.
#
# Flags that matter on a 2 GB / 20 GB box:
#   --skip-browser   omit Playwright/Chromium (the default install pulls a
#                    headless browser and an Electron desktop build)
#   --skip-setup     no interactive wizard; profiles are configured by step 03
#   --commit <sha>   pin the checkout, so a rebuild reproduces this deployment
#
# The installer itself is checksum-verified before execution. If upstream
# changes install.sh the run aborts rather than silently executing new code.
# Update INSTALLER_SHA deliberately after reviewing the diff.
# ---------------------------------------------------------------------------
set -euo pipefail

HOST="${1:-}"
[[ -n "$HOST" ]] || { echo "usage: $0 <host-ip>" >&2; exit 64; }

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
INSTALLER_SHA="${INSTALLER_SHA:-c5ba7e89627577fab914514736ecfb3359b66956ca00199bfef616ca35953cb9}"
PIN_COMMIT="${PIN_COMMIT:-f13f845116941ac5616e8df3294f3379a3efeb20}"

ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY" "root@$HOST" \
  "cat > /root/install-hermes.sh" <<REMOTE
#!/bin/bash
set -euo pipefail
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /root/hermes-install.sh
echo "${INSTALLER_SHA}  /root/hermes-install.sh" | sha256sum -c - || {
  echo "!!! installer checksum mismatch — upstream changed install.sh; aborting"
  echo "    got: \$(sha256sum /root/hermes-install.sh | cut -d' ' -f1)"
  exit 90
}
HOME=/root bash /root/hermes-install.sh --skip-setup --skip-browser --non-interactive --commit "${PIN_COMMIT}"
echo DONE > /root/.hermes-install-done
REMOTE

# systemd-run detaches the ~6 minute install from the SSH session. HOME must be
# set explicitly: without it the installer resolves HERMES_HOME to "/.hermes"
# and litters the filesystem root.
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i "$SSH_KEY" "root@$HOST" '
  chmod +x /root/install-hermes.sh
  rm -f /root/.hermes-install-done
  systemctl reset-failed hermes-install 2>/dev/null || true
  systemd-run --unit=hermes-install --collect --quiet --setenv=HOME=/root /root/install-hermes.sh
  echo "installing (~6 min)..."
  for i in $(seq 1 90); do
    [ -f /root/.hermes-install-done ] && break
    systemctl is-active --quiet hermes-install || break
    sleep 10
  done
  if [ -f /root/.hermes-install-done ]; then
    echo "OK: $(/usr/local/bin/hermes --version 2>&1 | head -1)"
  else
    echo "FAILED — journalctl -u hermes-install" >&2
    journalctl -u hermes-install --no-pager -n 20
    exit 1
  fi
'
