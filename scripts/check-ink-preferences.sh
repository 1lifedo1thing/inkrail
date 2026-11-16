#!/bin/bash
# Foundation-only regressions, independent of XCTest, UI and user preferences.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/ink-preference-checks"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache"
INKRAIL_FLAGS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
    INKRAIL_COMPILER=(xcrun --sdk macosx swiftc)
    INKRAIL_FLAGS=(-sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos13.0")
else
    INKRAIL_COMPILER=(swiftc)
fi
"${INKRAIL_COMPILER[@]}" -swift-version 5 -parse-as-library \
    "${INKRAIL_FLAGS[@]}" -module-cache-path "$INKRAIL_CHECK_DIR/ModuleCache" \
    "$INKRAIL_ROOT"/Sources/InkrailCore/*.swift \
    "$INKRAIL_ROOT/scripts/fixtures/ink-preferences-check.swift" \
    -o "$INKRAIL_CHECK_DIR/ink-preferences-check"
"$INKRAIL_CHECK_DIR/ink-preferences-check"
