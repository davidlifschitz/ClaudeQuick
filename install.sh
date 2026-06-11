#!/bin/bash
set -e

swift build -c release

APP="/Applications/ClaudeQuick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeQuick "$APP/Contents/MacOS/ClaudeQuick"
cp ClaudeQuick/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
mdimport "$APP"

echo "Installed to $APP"
