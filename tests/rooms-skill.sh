#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/home" "$root/project" "$root/installer"
git -C "$root/project" init -q

# Installation boundary: the standard skill manager must preserve the complete
# package in both supported scopes.
HOME="$root/home" npx --yes skills add "$repo" \
  --global --skill rooms --agent codex --yes --copy >/dev/null
test -x "$root/home/.agents/skills/rooms/scripts/bootstrap.sh"
(
  cd "$root/project"
  HOME="$root/home" npx --yes skills add "$repo" \
    --skill rooms --agent codex --yes --copy >/dev/null
)
test -x "$root/project/.agents/skills/rooms/scripts/bootstrap.sh"
grep -F '9d50e7ce1e64a731d88cca8ae15ec2c45b1375df' \
  "$root/project/.agents/skills/rooms/scripts/bootstrap.sh" >/dev/null
if grep -Fq '/archdev/main/install' \
  "$root/project/.agents/skills/rooms/scripts/bootstrap.sh"; then
  printf 'Rooms bootstrap must not execute a mutable main-branch installer.\n' >&2
  exit 1
fi

# Cold-machine boundary: bootstrap invokes the official installer contract and
# returns the exact binary path even though the install directory is not on PATH.
cat >"$root/installer/install.sh" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$ARCHDEV_INSTALL_DIR"
cat >"$ARCHDEV_INSTALL_DIR/archdev" <<'ARCHDEV'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '0.35.4\n'
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "start" && "${3:-}" == "--help" ]]; then
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "search" && "${3:-}" == "--help" ]]; then
  printf 'Usage: archdev rooms search [options] <query>\n  --messages Search recent messages directly\n'
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  [[ -f "$HOME/.archdev-test-authenticated" ]]
  exit
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  touch "$HOME/.archdev-test-authenticated"
  printf 'Signed in\n'
  exit 0
fi
if [[ "${1:-}" == "--json" ]]; then shift; fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "connect" ]]; then
  printf '{"id":"tem_room","name":"Company Room","threadId":"thr_room","joined":true}\n'
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "messages" && "${3:-}" == "tem_room" ]]; then
  printf '{"room":{"id":"tem_room"},"messages":[{"id":"msg_recent","content":"Recent team context","user":"usr_teammate","created_at":"2026-09-07T18:00:00Z"}]}\n'
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "search" ]]; then
  printf '{"room":{"id":"tem_room"},"source":"cks_room","data":[{"id":"cki_fact","content":"The stable retry key survives response loss","raw_content":{"id":"11de9a9e-93ea-428a-9224-0a94f3ef5a54","user_id":"547ec22d-cccf-4413-a883-0a5071e9e502","inserted_at":"2026-09-07T17:00:00Z","metadata":{"human":"Teammate","post_type":"lesson","refs":["https://example.com/review"]}},"similarity_score":0.9}]}\n'
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "lesson" ]]; then
  printf '{"room":{"id":"tem_room"},"postType":"lesson","queued":true,"woken":true,"idempotencyKey":"room-post:test"}\n'
  exit 0
fi
exit 2
ARCHDEV
chmod 0755 "$ARCHDEV_INSTALL_DIR/archdev"
INSTALLER
chmod 0755 "$root/installer/install.sh"

binary="$(
  cd "$root/project"
  HOME="$root/home" \
    PATH="/usr/bin:/bin" \
    ARCHDEV_INSTALL_DIR="$root/bin" \
    ARCHDEV_INSTALLER_URL="file://$root/installer/install.sh" \
    bash .agents/skills/rooms/scripts/bootstrap.sh
)"

expected="$(cd -P "$root/bin" && pwd)/archdev"
test "$binary" = "$expected"
test -x "$binary"
"$binary" rooms start --help

# Bootstrap compatibility: lifecycle commands alone are insufficient. An old
# CLI on PATH must be replaced, and the returned path must name the new binary.
mkdir -p "$root/old"
cat >"$root/old/archdev" <<'OLD_ARCHDEV'
#!/usr/bin/env bash
if [[ "$*" == '--version' ]]; then printf '0.34.0\n'; exit 0; fi
if [[ "$*" == 'rooms start --help' ]]; then exit 0; fi
if [[ "$*" == 'rooms search --help' ]]; then printf 'Usage: archdev rooms search <query>\n'; exit 0; fi
printf 'Usage: archdev rooms [options] [command]\n'
exit 0
OLD_ARCHDEV
chmod 0755 "$root/old/archdev"
upgraded="$(PATH="$root/old:/usr/bin:/bin" ARCHDEV_INSTALL_DIR="$root/upgraded" \
  ARCHDEV_INSTALLER_URL="file://$root/installer/install.sh" \
  bash "$root/project/.agents/skills/rooms/scripts/bootstrap.sh")"
test "$upgraded" = "$(cd -P "$root/upgraded" && pwd)/archdev" || {
  printf 'Bootstrap accepted a lifecycle-only CLI without Knowledge search.\n' >&2
  exit 1
}

# A capable binary must not invoke the installer, even if another install
# directory is configured. A failed upgrade must not return the old binary.
existing="$(PATH="$root/bin:/usr/bin:/bin" ARCHDEV_INSTALL_DIR="$root/unused" \
  ARCHDEV_INSTALLER_URL="file://$root/missing-installer" \
  bash "$root/project/.agents/skills/rooms/scripts/bootstrap.sh")"
test "$existing" = "$expected"
cat >"$root/installer/old.sh" <<'OLD_INSTALLER'
#!/usr/bin/env bash
mkdir -p "$ARCHDEV_INSTALL_DIR"
cp "$OLD_ARCHDEV" "$ARCHDEV_INSTALL_DIR/archdev"
OLD_INSTALLER
if PATH="$root/old:/usr/bin:/bin" ARCHDEV_INSTALL_DIR="$root/rejected" \
  OLD_ARCHDEV="$root/old/archdev" ARCHDEV_INSTALLER_URL="file://$root/installer/old.sh" \
  bash "$root/project/.agents/skills/rooms/scripts/bootstrap.sh" >"$root/rejected-output" 2>"$root/rejected-error"; then
  printf 'Bootstrap accepted an installer that still lacks Knowledge search.\n' >&2
  exit 1
fi
test ! -s "$root/rejected-output"
grep -F 'Installed ArchDev does not provide' "$root/rejected-error" >/dev/null

# Command-contract fixture only: this is not live authentication, Knowledge,
# or agent behavior. Those boundaries are verified separately.
if HOME="$root/home" "$binary" auth status; then
  printf 'Expected the cold test user to start signed out.\n' >&2
  exit 1
fi
HOME="$root/home" "$binary" auth login >/dev/null
HOME="$root/home" "$binary" auth status

connected="$(HOME="$root/home" "$binary" --json rooms connect)"
printf '%s' "$connected" | grep -F '"id":"tem_room"' >/dev/null
recent="$(HOME="$root/home" "$binary" --json rooms messages tem_room --limit 15)"
printf '%s' "$recent" | grep -F '"id":"msg_recent"' >/dev/null
answer_sources="$(HOME="$root/home" "$binary" --json rooms search 'how do retries avoid duplicates')"
printf '%s' "$answer_sources" | grep -F '"id":"11de9a9e-93ea-428a-9224-0a94f3ef5a54"' >/dev/null
published="$(HOME="$root/home" "$binary" --json rooms lesson 'Retry evidence is durable' -b 'Keep one stable key')"
printf '%s' "$published" | grep -F '"queued":true' >/dev/null

printf 'Rooms packaging passes both install scopes, CLI compatibility, and fixture command contracts.\n'
