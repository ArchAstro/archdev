#!/usr/bin/env bash
#
# ArchDev installer. https://archdev.ai/install.sh redirects to this file.
#
#   curl -fsSL https://archdev.ai/install.sh | bash
#
# Installs the archdev CLI, signs you in, and runs `archdev setup` with the
# placement and reporting choices you make here. Pass flags after `bash -s --`:
#
#   curl -fsSL https://archdev.ai/install.sh | bash -s -- --help
#
# Written for bash 3.2 (the macOS system bash). Everything lives in functions
# and `main` is called from the last line, so a truncated download runs nothing.

set -euo pipefail

OWNER="ArchAstro"
REPO="archdev"
BINARY_NAME="archdev"
DOCS_URL="https://docs.archdev.ai"
HELP_URL="https://github.com/${OWNER}/${REPO}/issues"

INSTALL_DIR="${ARCHDEV_INSTALL_DIR:-}"
REQUESTED_VERSION="${ARCHDEV_VERSION:-latest}"
RELEASE_BASE_URL="${ARCHDEV_RELEASE_BASE_URL:-}"
SKIP_PATH_UPDATE="${ARCHDEV_INSTALL_SKIP_PATH_UPDATE:-false}"
SKIP_COMPLETIONS="${ARCHDEV_INSTALL_SKIP_COMPLETIONS:-false}"
SKIP_VERIFY="${ARCHDEV_INSTALL_SKIP_VERIFY:-false}"
SKIP_LOGIN="${ARCHDEV_INSTALL_SKIP_LOGIN:-false}"
SKIP_SETUP="${ARCHDEV_INSTALL_SKIP_SETUP:-false}"
NONINTERACTIVE="${ARCHDEV_INSTALL_NONINTERACTIVE:-${NONINTERACTIVE:-false}}"
SETUP_SCOPE="${ARCHDEV_INSTALL_SCOPE:-}"
SETUP_REPORTING="${ARCHDEV_INSTALL_REPORTING:-}"
SYSTEM_INSTALL="false"
DRY_RUN="false"
PRINT_ASSET_URL="false"
FORCE="false"

# Runtime state shared between steps.
PLATFORM="" ARCH_LABEL="" PLATFORM_NAME="" ASSET_NAME="" ASSET_URL="" CHECKSUM_URL=""
RESOLVED_RELEASE_BASE_URL="" TARGET_VERSION="" BIN="" MANAGED_BY="installer"
INSTALLED_VERSION="" PATH_FILE="" PATH_HINT="" SIGNED_IN="false" SETUP_DONE="false"
ACCOUNT_EMAIL="" ACCOUNT_ORG="" TEMP_DIR="" LOG="" TTY_STATE="" CHILD_PID="" SETUP_FAILED="false"
INTERACTIVE="false" FANCY="false" UNICODE="false" COLOR_MODE="none" COLUMNS_WIDE=80

usage() {
  cat <<'EOF'
ArchDev installer

Usage:
  curl -fsSL https://archdev.ai/install.sh | bash
  curl -fsSL https://archdev.ai/install.sh | bash -s -- [options]

Install options:
  --version <version>       Install a specific version, for example 0.49.2
  --install-dir <dir>       Install into a specific directory
  --system                  Install into /usr/local/bin
  --force                   Reinstall even when that version is already installed
  --base-url <url>          Override the release download base URL
  --no-modify-path          Do not add the install directory to your shell profile

Sign-in and setup options:
  --scope <user|repository> Where `archdev setup` installs the skill and hooks
  --reporting <enabled|disabled>
                            Your answer to organization activity reporting.
                            Setup only runs with `enabled`.
  --skip-login              Install only; do not sign in
  --skip-setup              Do not run `archdev setup`
  -y, --yes                 Never prompt. Sign-in and setup then run only when
                            ARCHDEV_TOKEN, --scope and --reporting provide the answers.

Other:
  --dry-run                 Print the resolved install plan without downloading
  --print-asset-url         Print only the resolved asset URL and exit
  -h, --help                Show this help

Environment:
  ARCHDEV_VERSION, ARCHDEV_INSTALL_DIR, ARCHDEV_RELEASE_BASE_URL
  ARCHDEV_INSTALL_SKIP_PATH_UPDATE, ARCHDEV_INSTALL_SKIP_COMPLETIONS
  ARCHDEV_INSTALL_SKIP_VERIFY
  ARCHDEV_INSTALL_SKIP_LOGIN, ARCHDEV_INSTALL_SKIP_SETUP
  ARCHDEV_INSTALL_SCOPE, ARCHDEV_INSTALL_REPORTING, ARCHDEV_INSTALL_NONINTERACTIVE
  ARCHDEV_TOKEN             Personal access token; signs in without a browser
  NO_COLOR                  Disable colors

Uninstall:
  archdev uninstall         Removes hooks, skills, credentials and caches,
                            then prints the command that removes the binary.
EOF
}

# ---------------------------------------------------------------------------
# Terminal capabilities and palette
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

normalize_bool() {
  case "$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

RESET="" BOLD="" C_BRAND="" C_LIGHT="" C_DEEP="" C_OK="" C_FAIL="" C_WARN="" C_DIM="" C_LINK=""

# color <r> <g> <b> <256-color fallback>
color() {
  case "$COLOR_MODE" in
    true) printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3" ;;
    256) printf '\033[38;5;%sm' "$4" ;;
  esac
}

