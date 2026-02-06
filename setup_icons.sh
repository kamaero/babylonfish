#!/bin/bash

# setup_icons.sh
# Generates AppIcon.icns and tray icons from icon.png

if [ ! -f "icon.png" ]; then
    echo "Error: icon.png not found in current directory."
    echo "Please save your icon image as 'icon.png' in $(pwd)"
    exit 1
fi

echo "Generating icons from icon.png..."

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Generate standard sizes
sips -z 16 16     icon.png --out "${ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     icon.png --out "${ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     icon.png --out "${ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     icon.png --out "${ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   icon.png --out "${ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   icon.png --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   icon.png --out "${ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   icon.png --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   icon.png --out "${ICONSET}/icon_512x512.png" > /dev/null
sips -z 1024 1024 icon.png --out "${ICONSET}/icon_512x512@2x.png" > /dev/null

# Create icns
echo "Creating AppIcon.icns..."
iconutil -c icns "$ICONSET"

# Move to Resources
mkdir -p Sources/BabylonFish/Resources
mv AppIcon.icns Sources/BabylonFish/Resources/

# Generate Tray Icons
echo "Generating tray icons..."
# 22x22 points (standard) -> 22px and 44px
sips -z 22 22 icon.png --out Sources/BabylonFish/Resources/tray_icon.png > /dev/null
sips -z 44 44 icon.png --out "Sources/BabylonFish/Resources/tray_icon@2x.png" > /dev/null

# Clean up
rm -rf "$ICONSET"

echo "Done! Icons generated in Sources/BabylonFish/Resources/"
