#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
root="$(cd -P "$root" && pwd)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home" "$root/project" "$root/installer"
git -C "$root/project" init -q

# Cross the real skill-manager boundary in both supported installation scopes.
HOME="$root/home" npx --yes skills add "$repo" --global --skill agents --agent codex --yes --copy >/dev/null
test -x "$root/home/.agents/skills/agents/scripts/bootstrap.sh"
(
  cd "$root/project"
  HOME="$root/home" npx --yes skills add "$repo" --skill agents --agent codex --yes --copy >/dev/null
)
bootstrap="$root/project/.agents/skills/agents/scripts/bootstrap.sh"
test -x "$bootstrap"
test -f "$root/project/.agents/skills/agents/references/providers.md"
test -f "$root/project/.agents/skills/agents/references/execution.md"

# Substitute only the release boundary: no real installation or account writes.
cat > "$root/installer/install.sh" <<'INSTALLER'
set -eu
[[ -z "${ARCHDEV_RELEASE_BASE_URL:-}" ]] || exit 1
[[ "${ARCHDEV_INSTALL_SKIP_VERIFY:-}" == false ]] || exit 1
printf 'install\n' >> "$ARCHDEV_TEST_INSTALL_LOG"
mkdir -p "$ARCHDEV_INSTALL_DIR"
cat > "$ARCHDEV_INSTALL_DIR/archdev" <<'CLI'
#!/usr/bin/env bash
if [[ "$*" == '--version' ]]; then echo fixture; exit 0; fi
if [[ "$*" == 'agents run --help' ]]; then echo 'Usage: archdev agents run [options] [prompt]'; exit 0; fi
if [[ "$*" == 'settings provider models --help' ]]; then echo 'Usage: archdev settings provider models [options] <provider>'; exit 0; fi
exit 1
CLI
chmod +x "$ARCHDEV_INSTALL_DIR/archdev"
INSTALLER
source "$repo/tests/bootstrap-fixture.sh"
prepare_bootstrap_fixture
export ARCHDEV_INSTALL_DIR="$root/bin"
export ARCHDEV_TEST_INSTALL_LOG="$root/installs"

# A cold install returns one absolute executable path despite PATH omitting it.
binary="$(HOME="$root/home" PATH="$root/transport:/usr/bin:/bin" bash "$bootstrap")"
test "$binary" = "$root/bin/archdev"
"$binary" agents run --help
test "$(wc -l < "$root/installs" | tr -d ' ')" = 1

# A capable PATH installation must be reused without contacting the installer.
reused="$(PATH="$root/bin:$root/transport:/usr/bin:/bin" bash "$bootstrap")"
test "$reused" = "$binary"
test "$(wc -l < "$root/installs" | tr -d ' ')" = 1

# An older CLI is upgraded once; its replacement must satisfy the Agents/provider probes.
printf '#!/usr/bin/env bash\necho "Usage: archdev [options]"\nexit 0\n' > "$binary"
updated="$(PATH="$root/bin:$root/transport:/usr/bin:/bin" bash "$bootstrap")"
test "$updated" = "$binary"
test "$(wc -l < "$root/installs" | tr -d ' ')" = 2
"$updated" agents run --help

assert_bootstrap_rejects_untrusted_installer
printf 'Agents skill packages in both scopes; bootstrap handles cold, current, outdated, and failed installs.\n'
