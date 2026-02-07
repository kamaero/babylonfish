#!/bin/bash

# Build script for BabylonFish 3.0
set -e

echo "Building BabylonFish 3.0..."

# Clean previous build
rm -rf .build
rm -rf dist/BabylonFish3.app

# Build for both architectures
echo "Building for arm64..."
swift build -c release --product BabylonFish3 --arch arm64 --disable-sandbox

echo "Building for x86_64..."
arch -x86_64 swift build -c release --product BabylonFish3 --arch x86_64 --disable-sandbox

# Create universal binary
echo "Creating universal binary..."
mkdir -p dist/BabylonFish3.app/Contents/MacOS
mkdir -p dist/BabylonFish3.app/Contents/Resources

lipo -create -output "dist/BabylonFish3.app/Contents/MacOS/BabylonFish3" \
    ".build/arm64-apple-macosx/release/BabylonFish3" \
    ".build/x86_64-apple-macosx/release/BabylonFish3"

# Make executable
chmod +x "dist/BabylonFish3.app/Contents/MacOS/BabylonFish3"

# Create Info.plist
cat > dist/BabylonFish3.app/Contents/Info.plist << EOF
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
    <string>3.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
    cp Resources/AppIcon.icns dist/BabylonFish3.app/Contents/Resources/AppIcon.icns
else
    echo "Warning: AppIcon.icns not found in Resources/"
fi

echo "Build complete! App bundle created at: dist/BabylonFish3.app"
echo "Size: $(du -sh dist/BabylonFish3.app | cut -f1)"

# Create test script
cat > test_babylonfish3.sh << EOF
#!/bin/bash
echo "Testing BabylonFish 3.0..."
echo "App bundle: dist/BabylonFish3.app"
echo ""
echo "To test:"
echo "1. Open dist/BabylonFish3.app"
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
echo "  cp -r dist/BabylonFish3.app ~/Applications/"
echo ""
echo "To test: ./test_babylonfish3.sh"
