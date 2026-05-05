#!/usr/bin/env bash
# tailscale-download.sh — download Tailscale packages with changelog
set -euo pipefail

PKGS_BASE="https://pkgs.tailscale.com/stable"
PKGS_UNSTABLE="https://pkgs.tailscale.com/unstable"
CHANGELOG_RSS="https://tailscale.com/changelog/index.xml"
GH_API="https://api.github.com/repos/tailscale/tailscale/releases"
OUTPUT_DIR="${HOME}/Downloads"
CHANNEL="stable"
CHANGELOG_ENTRIES=10
PLATFORM=""
VERSION=""
LIST_ONLY=false
CHANGELOG_ONLY=false
NO_VERIFY=false

# ── colours ──────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD="\033[1m"; RESET="\033[0m"; GREEN="\033[32m"
  CYAN="\033[36m"; YELLOW="\033[33m"; RED="\033[31m"; DIM="\033[2m"
else
  BOLD=""; RESET=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; DIM=""
fi

info()    { echo -e "${CYAN}==>${RESET} ${BOLD}$*${RESET}"; }
ok()      { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
err()     { echo -e "${RED}  ✗${RESET} $*" >&2; }
dim()     { echo -e "${DIM}$*${RESET}"; }

usage() {
  cat <<EOF

${BOLD}tailscale-download${RESET} — fetch Tailscale packages with changelog

${BOLD}USAGE${RESET}
  $(basename "$0") [options]

${BOLD}OPTIONS${RESET}
  -o DIR      Output directory (default: ~/Downloads)
  -p PLATFORM Target platform (default: auto-detect)
              macos-pkg | macos-zip | linux-amd64 | linux-arm64 |
              linux-arm | linux-386 | windows-exe |
              windows-msi-amd64 | windows-msi-arm64
  -v VERSION  Specific version, e.g. 1.96.4 (default: latest)
  -n NUM      Changelog entries to show (default: 10)
  -u          Use unstable channel
  -l          List recent releases only, skip download
  -c          Show changelog only, skip download
  --no-verify Skip SHA256 checksum verification
  -h          Show this help

${BOLD}EXAMPLES${RESET}
  $(basename "$0")                        # auto-detect platform, download latest
  $(basename "$0") -p linux-arm64         # ARM64 Linux
  $(basename "$0") -v 1.94.2 -p macos-pkg # specific version
  $(basename "$0") -l -n 20              # list 20 most recent releases
  $(basename "$0") -c                    # changelog only

EOF
  exit 0
}

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUTPUT_DIR="$2"; shift 2 ;;
    -p) PLATFORM="$2"; shift 2 ;;
    -v) VERSION="$2"; shift 2 ;;
    -n) CHANGELOG_ENTRIES="$2"; shift 2 ;;
    -u) CHANNEL="unstable" ;;
    -l) LIST_ONLY=true; shift ;;
    -c) CHANGELOG_ONLY=true; shift ;;
    --no-verify) NO_VERIFY=true; shift ;;
    -h|--help) usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

PKGS_ROOT=$( [ "$CHANNEL" = "unstable" ] && echo "$PKGS_UNSTABLE" || echo "$PKGS_BASE" )

# ── dependency checks ─────────────────────────────────────────────────────────
for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { err "$cmd is required but not installed."; exit 1; }
done

HAS_XMLLINT=false
command -v xmllint >/dev/null 2>&1 && HAS_XMLLINT=true

# ── platform detection ────────────────────────────────────────────────────────
detect_platform() {
  local os arch
  os=$(uname -s); arch=$(uname -m)
  case "$os" in
    Darwin) echo "macos-pkg" ;;
    Linux)
      case "$arch" in
        x86_64)        echo "linux-amd64" ;;
        aarch64|arm64) echo "linux-arm64" ;;
        armv7l|armv6l) echo "linux-arm"   ;;
        i386|i686)     echo "linux-386"   ;;
        *)             echo "linux-amd64" ;;
      esac ;;
    MINGW*|CYGWIN*|MSYS*) echo "windows-exe" ;;
    *) echo "linux-amd64" ;;
  esac
}

