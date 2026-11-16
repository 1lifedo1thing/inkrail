#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Inkrail's desktop app must be built on macOS. Core tests can run elsewhere with: swift test" >&2
    exit 1
fi
if ! xcrun --sdk macosx --find swift >/dev/null 2>&1; then
    echo "Apple's developer tools are required. Install Xcode 15+ or run xcode-select --install, then retry." >&2
    exit 1
fi

echo "Developer directory: ${DEVELOPER_DIR:-$(xcode-select -p)}"
echo "Swift compiler: $(xcrun --sdk macosx --find swift)"
echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-path)"
echo "Checking SwiftUI state compatibility…"
bash "$ROOT/scripts/check-swiftui.sh"
echo "Building Inkrail for $(uname -m)…"
# Resolve the compiler through the selected Apple toolchain, not a Swift
# executable that a Python environment, Homebrew or another PATH entry adds.
xcrun --sdk macosx swift build -c release --product Inkrail
BIN="$(xcrun --sdk macosx swift build -c release --show-bin-path)"
APP="$ROOT/dist/Inkrail.app"
# Remove only this build's known output, never the user's installed app or data.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Inkrail" "$APP/Contents/MacOS/Inkrail"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
BUNDLE="$BIN/Inkrail_Inkrail.bundle"
if [[ ! -d "$BUNDLE" ]]; then
    echo "The SwiftPM resource bundle was not found at $BUNDLE" >&2
    exit 1
fi
# SwiftPM can retain deleted resources in an incremental build directory.
# Recreate this package's plain PNG/WAV resource payload from current sources
# while retaining the generated bundle layout and metadata. Never copy stale
# assets into a release, and never clean user data or unrelated build outputs.
PACKAGED_BUNDLE="$APP/Contents/Resources/Inkrail_Inkrail.bundle"
if [[ -d "$BUNDLE/Contents/Resources" ]]; then
    PACKAGED_RESOURCE_DIR="$PACKAGED_BUNDLE/Contents/Resources"
    mkdir -p "$PACKAGED_RESOURCE_DIR"
    cp "$BUNDLE/Contents/Info.plist" "$PACKAGED_BUNDLE/Contents/Info.plist"
else
    PACKAGED_RESOURCE_DIR="$PACKAGED_BUNDLE"
    mkdir -p "$PACKAGED_RESOURCE_DIR"
    if [[ -f "$BUNDLE/Info.plist" ]]; then
        cp "$BUNDLE/Info.plist" "$PACKAGED_BUNDLE/Info.plist"
    fi
fi
cp -R "$ROOT/Sources/Inkrail/Resources/." "$PACKAGED_RESOURCE_DIR/"

ICONSET="$ROOT/.build/Inkrail.iconset"
ICON_SOURCE="$ROOT/Sources/Inkrail/Resources/AppIcon.png"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signing for a local build. This is NOT Developer ID signing/notarization.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo ""
echo "Created: $APP"
echo "Launch with: open \"$APP\""
echo "You can also drag Inkrail.app to Applications. Your letters are stored separately."
