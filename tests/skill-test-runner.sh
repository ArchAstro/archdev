#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$repo/scripts/run-skill-tests.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
fixture="$root/repository with spaces"
mkdir -p "$fixture/skills/example" "$fixture/tests"
printf '%s\n' '---' 'description: Fixture skill' '---' >"$fixture/skills/example/SKILL.md"
cat >"$fixture/tests/example-skill.sh" <<'TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'example executed\n' >>"$SKILL_RUNNER_TEST_LOG"
TEST
chmod 0755 "$fixture/tests/example-skill.sh"

# Discovery proof: a skill package causes its matching executable acceptance
# script to run, including when the repository path contains spaces.
log="$root/executed.log"
SKILL_RUNNER_TEST_LOG="$log" "$runner" "$fixture" >/dev/null
test "$(cat "$log")" = "example executed"

# Coverage proof: a skill without a conventionally named acceptance test makes
# the runner fail instead of allowing a green check with missing coverage.
mkdir -p "$fixture/skills/uncovered"
printf '%s\n' '---' 'description: Uncovered fixture skill' '---' >"$fixture/skills/uncovered/SKILL.md"
if SKILL_RUNNER_TEST_LOG="$log" "$runner" "$fixture" >"$root/stdout" 2>"$root/stderr"; then
  printf 'Runner accepted a skill without an acceptance test.\n' >&2
  exit 1
fi
grep -F 'tests/uncovered-skill.sh' "$root/stderr" >/dev/null

# Bootstrap proof: the workflow can land before the first skill and begins
# enforcing coverage as soon as a skills directory appears.
empty="$root/empty repository"
mkdir -p "$empty"
"$runner" "$empty" >"$root/empty-output"
grep -F 'No skills found' "$root/empty-output" >/dev/null

printf 'Skill test discovery executes every matching test and fails closed on missing coverage.\n'
