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

supports_agents() {
  "$1" agents run --help 2>/dev/null | grep -Fq "Usage: archdev agents run " &&
    "$1" settings provider models --help 2>/dev/null | grep -Fq "Usage: archdev settings provider models "
}

if ! supports_agents "$executable"; then
  printf 'Updating ArchDev because this version lacks Agents and provider commands.\n' >&2
  install_archdev
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
supports_agents "$executable" || {
  printf 'Installed ArchDev does not provide Agents and provider commands.\n' >&2
  exit 1
}
printf '%s\n' "$executable"
