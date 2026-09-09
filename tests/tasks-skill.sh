#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
root="$(cd -P "$root" && pwd)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home" "$root/project" "$root/installer"
git -C "$root/project" init -q

# Cross the real skill-manager boundary in both supported installation scopes.
HOME="$root/home" npx --yes skills add "$repo" --global --skill tasks --agent codex --yes --copy >/dev/null
test -x "$root/home/.agents/skills/tasks/scripts/bootstrap.sh"
(
  cd "$root/project"
  HOME="$root/home" npx --yes skills add "$repo" --skill tasks --agent codex --yes --copy >/dev/null
)
bootstrap="$root/project/.agents/skills/tasks/scripts/bootstrap.sh"
test -x "$bootstrap"

# Substitute only the release boundary: no real installation or account writes.
cat > "$root/installer/install.sh" <<'INSTALLER'
set -eu
printf 'install\n' >> "$ARCHDEV_TEST_INSTALL_LOG"
mkdir -p "$ARCHDEV_INSTALL_DIR"
cat > "$ARCHDEV_INSTALL_DIR/archdev" <<'CLI'
#!/usr/bin/env bash
if [[ "$*" == '--version' ]]; then echo fixture; exit 0; fi
[[ "$*" == 'tasks review update --help' ]]
CLI
chmod +x "$ARCHDEV_INSTALL_DIR/archdev"
INSTALLER
export ARCHDEV_INSTALLER_URL="file://$root/installer/install.sh"
export ARCHDEV_INSTALL_DIR="$root/bin"
export ARCHDEV_TEST_INSTALL_LOG="$root/installs"

# A cold install returns one absolute executable path despite PATH omitting it.
binary="$(HOME="$root/home" PATH=/usr/bin:/bin bash "$bootstrap")"
test "$binary" = "$root/bin/archdev"
"$binary" tasks review update --help
test "$(wc -l < "$root/installs" | tr -d ' ')" = 1

# A capable PATH installation must be reused without contacting the installer.
reused="$(PATH="$root/bin:/usr/bin:/bin" bash "$bootstrap")"
test "$reused" = "$binary"
test "$(wc -l < "$root/installs" | tr -d ' ')" = 1

# An older CLI is upgraded once; its replacement must satisfy the review probe.
printf '#!/usr/bin/env bash\nexit 1\n' > "$binary"
updated="$(PATH="$root/bin:/usr/bin:/bin" bash "$bootstrap")"
test "$updated" = "$binary"
test "$(wc -l < "$root/installs" | tr -d ' ')" = 2
"$updated" tasks review update --help

# An installer failure must fail bootstrap rather than emit a usable-looking path.
if ARCHDEV_INSTALLER_URL="file://$root/missing" PATH=/usr/bin:/bin bash "$bootstrap" > "$root/failed-output" 2>/dev/null; then
  echo 'Expected installer failure' >&2
  exit 1
fi
test ! -s "$root/failed-output"
printf 'Tasks skill packages in both scopes; bootstrap handles cold, current, outdated, and failed installs.\n'
