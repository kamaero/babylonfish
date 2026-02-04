#!/bin/bash

APP_NAME="BabylonFish"
APP_ID="com.babylonfish.app"
USER_APPS="$HOME/Applications"
USER_APPS_RU="$HOME/Программы"

pkill -9 "$APP_NAME" 2>/dev/null || true
rm -rf "$USER_APPS/$APP_NAME.app"
rm -rf "$USER_APPS_RU/$APP_NAME.app"
rm -rf "$HOME/Library/Caches/$APP_ID" "$HOME/Library/Saved Application State/$APP_ID.savedState"
rm -rf "$HOME/Library/Preferences/$APP_ID.plist"
rm -rf "$HOME/Library/Preferences/$APP_ID."*.plist
rm -rf "$HOME/babylonfish_debug.log"
tccutil reset Accessibility "$APP_ID" 2>/dev/null || true
tccutil reset ListenEvent "$APP_ID" 2>/dev/null || true
