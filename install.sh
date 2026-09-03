#!/usr/bin/env bash

set -euo pipefail

OWNER="ArchAstro"
REPO="archdev"
BINARY_NAME="archdev"
SIDECAR_NAME="archdev-dashboard"
INSTALL_DIR="${ARCHDEV_INSTALL_DIR:-}"
REQUESTED_VERSION="${ARCHDEV_VERSION:-latest}"
RELEASE_BASE_URL="${ARCHDEV_RELEASE_BASE_URL:-}"
SYSTEM_INSTALL="false"
DRY_RUN="false"
PRINT_ASSET_URL="false"
SKIP_PATH_UPDATE="${ARCHDEV_INSTALL_SKIP_PATH_UPDATE:-false}"
SKIP_COMPLETIONS="${ARCHDEV_INSTALL_SKIP_COMPLETIONS:-false}"
SKIP_VERIFY="${ARCHDEV_INSTALL_SKIP_VERIFY:-false}"

usage() {
  cat <<'EOF'
Usage: install.sh [--version <version>] [--install-dir <dir>] [--base-url <url>] [--system] [--dry-run] [--print-asset-url]

Options:
  --version <version>       Install a specific version, for example 0.31.0
  --install-dir <dir>       Install into a specific directory
  --base-url <url>          Override the release download base URL
  --system                  Install into /usr/local/bin
  --dry-run                 Print the resolved install plan without downloading
  --print-asset-url         Print only the resolved asset URL and exit
  -h, --help                Show help
EOF
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) REQUESTED_VERSION="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --base-url) RELEASE_BASE_URL="$2"; shift 2 ;;
    --system) SYSTEM_INSTALL="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --print-asset-url) PRINT_ASSET_URL="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

SKIP_PATH_UPDATE="$(normalize_bool "$SKIP_PATH_UPDATE")"
SKIP_COMPLETIONS="$(normalize_bool "$SKIP_COMPLETIONS")"
SKIP_VERIFY="$(normalize_bool "$SKIP_VERIFY")"

case "$(uname -s)" in
  Darwin) PLATFORM="darwin" ;;
  Linux) PLATFORM="linux" ;;
  *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH_LABEL="x64" ;;
  arm64|aarch64) ARCH_LABEL="arm64" ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
if [[ "$PLATFORM" == linux && "$ARCH_LABEL" == x64 ]] &&
   command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
  ARCH_LABEL="x64-musl"
fi

if [[ -z "$INSTALL_DIR" ]]; then
  if [[ "$SYSTEM_INSTALL" == true ]]; then
    INSTALL_DIR="/usr/local/bin"
  elif [[ "$PLATFORM" == darwin && -d /usr/local/bin && -w /usr/local/bin ]]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
fi

VERSION_TAG="$REQUESTED_VERSION"
if [[ "$VERSION_TAG" != latest && "$VERSION_TAG" != v* ]]; then
  VERSION_TAG="v$VERSION_TAG"
fi
ASSET_NAME="archdev-${PLATFORM}-${ARCH_LABEL}.tar.gz"
if [[ -n "$RELEASE_BASE_URL" ]]; then
  RESOLVED_RELEASE_BASE_URL="${RELEASE_BASE_URL%/}"
elif [[ "$REQUESTED_VERSION" == latest ]]; then
  RESOLVED_RELEASE_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/latest/download"
else
  RESOLVED_RELEASE_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION_TAG}"
fi
ASSET_URL="${RESOLVED_RELEASE_BASE_URL}/${ASSET_NAME}"
CHECKSUM_URL="${RESOLVED_RELEASE_BASE_URL}/SHA256SUMS"

if [[ "$PRINT_ASSET_URL" == true ]]; then
  printf '%s\n' "$ASSET_URL"
  exit 0
fi
if [[ "$DRY_RUN" == true ]]; then
  cat <<EOF
