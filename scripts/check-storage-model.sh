#!/bin/bash
# Production AppModel + repository checks using disposable files and in-memory defaults.
# No app windows, picker automation, audio, or saved user letters/preferences.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Storage model checks require macOS; they were NOT run." >&2
    exit 1
fi
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/storage-model-checks"
INKRAIL_SDK="$(xcrun --sdk macosx --show-sdk-path)"
INKRAIL_TARGET="$(uname -m)-apple-macos13.0"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
    -sdk "$INKRAIL_SDK" -target "$INKRAIL_TARGET" \
    -module-cache-path "$INKRAIL_CHECK_DIR/ModuleCache" \
    -emit-library -emit-module -module-name InkrailCore \
    -emit-module-path "$INKRAIL_CHECK_DIR/InkrailCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libInkrailCore.dylib \
    "$INKRAIL_ROOT"/Sources/InkrailCore/*.swift \
    -o "$INKRAIL_CHECK_DIR/libInkrailCore.dylib"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
    -sdk "$INKRAIL_SDK" -target "$INKRAIL_TARGET" \
    -module-cache-path "$INKRAIL_CHECK_DIR/ModuleCache" \
    -I "$INKRAIL_CHECK_DIR" -L "$INKRAIL_CHECK_DIR" -lInkrailCore \
    -Xlinker -rpath -Xlinker @loader_path \
    "$INKRAIL_ROOT/Sources/Inkrail/AppModel.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/storage-model-check.swift" \
    -o "$INKRAIL_CHECK_DIR/storage-model-check"
"$INKRAIL_CHECK_DIR/storage-model-check"
