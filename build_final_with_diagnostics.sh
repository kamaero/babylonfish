#!/bin/bash

# Build script for BabylonFish 3.0 with enhanced permission diagnostics
set -e

echo "=== Building BabylonFish 3.0 with Permission Diagnostics ==="
echo ""

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
OUT_APP="dist/BabylonFish3_diagnostics_v${APP_VERSION}.app"
# Clean previous build
echo "1. Cleaning previous builds..."
rm -rf .build
rm -rf "$OUT_APP"

# Build for both architectures
echo ""
echo "2. Building universal binary..."
echo "   - Building for arm64..."
swift build -c release --product BabylonFish3 --arch arm64 --disable-sandbox

echo "   - Building for x86_64..."
arch -x86_64 swift build -c release --product BabylonFish3 --arch x86_64 --disable-sandbox

# Create universal binary
echo ""
echo "3. Creating app bundle..."
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"

lipo -create -output "$OUT_APP/Contents/MacOS/BabylonFish3" \
    ".build/arm64-apple-macosx/release/BabylonFish3" \
    ".build/x86_64-apple-macosx/release/BabylonFish3"

# Make executable
chmod +x "$OUT_APP/Contents/MacOS/BabylonFish3"
xattr -dr com.apple.quarantine "$OUT_APP" 2>/dev/null || true
if [ -x "/usr/bin/codesign" ]; then
  /usr/bin/codesign --force --deep --sign - "$OUT_APP" >/dev/null 2>&1 || true
fi

# Create Info.plist with correct bundle ID
echo ""
echo "4. Creating Info.plist..."
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

# Copy fix_permissions script to app bundle
echo ""
echo "5. Copying diagnostic tools..."
cp fix_permissions.sh "$OUT_APP/Contents/Resources/" 2>/dev/null || true

echo ""
echo "✅ Build complete!"
echo "   App: $OUT_APP"
echo "   Size: $(du -sh "$OUT_APP" | cut -f1)"
echo "   Version: $APP_VERSION ($BUILD_NUMBER)"
echo ""
# Optional: reset TCC permissions during testing
if [ "${DEV_RESET_TCC:-0}" = "1" ] && [ -x "./fix_permissions.sh" ]; then
  echo "DEV_RESET_TCC=1 detected, resetting permissions..."
  ./fix_permissions.sh
fi



# Create comprehensive test instructions
cat > TESTING_PERMISSIONS.md << 'EOF'
# BabylonFish 3.0 - Тестирование разрешений

## Проблема:
Разрешения (Accessibility и Input Monitoring) выдаются, но не принимаются системой.

## Решения:

### 1. Быстрая диагностика
```bash
# Запустите приложение и посмотрите логи
   open "$OUT_APP"
tail -f ~/babylonfish_debug.log
```

### 2. Использование скрипта для сброса разрешений
```bash
# Дайте скрипту права на выполнение
chmod +x fix_permissions.sh

# Запустите скрипт
./fix_permissions.sh
```

### 3. Ручной сброс разрешений

#### Шаг 1: Удалить приложение из списков
1. Откройте **Системные настройки** → **Конфиденциальность и безопасность**
2. Перейдите в **Универсальный доступ**
3. Найдите BabylonFish3 и удалите его (кнопка `-`)
4. Перейдите в **Мониторинг ввода**
5. Найдите BabylonFish3 и удалите его (кнопка `-`)

#### Шаг 2: Перезапустить TCC daemon
```bash
# В Терминале
sudo pkill -f tccd
```

#### Шаг 3: Перезапустить приложение
```bash
# Убить текущий процесс
pkill -f BabylonFish3

# Запустить заново
open dist/BabylonFish3_diagnostics.app
```

### 4. Ядерный вариант (если ничего не помогает)

#### Вариант A: Сбросить ВСЕ разрешения (осторожно!)
```bash
sudo tccutil reset All
```
**Внимание:** Это сбросит ВСЕ разрешения ВСЕХ приложений на вашем Mac!

#### Вариант B: Перезагрузка
1. Перезагрузите Mac
2. Запустите BabylonFish3 снова

### 5. Проверка статуса разрешений

#### Проверить через Терминал:
```bash
# Проверить Accessibility
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT * FROM access WHERE client LIKE '%babylonfish%';"

# Проверить Input Monitoring
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT client, auth_value, last_modified FROM access WHERE service='kTCCServiceListenEvent';"
```

#### Значения auth_value:
- `0` = denied (отказано)
- `2` = allowed (разрешено)
- `3` = limited (ограниченно)
- `NULL` = not set (не установлено)

### 6. Особенности BabylonFish 3.0

Приложение теперь включает:

1. **Расширенную диагностику** - подробные логи в `~/babylonfish_debug.log`
2. **Алерт при проблемах** - если разрешения не работают, покажет алерт с решениями
3. **Кнопку "Запустить скрипт"** - прямо из алерта можно запустить скрипт сброса
4. **Автоматическую проверку** - приложение само проверяет статус разрешений

### 7. Если всё ещё не работает

1. **Проверьте Bundle ID**:
   ```bash
   # Убедитесь, что bundle ID правильный
   defaults read "$OUT_APP/Contents/Info.plist" CFBundleIdentifier
   # Должно быть: com.babylonfish.app.v3
   ```

2. **Проверьте подпись кода**:
   ```bash
   codesign -dv --verbose=4 "$OUT_APP"
   ```

3. **Создайте новый bundle ID**:
   - Измените `CFBundleIdentifier` в Info.plist
   - Например: `com.babylonfish.app.v3.$(date +%s)`
   - Пересоберите приложение

### 8. Тестирование работы

После успешной выдачи разрешений:

1. Откройте TextEdit
2. Напечатайте `ghbdtn` → должно стать `привет`
3. Напечатайте `привет` → должно стать `ghbdtn`
4. Проверьте исправление опечаток: `havv` → `have`

Логи должны показывать:
```
BabylonFish 3.0 started successfully!
Event tap created successfully
Processing events...
```

Если видите `Event tap creation failed` - проблема с разрешениями.
EOF

echo "📋 Подробные инструкции сохранены в: TESTING_PERMISSIONS.md"
echo ""
echo "🚀 Запустите приложение для тестирования:"
echo "   open $OUT_APP"
echo ""
echo "🔧 Если будут проблемы с разрешениями:"
echo "   1. Приложение покажет алерт с решениями"
echo "   2. Используйте ./fix_permissions.sh"
echo "   3. Следуйте инструкциям в TESTING_PERMISSIONS.md"
