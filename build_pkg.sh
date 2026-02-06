#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASES_DIR="$ROOT_DIR/releases"
INSTALL_LOC="/Applications"
IDENTIFIER="com.babylonfish.app"

# 1. Build the App (this increments version and creates .app)
echo "Building App..."
"$ROOT_DIR/install_app.sh"

# 2. Find the generated app
# We look for the latest app in dist/ (sorted by modification time)
APP_NAME=$(ls -t "$DIST_DIR" | grep "BabylonFish_v" | head -n 1)
APP_PATH="$DIST_DIR/$APP_NAME"

if [ -z "$APP_NAME" ]; then
    echo "Error: Could not find built app in $DIST_DIR"
    exit 1
fi

echo "Found app: $APP_NAME"

# Extract Version from App Name (e.g. BabylonFish_v1.0.48.app -> 1.0.48)
VERSION=$(echo "$APP_NAME" | sed -E 's/BabylonFish_v([0-9]+\.[0-9]+\.[0-9]+)\.app/\1/')

PKG_NAME="BabylonFish-${VERSION}.pkg"
OUT_PKG="$RELEASES_DIR/$PKG_NAME"

echo "Creating pkg '$PKG_NAME'..."

# 3. Create PKG
pkgbuild --install-location "$INSTALL_LOC" \
         --component "$APP_PATH" \
         --identifier "$IDENTIFIER" \
         "$OUT_PKG"

echo "✅ Package created successfully:"
echo "$OUT_PKG"
