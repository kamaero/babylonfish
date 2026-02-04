#!/bin/bash
set -e

APP_NAME="BabylonFish"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
STAGING_DIR="pkg_staging"
OUTPUT_DIR="releases"
VERSION=$(sed -n 's/.*current = "\(.*\)"/\1/p' Sources/BabylonFish/Version.swift | tr -d '\r')
if [ -z "$VERSION" ]; then
    VERSION="1.0.0"
fi
PKG_NAME="${APP_NAME}_${VERSION}.pkg"

echo "🐠 Preparing to package $APP_NAME v$VERSION..."

# 1. Clean and Build
echo "Cleaning..."
rm -rf "$STAGING_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Building Release..."
# Ensure icons are generated
./setup_icons.sh

# Build binary
# Try to build universal if possible, otherwise host
swift build -c release --disable-sandbox

# 2. Prepare App Bundle Structure
echo "Creating App Bundle Structure..."
mkdir -p "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/Resources"

# Copy binary
# Note: universal build results in a binary in .build/apple/Products/Release/ or similar depending on swift version
# But 'swift build -c release' usually puts it in .build/release/BabylonFish (for host arch)
# For universal binary we might need more steps, but let's assume host arch (likely arm64 on M1) or standard release.
# To be safe, we check where it is.
if [ -f ".build/apple/Products/Release/$APP_NAME" ]; then
    cp ".build/apple/Products/Release/$APP_NAME" "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/MacOS/"
elif [ -f ".build/release/$APP_NAME" ]; then
    cp ".build/release/$APP_NAME" "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/MacOS/"
else
    echo "Error: Could not find built binary."
    exit 1
fi

# Copy Info.plist
cp "Sources/BabylonFish/Resources/Info.plist" "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/"

# Copy Resources (Icons)
if [ -d "Sources/BabylonFish/Resources" ]; then
    cp Sources/BabylonFish/Resources/*.icns "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    cp Sources/BabylonFish/Resources/*.png "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Update PkgInfo/Version
# (Optional: Use PlistBuddy to set version in Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%s)" "$STAGING_DIR/Applications/$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true

# 3. Signing (Self-signed or Developer ID)
# If you have a Developer ID, set it here. Otherwise, we'll try ad-hoc or skip.
# SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing App Bundle with $SIGNING_IDENTITY..."
    codesign --force --options runtime --deep --sign "$SIGNING_IDENTITY" "$STAGING_DIR/Applications/$APP_BUNDLE"
else
    echo "⚠️ No SIGNING_IDENTITY set. Signing ad-hoc (to run locally)."
    codesign --force --deep --sign - "$STAGING_DIR/Applications/$APP_BUNDLE"
fi

# 4. Build Package
echo "Building .pkg..."

# Identifier
IDENTIFIER="com.babylonfish.app"

pkgbuild --root "$STAGING_DIR" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --install-location "/" \
         "$OUTPUT_DIR/$PKG_NAME"

echo "✅ Package created at: $OUTPUT_DIR/$PKG_NAME"
echo ""
echo "📝 NOTE ON SIGNING:"
echo "This package is not notarized. To distribute it to others without warnings:"
echo "1. You need an Apple Developer Account ($99/year)."
echo "2. Set SIGNING_IDENTITY in this script."
echo "3. Use 'productsign' to sign the installer."
echo "4. Submit for notarization using 'xcrun notarytool'."
echo ""
echo "For local use, you can right-click the pkg and choose Open to bypass Gatekeeper."
