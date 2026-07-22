#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAMES=("robert" "sofia" "mattis" "love")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-$(id -un)}}"
DEPLOY_HOME="${DEPLOY_HOME:-$(eval echo "~${DEPLOY_USER}")}"
HERMES_BIN="${HERMES_BIN:-${DEPLOY_HOME}/.local/bin/hermes}"
SYSTEMD_FILE="/etc/systemd/system/hermes-gateway@.service"
ENABLE_NOW="${ENABLE_NOW:-false}"

if [[ ! -x "${HERMES_BIN}" ]]; then
  if command -v hermes >/dev/null 2>&1; then
    HERMES_BIN="$(command -v hermes)"
  fi
fi

if [[ ! -x "${HERMES_BIN}" ]]; then
  echo "hermes binary not found. Install Hermes first." >&2
  exit 1
fi

if [[ "${EUID}" -eq 0 && "${DEPLOY_USER}" == "root" ]]; then
  echo "Warning: DEPLOY_USER resolved to root. Set DEPLOY_USER to your Linux user if you want non-root services."
fi

run_hermes() {
  if [[ "$(id -un)" == "${DEPLOY_USER}" ]]; then
    PATH="${DEPLOY_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" "${HERMES_BIN}" "$@"
  else
    sudo -u "${DEPLOY_USER}" env PATH="${DEPLOY_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" "${HERMES_BIN}" "$@"
  fi
}

profile_exists() {
  local profile="$1"
  run_hermes profile list | awk '{print $1}' | grep -Fxq "${profile}"
}

create_profiles() {
  for profile in "${PROFILE_NAMES[@]}"; do
    if profile_exists "${profile}"; then
      echo "Profile ${profile} already exists."
    else
      echo "Creating profile ${profile}..."
      run_hermes profile create "${profile}"
    fi
  done
}

write_env_file() {
  local profile="$1"
  local env_path="${DEPLOY_HOME}/.hermes/profiles/${profile}/.env"
  local backup_path="${env_path}.bak.$(date +%Y%m%d%H%M%S)"

  if [[ -f "${env_path}" ]]; then
    cp "${env_path}" "${backup_path}"
    echo "Backed up ${env_path} -> ${backup_path}"
  fi

  cat > "${env_path}" <<EOF
# ------------------------------
# Hermes MVP profile: ${profile}
# Fill these values, then restart this profile service.
# ------------------------------

# Inference key (recommended: one key per profile)
OPENROUTER_API_KEY=

# MVP mode: messaging only, no web API server
API_SERVER_ENABLED=false

# OPTIONAL: set stricter command safety
# approvals.mode=smart

# Messaging preferences for this profile:
# robert -> Slack + WhatsApp
# sofia  -> WhatsApp
# mattis -> Discord + WhatsApp
# love   -> Discord + WhatsApp

# IMPORTANT:
# Use "hermes -p ${profile} setup" to configure the exact platform tokens
# and platform-specific settings for this profile.
EOF

  if [[ "$(id -un)" == "${DEPLOY_USER}" ]]; then
    chmod 600 "${env_path}"
  else
    chown "${DEPLOY_USER}" "${env_path}"
    chmod 600 "${env_path}"
  fi
  echo "Wrote ${env_path}"
}

write_env_files() {
  for profile in "${PROFILE_NAMES[@]}"; do
    write_env_file "${profile}"
  done
}

write_systemd_template() {
  local tmp_file
  tmp_file="$(mktemp)"

  cat > "${tmp_file}" <<EOF
[Unit]
Description=Hermes Gateway (%i profile)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${DEPLOY_USER}
WorkingDirectory=${DEPLOY_HOME}
ExecStart=/usr/bin/env PATH=${DEPLOY_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin ${HERMES_BIN} -p %i gateway
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

  if [[ "${EUID}" -eq 0 ]]; then
    cp "${tmp_file}" "${SYSTEMD_FILE}"
  else
    sudo cp "${tmp_file}" "${SYSTEMD_FILE}"
  fi

  rm -f "${tmp_file}"
  echo "Updated ${SYSTEMD_FILE}"
}

enable_services() {
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl daemon-reload
    for profile in "${PROFILE_NAMES[@]}"; do
      if [[ "${ENABLE_NOW}" == "true" ]]; then
        systemctl enable --now "hermes-gateway@${profile}"
      else
        systemctl enable "hermes-gateway@${profile}"
      fi
    done
  else
    sudo systemctl daemon-reload
    for profile in "${PROFILE_NAMES[@]}"; do
      if [[ "${ENABLE_NOW}" == "true" ]]; then
        sudo systemctl enable --now "hermes-gateway@${profile}"
      else
        sudo systemctl enable "hermes-gateway@${profile}"
      fi
    done
  fi
}

print_next_steps() {
  cat <<'EOF'

Scaffold complete.

Next steps (required):
  1) Configure per-profile platform creds:
       hermes -p robert setup
       hermes -p sofia setup
       hermes -p mattis setup
       hermes -p love setup

  2) Start profile services (after setup):
       sudo systemctl restart hermes-gateway@robert
       sudo systemctl restart hermes-gateway@sofia
       sudo systemctl restart hermes-gateway@mattis
       sudo systemctl restart hermes-gateway@love

  3) Verify services:
       systemctl status hermes-gateway@robert --no-pager
       systemctl status hermes-gateway@sofia --no-pager
       systemctl status hermes-gateway@mattis --no-pager
       systemctl status hermes-gateway@love --no-pager

  4) Tail logs for one profile:
       journalctl -u hermes-gateway@robert -f
EOF
}

main() {
  create_profiles
  write_env_files
  write_systemd_template
  enable_services
  print_next_steps
}

main "$@"
