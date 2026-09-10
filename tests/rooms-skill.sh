#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
root="$(cd -P "$root" && pwd)"
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
grep -F '7c16002d66a004b13812cf675042cb1c50fbf6df' \
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
[[ -z "${ARCHDEV_RELEASE_BASE_URL:-}" ]] || exit 1
[[ "${ARCHDEV_INSTALL_SKIP_VERIFY:-}" == false ]] || exit 1
mkdir -p "$ARCHDEV_INSTALL_DIR"
cat >"$ARCHDEV_INSTALL_DIR/archdev" <<'ARCHDEV'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'archdev test\n'
  exit 0
fi
if [[ "${1:-}" == "rooms" && "${2:-}" == "start" && "${3:-}" == "--help" ]]; then
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
  printf '{"room":{"id":"tem_room"},"data":[{"id":"msg_fact","content":"The stable retry key survives response loss","user":"usr_teammate","agent":null,"created_at":"2026-09-07T17:00:00Z","similarity_score":0.9}]}\n'
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
bootstrap="$root/project/.agents/skills/rooms/scripts/bootstrap.sh"
source "$repo/tests/bootstrap-fixture.sh"
prepare_bootstrap_fixture
export ARCHDEV_INSTALL_DIR="$root/bin"

binary="$(
  cd "$root/project"
  HOME="$root/home" \
    PATH="$root/transport:/usr/bin:/bin" \
    ARCHDEV_INSTALL_DIR="$root/bin" \
    bash .agents/skills/rooms/scripts/bootstrap.sh
)"

expected="$(cd -P "$root/bin" && pwd)/archdev"
test "$binary" = "$expected"
test -x "$binary"
"$binary" rooms start --help

# First-use boundary: follow the public skill's actual happy path from an
# unauthenticated machine through login, connection, recall, Q&A evidence, and
# one durable structured post.
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
printf '%s' "$answer_sources" | grep -F '"id":"msg_fact"' >/dev/null
published="$(HOME="$root/home" "$binary" --json rooms lesson 'Retry evidence is durable' -b 'Keep one stable key')"
printf '%s' "$published" | grep -F '"queued":true' >/dev/null

assert_bootstrap_rejects_untrusted_installer

printf 'Rooms installs in both scopes and completes login, join, recall, search, and publish.\n'
