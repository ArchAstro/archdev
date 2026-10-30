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
    ARCHDEV_FAKE_LOG="$case_dir/setup.log" ARCHDEV_FAKE_INVOCATIONS="$case_dir/invocations.log" "$@" \
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
  if [[ "$skill" == archdev ]] && [[ "$(wc -l <"$case_dir/invocations.log" | tr -d ' ')" != 7 || "$(sort "$case_dir/invocations.log" | uniq -d)" != "" ]]; then
    printf 'FAIL %s: healthy core bootstrap must probe version and six capabilities once\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi
  printf 'ok   %s: executable resolved, no hook installation or refresh\n' "$name"
}

for skill in archdev tasks tasks-execute tasks-audit; do
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

# Version output must also be drained before checking native exit status.
run_bootstrap "archdev-verbose-version" archdev ARCHDEV_FAKE_VERBOSE_VERSION=1

# Consume the entire help stream: with pipefail, grep -q can close early,
# SIGPIPE the producer, and trigger an unnecessary install of a current CLI.
for skill in archdev tasks tasks-execute tasks-audit; do
  run_bootstrap "$skill-verbose-help" "$skill" ARCHDEV_FAKE_VERBOSE_HELP=1
  # Both skills reject older releases that could silently opt in global hooks.
  rejections=(ARCHDEV_FAKE_NO_LOCAL=1 ARCHDEV_FAKE_VERSION=0.46.0 ARCHDEV_FAKE_VERSION=0.49.5)
  # Task execution also needs the lease heartbeat command.
  [[ "$skill" == tasks-execute ]] && rejections+=(ARCHDEV_FAKE_NO_HEARTBEAT=1)
  # Auditing paused work needs the human-attention inbox.
  [[ "$skill" == tasks-audit ]] && rejections+=(ARCHDEV_FAKE_NO_INBOX=1)
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

# Homebrew owns a copy linked from its Cellar. Bootstrap repairs that copy with
# brew and never installs a second one, which would shadow or be shadowed by it.
# Each case builds <prefix>/Cellar/archdev/<v>/bin/archdev with a
# <prefix>/bin/archdev link, as `brew install archastro/tools/archdev` leaves it.
fake_archdev_at() {
  printf '#!/bin/sh\nARCHDEV_FAKE_VERSION=%s exec "%s" "$@"\n' "$2" "$repo/scripts/fake-archdev" >"$1"
  chmod +x "$1"
}

# brew_case <name> <skill> <keg: old|stub|crash|version-error|current|missing|none> <brew: yes|no|fail>
#   <copy: none|old|current> [<variant: opt|other-brew>]
# An old keg is 0.49.0; every other keg is the formula's latest, 0.60.0, so a
# `brew upgrade` of it changes nothing, as with real Homebrew.
brew_case() {
  local name="$1" skill="$2" keg="$3" brew="$4" copy="$5" variant="${6:-}" keg_version=0.60.0 keg_dir path
  case_dir="$work/brew-$skill-$name"
  prefix="$case_dir/homebrew"
  mkdir -p "$case_dir/home" "$case_dir/bin" "$prefix/bin"
  printf '#!/bin/sh\nprintf "Blocked installer download\\n" >&2\nexit 1\n' >"$case_dir/bin/curl"
  chmod +x "$case_dir/bin/curl"
  : >"$case_dir/setup.log"
  : >"$case_dir/brew.log"
  expected_path="$prefix/bin/archdev"
  if [[ "$keg" != none ]]; then
    [[ "$keg" == old ]] && keg_version=0.49.0
    keg_dir="$prefix/Cellar/archdev/$keg_version/bin"
    mkdir -p "$keg_dir" "$prefix/opt"
    case "$keg" in
      old) fake_archdev_at "$keg_dir/archdev" 0.49.5 ;;
      current) fake_archdev_at "$keg_dir/archdev" 0.49.6 ;;
      # The stub that replaced a real keg: a high version, no commands.
      stub) printf '#!/bin/sh\necho "archdev 3.0.0"\n' >"$keg_dir/archdev" && chmod +x "$keg_dir/archdev" ;;
      # A binary that crashes before it can report a version.
      crash) printf '#!/bin/sh\nexit 139\n' >"$keg_dir/archdev" && chmod +x "$keg_dir/archdev" ;;
      version-error) printf '#!/bin/sh\necho "archdev 0.60.0"\nexit 139\n' >"$keg_dir/archdev" && chmod +x "$keg_dir/archdev" ;;
      missing) rm -rf "$prefix/Cellar/archdev" ;;
    esac
    ln -s "../Cellar/archdev/$keg_version/bin/archdev" "$prefix/bin/archdev"
    ln -s "../Cellar/archdev/$keg_version" "$prefix/opt/archdev"
  fi
  [[ "$brew" == no ]] || cp "$repo/scripts/fake-brew" "$prefix/bin/brew"
  path="$prefix/bin:$case_dir/bin:/usr/bin:/bin"
  case "$variant" in
    # PATH reaches the keg through Homebrew's opt link, which survives upgrades.
    opt)
      path="$prefix/opt/archdev/bin:$path"
      expected_path="$prefix/opt/archdev/bin/archdev"
      ;;
    # Another Homebrew prefix's brew comes first on PATH; it must not be used.
    other-brew)
      mkdir -p "$case_dir/other-homebrew/bin"
      printf '#!/bin/sh\necho "$*" >>"%s"\necho %s\n' "$case_dir/other-brew.log" "$case_dir/other-homebrew" >"$case_dir/other-homebrew/bin/brew"
      chmod +x "$case_dir/other-homebrew/bin/brew"
      : >"$case_dir/other-brew.log"
      path="$case_dir/other-homebrew/bin:$path"
      ;;
  esac
  if [[ "$copy" != none ]]; then
    # A previous installer copy that comes first on PATH.
    mkdir -p "$case_dir/home/.local/bin"
    fake_archdev_at "$case_dir/home/.local/bin/archdev" "$([[ "$copy" == old ]] && echo 0.49.5 || echo 0.49.6)"
    path="$case_dir/home/.local/bin:$path"
  fi
  home_files >"$case_dir/home.before"
  set +e
  env -i HOME="$case_dir/home" TMPDIR="$case_dir" PATH="$path" \
    ARCHDEV_FAKE_LOG="$case_dir/setup.log" ARCHDEV_FAKE_BIN="$repo/scripts/fake-archdev" \
    FAKE_BREW_LOG="$case_dir/brew.log" FAKE_BREW_PREFIX="$prefix" \
    FAKE_BREW_EXIT="$([[ "$brew" == fail ]] && echo 1 || echo 0)" \
    ARCHDEV_FAKE_VERBOSE_VERSION="$([[ "$variant" == verbose ]] && echo 1 || echo 0)" \
    bash "$repo/$skill/scripts/bootstrap.sh" >"$case_dir/out" 2>"$case_dir/stderr"
  case_exit=$?
  set -e
}

