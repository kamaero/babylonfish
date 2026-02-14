#!/bin/bash

# BabylonFish 3.0 Installer
# Устанавливает приложение в /Applications

set -e

echo "=== BabylonFish 3.0 Installer ==="
echo ""

# Получаем текущую дату и время для версии
BUILD_DATE=$(date +"%Y.%m.%d")
BUILD_TIME=$(date +"%H:%M")
BUILD_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Дата сборки: $BUILD_DATE $BUILD_TIME"
echo "Таймстамп: $BUILD_TIMESTAMP"
echo ""

# Проверяем, что сборка существует
if [ ! -f ".build/BabylonFish3" ]; then
    echo "❌ Ошибка: Сборка не найдена!"
    echo "Сначала выполните: ./build.sh"
    exit 1
fi

# Останавливаем запущенное приложение
echo "1. Останавливаем запущенное BabylonFish3..."
pkill -f "BabylonFish3" 2>/dev/null || true
sleep 1

# Удаляем предыдущую версию
echo "2. Удаляем предыдущую версию из /Applications..."
rm -rf "/Applications/BabylonFish3.app" 2>/dev/null || true
rm -rf "/Applications/BabylonFish 3.0.app" 2>/dev/null || true
rm -rf "/Applications/BabylonFish.app" 2>/dev/null || true

# Создаем структуру .app
echo "3. Создаем структуру приложения..."
APP_DIR="/Applications/BabylonFish3.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Копируем исполняемый файл
echo "4. Копируем исполняемый файл..."
cp ".build/BabylonFish3" "$MACOS_DIR/BabylonFish3"

# Делаем исполняемым
chmod +x "$MACOS_DIR/BabylonFish3"

# Создаем Info.plist
echo "5. Создаем Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BabylonFish3</string>
    <key>CFBundleIdentifier</key>
    <string>com.babylonfish.app.v3.ml</string>
    <key>CFBundleName</key>
    <string>BabylonFish 3.0</string>
    <key>CFBundleDisplayName</key>
    <string>BabylonFish 3.0</string>
    <key>CFBundleVersion</key>
    <string>3.0.$BUILD_TIMESTAMP</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.$BUILD_DATE</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 BabylonFish Team. Все права защищены.</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Копируем ресурсы
echo "6. Копируем ресурсы..."
cp -f "fix_permissions_safe.sh" "$RESOURCES_DIR/" 2>/dev/null || true

# Создаем файл с информацией о сборке
echo "7. Создаем файл с информацией о сборке..."
cat > "$RESOURCES_DIR/build_info.txt" << EOF
BabylonFish 3.0
Версия: 3.0.$BUILD_DATE
Сборка: $BUILD_TIMESTAMP
Дата: $BUILD_DATE $BUILD_TIME
Архитектура: $(uname -m)
EOF

# Устанавливаем иконку (если есть)
if [ -f "Resources/AppIcon.icns" ]; then
    echo "8. Устанавливаем иконку..."
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Чистим кэши
echo "9. Чистим кэши системы..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

# Устанавливаем права
echo "10. Устанавливаем права..."
chmod -R 755 "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true

echo ""
echo "✅ Установка завершена!"
echo "📁 Приложение установлено в: $APP_DIR"
echo "📋 Версия: 3.0.$BUILD_DATE (сборка $BUILD_TIMESTAMP)"
echo ""
echo "Для запуска выполните:"
echo "  open /Applications/BabylonFish3.app"
echo ""
echo "Или дважды кликните на приложение в Finder."
echo ""
echo "⚠️  После первого запуска необходимо:"
echo "   1. Выдать разрешение на Доступность"
echo "   2. Выдать разрешение на Мониторинг ввода"
echo "   3. Перезапустить приложение"