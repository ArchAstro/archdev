#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/home" "$root/global-project" "$root/project"
git -C "$root/global-project" init -q
git -C "$root/project" init -q
git -C "$root/project" config user.name 'Jobs Skill Test'
git -C "$root/project" config user.email 'jobs-skill@test.invalid'
printf 'tracked input\n' >"$root/project/input.txt"
git -C "$root/project" add input.txt
git -C "$root/project" commit -qm 'Seed exact input'

# Package installation: npx skills must retain the complete self-contained
# Jobs package in both supported scopes.
HOME="$root/home" npx --yes skills add "$repo" \
  --global --skill jobs --agent codex --yes --copy >/dev/null
test -x "$root/home/.agents/skills/jobs/scripts/bootstrap.sh"
(
  cd "$root/project"
  HOME="$root/home" npx --yes skills add "$repo" \
    --skill jobs --agent codex --yes --copy >/dev/null
)
test -x "$root/project/.agents/skills/jobs/scripts/bootstrap.sh"
grep -F 'releases/latest/download' \
  "$root/project/.agents/skills/jobs/scripts/bootstrap.sh" >/dev/null
grep -F 'releases/latest/download' \
  "$root/project/.agents/skills/jobs/scripts/bootstrap.ps1" >/dev/null
grep -F 'jobs setup --help' \
  "$root/project/.agents/skills/jobs/scripts/bootstrap.ps1" >/dev/null
if grep -ERq 'raw\.githubusercontent\.com/.*/(main|refs/heads)' \
  "$root/project/.agents/skills/jobs/scripts"; then
  printf 'Jobs bootstrap must not execute a mutable branch installer.\n' >&2
  exit 1
fi

# Cold bootstrap: the skill downloads a release archive, verifies its published
# checksum, and returns the absolute CLI path even when it is not on PATH.
mkdir -p "$root/release/fixture"
cat >"$root/release/fixture/archdev" <<'ARCHDEV'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${ARCHDEV_TEST_LOG:?}"
case "$*" in
  "--version") printf '0.33.2\n' ;;
  "jobs setup --help") ;;
  "check") printf 'Configuration is valid.\n' ;;
  "--json jobs runner status") printf '{"state":"stopped"}\n' ;;
  "--json jobs list") printf '[]\n' ;;
  "jobs run verification --here") printf 'foreground verification passed\n' ;;
  "jobs setup")
    mkdir -p "$HOME/.archdev"
    touch "$HOME/.archdev/runner-installed"
    printf '{"project_id":"project_test","runner":"running"}\n'
    ;;
  "--json jobs run verification") printf '{"id":"job_test","state":"queued","commit_oid":"commit_test"}\n' ;;
  "--json jobs show job_test") printf '{"id":"job_test","state":"succeeded","commit_oid":"commit_test"}\n' ;;
  "jobs logs job_test") printf 'focused verification passed\n' ;;
  "--json jobs cancel job_test") printf '{"id":"job_test","state":"cancelled"}\n' ;;
  "--json jobs retry job_test") printf '{"id":"job_test","state":"queued"}\n' ;;
  "--json jobs clean --status succeeded failed cancelled") printf '{"matched":1,"deleted":["job_test"],"failed":[]}\n' ;;
  "--json jobs runner doctor") printf '{"healthy":true}\n' ;;
  "jobs runner start") printf 'Runner started.\n' ;;
  "jobs runner stop") printf 'Runner stopped.\n' ;;
  "jobs runner uninstall") printf 'Runner uninstalled; data preserved.\n' ;;
  "jobs repo enable") printf 'Repository enabled.\n' ;;
  "jobs repo submit") printf 'Submitted commit_test.\n' ;;
  "jobs repo sync") printf 'Synchronized commit_test.\n' ;;
  "jobs repo disable") printf 'Repository disabled.\n' ;;
  "--json jobs trigger one_off --payload "*) printf '{"id":"job_trigger","state":"queued"}\n' ;;
  *) printf 'unexpected fake ArchDev arguments: %s\n' "$*" >&2; exit 2 ;;
