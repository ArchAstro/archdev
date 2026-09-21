#!/usr/bin/env bash

set -euo pipefail

installer_revision="9d50e7ce1e64a731d88cca8ae15ec2c45b1375df"
installer_url="https://raw.githubusercontent.com/ArchAstro/archdev/${installer_revision}/install.sh"
installer_sha256="04bde605fce1b3b2b33e13d730e31012e9fa53bce18465befd87b243ee70ffb2"
install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"

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

supports_rooms() {
  local help_text
  "$1" rooms start --help >/dev/null 2>&1 || return 1
  help_text="$("$1" rooms search --help 2>/dev/null)" || return 1
  grep -Fq -- '--messages' <<<"$help_text"
}

if ! supports_rooms "$executable"; then
  printf 'Updating ArchDev because this version lacks Rooms lifecycle or Knowledge search commands.\n' >&2
  install_archdev || exit 1
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
supports_rooms "$executable" || {
  printf 'Installed ArchDev does not provide Rooms lifecycle and Knowledge search commands.\n' >&2
  exit 1
}
printf '%s\n' "$executable"
