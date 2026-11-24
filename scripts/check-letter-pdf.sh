#!/bin/bash
# Exercise the production renderer with in-memory letters and no save dialog.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "The native letter PDF check requires macOS." >&2
    exit 1
fi
OUTPUT="$ROOT/.build/letter-pdf-check"
mkdir -p "$OUTPUT/ModuleCache" "$OUTPUT/FixtureResources.bundle"
cp "$ROOT"/Sources/Inkrail/Resources/*.png "$OUTPUT/FixtureResources.bundle/"
FLAGS=(-swift-version 5 -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)"
       -target "$(uname -m)-apple-macos13.0" -module-cache-path "$OUTPUT/ModuleCache")
xcrun --sdk macosx swiftc "${FLAGS[@]}" -emit-library -emit-module -module-name InkrailCore \
    -emit-module-path "$OUTPUT/InkrailCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libInkrailCore.dylib \
    "$ROOT"/Sources/InkrailCore/*.swift -o "$OUTPUT/libInkrailCore.dylib"
xcrun --sdk macosx swiftc "${FLAGS[@]}" -I "$OUTPUT" -L "$OUTPUT" -lInkrailCore \
    -Xlinker -rpath -Xlinker @loader_path \
    "$ROOT"/Sources/Inkrail/{Compatibility,Editor,Services,Views}/*.swift \
    "$ROOT/Sources/Inkrail/AppModel.swift" "$ROOT/scripts/fixtures/letter-pdf-check.swift" \
    -o "$OUTPUT/letter-pdf-check"
"$OUTPUT/letter-pdf-check" "$OUTPUT"
