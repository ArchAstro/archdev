#!/bin/sh
# Install the latest published release with this checkout's install.sh, inside
# a Linux distribution container, as a normal user:
#
#   docker run --rm -v "$PWD:/src:ro" ubuntu:20.04 sh /src/scripts/test-linux-release-install.sh
#
# Fixture releases cannot catch a binary that does not start on a
# distribution (an older glibc, a missing loader), so this one installs the
# real archive and runs it. EXPECT_MUSL_FALLBACK=1 marks an x64 host whose glibc
# is too old for the glibc build, where the musl build must be installed
# instead. EXPECT_GLIBC_FLOOR=1 marks an arm64 host whose
# glibc is older than the build needs: the installer must refuse and name the
# glibc version.
set -eu

# Prerequisites a fresh image lacks: curl, CA certificates, bash, useradd, su.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq curl ca-certificates >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q curl shadow-utils util-linux >/dev/null
elif command -v apk >/dev/null 2>&1; then
  apk add -q bash curl shadow >/dev/null
fi

useradd -m -s /bin/bash installer-test
exec su installer-test -s /bin/bash -c '
set -eu
export SHELL=/bin/bash
cd "$HOME"
echo "== $(. /etc/os-release; echo "$PRETTY_NAME") $(uname -m)"

if [ "${EXPECT_GLIBC_FLOOR:-}" = 1 ]; then
  if bash /src/install.sh --skip-login >out.log 2>&1; then
    cat out.log; echo "expected the installer to refuse this glibc"; exit 1
  fi
  cat out.log
  grep -q "needs glibc [0-9.]* or later" out.log
  test ! -e .local/bin/archdev
  echo "PASS refused with the glibc floor"
  exit 0
fi

# The documented one-liner shape: the script arrives on stdin, no terminal.
cat /src/install.sh | bash >out.log 2>&1 || { cat out.log; exit 1; }
cat out.log
if [ "${EXPECT_MUSL_FALLBACK:-}" = 1 ]; then
  grep -q "installing the static musl build" out.log
fi
version="$(.local/bin/archdev --version)"
echo "installed $version"
case "$version" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "bad version: $version"; exit 1 ;; esac

# A new login shell finds it through the PATH line the installer added.
test "$(bash -ic "command -v archdev" 2>/dev/null)" = "$HOME/.local/bin/archdev"

# A second run changes nothing.
cat /src/install.sh | bash >again.log 2>&1 || { cat again.log; exit 1; }
grep -q "already installed" again.log
test "$(grep -c "Added by the ArchDev installer" .bashrc)" = 1
echo "PASS"
'
