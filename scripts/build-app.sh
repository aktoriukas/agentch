#!/bin/bash
# Assembles Agentch.app from a release build. SwiftPM only produces a bare executable, and a bare
# executable has nowhere to put an icon and cannot register for launch-at-login, so the bundle is
# built here rather than by a checked-in Xcode project.
#
#   ./scripts/build-app.sh              -> build/Agentch.app
#   ./scripts/build-app.sh --install    -> also copies it to /Applications
#   ./scripts/build-app.sh --universal  -> arm64 + x86_64, for release artifacts (needs Xcode)
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL=false
ARCHS=()
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# A release tarball has no git metadata, so packagers pass the version in.
VERSION="${AGENTCH_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")}"
APP="build/Agentch.app"

echo "==> Building Agentch $VERSION"
# --disable-sandbox: SwiftPM sandboxes manifest evaluation with sandbox-exec, which is itself
# refused inside Homebrew's build sandbox.
swift build -c release --disable-sandbox ${ARCHS[@]+"${ARCHS[@]}"}
# A universal build lands somewhere else entirely, so ask rather than assume.
BIN="$(swift build -c release --disable-sandbox ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Agentch"

echo "==> Rendering the icon"
"$BIN" --icon >/dev/null
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size /tmp/agentch-icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) /tmp/agentch-icon.png \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Agentch"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>agentch</string>
    <key>CFBundleDisplayName</key><string>agentch</string>
    <key>CFBundleIdentifier</key><string>com.agentch.app</string>
    <key>CFBundleExecutable</key><string>Agentch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- No Dock icon, no menu bar: the notch panel is the whole interface. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc: enough for the app to run and to hold a stable identity for launch-at-login. Signing it
# for other people's machines needs an Apple Developer ID, which this project does not have.
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> Built $APP"

if [[ "$INSTALL" == true ]]; then
    echo "==> Installing to /Applications"
    rm -rf /Applications/Agentch.app
    cp -R "$APP" /Applications/Agentch.app
    echo "==> Installed. Open it with: open -a Agentch"
fi