detect_terminal() {
  if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    FANCY="true"
  fi
  if [ "$FANCY" = true ] && [ -z "${NO_COLOR:-}" ]; then
    case "${COLORTERM:-}" in
      truecolor | 24bit) COLOR_MODE="true" ;;
      *) COLOR_MODE="256" ;;
    esac
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8* | *utf-8* | *UTF8* | *utf8*) UNICODE="true" ;;
  esac
  if [ "$FANCY" = true ]; then
    # stdin is the script under `curl | bash`, so ask the terminal itself.
    COLUMNS_WIDE="$( (stty size </dev/tty) 2>/dev/null | awk '{ print $2 }' || true)"
    case "$COLUMNS_WIDE" in '' | 0 | *[!0-9]*) COLUMNS_WIDE="${COLUMNS:-80}" ;; esac
    case "$COLUMNS_WIDE" in '' | 0 | *[!0-9]*) COLUMNS_WIDE=80 ;; esac
  fi

  # Prompts read the terminal directly because stdin is the script under
  # `curl | bash`. CI and --yes never prompt.
  NONINTERACTIVE="$(normalize_bool "$NONINTERACTIVE")"
  if [ "$NONINTERACTIVE" != true ] && [ -z "${CI:-}" ] && [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
    INTERACTIVE="true"
  fi

  if [ "$COLOR_MODE" = none ]; then
    return 0
  fi
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  # The CLI's own theme: Catppuccin Mocha on dark terminals, Latte on light.
  local light="false"
  case "${COLORFGBG:-}" in *";7" | *";15") light="true" ;; esac
  if [ "$light" = true ]; then
    C_BRAND="$(color 136 57 239 93)"
    C_LIGHT="$(color 114 135 253 69)"
    C_DEEP="$(color 234 118 203 170)"
    C_OK="$(color 64 160 43 70)"
    C_FAIL="$(color 210 15 57 161)"
    C_WARN="$(color 254 100 11 202)"
    C_DIM="$(color 124 127 147 244)"
    C_LINK="$(color 4 165 229 38)"
  else
    C_BRAND="$(color 203 166 247 183)"
    C_LIGHT="$(color 180 190 254 147)"
    C_DEEP="$(color 245 194 231 218)"
    C_OK="$(color 166 227 161 151)"
    C_FAIL="$(color 243 139 168 211)"
    C_WARN="$(color 250 179 135 216)"
    C_DIM="$(color 127 132 156 245)"
    C_LINK="$(color 137 220 235 117)"
  fi
}

