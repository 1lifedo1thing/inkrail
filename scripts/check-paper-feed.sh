#!/bin/bash
# Programmatic native editor checks, independent of XCTest and saved letters.
# This is not a substitute for real input-method, menu, clipboard or visual QA.
set -euo pipefail

INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Paper-feed checks require macOS and AppKit; they were NOT run." >&2
    exit 1
fi
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/paper-feed-checks"
INKRAIL_SDK="$(xcrun --sdk macosx --show-sdk-path)"
INKRAIL_TARGET="$(uname -m)-apple-macos13.0"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache"

# Compile the real portable sources afresh so this probe never links an older
# preference model from a separate SwiftPM build configuration.
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
    "$INKRAIL_ROOT/Sources/Inkrail/Compatibility/InkrailState.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/Palette.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/WritingFont+AppKit.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/InkLayoutManager.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/LetterFormatting.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/MarkdownBlocks.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/LetterEditor.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/PaperEditor.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/AppModel.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/storage-model-support.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/editor-storage-check.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/paper-feed-check.swift" \
    -o "$INKRAIL_CHECK_DIR/paper-feed-check"

"$INKRAIL_CHECK_DIR/paper-feed-check"
