#!/usr/bin/env bash

set -euo pipefail

installer_revision="9d50e7ce1e64a731d88cca8ae15ec2c45b1375df"
installer_url="https://raw.githubusercontent.com/ArchAstro/archdev/${installer_revision}/install.sh"
installer_sha256="04bde605fce1b3b2b33e13d730e31012e9fa53bce18465befd87b243ee70ffb2"
install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"
min_version="0.45.1"

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
    "$1" agents run --help 2>/dev/null | grep -Fq "Usage: archdev agents run " &&
    "$1" settings provider models --help 2>/dev/null | grep -Fq "Usage: archdev settings provider models " &&
    "$1" repo status --help 2>/dev/null | grep -Fq "Probe CLI, login, model access"
}

if ! supports_skill "$executable"; then
  printf 'Updating ArchDev because this version lacks Agents, provider, or repo commands (need 0.45.1+).\n' >&2
  install_archdev || exit 1
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
supports_skill "$executable" || {
  printf 'Installed ArchDev does not provide Agents, provider, and repo commands.\n' >&2
  exit 1
}
printf '%s\n' "$executable"
