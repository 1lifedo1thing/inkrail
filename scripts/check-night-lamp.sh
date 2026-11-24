#!/bin/bash
# Render production SwiftUI lamp views in isolation, without opening user letters.
# These are component renders, not screenshots or interactive app/IME tests.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Night-lamp rendering checks require macOS; they were NOT run." >&2
    exit 1
fi
INKRAIL_CHECK_DIR="$INKRAIL_ROOT/.build/night-lamp-checks"
INKRAIL_SDK="$(xcrun --sdk macosx --show-sdk-path)"
INKRAIL_TARGET="$(uname -m)-apple-macos13.0"
mkdir -p "$INKRAIL_CHECK_DIR/ModuleCache" "$INKRAIL_CHECK_DIR/FixtureResources.bundle"
cp "$INKRAIL_ROOT"/Sources/Inkrail/Resources/{paper-grain,maker-mark}.png "$INKRAIL_CHECK_DIR/FixtureResources.bundle/"
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
    "$INKRAIL_ROOT/scripts/fixtures/lamp-profile-checks.swift" \
    "$INKRAIL_ROOT/scripts/fixtures/night-lamp-check.swift" \
    -o "$INKRAIL_CHECK_DIR/night-lamp-check"
"$INKRAIL_CHECK_DIR/night-lamp-check" "$INKRAIL_CHECK_DIR"
