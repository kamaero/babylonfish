#!/bin/bash

APP_NAME="BabylonFish"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INSTALL_DIR="$HOME/Программы"
DIST_DIR="dist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUILD_NUMBER="$(date +%s)"
ALT_INSTALL_DIR="$HOME/Applications"

pkill -9 "$APP_NAME" 2>/dev/null || true

# Reset permissions (Accessibility/Input Monitoring)
# This forces the system to forget the old binary signature and allows re-requesting permissions.
echo "Resetting TCC permissions for $APP_NAME..."
tccutil reset Accessibility com.babylonfish.app 2>/dev/null || true
tccutil reset All com.babylonfish.app 2>/dev/null || true

rm -rf ".build"
rm -rf "$HOME/Library/Caches/com.babylonfish.app" "$HOME/Library/Saved Application State/com.babylonfish.app.savedState"

# Increment Version
chmod +x ./increment_version.sh
./increment_version.sh

swift build -c release

echo "Creating $APP_BUNDLE..."

# Build output folder
rm -rf "$DIST_DIR/$APP_BUNDLE"
mkdir -p "$DIST_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp "Sources/BabylonFish/Resources/Info.plist" "$CONTENTS_DIR/"

# (Optional) You could generate an icns here or copy one if you had it.

echo "Staging into $DIST_DIR..."
ditto "$APP_BUNDLE" "$DIST_DIR/$APP_BUNDLE"

if [ -x "$PLISTBUDDY" ]; then
  "$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$DIST_DIR/$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
  "$PLISTBUDDY" -c "Add :CFBundleVersion string $BUILD_NUMBER" "$DIST_DIR/$APP_BUNDLE/Contents/Info.plist"
fi

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
ditto "$DIST_DIR/$APP_BUNDLE" "$INSTALL_DIR/$APP_BUNDLE"
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
if [ -x "/usr/bin/codesign" ]; then
  /usr/bin/codesign --force --deep --sign - "$INSTALL_DIR/$APP_BUNDLE" >/dev/null 2>&1 || true
fi
if [ "$INSTALL_DIR" != "$ALT_INSTALL_DIR" ]; then
  rm -rf "$ALT_INSTALL_DIR/$APP_BUNDLE"
fi

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$INSTALL_DIR/$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "$APP_NAME installed successfully to $INSTALL_DIR/$APP_BUNDLE"
echo "You can launch it via Spotlight or Finder."
echo "To run from terminal: open \"$INSTALL_DIR/$APP_BUNDLE\""
echo "Staged copy: $DIST_DIR/$APP_BUNDLE"
