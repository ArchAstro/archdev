#!/usr/bin/env bash
# Capability probes are permitted; bootstrap must never choose hook scope.
# The real CLI/process proof lives in test-skill-bootstrap-cli.sh.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/archdev-bootstrap-test.XXXXXX")"
work="$(cd -P "$work" && pwd)"
trap 'rm -rf "$work"' EXIT
failures=0

run_bootstrap() {
  local name="$1" skill="$2"
  shift 2
  local case_dir="$work/$name" out
  mkdir -p "$case_dir/home" "$case_dir/bin"
  cp "$repo/scripts/fake-archdev" "$case_dir/bin/archdev"
  # No fake-CLI regression may trigger a real download or installation.
  printf '#!/bin/sh\nprintf "Unexpected installer download\\n" >&2\nexit 1\n' >"$case_dir/bin/curl"
  chmod +x "$case_dir/bin/archdev" "$case_dir/bin/curl"
  : >"$case_dir/setup.log"
  if ! out="$(env -i HOME="$case_dir/home" PATH="$case_dir/bin:/usr/bin:/bin" \
    ARCHDEV_FAKE_LOG="$case_dir/setup.log" "$@" \
    bash "$repo/$skill/scripts/bootstrap.sh" 2>"$case_dir/stderr")"; then
    printf 'FAIL %s: bootstrap exited nonzero\n' "$name" >&2
    cat "$case_dir/stderr" >&2
    failures=$((failures + 1))
    return
  fi
  if [[ "$out" != "$case_dir/bin/archdev" || -s "$case_dir/setup.log" ]]; then
    printf 'FAIL %s: bootstrap must return only the binary path without hook writes\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi
  printf 'ok   %s: executable resolved, no hook installation or refresh\n' "$name"
}

for skill in archdev tasks tasks-execute; do
  run_bootstrap "$skill-claude" "$skill" CLAUDECODE=1
  run_bootstrap "$skill-codex" "$skill" CODEX_THREAD_ID=019a-thread
  run_bootstrap "$skill-grok" "$skill" GROK_SESSION_ID=grok-session
  run_bootstrap "$skill-claude-off" "$skill" CLAUDECODE=0
  run_bootstrap "$skill-factory" "$skill" CLAUDECODE=1 ARCHDEV_FACTORY_AGENT_ROLE=worker
  run_bootstrap "$skill-job" "$skill" CLAUDECODE=1 ARCHDEV_JOB_ID=job-1
  run_bootstrap "$skill-step" "$skill" CLAUDECODE=1 ARCHDEV_STEP_ID=step-1
  run_bootstrap "$skill-unknown" "$skill"
  run_bootstrap "$skill-setup-would-fail" "$skill" CLAUDECODE=1 ARCHDEV_FAKE_SETUP_EXIT=1
done

# Consume the entire help stream: with pipefail, grep -q can close early,
# SIGPIPE the producer, and trigger an unnecessary install of a current CLI.
for skill in archdev tasks tasks-execute; do
  run_bootstrap "$skill-verbose-help" "$skill" ARCHDEV_FAKE_VERBOSE_HELP=1
  # Both skills reject older releases that could silently opt in global hooks.
  rejections=(ARCHDEV_FAKE_NO_LOCAL=1 ARCHDEV_FAKE_VERSION=0.46.0 ARCHDEV_FAKE_VERSION=0.49.5)
  # Task execution also needs the lease heartbeat command.
  [[ "$skill" == tasks-execute ]] && rejections+=(ARCHDEV_FAKE_NO_HEARTBEAT=1)
  for rejection in "${rejections[@]}"; do
    case_dir="$work/$skill-${rejection%%=*}"
    mkdir -p "$case_dir/home" "$case_dir/bin"
    cp "$repo/scripts/fake-archdev" "$case_dir/bin/archdev"
    printf '#!/bin/sh\nprintf "Blocked installer download\\n" >&2\nexit 1\n' >"$case_dir/bin/curl"
    chmod +x "$case_dir/bin/archdev" "$case_dir/bin/curl"
    : >"$case_dir/setup.log"
    if env -i HOME="$case_dir/home" TMPDIR="$case_dir" PATH="$case_dir/bin:/usr/bin:/bin" \
      ARCHDEV_FAKE_LOG="$case_dir/setup.log" "$rejection" \
      bash "$repo/$skill/scripts/bootstrap.sh" >"$case_dir/out" 2>"$case_dir/stderr"; then
      printf 'FAIL %s %s: unsupported CLI was accepted\n' "$skill" "$rejection" >&2
      failures=$((failures + 1))
    elif [[ -s "$case_dir/setup.log" || -s "$case_dir/out" ]] || ! grep -F 'Blocked installer download' "$case_dir/stderr" >/dev/null; then
      printf 'FAIL %s %s: wrote hooks/path or escaped download interception\n' "$skill" "$rejection" >&2
      failures=$((failures + 1))
    else
      printf 'ok   %s %s: rejects without downloads or global fallback\n' "$skill" "$rejection"
    fi
  done
done

((failures == 0)) || exit 1
printf 'All bootstrap cases passed\n'