home_files() {
  find "$case_dir/home" -type f -exec cksum {} + | sort
}

brew_fail() {
  printf 'FAIL brew %s: %s\n' "$case_dir" "$1" >&2
  sed 's/^/  stderr: /' "$case_dir/stderr" >&2
  failures=$((failures + 1))
}

# Brew repaired the keg in place: the path on stdout is the Homebrew link,
# now reporting the upgraded version, and no other copy was downloaded.
expect_brew_repaired() {
  local action="$1"
  if ((case_exit != 0)); then
    brew_fail "exited $case_exit"
  elif [[ "$(cat "$case_dir/out")" != "$expected_path" ]]; then
    brew_fail "printed '$(cat "$case_dir/out")', not $expected_path"
  elif ! grep -Fx "$action archastro/tools/archdev" "$case_dir/brew.log" >/dev/null; then
    brew_fail "brew was not asked to $action: $(tr '\n' ';' <"$case_dir/brew.log")"
  elif ! grep -F "brew $action archastro/tools/archdev" "$case_dir/stderr" >/dev/null; then
    brew_fail "the brew command was not shown"
  elif [[ "$("$expected_path" --version)" != 0.60.0 ]]; then
    brew_fail "the Homebrew keg was not updated"
  else
    return 0
  fi
  return 1
}

expect_no_second_copy() {
  if grep -F 'Blocked installer download' "$case_dir/stderr" >/dev/null; then
    brew_fail "downloaded the installer for a second copy"
  elif [[ "$(home_files)" != "$(cat "$case_dir/home.before")" ]]; then
    brew_fail "changed files under HOME"
  elif [[ -s "$case_dir/setup.log" ]]; then
    brew_fail "wrote hooks"
  else
    return 0
  fi
  return 1
}

expect_brew_untouched() {
  if grep -E '^(upgrade|reinstall|install)' "$case_dir/brew.log" >/dev/null; then
    brew_fail "changed Homebrew: $(tr '\n' ';' <"$case_dir/brew.log")"
    return 1
  fi
}

