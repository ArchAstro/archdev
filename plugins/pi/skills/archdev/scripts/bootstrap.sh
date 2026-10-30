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

version_ok() {
  local version
  checked_version="$("$1" --version 2>/dev/null | head -n 1)" || return 1
  version="$(printf '%s' "$checked_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
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

# A Homebrew install owns its copy. Installing another one elsewhere leaves two
# binaries that are upgraded separately, and whichever comes first on PATH wins.
brew_formula="archastro/tools/archdev"

# Follows symlinks one hop at a time; macOS before 12.3 has no readlink -f.
real_path() {
  local path="$1" link hops=0 directory
  while [[ -L "$path" && "$hops" -lt 32 ]]; do
    link="$(readlink "$path")" || break
    case "$link" in
      /*) path="$link" ;;
      *) path="$(dirname "$path")/$link" ;;
    esac
    hops=$((hops + 1))
  done
  # A dangling keg link still names its Cellar path.
  directory="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || {
    printf '%s\n' "$path"
    return 0
  }
  printf '%s/%s\n' "$directory" "$(basename "$path")"
}

is_homebrew_archdev() {
  case "$(real_path "$1")" in
    */Cellar/archdev/*) return 0 ;;
  esac
  return 1
}

# The Homebrew-managed archdev on PATH, else <brew --prefix>/bin/archdev when
# Homebrew links it there, even if another copy comes first on PATH.
find_homebrew_archdev() {
  local candidate="$1" prefix
  if [[ -n "$candidate" ]] && is_homebrew_archdev "$candidate"; then
    # Keep the link path: an upgrade removes the versioned keg behind it.
    printf '%s/%s\n' "$(cd "$(dirname "$candidate")" && pwd -L)" "$(basename "$candidate")"
    return 0
  fi
  command -v brew >/dev/null 2>&1 || return 1
  prefix="$(brew --prefix 2>/dev/null)" || return 1
  [[ -n "$prefix" ]] || return 1
  if [[ -e "$prefix/bin/archdev" || -L "$prefix/bin/archdev" ]] &&
    is_homebrew_archdev "$prefix/bin/archdev"; then
    printf '%s/bin/archdev\n' "$prefix"
    return 0
  fi
  return 1
}

# Repairs a Homebrew-managed archdev with Homebrew rather than a second copy:
# upgrade when it reports a too-old version; reinstall when the binary is
# missing, crashes, or a current version fails the capability probes, where
# upgrade would be a no-op.
update_homebrew_archdev() {
  local binary="$1" action=reinstall brew version=""
  # The brew that owns this keg; another prefix's brew could install a second copy.
  brew="$(real_path "$binary")"
  brew="${brew%%/Cellar/archdev/*}/bin/brew"
  if [[ ! -x "$brew" ]]; then
    printf 'ArchDev at %s is managed by Homebrew, but %s is missing. Run: brew upgrade %s\n' "$binary" "$brew" "$brew_formula" >&2
    printf 'Not installing a second copy of ArchDev.\n' >&2
    return 1
  fi
  if [[ -x "$binary" ]]; then
    version="$("$binary" --version 2>/dev/null | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  fi
  # Only a readable, too-old version needs an upgrade; anything else is broken.
  if [[ -n "$version" ]] && ! version_ok "$binary"; then
    action=upgrade
  fi
  printf 'Updating Homebrew-managed ArchDev at %s: brew %s %s\n' "$binary" "$action" "$brew_formula" >&2
  if ! "$brew" "$action" "$brew_formula" >&2; then
    printf 'brew %s %s failed. ArchDev at %s is managed by Homebrew; not installing a second copy.\n' "$action" "$brew_formula" "$binary" >&2
    return 1
  fi
}

# Reuse successful checks only within this invocation. Installing or repairing
# the binary leaves this false so the replacement is checked from scratch.
skill_checked=false
checked_version=""
candidate="$(command -v archdev 2>/dev/null || true)"
homebrew_archdev="$(find_homebrew_archdev "$candidate" || true)"
if [[ -n "$homebrew_archdev" ]]; then
  executable="$homebrew_archdev"
  if [[ -n "$candidate" && "$(absolute_path "$candidate")" != "$executable" ]]; then
    printf 'Using Homebrew-managed ArchDev at %s; %s comes first on PATH.\n' "$executable" "$(absolute_path "$candidate")" >&2
  fi
  if supports_skill "$executable"; then
    skill_checked=true
  else
    update_homebrew_archdev "$executable" || exit 1
  fi
else
  if [[ -n "$candidate" ]]; then
    executable="$(absolute_path "$candidate")"
  else
    install_archdev || exit 1
    executable="$(absolute_path "$install_dir/archdev")"
  fi
  if supports_skill "$executable"; then
    skill_checked=true
  else
    printf 'Updating ArchDev: this skill requires 0.49.6+ and repository hook setup with --local.\n' >&2
    install_archdev || exit 1
    executable="$(absolute_path "$install_dir/archdev")"
  fi
fi

[[ -x "$executable" ]] || {
  if [[ -n "$homebrew_archdev" ]]; then
    printf 'Homebrew did not leave an executable at %s; not installing a second copy.\n' "$executable" >&2
  else
    printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  fi
  exit 1
}

if [[ "$skill_checked" != true ]] && ! supports_skill "$executable"; then
  if [[ -n "$homebrew_archdev" ]]; then
    printf 'Homebrew-managed ArchDev at %s still fails the capability check after brew; not installing a second copy.\n' "$executable" >&2
  fi
  printf 'Installed ArchDev lacks required commands or --local hook setup (need 0.49.6+); stopping without a global fallback.\n' >&2
  exit 1
fi
printf '%s\n' "$checked_version" >&2

# Resolving the executable must not choose configuration scope. Install and
# repair hooks only through the approved branch in https://archdev.ai/install.md.
printf '%s\n' "$executable"
