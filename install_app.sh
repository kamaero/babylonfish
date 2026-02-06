#!/bin/bash

APP_NAME="BabylonFish"
BUILD_DIR=".build/release"
# APP_BUNDLE will be defined after version increment
CONTENTS_DIR_NAME="Contents"
MACOS_DIR_NAME="MacOS"
RESOURCES_DIR_NAME="Resources"

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

# Remove old versions to prevent confusion
echo "Removing old versions from $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/BabylonFish"*.app

rm -rf ".build"
rm -rf "$HOME/Library/Caches/com.babylonfish.app" "$HOME/Library/Saved Application State/com.babylonfish.app.savedState"

# Increment Version
chmod +x ./increment_version.sh
./increment_version.sh

# Read Version to define APP_BUNDLE name
if [ -x "$PLISTBUDDY" ]; then
    VERSION=$("$PLISTBUDDY" -c "Print :CFBundleShortVersionString" "Sources/BabylonFish/Resources/Info.plist")
else
    VERSION="1.0.x"
fi

APP_BUNDLE="${APP_NAME}_v${VERSION}.app"
CONTENTS_DIR="$APP_BUNDLE/$CONTENTS_DIR_NAME"
MACOS_DIR="$CONTENTS_DIR/$MACOS_DIR_NAME"
RESOURCES_DIR="$CONTENTS_DIR/$RESOURCES_DIR_NAME"

swift build -c release --product BabylonFish2 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish2 --disable-sandbox

echo "Creating $APP_BUNDLE..."

# Build output folder
rm -rf "$DIST_DIR/BabylonFish*.app" # Clean old versions in dist
mkdir -p "$DIST_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
ARM_BIN=".build/arm64-apple-macosx/release/BabylonFish2"
X86_BIN=".build/x86_64-apple-macosx/release/BabylonFish2"
if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
    lipo -create -output "$MACOS_DIR/BabylonFish" "$ARM_BIN" "$X86_BIN"
else
    echo "Error: Missing architecture builds: arm64=$([ -f \"$ARM_BIN\" ] && echo ok || echo missing), x86_64=$([ -f \"$X86_BIN\" ] && echo ok || echo missing)"
    exit 1
fi

# Copy Info.plist
cp "Sources/BabylonFish/Resources/Info.plist" "$CONTENTS_DIR/"

# Copy Icons if they exist
if [ -f "Sources/BabylonFish/Resources/AppIcon.icns" ]; then
    echo "Copying AppIcon.icns..."
    cp "Sources/BabylonFish/Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Tray icons are now generated dynamically (SF Symbols), no need to copy PNGs
# if [ -f "Sources/BabylonFish/Resources/tray_icon.png" ]; then ...

echo "Staging into $DIST_DIR..."
ditto "$APP_BUNDLE" "$DIST_DIR/$APP_BUNDLE"

# Create Releases Directory and Copy
RELEASES_DIR="$HOME/Projects/babylonfish/releases"
mkdir -p "$RELEASES_DIR"
echo "Copying to releases: $RELEASES_DIR/$APP_BUNDLE"
ditto "$DIST_DIR/$APP_BUNDLE" "$RELEASES_DIR/$APP_BUNDLE"

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
