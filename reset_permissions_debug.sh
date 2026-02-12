#!/bin/bash

echo "=== BabylonFish ML - Debug Permission Reset ==="
echo "Bundle ID: com.babylonfish.app.ml"
echo ""

# Kill any running instances
echo "1. Killing running BabylonFish processes..."
pkill -9 "BabylonFish3" 2>/dev/null || true
pkill -9 "BabylonFish ML" 2>/dev/null || true
sleep 1

# Reset TCC permissions
echo "2. Resetting TCC permissions..."
echo "   - Resetting Accessibility..."
tccutil reset Accessibility com.babylonfish.app.ml 2>/dev/null || echo "   Warning: Failed to reset Accessibility"
echo "   - Resetting Input Monitoring..."
tccutil reset InputMonitoring com.babylonfish.app.ml 2>/dev/null || echo "   Warning: Failed to reset Input Monitoring"
echo "   - Resetting All permissions..."
tccutil reset All com.babylonfish.app.ml 2>/dev/null || echo "   Warning: Failed to reset All permissions"

# Also reset old bundle IDs
echo "3. Resetting old bundle IDs..."
tccutil reset Accessibility com.babylonfish.app 2>/dev/null || true
tccutil reset InputMonitoring com.babylonfish.app 2>/dev/null || true
tccutil reset All com.babylonfish.app 2>/dev/null || true

tccutil reset Accessibility com.babylonfish.app.v3 2>/dev/null || true
tccutil reset InputMonitoring com.babylonfish.app.v3 2>/dev/null || true
tccutil reset All com.babylonfish.app.v3 2>/dev/null || true

tccutil reset Accessibility com.babylonfish.app.v3.ml 2>/dev/null || true
tccutil reset InputMonitoring com.babylonfish.app.v3.ml 2>/dev/null || true
tccutil reset All com.babylonfish.app.v3.ml 2>/dev/null || true

# Clear caches
echo "4. Clearing caches..."
rm -rf "$HOME/Library/Caches/com.babylonfish.app" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.babylonfish.app.ml" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/com.babylonfish.app.savedState" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/com.babylonfish.app.ml.savedState" 2>/dev/null || true

# Clear preferences
echo "5. Clearing preferences..."
defaults delete com.babylonfish.app 2>/dev/null || true
defaults delete com.babylonfish.app.ml 2>/dev/null || true

# Clear debug log
echo "6. Clearing debug log..."
> "$HOME/babylonfish_debug.log" 2>/dev/null || true

# Force TCC database reload
echo "7. Forcing TCC database reload..."
sudo killall -HUP tccd 2>/dev/null || echo "   Note: Need sudo for tccd reload"
sudo killall -HUP usernoted 2>/dev/null || echo "   Note: Need sudo for usernoted reload"

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "1. Rebuild and install BabylonFish ML: ./install_app.sh"
echo "2. Launch the app from ~/Applications/BabylonFish ML.app"
echo "3. Grant BOTH permissions when prompted:"
echo "   - Accessibility (Универсальный доступ)"
echo "   - Input Monitoring (Мониторинг ввода)"
echo ""
echo "To monitor debug logs: tail -f ~/babylonfish_debug.log"
echo ""