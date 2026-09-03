#!/usr/bin/env bash

set -euo pipefail

OUTPUT_DIR=""
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[[ -n "$OUTPUT_DIR" && -n "$VERSION" ]] || { printf '%s\n' 'usage: create-unix-fixtures.sh --output-dir <dir> --version <version>' >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
for target in darwin-arm64 darwin-x64 linux-arm64 linux-x64 linux-x64-musl; do
  fixture="$(mktemp -d)"
  cat >"$fixture/archdev" <<EOF
#!/usr/bin/env sh
if [ "\${1:-}" = "--version" ]; then printf '%s\n' '$VERSION'; exit 0; fi
if [ "\${1:-}" = "completion" ]; then printf '# completion for %s\n' "\${2:-unknown}"; exit 0; fi
exit 0
EOF
  cat >"$fixture/archdev-dashboard" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$fixture/archdev" "$fixture/archdev-dashboard"
  tar -C "$fixture" -czf "$OUTPUT_DIR/archdev-$target.tar.gz" archdev archdev-dashboard
  rm -rf "$fixture"
done
(
  cd "$OUTPUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum archdev-*.tar.gz >SHA256SUMS
  else
    shasum -a 256 archdev-*.tar.gz >SHA256SUMS
  fi
)
