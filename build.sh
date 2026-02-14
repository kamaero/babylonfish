#!/bin/bash

# Скрипт сборки BabylonFish 3.0 без sandbox

echo "=== Сборка BabylonFish 3.0 ==="

# Создаем директорию для сборки
BUILD_DIR=".build"
mkdir -p "$BUILD_DIR"

# Компилируем все Swift файлы
echo "Компиляция Swift файлов..."

# Находим все Swift файлы
SWIFT_FILES=$(find Sources/BabylonFish3 -name "*.swift" | grep -v "\.build" | sort)

# Компилируем
swiftc \
    -target arm64-apple-macosx14.0 \
    -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
    -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
    -framework Carbon \
    -framework Cocoa \
    -framework CoreML \
    -framework NaturalLanguage \
    -o "$BUILD_DIR/BabylonFish3" \
    $SWIFT_FILES

# Проверяем результат
if [ $? -eq 0 ]; then
    echo "✅ Сборка успешна!"
    echo "Исполняемый файл: $BUILD_DIR/BabylonFish3"
    
    # Проверяем размер файла
    echo "Размер файла: $(du -h "$BUILD_DIR/BabylonFish3" | cut -f1)"
    
    # Проверяем архитектуру
    echo "Архитектура:"
    lipo -info "$BUILD_DIR/BabylonFish3"
else
    echo "❌ Ошибка сборки"
    exit 1
fi