# ── URL + filename resolution ─────────────────────────────────────────────────
resolve_url() {
  local platform="$1" version="$2" base="$3"
  case "$platform" in
    macos-pkg)         echo "${base}/Tailscale-${version}-macos.pkg" ;;
    macos-zip)         echo "${base}/Tailscale-${version}-macos.zip" ;;
    linux-amd64)       echo "${base}/tailscale_${version}_amd64.tgz" ;;
    linux-arm64)       echo "${base}/tailscale_${version}_arm64.tgz" ;;
    linux-arm)         echo "${base}/tailscale_${version}_arm.tgz"   ;;
    linux-386)         echo "${base}/tailscale_${version}_386.tgz"   ;;
    windows-exe)       echo "${base}/tailscale-setup-${version}.exe" ;;
    windows-msi-amd64) echo "${base}/tailscale-setup-${version}-amd64.msi" ;;
    windows-msi-arm64) echo "${base}/tailscale-setup-${version}-arm64.msi" ;;
    *) err "Unknown platform: $platform"; exit 1 ;;
  esac
}

# ── fetch recent GitHub releases ──────────────────────────────────────────────
fetch_releases() {
  local per_page="${1:-20}"
  curl -sf "${GH_API}?per_page=${per_page}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" 2>/dev/null \
  | jq -r '.[] | select(.prerelease == false) | "\(.tag_name) \(.published_at)"'
}

# ── fetch latest stable version from pkgs page ────────────────────────────────
fetch_latest_version() {
  local platform="$1"
  # Probe the pkgs page for the exact latest version per platform
  local html
  html=$(curl -sf "${PKGS_ROOT}/" 2>/dev/null) || { err "Could not reach ${PKGS_ROOT}/"; exit 1; }

  case "$platform" in
    macos-pkg|macos-zip)
      echo "$html" | grep -oE 'Tailscale-[0-9]+\.[0-9]+\.[0-9]+-macos\.pkg' \
        | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true ;;
    linux-*)
      echo "$html" | grep -oE 'tailscale_[0-9]+\.[0-9]+\.[0-9]+_amd64\.tgz' \
        | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true ;;
    windows-*)
      echo "$html" | grep -oE 'tailscale-setup-[0-9]+\.[0-9]+\.[0-9]+\.exe' \
        | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true ;;
  esac
}

# ── parse changelog RSS ───────────────────────────────────────────────────────
show_changelog() {
  local n="$1"
  info "Fetching changelog (${n} most recent entries)..."
  echo ""

  local rss
  rss=$(curl -sf "$CHANGELOG_RSS" 2>/dev/null) || { warn "Could not fetch changelog RSS."; return; }

  local tmpfile
  tmpfile=$(mktemp /tmp/ts-changelog.XXXXXX)
  echo "$rss" > "$tmpfile"

  python3 -c "
import sys, re, html

def strip_tags(s):
    s = re.sub(r'<!\[CDATA\[(.*?)\]\]>', r'\1', s, flags=re.DOTALL)
    s = html.unescape(s)
    s = re.sub(r'<[^>]+>', '', s)
    s = re.sub(r'\n{3,}', '\n\n', s)
    return re.sub(r'\n[ \t]+', '\n    ', s).strip()

with open(sys.argv[1]) as f:
    content = f.read()

limit = int(sys.argv[2])
items = re.split(r'<item>', content)[1:]

for item in items[:limit]:
    title = re.search(r'<title>([^<]+)</title>', item)
    date  = re.search(r'<pubDate>([^<]+)</pubDate>', item)
    link  = re.search(r'<link>([^<]+)</link>', item)
    desc  = re.search(r'<description>(.*?)</description>', item, re.DOTALL)

    title = title.group(1).strip() if title else ''
    date  = date.group(1).strip()  if date  else ''
    link  = link.group(1).strip()  if link  else ''
    desc  = strip_tags(desc.group(1)) if desc else ''

    print(f'  \033[1m{title}\033[0m')
    print(f'  \033[2m{date}\033[0m')
    if desc:
        for line in desc.splitlines():
            print(f'    {line}')
    print(f'  \033[36m{link}\033[0m')
    print()
" "$tmpfile" "$n"

  rm -f "$tmpfile"
}

