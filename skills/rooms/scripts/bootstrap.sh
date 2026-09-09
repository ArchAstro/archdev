#!/usr/bin/env bash

set -euo pipefail

installer_revision="9d50e7ce1e64a731d88cca8ae15ec2c45b1375df"
installer_url="${ARCHDEV_INSTALLER_URL:-https://raw.githubusercontent.com/ArchAstro/archdev/${installer_revision}/install.sh}"
install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"

absolute_path() {
  local candidate="$1"
  local directory
  directory="$(cd -P "$(dirname "$candidate")" && pwd)"
  printf '%s/%s\n' "$directory" "$(basename "$candidate")"
}

install_archdev() {
  curl --fail --silent --show-error --location "$installer_url" |
    ARCHDEV_INSTALL_DIR="$install_dir" \
      ARCHDEV_INSTALL_SKIP_PATH_UPDATE=true \
      ARCHDEV_INSTALL_SKIP_COMPLETIONS=true \
      bash >&2
}

candidate="$(command -v archdev 2>/dev/null || true)"
if [[ -n "$candidate" ]]; then
  executable="$(absolute_path "$candidate")"
else
  install_archdev
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
  install_archdev
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
