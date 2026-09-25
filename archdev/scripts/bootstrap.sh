#!/usr/bin/env bash

set -euo pipefail

installer_revision="9d50e7ce1e64a731d88cca8ae15ec2c45b1375df"
installer_url="https://raw.githubusercontent.com/ArchAstro/archdev/${installer_revision}/install.sh"
installer_sha256="04bde605fce1b3b2b33e13d730e31012e9fa53bce18465befd87b243ee70ffb2"
install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"
min_version="0.46.5"

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
    "$1" repo status --help 2>/dev/null | grep -Fq "Probe CLI, login, model access" &&
    "$1" projects list --help 2>/dev/null | grep -Fq "Usage: archdev projects list " &&
    "$1" log post --help 2>/dev/null | grep -Fq -- "--project <id>" &&
    "$1" extract finalize --help 2>/dev/null | grep -Fq -- "--publish <pull>"
}

if ! supports_skill "$executable"; then
  printf 'Updating ArchDev because this version lacks Agents, provider, repo, projects, log --project, or extract finalize --publish commands (need 0.46.5+).\n' >&2
  install_archdev || exit 1
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installer did not create an executable at %s\n' "$executable" >&2
  exit 1
}

"$executable" --version >&2
supports_skill "$executable" || {
  printf 'Installed ArchDev does not provide Agents, provider, repo, and projects commands.\n' >&2
  exit 1
}

# Ensure ArchDev hooks for the harness running this skill, so the monitor
# contract reaches later sessions even when they never load the skill. The
# harness comes from the marker it sets on the shells it spawns.
calling_harness() {
  if [[ "${CLAUDECODE:-}" == 1 ]]; then
    printf 'claude\n'
  elif [[ -n "${CODEX_THREAD_ID:-}" ]]; then
    printf 'codex\n'
  elif [[ -n "${GROK_SESSION_ID:-}" ]]; then
    printf 'grok\n'
  fi
}

# The file each harness reads hooks from; keep in step with the CLI's
# harnessHookFile.
harness_hook_file() {
  case "$1" in
    claude) printf '%s/settings.json\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    codex) printf '%s/hooks.json\n' "${CODEX_HOME:-$HOME/.codex}" ;;
    grok) printf '%s/hooks/archdev.json\n' "${GROK_HOME:-$HOME/.grok}" ;;
  esac
}

# Whether the harness config already carries a hook command archdev wrote.
has_archdev_hooks() {
  local file
  file="$(harness_hook_file "$1")"
  [[ -f "$file" ]] &&
    grep -Eq '"command"[[:space:]]*:[[:space:]]*"[[:space:]]*archdev (repo|inspect) hook ' "$file"
}

# The archdev Claude Code plugin ships the same hooks; settings.json hooks on
# top of it would run every hook twice. Same rule as the CLI's
# claudePluginInstall: an `archdev@<any marketplace>` install at user or
# managed scope (or unscoped) whose key `enabledPlugins` sets to true.
claude_plugin_installed() {
  local config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local records="$config/plugins/installed_plugins.json" settings="$config/settings.json"
  [[ -f "$records" && -f "$settings" ]] || return 1
  local installed enabled key rest value
  installed="$(tr -d ' \t\r\n' <"$records")"
  enabled="$(tr -d ' \t\r\n' <"$settings")"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    [[ "$enabled" == *"${key}true"* ]] || continue
    # The key's value: a list of installs (version 2) or one install.
    rest="${installed#*"$key"}"
    if [[ "$rest" == "["* ]]; then value="${rest%%]*}"; else value="${rest%%\}*}"; fi
    if [[ "$value" != *'"scope":'* || "$value" == *'"scope":"user"'* ||
      "$value" == *'"scope":"managed"'* ]]; then
      return 0
    fi
  done < <(grep -o '"archdev@[^"]*":' <<<"$installed" | sort -u)
  return 1
}

# `repo hook setup --uninstall` records an opt-out only on CLIs that also
# print the plugin hooks (`repo hook plugin-hooks-json`). An older CLI would
# undo a deliberate uninstall, so it only refreshes.
setup_honours_opt_out() {
  local help
  help="$("$executable" repo hook --help 2>/dev/null || true)"
  [[ "$help" == *plugin-hooks-json* ]]
}

# Failures are reported without blocking the skill (for example an older
# archdev earlier on PATH, which setup refuses to wire).
harness="$(calling_harness)"
if [[ -n "$harness" ]] && ! has_archdev_hooks "$harness" &&
  ! { [[ "$harness" == claude ]] && claude_plugin_installed; } &&
  setup_honours_opt_out; then
  "$executable" repo hook setup --harness "$harness" >&2 ||
    printf 'Could not install ArchDev hooks for %s; see above, then run: archdev repo hook setup --harness %s\n' "$harness" "$harness" >&2
fi
# Bring every harness that has archdev hooks, and ArchDev's own runtime, up
# to this CLI's hook wiring.
hook_help="$("$executable" repo hook setup --help 2>/dev/null || true)"
if [[ "$hook_help" == *"--refresh"* ]]; then
  "$executable" repo hook setup --refresh >&2 ||
    printf 'Could not refresh ArchDev hooks; see above, then run: archdev repo hook setup\n' >&2
fi
printf '%s\n' "$executable"