for skill in archdev tasks tasks-execute tasks-audit; do
  brew_case outdated "$skill" old yes none
  expect_brew_repaired upgrade && expect_no_second_copy &&
    printf 'ok   %s: outdated Homebrew copy upgraded with brew, no second copy\n' "$skill"

  # The incident: a stub reporting 3.0.0 passed the version check and failed
  # the capability probes, so `brew upgrade` would have been a no-op.
  brew_case verbose-old "$skill" old yes none verbose
  if expect_brew_repaired upgrade && expect_no_second_copy; then
    printf 'ok   %s: verbose outdated Homebrew version upgraded\n' "$skill"
  fi
  brew_case version-error "$skill" version-error yes none
  if expect_brew_repaired reinstall && expect_no_second_copy; then
    printf 'ok   %s: failed version command reinstalled despite version text\n' "$skill"
  fi

  brew_case broken "$skill" stub yes none
  expect_brew_repaired reinstall && expect_no_second_copy &&
    printf 'ok   %s: broken current Homebrew copy reinstalled with brew, no second copy\n' "$skill"

  brew_case crash "$skill" crash yes none
  expect_brew_repaired reinstall && expect_no_second_copy &&
    printf 'ok   %s: crashing current Homebrew copy reinstalled with brew, no second copy\n' "$skill"

  brew_case opt "$skill" old yes none opt
  expect_brew_repaired upgrade && expect_no_second_copy &&
    printf 'ok   %s: Homebrew copy on PATH through its opt link upgraded, opt path kept\n' "$skill"

  brew_case other-brew "$skill" old yes none other-brew
  if expect_brew_repaired upgrade && expect_no_second_copy; then
    if [[ -s "$case_dir/other-brew.log" ]]; then
      brew_fail "ran another prefix's brew: $(tr '\n' ';' <"$case_dir/other-brew.log")"
    else
      printf 'ok   %s: the keg'"'"'s own brew upgrades it, not the brew first on PATH\n' "$skill"
    fi
  fi

  brew_case missing "$skill" missing yes none
  expect_brew_repaired reinstall && expect_no_second_copy &&
    printf 'ok   %s: dangling Homebrew link reinstalled with brew, no second copy\n' "$skill"

  brew_case behind-copy "$skill" old yes old
  expect_brew_repaired upgrade && expect_no_second_copy &&
    printf 'ok   %s: Homebrew copy behind an installer copy on PATH is preferred and upgraded\n' "$skill"

  brew_case current-behind-copy "$skill" current yes current
  if ((case_exit != 0)) || [[ "$(cat "$case_dir/out")" != "$prefix/bin/archdev" ]]; then
    brew_fail "did not prefer the current Homebrew copy"
  elif ! grep -F 'comes first on PATH' "$case_dir/stderr" >/dev/null; then
    brew_fail "did not say which copy it skipped"
  elif expect_brew_untouched && expect_no_second_copy; then
    printf 'ok   %s: current Homebrew copy behind an installer copy is used as is\n' "$skill"
  fi

  brew_case current "$skill" current yes none
  if ((case_exit != 0)) || [[ "$(cat "$case_dir/out")" != "$prefix/bin/archdev" ]]; then
    brew_fail "did not use the current Homebrew copy"
  elif [[ -s "$case_dir/brew.log" ]]; then
    brew_fail "ran brew for a current copy: $(tr '\n' ';' <"$case_dir/brew.log")"
  elif expect_no_second_copy; then
    printf 'ok   %s: current Homebrew copy used without running brew\n' "$skill"
  fi

  brew_case no-brew "$skill" old no none
  if ((case_exit == 0)) || [[ -s "$case_dir/out" ]]; then
    brew_fail "accepted an outdated Homebrew copy without brew"
  elif ! grep -F "$prefix/bin/archdev is managed by Homebrew, but $prefix/bin/brew is missing" "$case_dir/stderr" >/dev/null; then
    brew_fail "error does not name the Homebrew-managed binary"
  elif expect_no_second_copy; then
    printf 'ok   %s: outdated Homebrew copy without brew stops with an error, no second copy\n' "$skill"
  fi

  brew_case brew-fails "$skill" old fail none
  if ((case_exit == 0)) || [[ -s "$case_dir/out" ]]; then
    brew_fail "continued after brew failed"
  elif ! grep -F "brew upgrade archastro/tools/archdev failed. ArchDev at $prefix/bin/archdev is managed by Homebrew" "$case_dir/stderr" >/dev/null; then
    brew_fail "error does not name the failed brew command and binary"
  elif expect_no_second_copy; then
    printf 'ok   %s: failed brew upgrade stops with an error, no second copy\n' "$skill"
  fi

  # Without a Homebrew keg, an installer copy keeps today's path: the pinned
  # installer (blocked here) replaces it, and brew is never asked to install.
  brew_case installer-copy "$skill" none yes old
  if ((case_exit == 0)) || ! grep -F 'Blocked installer download' "$case_dir/stderr" >/dev/null; then
    brew_fail "did not update the outdated installer copy with the pinned installer"
  elif expect_brew_untouched; then
    printf 'ok   %s: outdated installer copy still uses the pinned installer\n' "$skill"
  fi

  # A working installer copy with brew but no keg is used as is.
  brew_case working-installer-copy "$skill" none yes current
  if ((case_exit != 0)) || [[ "$(cat "$case_dir/out")" != "$case_dir/home/.local/bin/archdev" ]]; then
    brew_fail "did not use the working installer copy"
  elif expect_brew_untouched && expect_no_second_copy; then
    printf 'ok   %s: working installer copy used as is when brew has no keg\n' "$skill"
  fi

  for brew in yes no; do
    brew_case "nothing-installed-brew-$brew" "$skill" none "$brew" none
    if ((case_exit == 0)) || ! grep -F 'Blocked installer download' "$case_dir/stderr" >/dev/null; then
      brew_fail "a fresh install did not use the pinned installer"
    elif expect_brew_untouched; then
      printf 'ok   %s: no archdev (brew on PATH: %s) still uses the pinned installer\n' "$skill" "$brew"
    fi
  done
done

((failures == 0)) || exit 1
printf 'All bootstrap cases passed\n'
