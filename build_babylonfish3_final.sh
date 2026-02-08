#!/bin/bash

# Build script for BabylonFish 3.0 with first launch alert
set -e

echo "Building BabylonFish 3.0 with first launch alert..."

# Increment version (patch) and set build number
VERSION_FILE="Sources/BabylonFish3/Version.swift"
if [ -f "$VERSION_FILE" ]; then
  CURRENT_VERSION=$(grep -o '"[^"]*"' "$VERSION_FILE" | tr -d '"')
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  [ -z "$PATCH" ] && PATCH=0
  NEW_PATCH=$((PATCH + 1))
  APP_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
  sed -i '' "s/static let current = \\\"$CURRENT_VERSION\\\"/static let current = \\\"$APP_VERSION\\\"/" "$VERSION_FILE"
else
  APP_VERSION="3.0.0"
fi
BUILD_NUMBER=$(date +%Y%m%d%H%M)
OUT_APP="dist/BabylonFish3_final_v${APP_VERSION}.app"

# Clean previous build
rm -rf .build
rm -rf "$OUT_APP"

# Build for both architectures
echo "Building for arm64..."
swift build -c release --product BabylonFish3 --arch arm64 --disable-sandbox

echo "Building for x86_64..."
arch -x86_64 swift build -c release --product BabylonFish3 --arch x86_64 --disable-sandbox

# Create universal binary
echo "Creating universal binary..."
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"

# Copy fix_permissions.sh to Resources
if [ -f "fix_permissions.sh" ]; then
    cp fix_permissions.sh "$OUT_APP/Contents/Resources/"
    chmod +x "$OUT_APP/Contents/Resources/fix_permissions.sh"
    echo "Copied fix_permissions.sh to Resources"
fi

lipo -create -output "$OUT_APP/Contents/MacOS/BabylonFish3" \
    ".build/arm64-apple-macosx/release/BabylonFish3" \
    ".build/x86_64-apple-macosx/release/BabylonFish3"

# Make executable
chmod +x "$OUT_APP/Contents/MacOS/BabylonFish3"
xattr -dr com.apple.quarantine "$OUT_APP" 2>/dev/null || true
if [ -x "/usr/bin/codesign" ]; then
  /usr/bin/codesign --force --deep --sign - "$OUT_APP" >/dev/null 2>&1 || true
fi

# Create Info.plist
cat > "$OUT_APP/Contents/Info.plist" << EOF
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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
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

echo "Build complete! App bundle created at: $OUT_APP"
echo "Size: $(du -sh "$OUT_APP" | cut -f1)"
echo "Version: $APP_VERSION ($BUILD_NUMBER)"

# Optional: reset TCC permissions during testing
if [ "${DEV_RESET_TCC:-0}" = "1" ] && [ -x "./fix_permissions.sh" ]; then
  echo "DEV_RESET_TCC=1 detected, resetting permissions..."
  ./fix_permissions.sh
fi

# Create test instructions
cat > test_babylonfish3_final.md << 'EOF'
# BabylonFish 3.0 - Тестирование

## Особенности этой версии:
1. **Алерт при первом запуске** - при первом запуске показывается алерт с объяснением нужных разрешений
2. **Кнопка "Открыть настройки"** - сразу открывает настройки безопасности macOS
3. **Уведомления** - показывает уведомления о статусе приложения
4. **Меню бар** - иконка в меню баре с состоянием приложения

## Как тестировать:

### 1. Запуск приложения:
```bash
open dist/BabylonFish3_final_vX.Y.Z.app
```

### 2. Что произойдет:
- **Первый запуск**: Появится алерт с приветствием и объяснением нужных разрешений
- **Нажмите "Открыть настройки"**: Откроются настройки безопасности macOS
- **Включите разрешения**:
  - Универсальный доступ (Accessibility)
  - Мониторинг ввода (Input Monitoring)

### 3. Проверка работы:
- Откройте TextEdit или любой текстовый редактор
- Напечатайте "ghbdtn" в английской раскладке → должно переключиться на русскую "привет"
- Напечатайте "привет" в русской раскладке → должно переключиться на английскую "ghbdtn"
- Проверьте исправление опечаток: "havv" → "have"

### 4. Проверка логов:
```bash
tail -f ~/babylonfish_debug.log
```

### 5. Установка в Applications:
```bash
cp -r dist/BabylonFish3_final_vX.Y.Z.app ~/Applications/
```

## Что проверять в алерте:
✅ Сообщение понятное и дружелюбное  
✅ Кнопка "Открыть настройки" работает  
✅ Открываются правильные разделы настроек  
✅ После выдачи разрешений приложение запускается  
✅ Показывается уведомление об успешном запуске  
✅ Иконка в меню баре отображает статус приложения
EOF

echo ""
echo "✅ BabylonFish 3.0 с алертом при первом запуске успешно собран!"
echo ""
echo "📋 Инструкции по тестированию сохранены в: test_babylonfish3_final.md"
echo ""
echo "🚀 Чтобы протестировать:"
echo "   open $OUT_APP"
echo ""
echo "📝 Проверьте, что при первом запуске появляется алерт с предложением"
echo "   открыть настройки для выдачи разрешений."
