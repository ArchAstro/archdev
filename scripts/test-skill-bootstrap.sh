#!/usr/bin/env bash
# Runs archdev/scripts/bootstrap.sh against scripts/fake-archdev in a
# throwaway HOME for each case, and checks which `repo hook setup` calls the
# bootstrap made for the harness that ran it. What those calls do to hook
# files is the CLI's job; scripts/test-skill-bootstrap-cli.sh checks that
# against a real archdev.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-bootstrap-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0

# Run the bootstrap in a fresh HOME with only the given environment. Sets
# $log (the recorded setup calls) and $out (the bootstrap's stdout).
run_bootstrap() {
  local case_dir="$work/$1"
  shift
  log="$case_dir/setup.log"
  mkdir -p "$case_dir/home" "$case_dir/bin"
  cp "$repo/scripts/fake-archdev" "$case_dir/bin/archdev"
  chmod +x "$case_dir/bin/archdev"
  : >"$log"
  if ! out="$(env -i HOME="$case_dir/home" PATH="$case_dir/bin:/usr/bin:/bin" \
    ARCHDEV_FAKE_LOG="$log" "$@" \
    bash "$repo/archdev/scripts/bootstrap.sh" 2>"$case_dir/stderr")"; then
    printf 'FAIL %s: bootstrap exited nonzero\n' "$(basename "$case_dir")" >&2
    cat "$case_dir/stderr" >&2
    failures=$((failures + 1))
    return 1
  fi
  # Callers read stdout as the archdev path, so nothing else may reach it.
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

# Each harness installs its own hooks, then every hooked harness refreshes.
run_bootstrap claude CLAUDECODE=1 &&
  expect_calls "Claude Code installs Claude hooks" "repo hook setup --harness claude
repo hook setup --refresh"
run_bootstrap codex CODEX_THREAD_ID=019a-thread &&
  expect_calls "Codex installs Codex hooks" "repo hook setup --harness codex
repo hook setup --refresh"
run_bootstrap grok GROK_SESSION_ID=grok-session &&
  expect_calls "Grok installs Grok hooks" "repo hook setup --harness grok
repo hook setup --refresh"

# CLAUDECODE is a flag: only the value 1 marks Claude Code.
run_bootstrap claude-flag-off CLAUDECODE=0 &&
  expect_calls "CLAUDECODE=0 is not Claude Code" "repo hook setup --refresh"

# Factory workers and daemon pipeline steps leave harness config to their
# host, so only refresh.
for owned in ARCHDEV_FACTORY_AGENT_ROLE=worker ARCHDEV_JOB_ID=job-1 ARCHDEV_STEP_ID=step-1; do
  run_bootstrap "daemon-owned-${owned%%=*}" CLAUDECODE=1 "$owned" &&
    expect_calls "Daemon-owned session (${owned%%=*}) only refreshes" "repo hook setup --refresh"
done

# No harness marker: nothing to install for, so only refresh.
run_bootstrap unknown-harness &&
  expect_calls "Unknown harness only refreshes" "repo hook setup --refresh"

# A failing setup is reported but does not fail the bootstrap, and the
# refresh still runs.
if run_bootstrap setup-fails CLAUDECODE=1 ARCHDEV_FAKE_SETUP_EXIT=1; then
  expect_calls "Failed install does not block the skill" "repo hook setup --harness claude
repo hook setup --refresh"
  if grep -Fq 'then run: archdev repo hook setup --harness claude' "$work/setup-fails/stderr"; then
    printf 'ok   Failed install names the command to run\n'
  else
    printf 'FAIL Failed install names the command to run\n' >&2
    failures=$((failures + 1))
  fi
fi

if ((failures > 0)); then
  printf '%d bootstrap case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'All bootstrap cases passed\n'
