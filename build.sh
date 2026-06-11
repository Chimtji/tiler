#!/bin/sh
# Builds Tiler.app into ./build/Tiler.app
set -e
cd "$(dirname "$0")"

swift build -c release

APP_DIR="build/Tiler.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp .build/release/Tiler "$APP_DIR/Contents/MacOS/Tiler"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing with the hardened runtime (blocks code injection via
# DYLD_* variables, unsigned library loading, and debugger attachment).
codesign --force --options runtime --sign - "$APP_DIR"

echo ""
echo "Built $APP_DIR"
echo "Install with:  cp -r $APP_DIR /Applications/"
