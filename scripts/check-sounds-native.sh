#!/bin/bash
# Decode the shipped sounds with AVFoundation through the production resolver.
# Does not start playback, create AppModel, read letters, or write preferences.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Native audio decoding checks require macOS; they were NOT run." >&2
    exit 1
fi
INKRAIL_SOURCE_BUNDLE="${1:-$INKRAIL_ROOT/dist/Inkrail.app/Contents/Resources/Inkrail_Inkrail.bundle}"
if [[ ! -d "$INKRAIL_SOURCE_BUNDLE" ]]; then
    echo "Build the app first, or pass its Inkrail_Inkrail.bundle path." >&2
    exit 1
fi
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/sound-checks"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache"
# A fresh fixture prevents stale resources from concealing a missing asset.
INKRAIL_RUN_DIR="$(mktemp -d "$INKRAIL_CHECK_DIR/run-XXXXXX")"
INKRAIL_FIXTURE_APP="$INKRAIL_RUN_DIR/AudioCheck.app"
INKRAIL_FIXTURE_BUNDLE="$INKRAIL_FIXTURE_APP/Contents/Resources/Inkrail_Inkrail.bundle"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache" "$INKRAIL_FIXTURE_APP/Contents/MacOS" "$INKRAIL_FIXTURE_BUNDLE"
cp -R "$INKRAIL_SOURCE_BUNDLE/." "$INKRAIL_FIXTURE_BUNDLE/"
diff -rq "$INKRAIL_SOURCE_BUNDLE" "$INKRAIL_FIXTURE_BUNDLE"
cat > "$INKRAIL_FIXTURE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>audio-check</string>
<key>CFBundleIdentifier</key><string>local.inkrail.audio-check</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos13.0" \
    -module-cache-path "$INKRAIL_CHECK_DIR/ModuleCache" \
    "$INKRAIL_ROOT/Sources/InkrailCore/Customization.swift" \
    "$INKRAIL_ROOT/Sources/InkrailCore/DeskAppearance.swift" \
    "$INKRAIL_ROOT/Sources/InkrailCore/Page.swift" \
    "$INKRAIL_ROOT/Sources/InkrailCore/MechanismStyle.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Services/Resources.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/sound-check.swift" \
    -o "$INKRAIL_CHECK_DIR/audio-check"
"$INKRAIL_CHECK_DIR/audio-check" "$INKRAIL_SOURCE_BUNDLE" fallback
cp "$INKRAIL_CHECK_DIR/audio-check" "$INKRAIL_FIXTURE_APP/Contents/MacOS/audio-check"
"$INKRAIL_FIXTURE_APP/Contents/MacOS/audio-check" "$INKRAIL_FIXTURE_BUNDLE" packaged
