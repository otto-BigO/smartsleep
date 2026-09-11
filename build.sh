#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SmartSleep.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Bygger SmartSleep.app..."

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Compile Swift code
swiftc -O \
    -target arm64-apple-macosx12.0 \
    -o "$MACOS_DIR/SmartSleep" \
    "$SCRIPT_DIR/Log.swift" \
    "$SCRIPT_DIR/AudioActivity.swift" \
    "$SCRIPT_DIR/NowPlayingFetcher.swift" \
    "$SCRIPT_DIR/DisplayBrightnessManager.swift" \
    "$SCRIPT_DIR/AudioSleepMonitor.swift" \
    "$SCRIPT_DIR/SettingsView.swift" \
    "$SCRIPT_DIR/SettingsWindowController.swift" \
    "$SCRIPT_DIR/AppDelegate.swift"

# Signer med et fast designated requirement. Ellers ser macOS hver ny build som en ny app
# og beder om Automation-tilladelse til Spotify og Brave igen efter hver build.
codesign --force --sign - --identifier com.personal.SmartSleep \
    --requirements '=designated => identifier "com.personal.SmartSleep"' \
    "$APP_BUNDLE"

echo "✅ SmartSleep.app bygget i $APP_BUNDLE!"
