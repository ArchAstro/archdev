#!/usr/bin/env bash

set -euo pipefail

installer_revision="7c16002d66a004b13812cf675042cb1c50fbf6df"
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

if ! "$executable" tasks review update --help >/dev/null 2>&1; then
  printf 'Updating ArchDev because this version lacks Tasks web review commands.\n' >&2
  install_archdev
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
"$executable" tasks review update --help >/dev/null 2>&1 || {
  printf 'Installed ArchDev does not provide Tasks web review commands.\n' >&2
  exit 1
}
printf '%s\n' "$executable"
