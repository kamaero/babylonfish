#!/bin/bash

# Скрипт для запуска BabylonFish 3.0

echo "=== Запуск BabylonFish 3.0 ==="
echo "Очищаем логи..."
> ~/babylonfish_debug.log

echo "Собираем проект..."
cd "$(dirname "$0")"
swift build --product BabylonFish3

if [ $? -eq 0 ]; then
    echo "Запускаем BabylonFish 3.0..."
    echo "Логи будут записываться в ~/babylonfish_debug.log"
    echo "Для просмотра логов в реальном времени: tail -f ~/babylonfish_debug.log"
    echo ""
    .build/debug/BabylonFish3
else
    echo "Ошибка сборки!"
    exit 1
fi