#!/bin/bash

echo "=== BabylonFish 3.0 Permissions Fix ==="
echo ""

# Get current user
CURRENT_USER=$(whoami)
echo "Current user: $CURRENT_USER"

# App identifiers
APP_ID="com.babylonfish.app.v3"
APP_NAME="BabylonFish3"

echo ""
echo "1. Opening System Settings..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

echo ""
echo "2. Resetting TCC permissions..."

# Reset Accessibility
echo "   - Resetting Accessibility for $APP_ID..."
tccutil reset Accessibility "$APP_ID" 2>/dev/null || echo "   Warning: Could not reset Accessibility"

# Input Monitoring is trickier - need to use sqlite
echo "   - Checking Input Monitoring permissions..."
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
USER_TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

if [ -f "$USER_TCC_DB" ]; then
    echo "   Found user TCC database: $USER_TCC_DB"
    
    # Check if app exists in database
    EXISTS=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE client='$APP_ID' AND service='kTCCServiceListenEvent';" 2>/dev/null || echo "0")
    
    if [ "$EXISTS" -gt 0 ]; then
        echo "   - Removing Input Monitoring entry for $APP_ID..."
        sqlite3 "$USER_TCC_DB" "DELETE FROM access WHERE client='$APP_ID' AND service='kTCCServiceListenEvent';" 2>/dev/null || true
        echo "   - Input Monitoring entry removed"
    else
        echo "   - No Input Monitoring entry found for $APP_ID"
    fi
else
    echo "   User TCC database not found at: $USER_TCC_DB"
fi

echo ""
echo "3. Killing TCC daemon to reload permissions..."
sudo pkill -f tccd 2>/dev/null || true
sleep 2

echo ""
echo "4. Checking current permissions status..."
echo "   - Checking Accessibility:"
AX_STATUS=$(sqlite3 "$USER_TCC_DB" "SELECT auth_value FROM access WHERE client='$APP_ID' AND service='kTCCServiceAccessibility';" 2>/dev/null || echo "not found")
echo "     Accessibility status: $AX_STATUS (2 = allowed, 0 = denied, not found = not set)"

echo "   - Checking Input Monitoring:"
IM_STATUS=$(sqlite3 "$USER_TCC_DB" "SELECT auth_value FROM access WHERE client='$APP_ID' AND service='kTCCServiceListenEvent';" 2>/dev/null || echo "not found")
echo "     Input Monitoring status: $IM_STATUS (2 = allowed, 0 = denied, not found = not set)"

echo ""
echo "5. Checking if app is running..."
if pgrep -f "BabylonFish3" > /dev/null; then
    echo "   BabylonFish3 is running. Killing..."
    pkill -f "BabylonFish3"
    sleep 1
fi

echo ""
echo "6. Clearing Launch Services cache..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true

echo ""
echo "7. Clearing app-specific caches..."
rm -rf "$HOME/Library/Containers/$APP_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/$APP_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Preferences/$APP_ID.plist" 2>/dev/null || true

echo ""
echo "=== Instructions ==="
echo "1. System Settings windows should be open"
echo "2. Make sure BabylonFish3 is NOT in the lists"
echo "3. Close System Settings completely"
echo "4. Run BabylonFish3 again:"
echo "   open dist/BabylonFish3_final.app"
echo "5. When prompted, add BabylonFish3 to BOTH lists"
echo "6. Check if permissions work now"
echo ""
echo "If still not working, try:"
echo "1. Reboot your Mac"
echo "2. Or use this nuclear option (requires admin password):"
echo "   sudo tccutil reset All"
echo "   (WARNING: This resets ALL app permissions on your system!)"