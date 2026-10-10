#!/usr/bin/env bash
# Canonical proof: an agent resolves ArchDev without configuring hooks, then
# applies only an explicitly chosen placement. Real CLI and shell callbacks;
# no coding-agent trust or browser authentication is simulated as verified.
# Usage: scripts/test-skill-bootstrap-cli.sh (ArchDev 0.47.0+ and Node on PATH)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archdev="$(command -v archdev)"
archdev_dir="$(dirname "$archdev")"
node="$(command -v node)"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-bootstrap-cli-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
home="$work/home"
checkout="$work/checkout"
mkdir -p "$home/.claude" "$checkout" "$work/node-only" "$work/empty-templates"
git -c core.hooksPath=/dev/null -c init.templateDir="$work/empty-templates" init --quiet "$checkout"
ln -s "$node" "$work/node-only/node"
node_dir="$(dirname "$node")"

in_home() (
  cd "$checkout"
  env -i HOME="$home" PATH="$archdev_dir:$node_dir:/usr/bin:/bin" "$@"
)
snapshot() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob('*')):
    relative = path.relative_to(root)
    # Process logs/cache/crash records are not hook or user configuration.
    if relative.parts[:2] in [('.archdev', 'logs'), ('.cache', 'archdev')]:
        continue
    if path.is_file():
        print(relative, hashlib.sha256(path.read_bytes()).hexdigest())
PY
}

# Seed an unrelated personal hook. Existence of an agent config directory is
# not permission for the skill to install or refresh user-wide ArchDev hooks.
printf '%s\n' '{"permissions":{"allow":["Read"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"printf teammate"}]}]}}' >"$home/.claude/settings.json"
# Ordinary commands may initialize the product default. Seed this legitimate
# profile once so the proof measures hook/setting mutations, not initialization.
mkdir -p "$home/.config/archdev"
printf '%s\n' '{"defaultApp":"dap_033y70rWJriCRNyb9uL0Pm"}' >"$home/.config/archdev/config.json"
before="$(snapshot "$home")"
checkout_before="$(snapshot "$checkout")"
for skill in archdev tasks; do
  for marker in CLAUDECODE=1 CODEX_THREAD_ID=thread-1 GROK_SESSION_ID=session-1 ARCHDEV_FACTORY_AGENT_ROLE=worker; do
    out="$(in_home "$marker" bash "$repo/$skill/scripts/bootstrap.sh")"
    [[ "$out" == "$archdev" ]]
    [[ "$(snapshot "$home")" == "$before" ]]
    [[ "$(snapshot "$checkout")" == "$checkout_before" ]]
  done
done
# Ordinary authenticated/Tasks operations must not opt missing harnesses in.
# Missing login is expected in this isolated home; configuration must stay put.
for marker in CLAUDECODE=1 CODEX_THREAD_ID=thread-1; do
  in_home "$marker" archdev auth status >/dev/null 2>&1 || true
  in_home "$marker" archdev tasks guide >/dev/null
  [[ "$(snapshot "$home")" == "$before" ]]
  [[ "$(snapshot "$checkout")" == "$checkout_before" ]]
done
printf 'ok   core and Tasks resolve the real CLI without changing personal configuration\n'

# The agent has received explicit repository/reporting consent. Cross the real
# CLI process boundary into the isolated Git fixture; only shareable project
# files may be written.
(cd "$checkout" && in_home archdev repo hook setup --local)
[[ "$(snapshot "$home")" == "$before" ]]
for file in .claude/settings.json .archdev/hooks.json; do
  [[ -f "$checkout/$file" ]] || { printf 'Missing detected hook %s\n' "$file" >&2; exit 1; }
done
for file in .codex/hooks.json .agents/hooks.json .grok/hooks/archdev.json .pi/extensions/archdev.js; do
  [[ ! -e "$checkout/$file" ]] || { printf 'Undetected harness installed: %s\n' "$file" >&2; exit 1; }
done
printf 'ok   default repository placement prepares detected harnesses only\n'

# Preparing absent tools is a separate explicit selection, not implied by scope.
(cd "$checkout" && in_home archdev repo hook setup --local --all-harnesses)
[[ "$(snapshot "$home")" == "$before" ]]
for file in .claude/settings.json .codex/hooks.json .agents/hooks.json .grok/hooks/archdev.json .pi/extensions/archdev.js .archdev/hooks.json; do
  [[ -f "$checkout/$file" ]] || { printf 'Missing explicitly selected hook %s\n' "$file" >&2; exit 1; }
done
[[ ! -e "$checkout/.claude/settings.local.json" ]]
printf 'ok   explicit all-harness placement prepares every harness and leaves personal settings alone\n'

# Run the actual installed Claude callback as a harness would. The binary is
# present; its existing workflow contract must survive the shared launcher.
start_command="$(python3 - "$checkout/.claude/settings.json" <<'PY'
import json, sys
groups = json.load(open(sys.argv[1]))['hooks']['SessionStart']
print(next(h['command'] for g in groups for h in g['hooks'] if 'archdev repo hook ' in h.get('command', '')))
PY
)"
payload="$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$checkout")"
start="$(cd "$checkout" && printf '%s' "$payload" | in_home bash -c "$start_command")"
[[ "$start" == *'Load the `archdev` skill'* ]]
printf 'ok   installed shared callback delegates to the real CLI and delivers its contract\n'

# A teammate without the binary gets guidance, not an installer or config
# mutation. Node remains available, as required by repository JSON hooks.
missing_before="$(snapshot "$home")"
missing="$(cd "$checkout" && printf '%s' "$payload" | in_home PATH="$work/node-only:/usr/bin:/bin" bash -c "$start_command")"
[[ "$missing" == *'https://archdev.ai/install.md'* ]]
[[ "$(snapshot "$home")" == "$missing_before" ]]
printf 'ok   missing-binary callback points to the agent guide without installing anything\n'

# Re-loading either skill must not infer another scope from these files.
project_before="$(snapshot "$checkout")"
personal_before="$(snapshot "$home")"
for skill in archdev tasks; do
  (cd "$checkout" && in_home CLAUDECODE=1 bash "$repo/$skill/scripts/bootstrap.sh") >/dev/null
done
[[ "$(snapshot "$home")" == "$personal_before" ]]
[[ "$(snapshot "$checkout")" == "$project_before" ]]

# The user explicitly chooses machine-wide setup as a separate action. The
# real CLI may now modify personal hooks, but never the existing project ones.
(cd "$checkout" && in_home archdev repo hook setup)
[[ "$(snapshot "$checkout")" == "$project_before" ]]
python3 - "$home/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
assert settings['permissions'] == {'allow': ['Read']}
commands = [h['command'] for g in settings['hooks']['SessionStart'] for h in g['hooks']]
assert 'printf teammate' in commands
assert any(c.startswith('archdev repo hook start') for c in commands)
PY
printf 'ok   only explicit user-wide setup writes personal ArchDev hooks, preserving unrelated settings\n'

# An uninstall is not repaired by loading the skill. Project hooks survive;
# bootstrap leaves the user's opt-out and personal settings byte-for-byte.
in_home archdev repo hook setup --uninstall --harness claude
uninstalled="$(snapshot "$home")"
in_home CLAUDECODE=1 bash "$repo/archdev/scripts/bootstrap.sh" >/dev/null
[[ "$(snapshot "$home")" == "$uninstalled" ]]
[[ "$(snapshot "$checkout")" == "$project_before" ]]
printf 'All explicit-placement bootstrap CLI cases passed\n'
