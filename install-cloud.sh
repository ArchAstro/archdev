#!/usr/bin/env bash
# Claude Code cloud environment setup, before session variables are available.
# Setup failures must not prevent the environment from starting.
set +e
set +u
set -o pipefail

warn() { printf 'ArchDev cloud setup: %s; continuing without blocking the session.\n' "$1" >&2; }

work_dir="$(mktemp -d)"
if [[ -z "$work_dir" ]]; then
  warn 'could not create temporary directory'
  exit 0
fi
settings_tmp=''
trap 'rm -rf "$work_dir"; [[ -z "$settings_tmp" ]] || rm -f "$settings_tmp"' EXIT

# Download first so a failed or partial transfer cannot execute half a script.
if ! curl -fsSL https://raw.githubusercontent.com/ArchAstro/archdev/main/install.sh -o "$work_dir/install.sh"; then
  warn 'could not download install.sh'
  exit 0
fi
install_dir="${ARCHDEV_INSTALL_DIR:-/usr/local/bin}"
if ! ARCHDEV_INSTALL_DIR="$install_dir" ARCHDEV_INSTALL_SKIP_PATH_UPDATE=true \
  ARCHDEV_INSTALL_SKIP_COMPLETIONS=true bash "$work_dir/install.sh" --version latest; then
  warn 'CLI installation failed'
  exit 0
fi
if ! "$install_dir/archdev" repo hook setup --harness claude --force; then
  warn 'Claude hook installation failed'
  exit 0
fi

# Temporary bridge until released CLI auth resolves ARCHDEV_TOKEN directly.
# Keep the variable literal: setup has no token. Login happens at session start,
# alongside other SessionStart hooks. Claude runs these in parallel, so the
# first presence update can race login; direct env auth (section 3.1) fixes it.
if ! command -v jq >/dev/null 2>&1; then
  warn 'jq is required to install the session login hook'
  exit 0
fi
settings_dir="$HOME/.claude"
settings="$settings_dir/settings.json"
if ! mkdir -p "$settings_dir"; then
  warn 'could not create Claude settings directory'
  exit 0
fi
input="$settings"
if [[ ! -f "$input" ]]; then
  printf '{}\n' >"$work_dir/settings.json"
  input="$work_dir/settings.json"
fi
settings_tmp="$(mktemp "$settings_dir/.cloud-settings.XXXXXX")"
if [[ -z "$settings_tmp" ]]; then
  warn 'could not create temporary Claude settings'
  exit 0
fi
login='[ -z "${ARCHDEV_TOKEN:-}" ] || archdev auth login --token "$ARCHDEV_TOKEN" >/dev/null 2>&1 || true'
if jq --arg login "$login" '
  .hooks.SessionStart = (
    (.hooks.SessionStart // []) |
    if any(.[]; any(.hooks[]?; .command == $login)) then .
    else [{hooks: [{type: "command", command: $login, timeout: 30}]}] + . end
  )
' "$input" >"$settings_tmp" && mv "$settings_tmp" "$settings"; then
  printf 'ArchDev cloud setup complete. Authentication runs when a session starts.\n'
else
  warn 'could not update Claude settings with the session login hook'
fi
exit 0
