#!/usr/bin/env bash
# Test-only transport replacement. Production bootstraps have no URL/hash override.
prepare_bootstrap_fixture() {
  cmp "$bootstrap" "$repo/skills/$(basename "$(dirname "$(dirname "$bootstrap")")")/scripts/bootstrap.sh"
  mkdir -p "$root/transport" "$root/downloads"
  # Ambient installer overrides cannot replace the trusted release origin or skip verification.
  export ARCHDEV_RELEASE_BASE_URL="https://attacker.invalid/releases"
  export ARCHDEV_INSTALL_SKIP_VERIFY=true
  export TMPDIR="$root/downloads"
  export ARCHDEV_TEST_INSTALLER="$root/installer/install.sh"
  cat > "$root/transport/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" = 11 && "$1" = --fail && "$2" = --silent && "$3" = --show-error && "$4" = --location && "$5" = --proto && "$6" = '=https' && "$7" = --proto-redir && "$8" = '=https' && "$9" = --output ]]
[[ "${11}" = https://raw.githubusercontent.com/ArchAstro/archdev/7c16002d66a004b13812cf675042cb1c50fbf6df/install.sh ]]
cp "$ARCHDEV_TEST_INSTALLER" "${10}"
CURL
  chmod +x "$root/transport/curl"
  if command -v sha256sum >/dev/null 2>&1; then
    fixture_hash="$(sha256sum "$ARCHDEV_TEST_INSTALLER")"
  else
    fixture_hash="$(shasum -a 256 "$ARCHDEV_TEST_INSTALLER")"
  fi
  # Patch only the copy installed by the real skill manager, never repository code.
  sed "s/^installer_sha256=.*/installer_sha256=\"${fixture_hash%% *}\"/" "$bootstrap" > "$root/patched-bootstrap"
  cat "$root/patched-bootstrap" > "$bootstrap"
}

assert_bootstrap_rejects_untrusted_installer() {
  # Successful installation also removes the private download.
  test -z "$(ls -A "$root/downloads")"
  # A transport failure cannot produce a path or leave downloaded code behind.
  if ARCHDEV_TEST_INSTALLER="$root/missing" PATH="$root/transport:/usr/bin:/bin" bash "$bootstrap" > "$root/failed-output" 2> "$root/failed-error"; then
    echo 'Expected installer download failure' >&2
    exit 1
  fi
  test ! -s "$root/failed-output"
  grep -Fq 'Could not download' "$root/failed-error"
  test -z "$(ls -A "$root/downloads")"

  # Valid shell with different bytes must be rejected before its side effect.
  printf 'touch "%s"\n' "$root/tamper-executed" > "$root/installer/tampered.sh"
  if ARCHDEV_TEST_INSTALLER="$root/installer/tampered.sh" PATH="$root/transport:/usr/bin:/bin" bash "$bootstrap" > "$root/failed-output" 2> "$root/failed-error"; then
    echo 'Expected tampered installer rejection' >&2
    exit 1
  fi
  grep -Fq 'SHA-256 mismatch' "$root/failed-error"
  test ! -e "$root/tamper-executed"
  # Conditional callers disable errexit inside shell functions; rejection must persist.
  if ARCHDEV_TEST_INSTALLER="$root/installer/tampered.sh" PATH="$root/transport:/usr/bin:/bin" bash -c 'if source "$1"; then exit 0; else exit 1; fi' _ "$bootstrap" > "$root/failed-output" 2> "$root/failed-error"; then
    echo 'Expected conditional caller to reject tampered installer' >&2
    exit 1
  fi
  grep -Fq 'SHA-256 mismatch' "$root/failed-error"
  test ! -e "$root/tamper-executed"
  test ! -s "$root/failed-output"
  test -z "$(ls -A "$root/downloads")"
}
