#!/bin/sh
#
# install.sh — one-liner installer for Lineage (MLI-075 D5, REQ-6, ADR-068).
#
# Hosted at https://www.lineagent.ai/install.sh — usage:
#
#   curl -fsSL https://www.lineagent.ai/install.sh | sh
#
# Behavior:
#   1. Refuses root (per-user install only — `~/.local/bin/lineage`).
#   2. Detects platform (uname -s + uname -m → triple).
#   3. Fetches install-info.json from www.lineagent.ai (CDN-cached) for
#      the latest release pointer.
#   4. Downloads the platform-matching tarball.
#   5. Verifies sha256 against the release's checksums.txt.
#   6. Extracts the binary to ~/.local/bin/lineage.
#   7. Prints PATH hint if ~/.local/bin isn't already on PATH.
#
# Failure modes are loud and verbose. Exit status is non-zero on any
# failure; partial install state is cleaned up on exit. The script is
# POSIX sh-compatible (no bashisms) so it runs on Alpine, BusyBox, etc.

set -e

INSTALL_INFO_URL="${LINEAGE_INSTALL_INFO_URL:-https://www.lineagent.ai/install-info.json}"
INSTALL_DIR="${LINEAGE_INSTALL_DIR:-$HOME/.local/bin}"

# --- Refuse root -----------------------------------------------------
if [ "$(id -u)" = "0" ]; then
  echo "Don't install Lineage as root. Run as your own user:" >&2
  echo "  curl -fsSL ${INSTALL_INFO_URL%/install-info.json}/install.sh | sh" >&2
  echo "" >&2
  echo "If you need a system-wide install, use a package manager:" >&2
  echo "  brew install nowa/lineage/lineage    # macOS / linuxbrew" >&2
  echo "  npm install -g @lineage/cli          # via Node.js" >&2
  exit 1
fi

# --- Platform detection ----------------------------------------------
PLATFORM=$(uname -s)
ARCH=$(uname -m)

case "$PLATFORM-$ARCH" in
  Darwin-arm64)         TRIPLE="aarch64-apple-darwin"        PLATKEY="darwin-aarch64" ;;
  Darwin-x86_64)        TRIPLE="x86_64-apple-darwin"         PLATKEY="darwin-x86_64" ;;
  Linux-x86_64)         TRIPLE="x86_64-unknown-linux-gnu"    PLATKEY="linux-x86_64" ;;
  Linux-aarch64|Linux-arm64) TRIPLE="aarch64-unknown-linux-gnu" PLATKEY="linux-aarch64" ;;
  *)
    echo "Unsupported platform: $PLATFORM-$ARCH" >&2
    echo "Supported: macOS (x86_64, arm64), Linux (x86_64, aarch64)." >&2
    echo "Windows is not yet supported — try WSL or wait for Phase 1." >&2
    exit 1 ;;
esac

# --- Tool availability ----------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
sha256() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum;    then shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Need sha256sum or shasum installed to verify download." >&2
    exit 1
  fi
}

# --- Fetch install-info.json ----------------------------------------
echo "Fetching install info from $INSTALL_INFO_URL ..."
INFO_JSON=$(curl -fsSL "$INSTALL_INFO_URL")

# Extract version + tarball URL via grep + cut (avoid Python/jq dep).
VERSION=$(printf '%s' "$INFO_JSON" \
  | grep -m1 -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | cut -d'"' -f4)

TARBALL_URL=$(printf '%s' "$INFO_JSON" \
  | tr -d '\n' \
  | grep -o "\"$PLATKEY\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
  | head -1 \
  | cut -d'"' -f4)

CHECKSUMS_URL=$(printf '%s' "$INFO_JSON" \
  | grep -m1 -o '"checksums_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | cut -d'"' -f4)

if [ -z "$VERSION" ] || [ -z "$TARBALL_URL" ] || [ -z "$CHECKSUMS_URL" ]; then
  echo "Failed to parse install-info.json (got empty version/tarball/checksums)." >&2
  echo "Try installing manually from https://github.com/nowa/lineage/releases" >&2
  exit 1
fi

echo "Installing lineage $VERSION for $TRIPLE"
echo "  tarball: $TARBALL_URL"

# --- Download + verify ----------------------------------------------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

curl -fsSL "$TARBALL_URL"   -o "$TMPDIR/lineage.tar.gz"
curl -fsSL "$CHECKSUMS_URL" -o "$TMPDIR/checksums.txt"

EXPECTED=$(grep "lineage-${TRIPLE}.tar.gz" "$TMPDIR/checksums.txt" | awk '{print $1}')
ACTUAL=$(sha256 "$TMPDIR/lineage.tar.gz")

if [ -z "$EXPECTED" ]; then
  echo "Checksum file did not list lineage-${TRIPLE}.tar.gz." >&2
  echo "checksums.txt content:" >&2
  cat "$TMPDIR/checksums.txt" >&2
  exit 1
fi

if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "sha256 mismatch — refusing to install." >&2
  echo "  expected: $EXPECTED" >&2
  echo "  got:      $ACTUAL" >&2
  echo "If this persists, file an issue at https://github.com/nowa/lineage/issues" >&2
  exit 1
fi

# --- Extract + place -------------------------------------------------
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/lineage.tar.gz" -C "$TMPDIR"

# cargo-dist tarballs may put the binary in a `lineage-<triple>/` subdir
# or at the top level; handle both.
if [ -f "$TMPDIR/lineage" ]; then
  SRC="$TMPDIR/lineage"
elif [ -f "$TMPDIR/lineage-${TRIPLE}/lineage" ]; then
  SRC="$TMPDIR/lineage-${TRIPLE}/lineage"
else
  echo "Could not find 'lineage' binary in tarball. Contents:" >&2
  ls -la "$TMPDIR" >&2
  exit 1
fi

# Backup any existing install (lets `lineage self-update` rollback story work
# even when the binary was installed via this script first).
if [ -f "$INSTALL_DIR/lineage" ]; then
  mv -f "$INSTALL_DIR/lineage" "$INSTALL_DIR/lineage.prev" 2>/dev/null || true
fi

mv "$SRC" "$INSTALL_DIR/lineage"
chmod +x "$INSTALL_DIR/lineage"

echo ""
echo "✅ Installed lineage $VERSION to $INSTALL_DIR/lineage"

# --- PATH hint -------------------------------------------------------
case ":$PATH:" in
  *:"$INSTALL_DIR":*) ;;  # already on PATH
  *)
    echo ""
    echo "⚠️  $INSTALL_DIR is not on your PATH yet. Add it:"
    echo ""
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo ""
    echo "Then restart your shell or 'source ~/.zshrc' to pick it up."
    ;;
esac

# --- macOS Gatekeeper note -------------------------------------------
if [ "$PLATFORM" = "Darwin" ]; then
  echo ""
  echo "ℹ️  macOS may block the binary on first launch (\"can't be opened because Apple"
  echo "   cannot check it for malicious software\"). Right-click → Open, then"
  echo "   confirm. This is expected — Apple Developer ID notarization is on the"
  echo "   roadmap (Phase 1)."
fi

echo ""
echo "Try: lineage --version"
