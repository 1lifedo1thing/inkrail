#!/bin/bash
# Check the exact State-property-wrapper compatibility path before a full build.
# This checks compilation, not mounted-view behavior or UI rendering.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "SwiftUI compatibility type checking requires macOS; it was NOT run." >&2
    exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
if ! xcrun --sdk macosx swiftc -typecheck -swift-version 5 \
    -sdk "$SDK" -target "$(uname -m)-apple-macos13.0" \
    "$ROOT/Sources/Inkrail/Compatibility/InkrailState.swift" \
    "$ROOT/scripts/fixtures/state-smoke.swift"; then
    cat >&2 <<'HELP'

The small SwiftUI compatibility probe failed before the full app build.
The diagnostic above is the relevant error; this is not an app runtime test.
Confirm the selected developer tools and SDK belong together. A current full
Xcode installation is an alternative when standalone tools are incomplete:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-app.sh
Run that alternative only when Xcode is installed at the indicated path.
HELP
    exit 1
fi
echo "SwiftUI state compile probe passed."
