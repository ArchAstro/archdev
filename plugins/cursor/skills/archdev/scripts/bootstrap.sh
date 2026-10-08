#!/usr/bin/env bash

set -euo pipefail

installer_revision="a530d21dd04eaed5742b8ad7daf9140a3ee2ef0f"
installer_url="https://raw.githubusercontent.com/ArchAstro/archdev/${installer_revision}/install.sh"
installer_sha256="f838ca858f7db526cdf2a2697001ae1d404edf3df93617e525efa9d171be7e64"
install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"
min_version="0.49.6"

absolute_path() {
  local candidate="$1"
  local directory
  directory="$(cd -P "$(dirname "$candidate")" && pwd)"
  printf '%s/%s\n' "$directory" "$(basename "$candidate")"
}

install_archdev() (
  # Keep downloaded code private and verify its reviewed bytes before execution.
  umask 077
  installer_file="$(mktemp "${TMPDIR:-/tmp}/archdev-installer.XXXXXX")" || {
    printf 'Could not create a private ArchDev installer file.\n' >&2
    exit 1
  }
  trap 'rm -f "$installer_file"' EXIT
  trap 'exit 1' HUP INT TERM
  if ! curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --output "$installer_file" "$installer_url"; then
    printf 'Could not download the pinned ArchDev installer.\n' >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha256="$(sha256sum "$installer_file")" || {
      printf 'Could not hash the ArchDev installer.\n' >&2
      exit 1
    }
  elif command -v shasum >/dev/null 2>&1; then
    actual_sha256="$(shasum -a 256 "$installer_file")" || {
      printf 'Could not hash the ArchDev installer.\n' >&2
      exit 1
    }
  else
    printf 'ArchDev installer verification requires sha256sum or shasum.\n' >&2
    exit 1
  fi
  if [[ "${actual_sha256%% *}" != "$installer_sha256" ]]; then
    printf 'ArchDev installer SHA-256 mismatch; refusing to execute it.\n' >&2
    exit 1
  fi
  if ! ARCHDEV_INSTALL_DIR="$install_dir" \
    ARCHDEV_RELEASE_BASE_URL= \
    ARCHDEV_INSTALL_SKIP_VERIFY=false \
    ARCHDEV_INSTALL_SKIP_PATH_UPDATE=true \
    ARCHDEV_INSTALL_SKIP_COMPLETIONS=true \
    bash "$installer_file" >&2; then
    printf 'Verified ArchDev installer failed.\n' >&2
    exit 1
  fi
)

candidate="$(command -v archdev 2>/dev/null || true)"
if [[ -n "$candidate" ]]; then
  executable="$(absolute_path "$candidate")"
else
  install_archdev || exit 1
  executable="$(absolute_path "$install_dir/archdev")"
fi

version_ok() {
  local raw version
  raw="$("$1" --version 2>/dev/null | head -n 1)"
  version="$(printf '%s' "$raw" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
  [[ -n "$version" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$min_version" "$version" | sort -V | head -n 1)" == "$min_version" ]]
}

supports_skill() {
  version_ok "$1" &&
    "$1" agents run --help 2>/dev/null | grep -F "Usage: archdev agents run " >/dev/null &&
    "$1" settings provider models --help 2>/dev/null | grep -F "Usage: archdev settings provider models " >/dev/null &&
    "$1" repo status --help 2>/dev/null | grep -F "Probe CLI, login, model access" >/dev/null &&
    "$1" projects list --help 2>/dev/null | grep -F "Usage: archdev projects list " >/dev/null &&
    "$1" log post --help 2>/dev/null | grep -F -- "--project <id>" >/dev/null &&
    "$1" repo hook setup --help 2>/dev/null | grep -F -- "--local" >/dev/null
}

if ! supports_skill "$executable"; then
  printf 'Updating ArchDev: this skill requires 0.49.6+ and repository hook setup with --local.\n' >&2
  install_archdev || exit 1
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
supports_skill "$executable" || {
  printf 'Installed ArchDev lacks required commands or --local hook setup (need 0.49.6+); stopping without a global fallback.\n' >&2
  exit 1
}

# Resolving the executable must not choose configuration scope. Install and
# repair hooks only through the approved branch in https://archdev.ai/install.md.
printf '%s\n' "$executable"
