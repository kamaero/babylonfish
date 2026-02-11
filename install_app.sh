#!/bin/bash

# Configuration
APP_NAME="BabylonFish ML"
EXECUTABLE_NAME="BabylonFish3"
BUNDLE_ID="com.babylonfish.app.ml"
VERSION="3.0.17"
INSTALL_DIR="$HOME/Applications"
BUILD_DIR=".build/release"

# APP_BUNDLE will be defined after version increment
CONTENTS_DIR_NAME="Contents"
MACOS_DIR_NAME="MacOS"
RESOURCES_DIR_NAME="Resources"

DIST_DIR="dist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUILD_NUMBER="$(date +%s)"
ALT_INSTALL_DIR=""

pkill -9 "$APP_NAME" 2>/dev/null || true

# Reset permissions (Accessibility/Input Monitoring)
# This forces the system to forget the old binary signature and allows re-requesting permissions.
echo "Resetting TCC permissions for $APP_NAME..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

# Remove old versions to prevent confusion
echo "Removing old versions from $INSTALL_DIR and $ALT_INSTALL_DIR..."
for dir in "$INSTALL_DIR" "$ALT_INSTALL_DIR"; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 1 -name "BabylonFish*.app" -print0 | while IFS= read -r -d '' app; do
    if [ -x "$LSREGISTER" ]; then
      "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    fi
    rm -rf "$app"
  done
done

rm -rf ".build"
rm -rf "$HOME/Library/Caches/com.babylonfish.app" "$HOME/Library/Saved Application State/com.babylonfish.app.savedState"

# Increment Version
chmod +x ./increment_version.sh
./increment_version.sh

# Read Version to define APP_BUNDLE name
VERSION_FILE="Sources/BabylonFish3/Version.swift"
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(grep -o '"[^"]*"' "$VERSION_FILE" | tr -d '"')
fi
if [ -z "$VERSION" ]; then
    VERSION="3.0.0"
fi

APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/$CONTENTS_DIR_NAME"
MACOS_DIR="$CONTENTS_DIR/$MACOS_DIR_NAME"
RESOURCES_DIR="$CONTENTS_DIR/$RESOURCES_DIR_NAME"

swift build -c release --product BabylonFish3 --arch arm64 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish3 --arch x86_64 --disable-sandbox

echo "Creating $APP_BUNDLE..."

# Build output folder
rm -rf "$DIST_DIR/BabylonFish*.app" # Clean old versions in dist
mkdir -p "$DIST_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy fix_permissions.sh to Resources if present
if [ -f "fix_permissions.sh" ]; then
    cp fix_permissions.sh "$RESOURCES_DIR/"
    chmod +x "$RESOURCES_DIR/fix_permissions.sh"
    echo "Copied fix_permissions.sh to Resources"
fi

# Copy executable
ARM_BIN=".build/arm64-apple-macosx/release/BabylonFish3"
X86_BIN=".build/x86_64-apple-macosx/release/BabylonFish3"
if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
    lipo -create -output "$MACOS_DIR/BabylonFish3" "$ARM_BIN" "$X86_BIN"
else
    echo "Error: Missing architecture builds: arm64=$([ -f \"$ARM_BIN\" ] && echo ok || echo missing), x86_64=$([ -f \"$X86_BIN\" ] && echo ok || echo missing)"
    exit 1
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BabylonFish3</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 BabylonFish. All rights reserved.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSInputMonitoringUsageDescription</key>
    <string>BabylonFish needs Input Monitoring to detect typing and switch keyboard layouts automatically.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>BabylonFish needs Accessibility to correct text in other applications.</string>
</dict>
</plist>
EOF

# Copy Icons if they exist
if [ -f "Resources/icon.icns" ]; then
    echo "Copying icon.icns..."
    cp "Resources/icon.icns" "$RESOURCES_DIR/"
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
  /usr/bin/codesign --force --deep --sign - --entitlements Entitlements.plist "$INSTALL_DIR/$APP_BUNDLE" >/dev/null 2>&1 || true
fi
if [ -n "$ALT_INSTALL_DIR" ] && [ "$INSTALL_DIR" != "$ALT_INSTALL_DIR" ]; then
  rm -rf "$ALT_INSTALL_DIR/$APP_BUNDLE"
fi

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$INSTALL_DIR/$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "$APP_NAME installed successfully to $INSTALL_DIR/$APP_BUNDLE"
echo "You can launch it via Spotlight or Finder."
echo "To run from terminal: open \"$INSTALL_DIR/$APP_BUNDLE\""
echo "Staged copy: $DIST_DIR/$APP_BUNDLE"
