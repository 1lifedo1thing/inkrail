#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if ! bash "$ROOT/scripts/build-app.sh"; then
    echo ""
    echo "The build did not finish. Read the error above; setup and troubleshooting are in README.md."
    read -r -p "Press Return to close this window. " _ || true
    exit 1
fi
open "$ROOT/dist/Inkrail.app"
