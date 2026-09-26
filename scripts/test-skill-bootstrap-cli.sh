#!/usr/bin/env bash
# End-to-end check of the skill bootstrap against the real archdev on PATH
# (CI installs the latest release first). Each case runs
# archdev/scripts/bootstrap.sh in a throwaway HOME as a harness would, then
# reads the hook files the CLI wrote.
#
# Usage: scripts/test-skill-bootstrap-cli.sh   (needs archdev 0.46.6+ on PATH)

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archdev="$(command -v archdev)" || {
  printf 'archdev is not on PATH; install it first (./install.sh)\n' >&2
  exit 1
}
archdev_dir="$(dirname "$archdev")"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-bootstrap-cli-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}
pass() { printf 'ok   %s\n' "$1"; }

# Run a command as a harness would, in $home with only the given variables.
in_home() {
  env -i HOME="$home" PATH="$archdev_dir:/usr/bin:/bin" "$@"
}

# Distinct archdev hook events in a hook file, sorted, one line.
archdev_events() {
  [[ -f "$1" ]] || return 0
  python3 - "$1" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1])).get("hooks", {})
events = sorted(
    event for event, groups in hooks.items()
    if any(h.get("command", "").startswith("archdev repo hook ")
           for g in groups for h in g.get("hooks", []))
)
print(" ".join(events))
PY
}

# Claude Code session on a machine with Claude installed but no ArchDev
# hooks, the state behind `hooks:claude missing`.
home="$work/claude/home"
mkdir -p "$home/.claude"
settings="$home/.claude/settings.json"

# Boundary: the bootstrap runs the real CLI, which writes settings.json.
out="$(in_home CLAUDECODE=1 bash "$repo/archdev/scripts/bootstrap.sh" 2>"$work/claude.stderr")" ||
  { cat "$work/claude.stderr" >&2; fail "bootstrap exited nonzero in Claude Code"; }
[[ "$out" == "$archdev" ]] && pass "bootstrap prints only the archdev path" ||
  fail "bootstrap printed '$out', not $archdev"

# Outcome: every Claude event, subagents included, runs an archdev hook.
events="$(archdev_events "$settings")"
[[ "$events" == "PostToolUse SessionStart Stop SubagentStart SubagentStop UserPromptSubmit" ]] &&
  pass "Claude Code gets session and subagent hooks" ||
  fail "Claude hook events: '$events'"

# The command settings.json installed for one event.
installed_command() {
  python3 - "$settings" "$1" <<'PY'
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"][sys.argv[2]]
print(next(h["command"] for g in groups for h in g["hooks"]
           if h["command"].startswith("archdev repo hook ")))
PY
}

# Boundary: run the installed SessionStart and SubagentStart commands as
# Claude Code would, in a Git checkout. Both tell the agent to load the
# archdev skill.
checkout="$work/checkout"
git init --quiet "$checkout"
start="$(cd "$checkout" && printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$checkout" |
  in_home bash -c "$(installed_command SessionStart 2>/dev/null)" 2>/dev/null || true)"
[[ "$start" == *'Load the `archdev` skill'* ]] &&
  pass "session start hook asks the agent to load the skill" ||
  fail "session start hook output: $start"
subagent="$(cd "$checkout" && printf '{"hook_event_name":"SubagentStart","agent_type":"general-purpose","cwd":"%s"}' "$checkout" |
  in_home bash -c "$(installed_command SubagentStart 2>/dev/null)" 2>/dev/null || true)"
[[ "$subagent" == *'Load the `archdev` skill'* ]] &&
  pass "subagent start hook asks the subagent to load the skill" ||
  fail "subagent start hook output: $subagent"

# A second bootstrap leaves the installed hooks as they are.
before="$(cat "$settings" 2>/dev/null || true)"
in_home CLAUDECODE=1 bash "$repo/archdev/scripts/bootstrap.sh" >/dev/null 2>&1 ||
  fail "second bootstrap exited nonzero"
[[ -f "$settings" && "$(cat "$settings")" == "$before" ]] && pass "second bootstrap changes nothing" ||
  fail "second bootstrap rewrote settings.json"

# The user removes the hooks; the next bootstrap must not put them back.
in_home archdev repo hook setup --uninstall --harness claude >/dev/null 2>&1 ||
  fail "repo hook setup --uninstall exited nonzero"
in_home CLAUDECODE=1 bash "$repo/archdev/scripts/bootstrap.sh" >/dev/null 2>&1 ||
  fail "bootstrap after uninstall exited nonzero"
events="$(archdev_events "$settings")"
[[ -z "$events" ]] && pass "bootstrap respects an uninstall opt-out" ||
  fail "hooks came back after --uninstall: '$events'"

# A Factory worker in Claude Code leaves the user's settings alone.
home="$work/factory/home"
mkdir -p "$home/.claude"
in_home CLAUDECODE=1 ARCHDEV_FACTORY_AGENT_ROLE=worker bash "$repo/archdev/scripts/bootstrap.sh" >/dev/null 2>&1 ||
  fail "bootstrap exited nonzero in a Factory worker"
events="$(archdev_events "$home/.claude/settings.json")"
[[ -z "$events" ]] && pass "Factory worker installs no Claude hooks" ||
  fail "Factory worker installed Claude hooks: '$events'"

# Codex session: its own hooks.json gets the session hooks.
home="$work/codex/home"
mkdir -p "$home/.codex"
in_home CODEX_THREAD_ID=019a-thread bash "$repo/archdev/scripts/bootstrap.sh" >/dev/null 2>"$work/codex.stderr" ||
  { cat "$work/codex.stderr" >&2; fail "bootstrap exited nonzero in Codex"; }
events="$(archdev_events "$home/.codex/hooks.json")"
[[ "$events" == "PostToolUse SessionStart Stop UserPromptSubmit" ]] &&
  pass "Codex gets session hooks" || fail "Codex hook events: '$events'"

if ((failures > 0)); then
  printf '%d bootstrap CLI case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'All bootstrap CLI cases passed\n'
