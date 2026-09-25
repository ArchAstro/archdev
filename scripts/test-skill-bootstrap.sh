#!/usr/bin/env bash
# Runs archdev/scripts/bootstrap.sh against scripts/fake-archdev in a
# throwaway HOME for each case, and checks which `repo hook setup` call the
# bootstrap made for the harness that ran it.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-bootstrap-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0

# Run the bootstrap in a fresh HOME with only the given environment. Sets
# $home, $log (the recorded setup calls), and $out (the bootstrap's stdout).
run_bootstrap() {
  local case_dir="$work/$1"
  shift
  home="$case_dir/home"
  log="$case_dir/setup.log"
  mkdir -p "$home" "$case_dir/bin"
  cp "$repo/scripts/fake-archdev" "$case_dir/bin/archdev"
  chmod +x "$case_dir/bin/archdev"
  : >"$log"
  if [[ -n "${prepare:-}" ]]; then "$prepare"; fi
  if ! out="$(env -i HOME="$home" PATH="$case_dir/bin:/usr/bin:/bin" \
    ARCHDEV_FAKE_LOG="$log" "$@" \
    bash "$repo/archdev/scripts/bootstrap.sh" 2>"$case_dir/stderr")"; then
    printf 'FAIL %s: bootstrap exited nonzero\n' "$(basename "$case_dir")" >&2
    cat "$case_dir/stderr" >&2
    failures=$((failures + 1))
    return 1
  fi
  if [[ "$out" != "$case_dir/bin/archdev" ]]; then
    printf 'FAIL %s: bootstrap printed %q, not the archdev path\n' "$(basename "$case_dir")" "$out" >&2
    failures=$((failures + 1))
    return 1
  fi
}

expect_calls() {
  local name="$1" expected="$2" actual
  actual="$(cat "$log")"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n  expected setup calls: %q\n  actual setup calls:   %q\n' "$name" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

write_claude_hooks() {
  mkdir -p "$home/.claude"
  cat >"$home/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "archdev repo hook start --harness claude --spec 3"}]}
    ]
  }
}
EOF
}

write_claude_plugin() {
  mkdir -p "$home/.claude/plugins"
  cat >"$home/.claude/plugins/installed_plugins.json" <<'EOF'
{"version": 2, "plugins": {"archdev@archastro": [{"scope": "user", "version": "f1f606d1df2c"}]}}
EOF
}

write_disabled_claude_plugin() {
  write_claude_plugin
  printf '%s\n' '{"enabledPlugins": {"archdev@archastro": false}}' >"$home/.claude/settings.json"
}

write_project_claude_plugin() {
  mkdir -p "$home/.claude/plugins"
  printf '%s\n' '{"version": 2, "plugins": {"archdev@archastro": [{"scope": "project", "projectPath": "/elsewhere"}]}}' \
    >"$home/.claude/plugins/installed_plugins.json"
}

write_other_claude_hooks() {
  mkdir -p "$home/.claude"
  cat >"$home/.claude/settings.json" <<'EOF'
{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "my-wrapper archdev repo hook stop"}]}]}}
EOF
}

# Claude Code session, no archdev hooks yet: install them for Claude.
prepare="" run_bootstrap claude-no-hooks CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude without hooks installs them" "repo hook setup --harness claude
repo hook setup --refresh"

# Another tool's hook that merely invokes archdev is not an archdev hook.
prepare=write_other_claude_hooks run_bootstrap claude-foreign-hooks CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude with only a wrapper hook installs them" "repo hook setup --harness claude
repo hook setup --refresh"

# Claude Code session that already has archdev hooks: refresh them.
prepare=write_claude_hooks run_bootstrap claude-hooks-present CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude with hooks refreshes" "repo hook setup --refresh"

# CLAUDE_CONFIG_DIR moves the settings file the bootstrap inspects.
move_claude_config() { write_claude_hooks && mv "$home/.claude" "$home/claude-config"; }
prepare=move_claude_config run_bootstrap claude-config-dir CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 \
  CLAUDE_CONFIG_DIR="$work/claude-config-dir/home/claude-config" &&
  expect_calls "Claude hooks under CLAUDE_CONFIG_DIR refresh" "repo hook setup --refresh"

# The archdev Claude plugin already provides the hooks: no settings.json hooks.
prepare=write_claude_plugin run_bootstrap claude-plugin CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude with the archdev plugin does not install settings hooks" "repo hook setup --refresh"

# A disabled plugin, or one installed only for another project, gives this
# session no hooks, so settings.json hooks are still installed.
prepare=write_disabled_claude_plugin run_bootstrap claude-plugin-disabled CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude with the plugin disabled installs settings hooks" "repo hook setup --harness claude
repo hook setup --refresh"
prepare=write_project_claude_plugin run_bootstrap claude-plugin-other-project CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Claude with a project-scope plugin elsewhere installs settings hooks" "repo hook setup --harness claude
repo hook setup --refresh"

# A CLI that cannot record an uninstall opt-out never installs, so a user who
# ran `repo hook setup --uninstall` keeps no hooks.
prepare="" run_bootstrap claude-opted-out-old-cli CLAUDECODE=1 &&
  expect_calls "CLI without opt-out support only refreshes" "repo hook setup --refresh"

# Codex and Grok sessions install for their own harness.
prepare="" run_bootstrap codex-no-hooks CODEX_THREAD_ID=019a-thread ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Codex without hooks installs them" "repo hook setup --harness codex
repo hook setup --refresh"
prepare="" run_bootstrap grok-no-hooks GROK_SESSION_ID=grok-session ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Grok without hooks installs them" "repo hook setup --harness grok
repo hook setup --refresh"

# No harness marker: keep the refresh-only behaviour.
prepare="" run_bootstrap unknown-harness ARCHDEV_FAKE_TRACK1=1 &&
  expect_calls "Unknown harness only refreshes" "repo hook setup --refresh"

# A failing setup is reported but does not fail the bootstrap.
prepare="" run_bootstrap setup-fails CLAUDECODE=1 ARCHDEV_FAKE_TRACK1=1 ARCHDEV_FAKE_SETUP_EXIT=1 &&
  expect_calls "Failed install does not block the skill" "repo hook setup --harness claude
repo hook setup --refresh"

if ((failures > 0)); then
  printf '%d bootstrap case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'All bootstrap cases passed\n'