glyph() {
  # glyph <unicode> <ascii>
  if [ "$UNICODE" = true ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

pretty_path() {
  # shellcheck disable=SC2088 # a literal ~ for display, never expanded
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

human_mb() {
  awk -v bytes="${1:-0}" 'BEGIN { printf "%.1f MB", bytes / 1048576 }'
}

# ---------------------------------------------------------------------------
# Output primitives
# ---------------------------------------------------------------------------

PAD="     "

banner() {
  local subtitle="installer"
  if [ -n "$PLATFORM_NAME" ]; then
    subtitle="installer $(glyph '·' '-') ${PLATFORM_NAME}"
  fi
  if [ "$FANCY" != true ]; then
    printf 'ArchDev %s\n' "$subtitle"
    return 0
  fi
  printf '\n'
  if [ "$UNICODE" = true ] && [ "$COLUMNS_WIDE" -ge 56 ]; then
    printf '%s%s      ▄████▄     %s\n' "$BOLD" "$C_LIGHT" "$RESET"
    printf '%s%s   ▄████▀▀████▄  %s\n' "$BOLD" "$C_LIGHT" "$RESET"
    printf '%s%s  ███▀▀▄▄▄▄▀▀███ %s   %sArchDev%s  %s%s%s\n' "$BOLD" "$C_BRAND" "$RESET" "$BOLD" "$RESET" "$C_DIM" "$subtitle" "$RESET"
    printf '%s%s  ████████████▄  %s   %sInstalls the CLI, signs you in and sets up your agents%s\n' "$BOLD" "$C_BRAND" "$RESET" "$C_DIM" "$RESET"
    printf '%s%s  █████▀  ▀█████ %s\n' "$BOLD" "$C_DEEP" "$RESET"
    printf '%s%s   ▀▀        ▀▀  %s\n' "$BOLD" "$C_DEEP" "$RESET"
  else
    printf '  %s%sArchDev%s  %s%s%s\n' "$BOLD" "$C_BRAND" "$RESET" "$C_DIM" "$subtitle" "$RESET"
  fi
}

# step <n> <title>
step() {
  if [ "$FANCY" = true ]; then
    printf '\n  %s%s%s%s  %s%s%s\n' "$BOLD" "$C_BRAND" "$1" "$RESET" "$BOLD" "$2" "$RESET"
  else
    printf '\n==> %s. %s\n' "$1" "$2"
  fi
}

ok() { printf '%s%s%s%s %s\n' "$PAD" "$C_OK" "$(glyph '✓' 'ok')" "$RESET" "$1"; }
skip() { printf '%s%s%s %s%s\n' "$PAD" "$C_DIM" "$(glyph '–' '-')" "$1" "$RESET"; }
# Dim explanatory text, wrapped to the terminal.
info() {
  local width=$((COLUMNS_WIDE - 6)) line
  if [ "$width" -lt 30 ]; then width=30; fi
  printf '%s\n' "$1" | fold -s -w "$width" | while IFS= read -r line; do
    printf '%s%s%s%s\n' "$PAD" "$C_DIM" "$line" "$RESET"
  done
}
warn() { printf '%s%s%s%s %s\n' "$PAD" "$C_WARN" "$(glyph '▲' '!')" "$RESET" "$1"; }
fail() { printf '%s%s%s%s %s\n' "$PAD" "$C_FAIL" "$(glyph '✗' 'x')" "$RESET" "$1" >&2; }

# Print command output indented and dimmed, wrapped to the terminal.
quote_block() {
  local width=$((COLUMNS_WIDE - 9)) line
  if [ "$width" -gt 76 ]; then width=76; fi
  if [ "$width" -lt 30 ]; then width=30; fi
  fold -s -w "$width" | while IFS= read -r line; do
    printf '%s%s%s%s %s%s\n' "$PAD" "$C_DIM" "$(glyph '│' '|')" "$RESET$C_DIM" "$line" "$RESET"
  done
}

# die <message> [hint]
die() {
  printf '\n' >&2
  fail "$1"
  if [ -n "${2:-}" ]; then
    printf '%s  %s%s%s\n' "$PAD" "$C_DIM" "$2" "$RESET" >&2
  fi
  printf '%s  %sHelp: %s%s\n' "$PAD" "$C_DIM" "$HELP_URL" "$RESET" >&2
  exit 1
}

# Keys typed while the installer draws would be echoed into the output and
# shift the lines a menu redraws in place, so echo stays off between prompts.
tty_quiet() {
  if [ -n "$TTY_STATE" ]; then
    stty -echo -echonl </dev/tty 2>/dev/null || true
  fi
}

tty_restore() {
  if [ -n "$TTY_STATE" ]; then
    stty "$TTY_STATE" </dev/tty 2>/dev/null || true
  fi
}

cleanup() {
  local status=$?
  if [ "$FANCY" = true ]; then
    printf '\033[?25h'
  fi
  if [ -n "$CHILD_PID" ]; then
    kill "$CHILD_PID" 2>/dev/null || true
  fi
  tty_restore
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  exit "$status"
}

# spin <label> <command...>: run a command with a spinner; output goes to $LOG.
spin() {
  local label="$1" pid rc=0 i=0
  shift
  if [ "$FANCY" != true ]; then
    "$@" >"$LOG" 2>&1 </dev/null || rc=$?
    return "$rc"
  fi
  "$@" >"$LOG" 2>&1 </dev/null &
  pid=$!
  CHILD_PID=$pid
  local frames
  if [ "$UNICODE" = true ]; then
    frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  else
    # shellcheck disable=SC1003
    frames=('|' '/' '-' '\')
  fi
  # The line is redrawn in place, so it must not wrap.
  if [ "${#label}" -gt $((COLUMNS_WIDE - 8)) ]; then
    label="${label:0:$((COLUMNS_WIDE - 11))}..."
  fi
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[2K%s%s%s%s %s' "$PAD" "$C_BRAND" "${frames[$((i % ${#frames[@]}))]}" "$RESET" "$label"
    i=$((i + 1))
    sleep 0.08
  done
  wait "$pid" || rc=$?
  CHILD_PID=""
  printf '\r\033[2K\033[?25h'
  return "$rc"
}

# ---------------------------------------------------------------------------
# Prompts (read from /dev/tty)
# ---------------------------------------------------------------------------

CHOICE=0

# choose <question> <default index> <"Label|hint">...
# Arrow keys or j/k move, Enter selects, digits jump. Sets CHOICE.
choose() {
  local question="$1" current="$2" count key rest index option label hint
  shift 2
  count=$#

  if [ "$FANCY" != true ]; then
    printf '%s%s\n' "$PAD" "$question"
    index=0
    for option in "$@"; do
      index=$((index + 1))
      printf '%s  %s) %s\n' "$PAD" "$index" "${option%%|*}"
    done
    printf '%sChoose [%s]: ' "$PAD" "$((current + 1))"
    IFS= read -r key </dev/tty || key=""
    case "$key" in
      [1-9]) if [ "$key" -le "$count" ]; then current=$((key - 1)); fi ;;
    esac
    CHOICE=$current
    return 0
  fi

  printf '%s%s%s%s\n' "$PAD" "$BOLD" "$question" "$RESET"
  printf '\033[?25l'
  while :; do
    index=0
    for option in "$@"; do
      label="${option%%|*}"
      hint=""
      case "$option" in *"|"*) hint="${option#*|}" ;; esac
      # A row that wraps would throw off the cursor-up redraw below.
      if [ $((${#label} + ${#hint} + 10)) -gt "$COLUMNS_WIDE" ]; then
        hint=""
      fi
      if [ "$index" -eq "$current" ]; then
        printf '\033[2K%s%s%s %s%s%s  %s%s%s\n' "$PAD" "$C_BRAND" "$(glyph '❯' '>')" "$BOLD" "$label" "$RESET" "$C_DIM" "$hint" "$RESET"
      else
        printf '\033[2K%s  %s  %s%s%s\n' "$PAD" "$label" "$C_DIM" "$hint" "$RESET"
      fi
      index=$((index + 1))
    done
    printf '\033[2K%s%s%s move  %s select%s' "$PAD" "$C_DIM" "$(glyph '↑↓' 'j/k')" "$(glyph '↵' 'enter')" "$RESET"

    key=""
    IFS= read -rsn1 key </dev/tty || key=""
    case "$key" in
      "")
        break
        ;;
      $'\033')
        rest=""
        IFS= read -rsn2 -t 1 rest </dev/tty || rest=""
        case "$rest" in
          "[A" | "OA") current=$(((current + count - 1) % count)) ;;
          "[B" | "OB") current=$(((current + 1) % count)) ;;
        esac
        ;;
      k | K) current=$(((current + count - 1) % count)) ;;
      j | J) current=$(((current + 1) % count)) ;;
      [1-9])
        if [ "$key" -le "$count" ]; then
          current=$((key - 1))
        fi
        ;;
    esac
    printf '\r\033[%sA' "$count"
  done

  # Collapse the menu into one line recording the answer.
  printf '\r\033[%sA\033[J\033[?25h' "$((count + 1))"
  index=0
  for option in "$@"; do
    if [ "$index" -eq "$current" ]; then
      label="${option%%|*}"
      if [ $((${#question} + ${#label} + 10)) -gt "$COLUMNS_WIDE" ]; then
        printf '%s%s%s%s %s\n' "$PAD" "$C_BRAND" "$(glyph '◆' '*')" "$RESET" "$label"
      else
        printf '%s%s%s%s %s  %s%s%s\n' "$PAD" "$C_BRAND" "$(glyph '◆' '*')" "$RESET" "$question" "$C_DIM" "$label" "$RESET"
      fi
    fi
    index=$((index + 1))
  done
  CHOICE=$current
}

# ---------------------------------------------------------------------------
# Step 1: install the CLI
# ---------------------------------------------------------------------------

# musl's ldd prints its name and exits 1, so read the output, not the status.
is_musl() {
  local out=""
  if have ldd; then
    out="$(ldd --version 2>&1 || true)"
  fi
  case "$out" in
    *musl*) return 0 ;;
    *GNU* | *GLIBC* | *glibc*) return 1 ;;
  esac
  ls /lib/ld-musl-* >/dev/null 2>&1
}

detect_platform() {
  local os machine
  os="$(uname -s)"
  machine="$(uname -m)"
  case "$os" in
    Darwin) PLATFORM="darwin" ;;
    Linux) PLATFORM="linux" ;;
    MINGW* | MSYS* | CYGWIN*)
      die "This installer supports macOS and Linux." \
        "On Windows, use https://raw.githubusercontent.com/${OWNER}/${REPO}/main/install.ps1"
      ;;
    *) die "Unsupported operating system: ${os}" ;;
  esac
  case "$machine" in
    x86_64 | amd64) ARCH_LABEL="x64" ;;
    arm64 | aarch64) ARCH_LABEL="arm64" ;;
    *) die "Unsupported architecture: ${machine}" ;;
  esac
  # A shell running under Rosetta reports x86_64 on Apple silicon.
  if [ "$PLATFORM" = darwin ] && [ "$ARCH_LABEL" = x64 ] &&
    [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || printf '0')" = "1" ]; then
    ARCH_LABEL="arm64"
  fi
  if [ "$PLATFORM" = linux ] && is_musl; then
    if [ "$ARCH_LABEL" = arm64 ]; then
      die "ArchDev has no build for musl Linux on arm64 yet." \
        "Use a glibc distribution, or an x64 musl host."
    fi
    ARCH_LABEL="x64-musl"
  fi
  case "$PLATFORM-$ARCH_LABEL" in
    darwin-arm64) PLATFORM_NAME="macOS arm64" ;;
    darwin-x64) PLATFORM_NAME="macOS x64" ;;
    linux-arm64) PLATFORM_NAME="Linux arm64" ;;
    linux-x64) PLATFORM_NAME="Linux x64" ;;
    linux-x64-musl) PLATFORM_NAME="Linux x64 (musl)" ;;
  esac
  ASSET_NAME="archdev-${PLATFORM}-${ARCH_LABEL}.tar.gz"
}

