#!/bin/bash
# Checks the built bundle and the real NSApplication icon setter without
# launching Inkrail, opening windows, or accessing saved letters/preferences.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "App icon checks require macOS; they were NOT run." >&2
    exit 1
fi
INKRAIL_APP="${1:-$INKRAIL_ROOT/dist/Inkrail.app}"
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/app-icon-checks"
INKRAIL_SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$INKRAIL_CHECK_DIR/FixtureResources.bundle" "$INKRAIL_CHECK_DIR/Empty.bundle"
cp "$INKRAIL_ROOT/Sources/Inkrail/Resources/AppIcon.png" "$INKRAIL_CHECK_DIR/FixtureResources.bundle/AppIcon.png"
# Reuse the native UI fixture's module cache if available.
INKRAIL_MODULE_CACHE="$INKRAIL_ROOT/.build/settings-popup-checks/ModuleCache"
mkdir -p "$INKRAIL_MODULE_CACHE"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
    -sdk "$INKRAIL_SDK" -target "$(uname -m)-apple-macos13.0" \
    -module-cache-path "$INKRAIL_MODULE_CACHE" \
    "$INKRAIL_ROOT/Sources/Inkrail/Services/Resources.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Services/AppIcon.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/app-icon-check.swift" \
    -o "$INKRAIL_CHECK_DIR/app-icon-check"
"$INKRAIL_CHECK_DIR/app-icon-check" "$INKRAIL_CHECK_DIR" "$INKRAIL_APP"
