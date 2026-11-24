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
# Single-architecture builds also work with standalone Command Line Tools.
# Some SwiftPM versions share one product directory across architectures.
SLICES=()
for arch in x86_64 arm64; do
    echo "Building Inkrail for ${arch}…"
    BUILD=(xcrun --sdk macosx swift build -c release --arch "$arch" --scratch-path "$ROOT/.build/macos-$arch")
    "${BUILD[@]}" --product Inkrail
    BIN="$("${BUILD[@]}" --show-bin-path)"
    SLICES+=("$BIN/Inkrail")
done
FINAL_APP="$ROOT/dist/Inkrail.app"
mkdir -p "$ROOT/dist"
STAGING_DIR="$(mktemp -d "$ROOT/dist/.inkrail-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/Inkrail.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
EXECUTABLE="$APP/Contents/MacOS/Inkrail"
xcrun lipo -create "${SLICES[@]}" -output "$EXECUTABLE"
xcrun lipo "$EXECUTABLE" -verify_arch x86_64
xcrun lipo "$EXECUTABLE" -verify_arch arm64
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

ICONSET="$STAGING_DIR/Inkrail.iconset"
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
codesign --verify --all-architectures --deep --strict "$APP"
# Publish only after the icon and signature are in place. Keep an existing
# bundle directory so Finder references continue to identify the same app.
if [[ -d "$FINAL_APP" ]]; then
    xcrun --sdk macosx swift -e '
        import Foundation
        let files = FileManager.default
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let target = URL(fileURLWithPath: CommandLine.arguments[2])
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: source, options: .usingNewMetadataOnly)
        } else {
            try files.moveItem(at: source, to: target)
        }' "$APP/Contents" "$FINAL_APP/Contents"
else
    mv "$APP" "$FINAL_APP"
fi
touch "$FINAL_APP"
echo ""
echo "Created: $FINAL_APP"
echo "Launch with: open \"$FINAL_APP\""
echo "You can also drag Inkrail.app to Applications. Your letters are stored separately."
