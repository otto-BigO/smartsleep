#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SmartSleep.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Bygger SmartSleep.app..."

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

swiftc -O \
    -target arm64-apple-macosx12.0 \
    -o "$MACOS_DIR/SmartSleep" \
    "$SCRIPT_DIR"/Sources/*.swift

# Signer med et fast designated requirement. Ellers ser macOS hver ny build som en ny app
# og beder om Automation-tilladelse til Spotify og Brave igen efter hver build.
codesign --force --sign - --identifier com.personal.SmartSleep \
    --requirements '=designated => identifier "com.personal.SmartSleep"' \
    "$APP_BUNDLE"

echo "✅ SmartSleep.app bygget i $APP_BUNDLE!"
