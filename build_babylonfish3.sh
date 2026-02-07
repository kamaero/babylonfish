#!/bin/bash

# Build script for BabylonFish 3.0
set -e

echo "Building BabylonFish 3.0..."

# Increment version (patch) and set build number
VERSION_FILE="Sources/BabylonFish3/Version.swift"
if [ -f "$VERSION_FILE" ]; then
  CURRENT_VERSION=$(grep -o '"[^"]*"' "$VERSION_FILE" | tr -d '"')
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  [ -z "$PATCH" ] && PATCH=0
  NEW_PATCH=$((PATCH + 1))
  APP_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
  # Update Version.swift
  sed -i '' "s/static let current = \\\"$CURRENT_VERSION\\\"/static let current = \\\"$APP_VERSION\\\"/" "$VERSION_FILE"
else
  APP_VERSION="3.0.0"
fi
BUILD_NUMBER=$(date +%Y%m%d%H%M)
APP_NAME_BASE="BabylonFish3"
OUT_APP="dist/${APP_NAME_BASE}_v${APP_VERSION}.app"

# Clean previous build
rm -rf .build
rm -rf "$OUT_APP"

# Build for both architectures
echo "Building for arm64..."
swift build -c release --product BabylonFish3 --arch arm64 --disable-sandbox

echo "Building for x86_64..."
arch -x86_64 swift build -c release --product BabylonFish3 --arch x86_64 --disable-sandbox

# Create universal binary
echo "Creating universal binary..."
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"

lipo -create -output "$OUT_APP/Contents/MacOS/BabylonFish3" \
    ".build/arm64-apple-macosx/release/BabylonFish3" \
    ".build/x86_64-apple-macosx/release/BabylonFish3"

# Make executable
chmod +x "$OUT_APP/Contents/MacOS/BabylonFish3"
xattr -dr com.apple.quarantine "$OUT_APP" 2>/dev/null || true
if [ -x "/usr/bin/codesign" ]; then
  /usr/bin/codesign --force --deep --sign - "$OUT_APP" >/dev/null 2>&1 || true
fi

# Create Info.plist
cat > "$OUT_APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BabylonFish3</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.babylonfish.app.v3</string>
    <key>CFBundleName</key>
    <string>BabylonFish 3.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
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
</dict>
</plist>
EOF

# Copy icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$OUT_APP/Contents/Resources/AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found in Resources/"
fi

echo "Build complete! App bundle created at: $OUT_APP"
echo "Size: $(du -sh "$OUT_APP" | cut -f1)"
echo "Version: $APP_VERSION ($BUILD_NUMBER)"

# Optional: reset TCC permissions during testing
if [ "${DEV_RESET_TCC:-0}" = "1" ] && [ -x "./fix_permissions.sh" ]; then
  echo "DEV_RESET_TCC=1 detected, resetting permissions..."
  ./fix_permissions.sh
fi

# Create test script
cat > test_babylonfish3.sh << EOF
#!/bin/bash
echo "Testing BabylonFish 3.0..."
echo "App bundle: $OUT_APP"
echo ""
echo "To test:"
echo "1. Open $OUT_APP"
echo "2. Grant Accessibility and Input Monitoring permissions"
echo "3. Test typing in TextEdit or any text editor:"
echo "   - Type 'ghbdtn' (English layout) → should switch to Russian 'привет'"
echo "   - Type 'привет' (Russian layout) → should switch to English 'ghbdtn'"
echo "   - Test typo correction: 'havv' → 'have'"
echo "   - Test auto-completion"
echo ""
echo "Check debug logs: tail -f ~/babylonfish_debug.log"
EOF

chmod +x test_babylonfish3.sh

echo ""
echo "To install to Applications:"
echo "  cp -r $OUT_APP ~/Applications/"
echo ""
echo "To test: ./test_babylonfish3.sh"
