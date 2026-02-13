#!/bin/bash

# Enhanced Typo Correction Installation Script
# BabylonFish v3.0.60+ with CoreML+NSSpellChecker integration

# Configuration
APP_NAME="BabylonFish Enhanced"
EXECUTABLE_NAME="BabylonFish"
BUNDLE_ID="com.babylonfish.app.enhanced"
VERSION="3.0.60"

# Always install to ~/Applications for easier permissions
INSTALL_DIR="$HOME/Applications"
echo "Installing BabylonFish Enhanced (v$VERSION) to: $INSTALL_DIR"

# Create installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Stop any running instances
echo "Stopping any running BabylonFish instances..."
pkill -9 "BabylonFish" 2>/dev/null || true
sleep 1

# Reset TCC permissions
echo "Resetting TCC permissions for $APP_NAME..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset InputMonitoring "$BUNDLE_ID" 2>/dev/null || true
sleep 1

# Create app bundle structure
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy executable
echo "Copying universal binary..."
cp "BabylonFish" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# Create Info.plist
echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 BabylonFish. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    
    <!-- Permissions -->
    <key>NSAppleEventsUsageDescription</key>
    <string>BabylonFish needs accessibility permissions to monitor keyboard input and correct typos.</string>
    
    <!-- Background execution -->
    <key>LSBackgroundOnly</key>
    <string>1</string>
    
    <!-- Hide from Dock -->
    <key>LSUIElement</key>
    <true/>
    
    <!-- Supported architectures -->
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
    
    <!-- CoreML requirements -->
    <key>LSRequiresNativeExecution</key>
    <true/>
</dict>
</plist>
EOF

# Create Entitlements.plist (EMPTY - critical for permissions)
echo "Creating empty Entitlements.plist..."
cat > "$CONTENTS_DIR/Entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- EMPTY - This is critical for permissions to work correctly -->
    <!-- Do NOT add get-task-allow or any other entitlements -->
</dict>
</plist>
EOF

# Copy icon if exists
if [ -f "icon.png" ]; then
    echo "Generating app icon..."
    # Convert icon to icns format
    mkdir -p "$RESOURCES_DIR/icon.iconset"
    
    # Create various icon sizes
    sips -z 16 16 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 icon.png --out "$RESOURCES_DIR/icon.iconset/icon_512x512@2x.png" >/dev/null 2>&1
    
    # Create icns file
    iconutil -c icns "$RESOURCES_DIR/icon.iconset" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || true
    rm -rf "$RESOURCES_DIR/icon.iconset"
    
    # Update Info.plist with icon reference
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
fi

# Copy tray icon if exists
if [ -f "tray_icon.png" ]; then
    cp "tray_icon.png" "$RESOURCES_DIR/tray_icon.png"
fi

# Copy ML model if exists
if [ -d "Sources/BabylonFish3/ML/Models" ]; then
    echo "Copying CoreML models..."
    mkdir -p "$RESOURCES_DIR/ML/Models"
    cp -r "Sources/BabylonFish3/ML/Models/"* "$RESOURCES_DIR/ML/Models/" 2>/dev/null || true
fi

# Register with LaunchServices
echo "Registering app with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

# Set permissions
echo "Setting permissions..."
chmod -R 755 "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Create desktop shortcut
echo "Creating desktop shortcut..."
ln -sf "$APP_BUNDLE" "$HOME/Desktop/$APP_NAME.app" 2>/dev/null || true

echo ""
echo "================================================"
echo "  BabylonFish Enhanced v$VERSION installed!"
echo "================================================"
echo ""
echo "App location: $APP_BUNDLE"
echo "Bundle ID: $BUNDLE_ID"
echo ""
echo "IMPORTANT NEXT STEPS:"
echo "1. Open System Settings → Privacy & Security"
echo "2. Go to 'Accessibility'"
echo "3. Click the '+' button and add '$APP_NAME.app'"
echo "4. Go to 'Input Monitoring'"
echo "5. Click the '+' button and add '$APP_NAME.app'"
echo "6. Launch the app from $INSTALL_DIR"
echo ""
echo "Features included:"
echo "✓ CoreML + NSSpellChecker integration"
echo "✓ Enhanced typo correction"
echo "✓ Short word detection"
echo "✓ Cross-layout conversion"
echo "✓ Universal binary (arm64 + x86_64)"
echo ""
echo "To start testing:"
echo "1. Launch '$APP_NAME.app'"
echo "2. Open any text editor"
echo "3. Test typo correction: 'teh' → 'the'"
echo "4. Test short words: 'фку' → 'are'"
echo "5. Check logs: tail -f ~/babylonfish_debug.log"
echo "================================================"

# Make script executable
chmod +x "$0"