esac
ARCHDEV
chmod 0755 "$root/release/fixture/archdev"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target="darwin-arm64" ;;
  Darwin-x86_64) target="darwin-x64" ;;
  Linux-aarch64) target="linux-arm64" ;;
  Linux-x86_64) target="linux-x64" ;;
  *) printf 'Unsupported test host: %s %s\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
esac
if [[ "$target" == linux-x64 ]] && command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
  target="linux-x64-musl"
fi
asset="archdev-$target.tar.gz"
tar -C "$root/release/fixture" -czf "$root/release/$asset" archdev
(
  cd "$root/release"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$asset" >SHA256SUMS
  else
    shasum -a 256 "$asset" >SHA256SUMS
  fi
)

log="$root/archdev.log"
mkdir -p "$root/bin"
touch "$root/bin/archdev-dashboard"
binary="$(
  cd "$root/project"
  HOME="$root/home" \
    PATH="/usr/bin:/bin" \
    ARCHDEV_INSTALL_DIR="$root/bin" \
    ARCHDEV_RELEASE_BASE_URL="file://$root/release" \
    ARCHDEV_TEST_LOG="$log" \
    bash .agents/skills/jobs/scripts/bootstrap.sh
)"
expected_binary="$(cd -P "$root/bin" && pwd)/archdev"
test "$binary" = "$expected_binary"
test -x "$binary"
test ! -e "$root/bin/archdev-dashboard"
cp -R "$root/release" "$root/tampered-release"
printf '%064d  %s\n' 0 "$asset" >"$root/tampered-release/SHA256SUMS"
if HOME="$root/tampered-home" \
  PATH="/usr/bin:/bin" \
  ARCHDEV_INSTALL_DIR="$root/tampered-bin" \
  ARCHDEV_RELEASE_BASE_URL="file://$root/tampered-release" \
  bash "$root/project/.agents/skills/jobs/scripts/bootstrap.sh" >/dev/null 2>&1; then
  printf 'Jobs bootstrap accepted a release with the wrong checksum.\n' >&2
  exit 1
fi
test ! -e "$root/tampered-bin/archdev"

run_archdev() {
  (
    cd "$root/project"
    HOME="$root/home" ARCHDEV_TEST_LOG="$log" "$binary" "$@"
  )
}

# First-use story: inspect before mutation, choose the foreground path once,
# then enable durable execution and observe the exact submitted job.
run_archdev check >/dev/null
run_archdev --json jobs runner status >/dev/null
run_archdev --json jobs list >/dev/null
run_archdev jobs run verification --here >/dev/null
run_archdev jobs setup >/dev/null
test -e "$root/home/.archdev/runner-installed"
created="$(run_archdev --json jobs run verification)"
printf '%s' "$created" | grep -F '"id":"job_test"' >/dev/null
printf '%s' "$created" | grep -F '"commit_oid":"commit_test"' >/dev/null
shown="$(run_archdev --json jobs show job_test)"
printf '%s' "$shown" | grep -F '"state":"succeeded"' >/dev/null
run_archdev jobs logs job_test >/dev/null
run_archdev --json jobs cancel job_test >/dev/null
run_archdev --json jobs retry job_test >/dev/null
run_archdev --json jobs clean --status succeeded failed cancelled >/dev/null
run_archdev --json jobs runner doctor >/dev/null
run_archdev jobs runner stop >/dev/null
run_archdev jobs runner start >/dev/null
run_archdev jobs repo enable >/dev/null
run_archdev jobs repo submit >/dev/null
run_archdev jobs repo sync >/dev/null
run_archdev --json jobs trigger one_off --payload '{"prompt":"Run the focused verification"}' >/dev/null
run_archdev jobs repo disable >/dev/null
run_archdev jobs runner uninstall >/dev/null

# Jobs setup must remain local and must not invent a user or provider login.
if grep -Eq 'auth login|agents setup|provider login|^setup$' "$log"; then
  printf 'Jobs skill crossed into authentication or another setup domain.\n' >&2
  exit 1
fi
test ! -e "$root/home/.archdev-test-authenticated"
test ! -e "$root/home/.archdev/credentials"

printf 'Jobs installs in both scopes and completes foreground and durable automation without authentication.\n'
