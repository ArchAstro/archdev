#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/home" "$root/global-project" "$root/project"
git -C "$root/global-project" init -q
git -C "$root/project" init -q

# Package installation: npx skills must retain the complete self-contained
# Tasks package in both supported scopes.
HOME="$root/home" npx --yes skills add "$repo" \
  --global --skill tasks --agent codex --yes --copy >/dev/null
test -x "$root/home/.agents/skills/tasks/scripts/bootstrap.sh"
(
  cd "$root/project"
  HOME="$root/home" npx --yes skills add "$repo" \
    --skill tasks --agent codex --yes --copy >/dev/null
)
test -x "$root/project/.agents/skills/tasks/scripts/bootstrap.sh"
grep -F 'releases/latest/download' \
  "$root/project/.agents/skills/tasks/scripts/bootstrap.sh" >/dev/null
grep -F 'releases/latest/download' \
  "$root/project/.agents/skills/tasks/scripts/bootstrap.ps1" >/dev/null
grep -F 'tasks guide --help' \
  "$root/project/.agents/skills/tasks/scripts/bootstrap.ps1" >/dev/null
if grep -ERq 'raw\.githubusercontent\.com/.*/(main|refs/heads)' \
  "$root/project/.agents/skills/tasks/scripts"; then
  printf 'Tasks bootstrap must not execute a mutable branch installer.\n' >&2
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
  "tasks guide --help") ;;
  "tasks guide") printf 'Claim atomically and retain the lease and session IDs.\n' ;;
  "auth status") test -f "$HOME/.archdev-test-authenticated" ;;
  "auth login") touch "$HOME/.archdev-test-authenticated"; printf 'Signed in\n' ;;
  "--json tasks claim "*) printf '{"lease":{"id":"lease_test"},"session_id":"session_test","task":{"id":"tsk_ready","status":"in_progress"}}\n' ;;
  "--json tasks "*) printf '{"ok":true}\n' ;;
  "tasks graph schema") printf '{"type":"object"}\n' ;;
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
    bash .agents/skills/tasks/scripts/bootstrap.sh
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
  bash "$root/project/.agents/skills/tasks/scripts/bootstrap.sh" >/dev/null 2>&1; then
  printf 'Tasks bootstrap accepted a release with the wrong checksum.\n' >&2
  exit 1
fi
test ! -e "$root/tampered-bin/archdev"

run_archdev() {
  HOME="$root/home" ARCHDEV_TEST_LOG="$log" "$binary" "$@"
}

# First-use story: start signed out, authenticate once, inspect shared work,
# author dependencies, claim atomically, and preserve the returned fence.
run_archdev tasks guide >/dev/null
if run_archdev auth status >/dev/null 2>&1; then
  printf 'Expected the cold Tasks user to start signed out.\n' >&2
  exit 1
fi
run_archdev auth login >/dev/null
run_archdev auth status
run_archdev --json tasks search 'retry handling' >/dev/null
run_archdev --json tasks ready --explain >/dev/null
run_archdev --json tasks blocked >/dev/null
run_archdev --json tasks show tsk_ready >/dev/null
run_archdev --json tasks create 'Add retry handling' --priority 1 --tag reliability >/dev/null
run_archdev tasks graph schema >"$root/task-graph.schema.json"
printf '{"tasks":[]}\n' >"$root/project/plan.json"
run_archdev --json tasks graph import --file "$root/project/plan.json" >/dev/null
run_archdev --json tasks deps add tsk_ready --blocked-by tsk_prerequisite >/dev/null
run_archdev --json tasks deps list tsk_ready >/dev/null
run_archdev --json tasks deps remove tsk_ready --blocked-by tsk_prerequisite >/dev/null
run_archdev --json tasks deps cycles >/dev/null
claim="$(run_archdev --json tasks claim tsk_ready --session-name 'retry implementation')"
printf '%s' "$claim" | grep -F '"id":"lease_test"' >/dev/null
printf '%s' "$claim" | grep -F '"session_id":"session_test"' >/dev/null
run_archdev --json tasks update tsk_ready --description 'Current verified state' --lease-id lease_test --session-id session_test >/dev/null
run_archdev --json tasks comment tsk_ready 'Focused verification passed' >/dev/null
run_archdev --json tasks links add tsk_ready 'owner/repo#42' >/dev/null
run_archdev --json tasks links remove tsk_ready 'owner/repo#42' >/dev/null
run_archdev --json tasks close tsk_ready --lease-id lease_test --session-id session_test >/dev/null
run_archdev --json tasks claim tsk_abandoned --session-name 'abandoned follow-up' >/dev/null
run_archdev --json tasks release tsk_abandoned --lease-id lease_test --session-id session_test >/dev/null
run_archdev --json tasks reopen tsk_completed >/dev/null
run_archdev --json tasks list --room tem_room >/dev/null
run_archdev --json tasks create 'Watch deploy health' --room tem_room --kind daily >/dev/null
run_archdev --json tasks close tsk_room --room tem_room >/dev/null

# Tasks stays independent of local automation and repository setup.
test ! -e "$root/project/archdev.json"
test ! -e "$root/home/.archdev/daemon.sqlite"
if grep -Eq '(^| )jobs( |$)|provider|agents setup| setup$' "$log"; then
  printf 'Tasks skill crossed into another setup domain.\n' >&2
  exit 1
fi

printf 'Tasks installs in both scopes and completes an authenticated fenced work lifecycle without Jobs.\n'
