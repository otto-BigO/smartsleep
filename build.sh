#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SmartSleep.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Bygger SmartSleep.app med SwiftUI Settings GUI..."

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Compile Swift code including SwiftUI SettingsView and SettingsWindowController
swiftc -O \
    -target arm64-apple-macosx12.0 \
    -o "$MACOS_DIR/SmartSleep" \
    "$SCRIPT_DIR/DisplayBrightnessManager.swift" \
    "$SCRIPT_DIR/AudioSleepMonitor.swift" \
    "$SCRIPT_DIR/SettingsView.swift" \
    "$SCRIPT_DIR/SettingsWindowController.swift" \
    "$SCRIPT_DIR/AppDelegate.swift"

echo "✅ SmartSleep.app blev bygget succesfuldt med Glass GUI i $APP_BUNDLE!"
