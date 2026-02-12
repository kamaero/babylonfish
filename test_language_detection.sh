#!/bin/bash

echo "=== BabylonFish ML - Language Detection Test ==="
echo ""

# Test cases for "wrong layout" detection
declare -A test_cases=(
    ["ghbdtn"]="привет"      # hello (Russian on English layout)
    ["rfr"]="как"           # how
    ["plhf"]="йцук"         # qwert (Russian layout test)
    ["ntrcn"]="текст"       # text
    ["gjxtve"]="почему"     # why
    ["cgfc"]="спас"         # save
    ["ytn"]="нет"           # no
    ["ds"]="вы"             # you (plural)
    ["z"]="я"               # I
    ["ns"]="ты"             # you (singular)
)

echo "Test cases for 'wrong layout' detection:"
echo "----------------------------------------"

for wrong_layout in "${!test_cases[@]}"; do
    expected="${test_cases[$wrong_layout]}"
    echo "Test: '$wrong_layout' → Expected: '$expected'"
done

echo ""
echo "=== Running BabylonFish ML ==="
echo ""

# Check if app is installed
APP_PATH="$HOME/Applications/BabylonFish ML.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: BabylonFish ML.app not found in ~/Applications/"
    echo "Please run: ./install_app.sh"
    exit 1
fi

# Check permissions
echo "Checking permissions..."
echo "1. Open System Settings → Privacy & Security"
echo "2. Check both sections:"
echo "   - Accessibility"
echo "   - Input Monitoring"
echo "3. Ensure 'BabylonFish ML' is enabled in BOTH sections"
echo ""
echo "If not enabled:"
echo "1. Remove BabylonFish from both lists (if present)"
echo "2. Run: ./reset_permissions_debug.sh"
echo "3. Reinstall: ./install_app.sh"
echo "4. Launch app and grant permissions"
echo ""

# Monitor debug log
echo "=== Monitoring Debug Log ==="
echo "Log file: ~/babylonfish_debug.log"
echo ""
echo "To test manually:"
echo "1. Open TextEdit or any text editor"
echo "2. Type 'ghbdtn' (should switch to 'привет')"
echo "3. Type 'rfr' (should switch to 'как')"
echo "4. Check debug log for detection results"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""

tail -f ~/babylonfish_debug.log 2>/dev/null || echo "Debug log not found. Start the app first."