#!/bin/bash
# Development only: original native 3D geometry -> bundled transparent artwork.
# The app consumes the PNGs; it does not require SceneKit or a rendering loop.
set -euo pipefail
INKRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INKRAIL_RENDER_DIR="$INKRAIL_ROOT/.build/physical-lamps"
mkdir -p "$INKRAIL_RENDER_DIR/ModuleCache"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$INKRAIL_RENDER_DIR/ModuleCache" \
  "$INKRAIL_ROOT/scripts/fixtures/render-desk-lamps.swift" \
  -o "$INKRAIL_RENDER_DIR/render-desk-lamps"
"$INKRAIL_RENDER_DIR/render-desk-lamps" "$INKRAIL_ROOT/Sources/Inkrail/Resources"