resolve_urls() {
  local version_tag="$REQUESTED_VERSION"
  if [ "$version_tag" != latest ]; then
    version_tag="v${version_tag#v}"
    case "${version_tag#v}" in
      *[!0-9.]* | "" | .* | *.) die "Not a version: ${REQUESTED_VERSION}" "Use a release number such as 0.49.2." ;;
    esac
    TARGET_VERSION="${version_tag#v}"
  fi
  if [ -n "$RELEASE_BASE_URL" ]; then
    RESOLVED_RELEASE_BASE_URL="${RELEASE_BASE_URL%/}"
  elif [ "$REQUESTED_VERSION" = latest ]; then
    RESOLVED_RELEASE_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/latest/download"
  else
    RESOLVED_RELEASE_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${version_tag}"
  fi
  ASSET_URL="${RESOLVED_RELEASE_BASE_URL}/${ASSET_NAME}"
  CHECKSUM_URL="${RESOLVED_RELEASE_BASE_URL}/SHA256SUMS"
}

# fetch <url> <output file> [header file]
fetch() {
  local url="$1" out="$2" headers="${3:-/dev/null}"
  case "$url" in
    https://*) curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -D "$headers" -o "$out" "$url" ;;
    *) curl -fsSL --retry 2 -D "$headers" -o "$out" "$url" ;;
  esac
}

# Print the latest version, read from the release redirect; the GitHub API is
# rate limited for unauthenticated callers and the redirect is not.
latest_version() {
  local effective
  effective="$(curl -fsSLI --proto '=https' --tlsv1.2 -o /dev/null -w '%{url_effective}' \
    "https://github.com/${OWNER}/${REPO}/releases/latest")"
  case "$effective" in
    */releases/tag/v*) printf '%s\n' "${effective##*/releases/tag/v}" ;;
  esac
}

# A failed lookup is not fatal: the latest/download URL still resolves, and
# the version is then read from the installed binary.
resolve_latest_version() {
  local version
  if [ -n "$TARGET_VERSION" ] || [ -n "$RELEASE_BASE_URL" ]; then
    return 0
  fi
  spin "Finding the latest release" latest_version || return 0
  version="$(head -n 1 "$LOG" | tr -d '[:space:]')"
  case "$version" in
    *[!0-9.]* | "") ;;
    *) TARGET_VERSION="$version" ;;
  esac
}

binary_version() {
  ARCHDEV_NO_UPDATE_CHECK=1 "$1" --version 2>/dev/null | head -n 1 | tr -d '[:space:]' || true
}

is_homebrew_binary() {
  local path="$1" link="" physical=""
  if [ -L "$path" ]; then
    link="$(readlink "$path" 2>/dev/null || true)"
  fi
  # Also catches a PATH entry that reaches the keg through Homebrew's opt link.
  physical="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P || true)"
  case "$path $link $physical/" in
    *"/Cellar/${BINARY_NAME}/"*) return 0 ;;
  esac
  return 1
}

