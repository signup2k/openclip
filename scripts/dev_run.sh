#!/bin/bash
# Fast local development build & run (No installation to /Applications required)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"

echo "⚡️ Building Debug build..."
xcodegen
xcodebuild -project OpenClip.xcodeproj -derivedDataPath "$DERIVED_DATA" -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' build > /dev/null

APP_PATH="$DERIVED_DATA/Build/Products/Debug/OpenClip.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Could not find built OpenClip.app in DerivedData"
  exit 1
fi

echo "Terminating old instances & launching from DerivedData..."
pkill -x OpenClip || true
"$APP_PATH/Contents/MacOS/OpenClip" > /tmp/openclip.log 2>&1 &

echo "Running directly from: $APP_PATH (logs at /tmp/openclip.log)"
