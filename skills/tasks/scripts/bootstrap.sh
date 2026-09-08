#!/usr/bin/env bash

set -euo pipefail

install_dir="${ARCHDEV_INSTALL_DIR:-$HOME/.local/bin}"
requested_version="${ARCHDEV_VERSION:-latest}"
release_base_url="${ARCHDEV_RELEASE_BASE_URL:-}"

absolute_path() {
  local candidate="$1"
  local directory
  directory="$(cd -P "$(dirname "$candidate")" && pwd)"
  printf '%s/%s\n' "$directory" "$(basename "$candidate")"
}

install_archdev() (
  set -euo pipefail
  local platform architecture asset base temp_dir archive checksums expected actual
  for command_name in curl tar mktemp install; do
    command -v "$command_name" >/dev/null 2>&1 || {
      printf 'Missing required command: %s\n' "$command_name" >&2
      exit 1
    }
  done
  case "$(uname -s)" in
    Darwin) platform="darwin" ;;
    Linux) platform="linux" ;;
    *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) architecture="x64" ;;
    arm64|aarch64) architecture="arm64" ;;
    *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
  if [[ "$platform" == linux && "$architecture" == x64 ]] &&
     command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    architecture="x64-musl"
  fi
  asset="archdev-${platform}-${architecture}.tar.gz"
  if [[ -n "$release_base_url" ]]; then
    base="${release_base_url%/}"
  elif [[ "$requested_version" == latest ]]; then
    base="https://github.com/ArchAstro/archdev/releases/latest/download"
  else
    [[ "$requested_version" == v* ]] || requested_version="v$requested_version"
    base="https://github.com/ArchAstro/archdev/releases/download/$requested_version"
  fi
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  archive="$temp_dir/$asset"
  checksums="$temp_dir/SHA256SUMS"
  curl --fail --silent --show-error --location "$base/$asset" --output "$archive"
  curl --fail --silent --show-error --location "$base/SHA256SUMS" --output "$checksums"
  expected="$(awk -v asset="$asset" '$2 == asset { print $1 }' "$checksums")"
  [[ -n "$expected" ]] || { printf 'Checksum missing for %s\n' "$asset" >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$archive" | awk '{print $1}')"
  else
    command -v shasum >/dev/null 2>&1 || { printf 'SHA-256 tool is required\n' >&2; exit 1; }
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  fi
  [[ "$actual" == "$expected" ]] || { printf 'Checksum mismatch for %s\n' "$asset" >&2; exit 1; }
  mkdir -p "$temp_dir/extract" "$install_dir"
  tar -xzf "$archive" -C "$temp_dir/extract"
  [[ -f "$temp_dir/extract/archdev" ]] || { printf 'Archive is missing archdev\n' >&2; exit 1; }
  install -m 0755 "$temp_dir/extract/archdev" "$install_dir/archdev"
  rm -f "$install_dir/archdev-dashboard"
)

candidate="$(command -v archdev 2>/dev/null || true)"
if [[ -n "$candidate" ]]; then
  executable="$(absolute_path "$candidate")"
else
  install_archdev
  executable="$(absolute_path "$install_dir/archdev")"
fi

if ! "$executable" tasks guide --help >/dev/null 2>&1; then
  printf 'Updating ArchDev because this version lacks the Tasks domain.\n' >&2
  install_archdev
  executable="$(absolute_path "$install_dir/archdev")"
fi

[[ -x "$executable" ]] || {
  printf 'ArchDev installation did not create an executable at %s\n' "$executable" >&2
  exit 1
}
"$executable" --version >&2
"$executable" tasks guide --help >/dev/null 2>&1 || {
  printf 'Installed ArchDev does not provide the Tasks domain.\n' >&2
  exit 1
}
printf '%s\n' "$executable"
