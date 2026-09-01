#!/bin/bash
# Downloads the latest prebuilt Agentch.app and puts it in /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/aktoriukas/agentch/main/scripts/install.sh | bash
#
# The app is ad-hoc signed, not signed with an Apple Developer ID, so macOS quarantines it on
# download and refuses to open it. This script removes that quarantine flag. That is the whole
# reason the script exists — read it before you run it, which is also why it is not minified.
set -euo pipefail

REPO="aktoriukas/agentch"
BASE="https://github.com/$REPO/releases/latest/download"
DEST="${DEST:-/Applications}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading the latest Agentch.app"
curl -fsSL "$BASE/Agentch.app.zip" -o "$WORK/Agentch.app.zip"
curl -fsSL "$BASE/Agentch.app.zip.sha256" -o "$WORK/expected.sha256"

echo "==> Verifying the checksum"
EXPECTED=$(awk '{print $1}' "$WORK/expected.sha256")
ACTUAL=$(shasum -a 256 "$WORK/Agentch.app.zip" | awk '{print $1}')
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "Checksum mismatch. Expected $EXPECTED, got $ACTUAL. Refusing to install." >&2
    exit 1
fi

echo "==> Unpacking"
ditto -x -k "$WORK/Agentch.app.zip" "$WORK/unpacked"

if pgrep -f "Agentch.app/Contents/MacOS/Agentch" >/dev/null; then
    echo "==> Quitting the running copy"
    pkill -f "Agentch.app/Contents/MacOS/Agentch" || true
    sleep 1
fi

echo "==> Installing to $DEST"
rm -rf "$DEST/Agentch.app"
ditto "$WORK/unpacked/Agentch.app" "$DEST/Agentch.app"

# Without this the app is quarantined and Gatekeeper refuses it, because there is no Developer ID
# signature for it to check.
echo "==> Removing the download quarantine"
xattr -dr com.apple.quarantine "$DEST/Agentch.app" 2>/dev/null || true

echo "==> Installed. Starting it."
open -a "$DEST/Agentch.app"
echo
echo "Nothing appears in the Dock or the menu bar — move the pointer to the notch."
