#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BabylonFish.app"
IDENTIFIER="com.babylonfish.app"
INSTALL_LOC="/Applications"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME"

INFO_PLIST="$ROOT_DIR/Sources/BabylonFish/Resources/Info.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
VERSION="$("$PLISTBUDDY" -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"

if [ ! -d "$APP_PATH" ]; then
  echo "Dist app not found. Building and staging..."
  "$ROOT_DIR/install_app.sh"
fi

PKG_NAME="BabylonFish-$VERSION.pkg"
OUT_PKG="$ROOT_DIR/$PKG_NAME"

echo "Creating pkg '$PKG_NAME' from $APP_PATH ..."
pkgbuild --install-location "$INSTALL_LOC" --component "$APP_PATH" --identifier "$IDENTIFIER" "$OUT_PKG"

echo "Package created: $OUT_PKG"
echo "Note: For distribution to others, consider code signing and notarization."
