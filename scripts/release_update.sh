#!/bin/bash
# Build manual-install personal release packages. No Sparkle appcast or upstream publishing.
# Usage: ./scripts/release_update.sh [version]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
cd "$PROJECT_DIR"
VERSION="${1:-$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: Expected a personal version such as 1.0.0" >&2
    exit 1
fi

xcodegen generate
mkdir -p "$BUILD_DIR"
xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release \
    -derivedDataPath "$DERIVED_DATA" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" build

APP_PATH="$DERIVED_DATA/Build/Products/Release/OpenClip.app"
test -d "$APP_PATH"
codesign --force --deep -s - "$APP_PATH"
ZIP_PATH="$BUILD_DIR/OpenClip-v$VERSION.zip"
DMG_PATH="$BUILD_DIR/OpenClip-v$VERSION.dmg"
# Do not leave an old signed upstream appcast next to personal artifacts.
rm -f "$BUILD_DIR/appcast.xml" "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "OpenClip" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
echo "Personal release packages:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
