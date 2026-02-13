#!/bin/bash

# Скрипт установки BabylonFish v3.0.61 с улучшенным контекстным анализом
# Версия с анализом границ предложений и исправленной логикой приоритетов

set -e

echo "=== Установка BabylonFish v3.0.61 с улучшенным контекстным анализом ==="
echo ""

# Проверяем, что мы в правильной директории
if [ ! -f "Package.swift" ]; then
    echo "Ошибка: Запустите скрипт из корневой директории проекта BabylonFish"
    exit 1
fi

# Создаем директорию для приложения
APP_NAME="BabylonFish3"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Создаем структуру приложения..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Копируем универсальный бинарник
echo "Копируем универсальный бинарник..."
cp "build/universal/$APP_NAME" "$MACOS_DIR/"

# Делаем бинарник исполняемым
chmod +x "$MACOS_DIR/$APP_NAME"

# Копируем иконки
echo "Копируем иконки..."
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
elif [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/"
else
    echo "Предупреждение: Файл иконки не найден"
fi

if [ -f "Resources/tray_icon.png" ]; then
    cp "Resources/tray_icon.png" "$RESOURCES_DIR/"
elif [ -f "tray_icon.png" ]; then
    cp "tray_icon.png" "$RESOURCES_DIR/"
fi

# Создаем Info.plist
echo "Создаем Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.babylonfish.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>3.0.61</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.61</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 BabylonFish. All rights reserved.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    
    <!-- Запрашиваем разрешения -->
    <key>NSAppleEventsUsageDescription</key>
    <string>BabylonFish needs accessibility permissions to monitor keyboard input and correct typos.</string>
    
    <!-- Требуемые разрешения для macOS -->
    <key>NSAccessibilityUsageDescription</key>
    <string>BabylonFish needs accessibility permissions to monitor keyboard input and correct typos.</string>
    
    <!-- Input Monitoring (необходимо для CGEventTap) -->
    <key>NSInputMonitoringUsageDescription</key>
    <string>BabylonFish needs input monitoring permissions to detect keyboard layout switches and correct typos in real-time.</string>
</dict>
</plist>
EOF

# Создаем простой entitlements файл (БЕЗ get-task-allow)
echo "Создаем entitlements файл..."
cat > "$CONTENTS_DIR/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Пустой файл entitlements для ad-hoc подписи -->
</dict>
</plist>
EOF

# Подписываем приложение (ad-hoc подпись)
echo "Подписываем приложение (ad-hoc)..."
codesign --force --deep --sign - --entitlements "$CONTENTS_DIR/entitlements.plist" --timestamp "$APP_DIR"

echo ""
echo "=== Установка завершена! ==="
echo ""
echo "Приложение установлено в: $APP_DIR"
echo ""
echo "Следующие шаги:"
echo "1. Откройте приложение из папки Applications"
echo "2. Предоставьте необходимые разрешения в системных настройках:"
echo "   - Системные настройки → Конфиденциальность и безопасность → Доступность"
echo "   - Системные настройки → Конфиденциальность и безопасность → Ввод с клавиатуры"
echo "3. Перезапустите приложение после предоставления разрешений"
echo ""
echo "Новые возможности v3.0.61:"
echo "✓ Улучшенный контекстный анализ с границами предложений"
echo "✓ Исправлена логика приоритетов между нейросетью и контекстом"
echo "✓ Анализ текста от точки до точки"
echo "✓ Конвертация целых предложений при обнаружении ошибок раскладки"
echo "✓ Улучшенная обработка смешанных языковых контекстов"
echo ""
echo "Для отладки проверьте логи:"
echo "tail -f ~/babylonfish_debug.log"
echo ""
echo "Для сброса разрешений (если нужно):"
echo "./fix_permissions.sh"