# The archdev executable PATH resolves to, or nothing.
path_binary() {
  local found
  found="$(command -v "$BINARY_NAME" 2>/dev/null || true)"
  case "$found" in
    /*) printf '%s' "$found" ;;
  esac
}

choose_install_dir() {
  local existing=""
  existing="$(path_binary)"

  if [ -n "$INSTALL_DIR" ]; then
    # The directory is written into a shell profile, so keep it to an
    # absolute path that needs no quoting there.
    case "$INSTALL_DIR" in
      *[\"\$\`\\]* | *"
"*) die "Unsupported character in --install-dir: ${INSTALL_DIR}" "Use a path without quotes, \$, backticks or backslashes." ;;
      /*) ;;
      *) INSTALL_DIR="$PWD/$INSTALL_DIR" ;;
    esac
    INSTALL_DIR="${INSTALL_DIR%/}"
    return 0
  fi
  if [ "$SYSTEM_INSTALL" = true ]; then
    INSTALL_DIR="/usr/local/bin"
    return 0
  fi
  # Homebrew owns its copy: installing a second one would leave two binaries
  # that `archdev upgrade` updates separately.
  if [ -n "$existing" ] && is_homebrew_binary "$existing"; then
    MANAGED_BY="homebrew"
    BIN="$existing"
    INSTALL_DIR="$(dirname "$existing")"
    return 0
  fi
  # Upgrade a previous installer copy in place.
  if [ -n "$existing" ] && [ -w "$(dirname "$existing")" ]; then
    INSTALL_DIR="$(dirname "$existing")"
    return 0
  fi
  if [ "$PLATFORM" = darwin ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
}

sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{ print $1 }'
  elif have shasum; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  elif have openssl; then
    openssl dgst -sha256 "$1" | awk '{ print $NF }'
  else
    return 1
  fi
}

# Download the release archive, drawing a progress bar from the size the
# server reports and the bytes written so far.
download_asset() {
  local out="$1" headers="$TEMP_DIR/headers" pid rc=0 total=0 have_bytes=0 width=26 filled percent bar rest i
  if [ "$FANCY" != true ]; then
    printf '%sDownloading %s\n' "$PAD" "$ASSET_NAME"
    fetch "$ASSET_URL" "$out" 2>"$LOG" || rc=$?
    return "$rc"
  fi
  : >"$headers"
  fetch "$ASSET_URL" "$out" "$headers" 2>"$LOG" &
  pid=$!
  CHILD_PID=$pid
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    # Redirects add header blocks; the last Content-Length is the archive's.
    total="$(awk 'tolower($1) == "content-length:" { v = $2 } END { print v + 0 }' "$headers" 2>/dev/null | tr -d '\r')"
    if [ -f "$out" ]; then
      have_bytes="$(wc -c <"$out" | tr -d '[:space:]')"
    fi
    if [ "${total:-0}" -gt 0 ] && [ "$have_bytes" -le "$total" ]; then
      percent=$((have_bytes * 100 / total))
      filled=$((have_bytes * width / total))
      bar="" rest="" i=0
      while [ "$i" -lt "$width" ]; do
        if [ "$i" -lt "$filled" ]; then bar="${bar}$(glyph '━' '#')"; else rest="${rest}$(glyph '━' '-')"; fi
        i=$((i + 1))
      done
      printf '\r\033[2K%s%s%s%s%s%s  %s%s of %s  %s%%%s' "$PAD" "$C_BRAND" "$bar" "$C_DIM" "$rest" "$RESET" \
        "$C_DIM" "$(human_mb "$have_bytes")" "$(human_mb "$total")" "$percent" "$RESET"
    else
      printf '\r\033[2K%s%sConnecting%s' "$PAD" "$C_DIM" "$RESET"
    fi
    sleep 0.05
  done
  wait "$pid" || rc=$?
  CHILD_PID=""
  printf '\r\033[2K\033[?25h'
  return "$rc"
}

install_binary() {
  local archive="$TEMP_DIR/$ASSET_NAME" sums="$TEMP_DIR/SHA256SUMS" extract="$TEMP_DIR/extract"
  local expected actual staged current="" command_name

  for command_name in curl tar mktemp awk; do
    have "$command_name" || die "Missing required command: ${command_name}" "Install it and run the installer again."
  done

  if [ "$MANAGED_BY" = homebrew ]; then
    INSTALLED_VERSION="$(binary_version "$BIN")"
    ok "ArchDev ${INSTALLED_VERSION} is installed with Homebrew  ${C_DIM}$(pretty_path "$BIN")${RESET}"
    if [ -n "$TARGET_VERSION" ] && [ "$INSTALLED_VERSION" != "$TARGET_VERSION" ]; then
      warn "Version ${TARGET_VERSION} is available. Update with: ${BOLD}archdev upgrade${RESET}"
    fi
    return 0
  fi

  BIN="$INSTALL_DIR/$BINARY_NAME"
  if [ -x "$BIN" ]; then
    current="$(binary_version "$BIN")"
  fi
  if [ "$FORCE" != true ] && [ -n "$current" ] && [ -n "$TARGET_VERSION" ] && [ "$current" = "$TARGET_VERSION" ]; then
    INSTALLED_VERSION="$current"
    ok "ArchDev ${current} is already installed  ${C_DIM}$(pretty_path "$BIN")${RESET}"
    return 0
  fi

  mkdir -p "$INSTALL_DIR" 2>/dev/null || true
  if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
    die "Cannot write to $(pretty_path "$INSTALL_DIR")." \
      "Choose another directory with --install-dir, for example --install-dir \"\$HOME/.local/bin\"."
  fi

  if ! download_asset "$archive"; then
    die "Could not download ${ASSET_NAME}." "Tried ${ASSET_URL}. Check your connection, or pin a release with --version."
  fi
  ok "Downloaded ${ASSET_NAME}  ${C_DIM}$(human_mb "$(wc -c <"$archive" | tr -d '[:space:]')")${RESET}"

  if ! fetch "$CHECKSUM_URL" "$sums" 2>"$LOG"; then
    die "Could not download the release checksums." "Tried ${CHECKSUM_URL}."
  fi
  expected="$(awk -v asset="$ASSET_NAME" '$2 == asset { print $1 }' "$sums")"
  [ -n "$expected" ] || die "The release has no checksum for ${ASSET_NAME}."
  actual="$(sha256_of "$archive")" || die "No SHA-256 tool found." "Install sha256sum, shasum or openssl."
  if [ "$actual" != "$expected" ]; then
    die "Checksum mismatch for ${ASSET_NAME}; nothing was installed." "expected ${expected}, got ${actual}"
  fi
  ok "Verified SHA-256  ${C_DIM}${expected:0:12}$(glyph '…' '...')${RESET}"

  mkdir -p "$extract"
  tar -xzf "$archive" -C "$extract" || die "Could not unpack ${ASSET_NAME}."
  [ -f "$extract/$BINARY_NAME" ] || die "The archive does not contain ${BINARY_NAME}."
  chmod 0755 "$extract/$BINARY_NAME"

  if [ "$SKIP_VERIFY" != true ]; then
    INSTALLED_VERSION="$(binary_version "$extract/$BINARY_NAME")"
    [ -n "$INSTALLED_VERSION" ] || die "The downloaded ${BINARY_NAME} does not run on this machine." \
      "Platform detected: ${PLATFORM_NAME}."
  else
    INSTALLED_VERSION="${TARGET_VERSION:-}"
  fi

  # Stage beside the target and rename, so a running archdev is never left
  # half written.
  staged="$INSTALL_DIR/.${BINARY_NAME}-install-$$"
  cp "$extract/$BINARY_NAME" "$staged"
  chmod 0755 "$staged"
  mv -f "$staged" "$BIN"

  if [ -n "$current" ] && [ "$current" != "$INSTALLED_VERSION" ]; then
    ok "Upgraded ${current} $(glyph '→' '->') ${INSTALLED_VERSION}  ${C_DIM}$(pretty_path "$BIN")${RESET}"
  else
    ok "Installed ArchDev ${INSTALLED_VERSION}  ${C_DIM}$(pretty_path "$BIN")${RESET}"
  fi
}

# Returns 1 when the line was already there.
append_once() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -Fqx "$line" "$file"; then
    return 1
  fi
  printf '\n# Added by the ArchDev installer\n%s\n' "$line" >>"$file"
}

# Put the install directory on PATH for this process (setup requires it) and,
# unless opted out, for new shells.
ensure_path() {
  local dir="$INSTALL_DIR" line shell_name first candidate
  case ":$PATH:" in
    *":$dir:"*) ;;
    *)
      export PATH="$dir:$PATH"
      shell_name="$(basename "${SHELL:-sh}")"
      case "$dir" in
        "$HOME"/*) line="export PATH=\"\$HOME/${dir#"$HOME"/}:\$PATH\"" ;;
        *) line="export PATH=\"$dir:\$PATH\"" ;;
      esac
      if [ "$SKIP_PATH_UPDATE" = true ]; then
        warn "$(pretty_path "$dir") is not on your PATH. Add it to your shell profile."
        PATH_HINT="$line"
      else
        case "$shell_name" in
          fish)
            PATH_FILE="$HOME/.config/fish/config.fish"
            case "$dir" in
              "$HOME"/*) line="fish_add_path \"\$HOME/${dir#"$HOME"/}\"" ;;
              *) line="fish_add_path \"$dir\"" ;;
            esac
            ;;
          zsh) PATH_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
          bash)
            # Terminal.app starts login shells. bash reads only the first of
            # these that exists, so never create one that would shadow another.
            PATH_FILE="$HOME/.bashrc"
            if [ "$PLATFORM" = darwin ]; then
              PATH_FILE="$HOME/.bash_profile"
              for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
                if [ -f "$candidate" ]; then
                  PATH_FILE="$candidate"
                  break
                fi
              done
            fi
            ;;
          *) PATH_FILE="$HOME/.profile" ;;
        esac
        PATH_HINT="$line"
        if append_once "$PATH_FILE" "$line"; then
          ok "Added $(pretty_path "$dir") to PATH  ${C_DIM}$(pretty_path "$PATH_FILE")${RESET}"
        fi
      fi
      ;;
  esac

  # Hooks call whichever archdev comes first on PATH.
  hash -r 2>/dev/null || true
  first="$(path_binary)"
  if [ -n "$first" ] && [ "$first" != "$BIN" ] && [ ! "$first" -ef "$BIN" ]; then
    warn "Another archdev comes first on your PATH: $(pretty_path "$first")"
    info "Remove it, or move $(pretty_path "$INSTALL_DIR") earlier in PATH."
  fi
}

# Shell completions are optional. The Rust archdev has no `completion`
# command, so a failure here must not fail the install or leave an empty
# completion file behind.
install_completion() {
  local shell_name="$1" target="$2" staged="$TEMP_DIR/completion"
  if "$BIN" completion "$shell_name" >"$staged" 2>/dev/null </dev/null && [ -s "$staged" ]; then
    mkdir -p "$(dirname "$target")"
    mv "$staged" "$target"
    chmod 0644 "$target"
    return 0
  fi
  rm -f "$staged"
  return 1
}

install_completions() {
  local shell_name
  shell_name="$(basename "${SHELL:-sh}")"
  if [ "$SKIP_COMPLETIONS" = true ]; then
    return 0
  fi
  case "$shell_name" in
    fish) install_completion fish "$HOME/.config/fish/completions/archdev.fish" || return 0 ;;
    zsh)
      install_completion zsh "$HOME/.zsh/completions/_archdev" || return 0
      # shellcheck disable=SC2016 # written to .zshrc for zsh to expand
      append_once "${ZDOTDIR:-$HOME}/.zshrc" 'fpath=("$HOME/.zsh/completions" $fpath)' || true
      if ! grep -Fq 'compinit' "${ZDOTDIR:-$HOME}/.zshrc"; then
        printf '\nautoload -Uz compinit\ncompinit\n' >>"${ZDOTDIR:-$HOME}/.zshrc"
      fi
      ;;
    bash) install_completion bash "$HOME/.local/share/bash-completion/completions/archdev" || return 0 ;;
    *) return 0 ;;
  esac
  ok "Installed ${shell_name} completions"
}

# ---------------------------------------------------------------------------
# Step 2: sign in
# ---------------------------------------------------------------------------

# Run the installed CLI. Not named `archdev`: a function by that name would
# answer `command -v archdev` and hide the real binary.
cli() { ARCHDEV_NO_UPDATE_CHECK=1 "$BIN" "$@"; }

# `archdev auth status` exits 0 only when the saved session is usable.
read_auth_status() {
  SIGNED_IN="false"
  spin "Checking your session" cli auth status || return 1
  ACCOUNT_EMAIL="$(awk -F': ' '$1 == "Email" { print $2; exit }' "$LOG")"
  ACCOUNT_ORG="$(awk -F': ' '$1 == "Organization" { print $2; exit }' "$LOG")"
  SIGNED_IN="true"
}

signed_in_line() {
  local who="${ACCOUNT_EMAIL:-your account}"
  if [ -n "$ACCOUNT_ORG" ]; then
    ok "Signed in as ${BOLD}${who}${RESET}  ${C_DIM}${ACCOUNT_ORG}${RESET}"
  else
    ok "Signed in as ${BOLD}${who}${RESET}"
  fi
}

sign_in() {
  if [ "$SKIP_LOGIN" = true ]; then
    skip "Skipped. Sign in later with: archdev auth login"
    return 0
  fi
  if read_auth_status; then
    signed_in_line
    return 0
  fi
  if [ "$INTERACTIVE" != true ]; then
    skip "No terminal to sign in from. Run: archdev auth login"
    info "For CI, set ARCHDEV_TOKEN to a personal access token."
    return 0
  fi

  info "ArchDev signs you in with GitHub in your browser."
  choose "Sign in now?" 0 "Open the browser|recommended" "Skip|sign in later with archdev auth login"
  if [ "$CHOICE" -ne 0 ]; then
    skip "Skipped. Sign in later with: archdev auth login"
    return 0
  fi

  # The CLI owns the browser and copy/paste flows; give it the real terminal.
  printf '\n'
  tty_restore
  if cli auth login </dev/tty; then
    tty_quiet
    printf '\n'
  else
    tty_quiet
    printf '\n'
    warn "Sign-in did not finish. Run: archdev auth login"
    return 0
  fi
  if read_auth_status; then
    signed_in_line
  else
    warn "Sign-in did not finish. Run: archdev auth login"
  fi
}

# ---------------------------------------------------------------------------
# Step 3: set up this machine
# ---------------------------------------------------------------------------

REPORTING_NOTICE="Setup posts a one-time installation announcement, and session hooks can report activity and findings to your organization's shared stream, visible to its members."

repository_root() {
  have git && git rev-parse --show-toplevel 2>/dev/null || true
}

run_setup() {
  local repo_root scope="$SETUP_SCOPE" reporting="$SETUP_REPORTING" label announcement

  if [ "$SKIP_SETUP" = true ]; then
    skip "Skipped. Finish later with: archdev setup"
    return 0
  fi
  if [ "$SIGNED_IN" != true ]; then
    skip "Sign in first, then run: archdev setup"
    return 0
  fi

  repo_root="$(repository_root)"

  if [ -z "$scope" ]; then
    if [ "$INTERACTIVE" != true ]; then
      skip "Not configured: placement needs your answer. Run: archdev setup"
      return 0
    fi
    info "Setup installs the ArchDev skill and session hooks for your coding agents."
    if [ -n "$repo_root" ] && have node; then
      choose "Where should ArchDev be configured?" 0 \
        "For me on this machine|every repository you work in" \
        "For this repository|$(pretty_path "$repo_root")" \
        "Skip|run archdev setup later"
      case "$CHOICE" in
        0) scope="user" ;;
        1) scope="repository" ;;
        *) scope="" ;;
      esac
    else
      choose "Where should ArchDev be configured?" 0 \
        "For me on this machine|every repository you work in" \
        "Skip|run archdev setup later"
      case "$CHOICE" in
        0) scope="user" ;;
        *) scope="" ;;
      esac
    fi
    if [ -z "$scope" ]; then
      skip "Skipped. Finish later with: archdev setup"
      return 0
    fi
  fi

  if [ "$scope" = repository ]; then
    [ -n "$repo_root" ] || die "--scope repository needs a Git repository." "Run the installer from inside the repository."
    have node || die "Repository hooks need Node.js on PATH." "Install Node.js, or use --scope user."
  fi

  if [ -z "$reporting" ]; then
    if [ "$INTERACTIVE" != true ]; then
      skip "Not configured: activity reporting needs your answer. Run: archdev setup"
      return 0
    fi
    printf '%s\n' "$REPORTING_NOTICE" | quote_block
    # Reporting is shared with the organization, so Enter alone does not opt in.
    choose "Share activity with your organization?" 1 \
      "Enable reporting|finish setup" \
      "Not now|leave this machine unconfigured"
    if [ "$CHOICE" -eq 0 ]; then reporting="enabled"; else reporting="disabled"; fi
  fi

  if [ "$reporting" != enabled ]; then
    skip "Nothing changed. Setup requires reporting; run archdev setup when ready."
    return 0
  fi

  if [ "$scope" = repository ]; then
    label="Configuring $(pretty_path "$repo_root")"
    cd "$repo_root"
  else
    label="Installing the ArchDev skill and hooks for this user"
  fi
  if spin "$label" cli setup --scope "$scope" --reporting enabled; then
    SETUP_DONE="true"
    if [ "$scope" = repository ]; then
      ok "Skill and hooks installed for $(pretty_path "$repo_root")"
    else
      ok "Skill and hooks installed for this user"
    fi
    # The CLI reports whether the one-time announcement was recorded, queued
    # or failed; pass that sentence through instead of restating it.
    announcement="$(grep -m 1 -i 'announcement' "$LOG" || true)"
    case "$announcement" in
      "") ;;
      *"could not"*) warn "$announcement" ;;
      *) ok "${announcement%% (*}" ;;
    esac
    info "Restart your coding agents so they load the hooks. Codex and Grok ask you to trust repository hooks; that approval stays with you."
  else
    SETUP_FAILED="true"
    fail "archdev setup did not finish:"
    grep -v '^[[:space:]]*$' "$LOG" | quote_block >&2 || true
    info "Fix the issue above, then run: archdev setup --scope ${scope} --reporting enabled"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

next_command() {
  if [ $((${#2} + 28)) -gt "$COLUMNS_WIDE" ]; then
    printf '    %s%s%s\n' "$BOLD" "$1" "$RESET"
  else
    printf '    %s%-22s%s %s%s%s\n' "$BOLD" "$1" "$RESET" "$C_DIM" "$2" "$RESET"
  fi
}

summary() {
  local reload=""
  printf '\n'
  if [ "$SIGNED_IN" = true ] && [ "$SETUP_DONE" = true ]; then
    printf '  %s%s%s %sArchDev %s is ready%s  %s%s%s\n' "$C_OK" "$(glyph '✓' 'ok')" "$RESET" "$BOLD" "$INSTALLED_VERSION" "$RESET" "$C_DIM" "in ${SECONDS}s" "$RESET"
  else
    printf '  %s%s%s %sArchDev %s is installed%s  %s%s%s\n' "$C_OK" "$(glyph '✓' 'ok')" "$RESET" "$BOLD" "$INSTALLED_VERSION" "$RESET" "$C_DIM" "in ${SECONDS}s" "$RESET"
  fi
  printf '\n'

  if [ -n "$PATH_FILE" ]; then
    reload="source $(pretty_path "$PATH_FILE")"
    next_command "$reload" "load archdev into this shell, or open a new terminal"
  elif [ -n "$PATH_HINT" ]; then
    next_command "$PATH_HINT" "add to your shell profile"
  fi
  if [ "$SIGNED_IN" != true ]; then
    next_command "archdev auth login" "sign in with GitHub"
  fi
  if [ "$SETUP_DONE" != true ]; then
    next_command "archdev setup" "install the skill and hooks for your agents"
  else
    next_command "archdev repo status" "check this repository's readiness"
  fi
  next_command "archdev tasks" "plan, claim and complete shared work"
  next_command "archdev review" "review local changes in ArchCode"
  next_command "archdev upgrade" "update the CLI, skills and hooks"
  printf '\n    %sDocs  %s%s%s\n\n' "$C_DIM" "$C_LINK" "$DOCS_URL" "$RESET"
}

# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) REQUESTED_VERSION="${2:?--version needs a value}"; shift 2 ;;
      --install-dir) INSTALL_DIR="${2:?--install-dir needs a value}"; shift 2 ;;
      --base-url) RELEASE_BASE_URL="${2:?--base-url needs a value}"; shift 2 ;;
      --scope) SETUP_SCOPE="${2:?--scope needs a value}"; shift 2 ;;
      --reporting) SETUP_REPORTING="${2:?--reporting needs a value}"; shift 2 ;;
      --system) SYSTEM_INSTALL="true"; shift ;;
      --force) FORCE="true"; shift ;;
      --no-modify-path) SKIP_PATH_UPDATE="true"; shift ;;
      --skip-login) SKIP_LOGIN="true"; shift ;;
      --skip-setup) SKIP_SETUP="true"; shift ;;
      -y | --yes) NONINTERACTIVE="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --print-asset-url) PRINT_ASSET_URL="true"; shift ;;
      -h | --help) usage; exit 0 ;;
      *) printf 'Unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
  done
  case "$SETUP_SCOPE" in
    "" | user | repository) ;;
    *) printf 'Unknown --scope: %s (use user or repository)\n' "$SETUP_SCOPE" >&2; exit 1 ;;
  esac
  case "$SETUP_REPORTING" in
    "" | enabled | disabled) ;;
    *) printf 'Unknown --reporting: %s (use enabled or disabled)\n' "$SETUP_REPORTING" >&2; exit 1 ;;
  esac
  SKIP_PATH_UPDATE="$(normalize_bool "$SKIP_PATH_UPDATE")"
  SKIP_COMPLETIONS="$(normalize_bool "$SKIP_COMPLETIONS")"
  SKIP_VERIFY="$(normalize_bool "$SKIP_VERIFY")"
  SKIP_LOGIN="$(normalize_bool "$SKIP_LOGIN")"
  SKIP_SETUP="$(normalize_bool "$SKIP_SETUP")"
}

main() {
  parse_args "$@"
  detect_terminal
  detect_platform
  resolve_urls
  choose_install_dir

  if [ "$PRINT_ASSET_URL" = true ]; then
    printf '%s\n' "$ASSET_URL"
    exit 0
  fi
  if [ "$DRY_RUN" = true ]; then
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
EOF
    exit 0
  fi

  # A root-owned binary in a home directory breaks `archdev upgrade`.
  if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ] && [ "$SYSTEM_INSTALL" != true ]; then
    die "Do not run this installer with sudo." "Run it as ${SUDO_USER}; pass --system only for a /usr/local/bin install."
  fi

  TEMP_DIR="$(mktemp -d)"
  LOG="$TEMP_DIR/log"
  : >"$LOG"
  if [ "$INTERACTIVE" = true ]; then
    TTY_STATE="$(stty -g </dev/tty 2>/dev/null || true)"
  fi
  trap cleanup EXIT
  tty_quiet
  trap 'exit 130' INT
  trap 'exit 143' TERM

  banner

  step 1 "Install the CLI"
  resolve_latest_version
  install_binary
  if [ "$MANAGED_BY" != homebrew ]; then
    ensure_path
    install_completions
  fi

  step 2 "Sign in"
  sign_in

  step 3 "Set up your agents"
  run_setup

  summary
  # The CLI is installed, but a setup the user asked for did not complete.
  if [ "$SETUP_FAILED" = true ]; then
    exit 1
  fi
}

# A brace group is parsed whole before it runs: cut anywhere, it is a syntax error.
{ main "$@"; }