version=${REQUESTED_VERSION}
platform=${PLATFORM}
arch=${ARCH_LABEL}
asset=${ASSET_NAME}
release_base_url=${RESOLVED_RELEASE_BASE_URL}
asset_url=${ASSET_URL}
checksum_url=${CHECKSUM_URL}
install_dir=${INSTALL_DIR}
binary_path=${INSTALL_DIR}/${BINARY_NAME}
sidecar_path=${INSTALL_DIR}/${SIDECAR_NAME}
EOF
  exit 0
fi

for command_name in curl tar mktemp install; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

mkdir -p "$INSTALL_DIR"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ASSET_PATH="$TEMP_DIR/$ASSET_NAME"
CHECKSUM_PATH="$TEMP_DIR/SHA256SUMS"
EXTRACT_DIR="$TEMP_DIR/extract"

printf 'Downloading %s\n' "$ASSET_NAME"
curl -fsSL "$ASSET_URL" -o "$ASSET_PATH"
curl -fsSL "$CHECKSUM_URL" -o "$CHECKSUM_PATH"
EXPECTED_SUM="$(awk -v asset="$ASSET_NAME" '$2 == asset { print $1 }' "$CHECKSUM_PATH")"
[[ -n "$EXPECTED_SUM" ]] || { printf 'Checksum missing for %s\n' "$ASSET_NAME" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SUM="$(sha256sum "$ASSET_PATH" | awk '{print $1}')"
else
  command -v shasum >/dev/null 2>&1 || { printf 'SHA-256 tool is required\n' >&2; exit 1; }
  ACTUAL_SUM="$(shasum -a 256 "$ASSET_PATH" | awk '{print $1}')"
fi
[[ "$ACTUAL_SUM" == "$EXPECTED_SUM" ]] || { printf 'Checksum mismatch for %s\n' "$ASSET_NAME" >&2; exit 1; }

mkdir -p "$EXTRACT_DIR"
tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR"
for executable in "$BINARY_NAME" "$SIDECAR_NAME"; do
  [[ -f "$EXTRACT_DIR/$executable" ]] || { printf 'Archive is missing %s\n' "$executable" >&2; exit 1; }
  install -m 0755 "$EXTRACT_DIR/$executable" "$INSTALL_DIR/$executable"
done

append_once() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" || printf '\n%s\n' "$line" >>"$file"
}

if [[ "$SKIP_PATH_UPDATE" != true && "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      case "$(basename "${SHELL:-}")" in
        fish) append_once "$HOME/.config/fish/config.fish" 'fish_add_path $HOME/.local/bin' ;;
        zsh) append_once "$HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"' ;;
        bash) append_once "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"' ;;
        *) printf 'Add %s to your PATH manually.\n' "$HOME/.local/bin" ;;
      esac
  esac
fi

if [[ "$SKIP_COMPLETIONS" != true ]]; then
  case "$(basename "${SHELL:-}")" in
    fish)
      completion="$HOME/.config/fish/completions/archdev.fish"
      mkdir -p "$(dirname "$completion")"
      "$INSTALL_DIR/$BINARY_NAME" completion fish >"$completion"
      ;;
    zsh)
      completion="$HOME/.zsh/completions/_archdev"
      mkdir -p "$(dirname "$completion")"
      "$INSTALL_DIR/$BINARY_NAME" completion zsh >"$completion"
      append_once "$HOME/.zshrc" 'fpath=("$HOME/.zsh/completions" $fpath)'
      if ! grep -Fq 'compinit' "$HOME/.zshrc"; then
        printf '\nautoload -Uz compinit\ncompinit\n' >>"$HOME/.zshrc"
      fi
      ;;
    bash)
      completion="$HOME/.local/share/bash-completion/completions/archdev"
      mkdir -p "$(dirname "$completion")"
      "$INSTALL_DIR/$BINARY_NAME" completion bash >"$completion"
      ;;
  esac
fi

if [[ "$SKIP_VERIFY" != true ]]; then
  "$INSTALL_DIR/$BINARY_NAME" --version
fi
printf 'Installed %s and %s to %s\n' "$BINARY_NAME" "$SIDECAR_NAME" "$INSTALL_DIR"
