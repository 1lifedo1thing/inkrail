#!/bin/bash
# Isolated native editor/component captures, not running-app screenshots.
# Never creates AppModel, opens saved letters, writes preferences or plays audio.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Native paper-roll renders require macOS; they were NOT run." >&2
    exit 1
fi
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/paper-roll-renders"
INKRAIL_SDK="$(xcrun --sdk macosx --show-sdk-path)"
INKRAIL_TARGET="$(uname -m)-apple-macos13.0"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache" "$INKRAIL_CHECK_DIR/FixtureResources.bundle"
cp "$INKRAIL_ROOT/Sources/Inkrail/Resources/paper-grain.png" "$INKRAIL_CHECK_DIR/FixtureResources.bundle/"
bash "$INKRAIL_ROOT/scripts/check-swiftui.sh"
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
    "$INKRAIL_ROOT/Sources/Inkrail/Services/Resources.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/Palette.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/WritingFont+AppKit.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/PaperDetails.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/MechanismMaterials.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/Mechanism.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/PaperSurface.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Views/DeskSceneLighting.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/InkLayoutManager.swift" \
    "$INKRAIL_ROOT/Sources/Inkrail/Editor/PaperEditor.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/paper-roll-render.swift" \
    -o "$INKRAIL_CHECK_DIR/paper-roll-render"
"$INKRAIL_CHECK_DIR/paper-roll-render" "$INKRAIL_CHECK_DIR"