# ── list recent releases ──────────────────────────────────────────────────────
list_releases() {
  info "Recent stable releases:"
  echo ""
  fetch_releases 20 | while read -r tag date; do
    ver="${tag#v}"
    printf "  ${BOLD}%-10s${RESET}  ${DIM}%s${RESET}\n" "$ver" "${date%T*}"
  done
  echo ""
}

# ── verify SHA256 ─────────────────────────────────────────────────────────────
verify_checksum() {
  local file="$1" url="$2"
  local expected actual

  info "Verifying SHA256..."
  expected=$(curl -sf "${url}.sha256" 2>/dev/null | awk '{print $1}') || {
    warn "Could not fetch checksum — skipping verification."
    return 0
  }

  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  else
    warn "No sha256sum or shasum found — skipping verification."
    return 0
  fi

  if [ "$expected" = "$actual" ]; then
    ok "Checksum verified: ${DIM}${actual}${RESET}"
  else
    err "Checksum MISMATCH!"
    err "  Expected: $expected"
    err "  Got:      $actual"
    rm -f "$file"
    exit 1
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Tailscale Downloader${RESET}  ${DIM}channel: ${CHANNEL}${RESET}"
echo ""

# Changelog-only mode
if $CHANGELOG_ONLY; then
  show_changelog "$CHANGELOG_ENTRIES"
  exit 0
fi

# List-only mode
if $LIST_ONLY; then
  list_releases
  show_changelog "$CHANGELOG_ENTRIES"
  exit 0
fi

# Resolve platform
[ -z "$PLATFORM" ] && PLATFORM=$(detect_platform)
info "Platform: ${BOLD}${PLATFORM}${RESET}"

# Resolve version
if [ -z "$VERSION" ]; then
  info "Fetching latest version for ${PLATFORM}..."
  VERSION=$(fetch_latest_version "$PLATFORM")
  if [ -z "$VERSION" ]; then
    # Fall back to GitHub releases
    VERSION=$(fetch_releases 1 | awk '{print $1}' | sed 's/^v//')
  fi
fi

if [ -z "$VERSION" ]; then
  err "Could not determine latest version. Use -v to specify one."
  exit 1
fi

info "Version: ${BOLD}${VERSION}${RESET}"

# Show changelog before downloading
show_changelog "$CHANGELOG_ENTRIES"

# Build URL
DOWNLOAD_URL=$(resolve_url "$PLATFORM" "$VERSION" "$PKGS_ROOT")
FILENAME=$(basename "$DOWNLOAD_URL")
DEST="${OUTPUT_DIR}/${FILENAME}"

info "Downloading: ${DIM}${DOWNLOAD_URL}${RESET}"

# Check if already exists
if [ -f "$DEST" ]; then
  warn "Already exists: ${DEST}"
  read -rp "  Overwrite? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Skipped."; exit 0; }
fi

mkdir -p "$OUTPUT_DIR"

# Download with progress
HTTP_STATUS=$(curl -L --progress-bar -o "$DEST" -w "%{http_code}" "$DOWNLOAD_URL")

if [ "$HTTP_STATUS" != "200" ]; then
  err "Download failed (HTTP ${HTTP_STATUS}): ${DOWNLOAD_URL}"
  rm -f "$DEST"
  # Suggest nearby versions
  echo ""
  warn "This version/platform combination may not exist. Recent releases:"
  fetch_releases 5 | while read -r tag date; do
    printf "    %s  (%s)\n" "${tag#v}" "${date%T*}"
  done
  exit 1
fi

echo ""
ok "Saved to: ${BOLD}${DEST}${RESET}"

# Checksum
$NO_VERIFY || verify_checksum "$DEST" "$DOWNLOAD_URL"

# macOS: offer to open installer
if [[ "$PLATFORM" == macos-pkg ]] && command -v open >/dev/null 2>&1; then
  echo ""
  read -rp "  Open installer now? [y/N] " open_answer
  [[ "$open_answer" =~ ^[Yy]$ ]] && open "$DEST"
fi

echo ""
ok "Done."
echo ""
