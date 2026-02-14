#!/bin/bash

# Скрипт для компиляции CoreML модели

echo "Компиляция CoreML модели..."

# Пути к файлам
MLMODEL_PATH="ML/Models/BabylonFishClassifier.mlmodel"
MLMODELC_PATH="ML/Models/BabylonFishClassifier.mlmodelc"

# Проверяем, существует ли исходная модель
if [ ! -f "$MLMODEL_PATH" ]; then
    echo "Ошибка: Файл $MLMODEL_PATH не найден"
    exit 1
fi

# Удаляем старую скомпилированную модель (если есть)
if [ -d "$MLMODELC_PATH" ]; then
    echo "Удаление старой скомпилированной модели..."
    rm -rf "$MLMODELC_PATH"
fi

# Компилируем модель
echo "Компиляция $MLMODEL_PATH..."
xcrun coremlc compile "$MLMODEL_PATH" "ML/Models/"

if [ $? -eq 0 ]; then
    echo "✅ Модель успешно скомпилирована в $MLMODELC_PATH"
    
    # Проверяем размер
    if [ -d "$MLMODELC_PATH" ]; then
        SIZE=$(du -sh "$MLMODELC_PATH" | cut -f1)
        echo "Размер скомпилированной модели: $SIZE"
    else
        echo "⚠️  Скомпилированная модель не найдена по ожидаемому пути"
    fi
else
    echo "❌ Ошибка компиляции модели"
    exit 1
fi

echo ""
echo "Для использования модели в приложении:"
echo "1. Скопируйте $MLMODELC_PATH в Resources проекта"
echo "2. Убедитесь, что модель добавлена в Package.swift"
echo "3. Пересоберите проект"