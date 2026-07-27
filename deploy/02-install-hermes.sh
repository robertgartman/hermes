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

# Messaging platform dependencies, installed once here at build time.
#
# Hermes can lazy-install these on first use (tools/lazy_deps.py), but the
# gateway units run under ProtectSystem=full, so /usr/local/lib is read-only to
# them and the lazy path can never succeed on this host. Without this step,
# adding any channel later fails at runtime with
#   Platform 'Discord' requirements not met (pip install 'hermes-agent[messaging]')
# and the gateway starts with no platforms connected.
#
# Specs are read from the pinned tree's own LAZY_DEPS table rather than
# duplicated here, so they cannot drift from PIN_COMMIT.
VENV_PY=/usr/local/lib/hermes-agent/venv/bin/python
SPECS=\$(\$VENV_PY <<PYEOF
import sys
sys.path.insert(0, "/usr/local/lib/hermes-agent")
from tools.lazy_deps import LAZY_DEPS
want = ("platform.discord", "platform.slack", "platform.telegram")
print(" ".join(dict.fromkeys(s for k in want for s in LAZY_DEPS[k])))
PYEOF
)
# SPECS must word-split into separate arguments, but contains extras brackets
# (discord.py[voice]) that the shell would glob. Disable globbing across it.
# The venv is uv-created and has no pip; use the uv the installer dropped.
set -f
/root/.hermes/bin/uv pip install --python "\$VENV_PY" \$SPECS
set +f

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
    # Bundled skills (google-workspace among them) invoke `python` or `python3`
    # interchangeably — the model picks whichever name it reaches for, and
    # both need to land on the same interpreter. Debian ships neither, and the
    # agent shell tool runs with a sanitized PATH (/usr/local/bin:/usr/bin:/bin:...)
    # that excludes the Hermes venv — so without this, bare `python` fails
    # outright and bare `python3` silently resolves to the system interpreter
    # (present on Debian, unlike `python`) with none of the skill deps
    # installed: ModuleNotFoundError, then the agent burns its tool budget
    # trying to self-heal via pip (no pip in that interpreter), uv (not on
    # this PATH — see README), and apt-get (not root) before giving up.
    # Reproduced 2026-07-27 via both the API server and the CLI directly.
    # A symlink does NOT work for either name: it resolves through to the uv
    # interpreter, which then cannot see the venv site-packages. exec the venv
    # interpreter by its own path instead, for both names.
    for bin in python python3; do
      cat > "/usr/local/bin/$bin" <<"EOF"
#!/bin/sh
exec /usr/local/lib/hermes-agent/venv/bin/python "$@"
EOF
      chmod 755 "/usr/local/bin/$bin"
      echo "OK: $bin wrapper -> venv ($(/usr/local/bin/$bin -V 2>&1))"
    done
  else
    echo "FAILED — journalctl -u hermes-install" >&2
    journalctl -u hermes-install --no-pager -n 20
    exit 1
  fi
'
