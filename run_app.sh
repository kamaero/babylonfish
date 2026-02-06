#!/bin/bash

APP_NAME="BabylonFish"
INSTALL_DIR="$HOME/Программы"
ALT_INSTALL_DIR="$HOME/Applications"

pkill -9 "$APP_NAME" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.babylonfish.app" "$HOME/Library/Saved Application State/com.babylonfish.app.savedState"
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
  open -n "$INSTALL_DIR/$APP_NAME.app"
else
  open -n "$ALT_INSTALL_DIR/$APP_NAME.app"
fi
