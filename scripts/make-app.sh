#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/HiClaude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HiClaude "$APP/Contents/MacOS/HiClaude"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Gerado: $APP"
