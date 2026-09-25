#!/usr/bin/env bash
# Installs this checkout as a Claude Code plugin marketplace in a throwaway
# HOME, then starts a Claude session and checks that the plugin's hooks call
# archdev with the Claude wiring, and stay silent when archdev is missing.
# The session is not logged in: Claude Code still runs the SessionStart and
# UserPromptSubmit hooks before it refuses the prompt, so no credentials or
# model calls are needed. Requires claude and jq.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-plugin-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/bin" "$work/project" "$work/tools"
# Only claude (and node, which an npm-installed claude runs on) join the
# sessions' PATH, so no archdev from the host can answer the hooks.
ln -s "$(readlink -f "$(command -v claude)")" "$work/tools/claude"
if command -v node >/dev/null 2>&1; then ln -s "$(readlink -f "$(command -v node)")" "$work/tools/node"; fi
if env -i PATH="/nonexistent:$work/tools:/usr/bin:/bin" sh -c 'command -v archdev' >/dev/null; then
  printf 'archdev is installed in /usr/bin or /bin; the no-archdev session cannot be isolated here\n' >&2
  exit 1
fi
failures=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Run claude as a user whose only config is the temp HOME.
in_home() {
  (cd "$work/project" && env -i HOME="$work/home" CLAUDE_CONFIG_DIR="$work/home/.claude" \
    PATH="$1:$work/tools:/usr/bin:/bin" "${@:2}")
}

# Setup: add the checkout as the archastro marketplace and install the plugin
# the way the README tells users to.
in_home /nonexistent claude plugin marketplace add "$repo" >/dev/null
in_home /nonexistent claude plugin install archdev@archastro --scope user >/dev/null

# The installed plugin carries both skills and every hook event.
details="$(in_home /nonexistent claude plugin details archdev@archastro)"
grep -Eq 'Skills \(2\) +archdev, tasks' <<<"$details" ||
  fail "installed plugin does not list the archdev and tasks skills: $details"
hook_line="$(grep -E 'Hooks \(6\) ' <<<"$details" || true)"
for event in SessionStart SubagentStart UserPromptSubmit PostToolUse Stop SubagentStop; do
  grep -Eq "[ ,]$event(,| |\$)" <<<"$hook_line" ||
    fail "installed plugin does not list the $event hook among six: $details"
done
install_path="$(in_home /nonexistent claude plugin list --json | jq -r '.[] | select(.id == "archdev@archastro") | .installPath')"
cmp -s "$repo/archdev/SKILL.md" "$install_path/archdev/SKILL.md" ||
  fail "installed plugin does not carry archdev/SKILL.md from this checkout"

# A recording archdev: the hooks resolve archdev through PATH.
cat >"$work/bin/archdev" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/hook-calls.log"
cat >/dev/null
printf '{}\n'
EOF
chmod +x "$work/bin/archdev"

# Session with archdev on PATH: the start and prompt hooks call it with the
# Claude wiring. The prompt itself fails because the session is not logged in.
in_home "$work/bin" claude -p "hello" >/dev/null 2>&1 || true
calls="$(cat "$work/hook-calls.log" 2>/dev/null || true)"
grep -Eq '^repo hook start --harness claude --spec 4$' <<<"$calls" ||
  fail "SessionStart did not call archdev repo hook start: $calls"
grep -Eq '^repo hook prompt --harness claude --spec 4$' <<<"$calls" ||
  fail "UserPromptSubmit did not call archdev repo hook prompt: $calls"

# Session without archdev on PATH: the hooks succeed with no output, so a
# machine without the CLI sees no hook errors.
events="$(in_home /nonexistent claude -p "hello" --output-format stream-json --verbose \
  --include-hook-events 2>/dev/null || true)"
responses="$(jq -c 'select(.type == "system" and .subtype == "hook_response")
  | {event: .hook_event, exit_code, stdout, stderr}' <<<"$events")"
[[ -n "$responses" ]] || fail "no hook responses reported without archdev: $events"
while IFS= read -r response; do
  [[ -z "$response" ]] && continue
  jq -e '.exit_code == 0 and .stdout == "" and .stderr == ""' <<<"$response" >/dev/null ||
    fail "hook was not silent without archdev: $response"
done <<<"$responses"

if ((failures > 0)); then
  printf '%d plugin install check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'ok   plugin installs with both skills and six hooks\n'
printf 'ok   hooks call: %s\n' "$(tr '\n' ';' <<<"$calls")"
printf 'ok   hooks are silent without archdev (%s responses)\n' "$(grep -c . <<<"$responses")"
