#!/bin/bash

# ============================================================================
# BabylonFish 3.0 Safe Permissions Fix Script
# Защищенная версия с таймаутами и защитой от зависаний
# ============================================================================

set -euo pipefail

# Настройки безопасности
TIMEOUT_SECONDS=30
MAX_RETRIES=3
CURRENT_USER=$(whoami)
APP_ID="com.babylonfish.app.v3.ml"
APP_NAME="BabylonFish3"

# Функция для безопасного выполнения команды с таймаутом
safe_execute() {
    local cmd="$1"
    local timeout="${2:-10}"
    local retry_count=0
    
    echo "  [SAFE] Выполняем: $cmd"
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if timeout $timeout bash -c "$cmd" 2>/dev/null; then
            echo "  [SAFE] ✅ Успешно выполнено"
            return 0
        else
            retry_count=$((retry_count + 1))
            echo "  [SAFE] ⚠️ Попытка $retry_count/$MAX_RETRIES не удалась, повторяем..."
            sleep 1
        fi
    done
    
    echo "  [SAFE] ❌ Не удалось выполнить после $MAX_RETRIES попыток"
    return 1
}

# Функция для безопасного открытия системных настроек
safe_open_settings() {
    local url="$1"
    local label="$2"
    
    echo "  [SAFE] Открываем $label..."
    
    # Используем background процесс с таймаутом
    (timeout 5 open "$url" 2>/dev/null || true) &
    sleep 1
}

# Функция для безопасного сброса TCC
safe_tcc_reset() {
    local service="$1"
    
    echo "  [SAFE] Сбрасываем $service для $APP_ID..."
    
    # Пробуем сбросить через tccutil
    if command -v tccutil >/dev/null 2>&1; then
        if timeout 10 tccutil reset "$service" "$APP_ID" 2>/dev/null; then
            echo "  [SAFE] ✅ $service сброшен"
        else
            echo "  [SAFE] ⚠️ Не удалось сбросить $service через tccutil"
        fi
    else
        echo "  [SAFE] ⚠️ tccutil не найден"
    fi
}

# Функция для безопасной проверки и остановки приложения
safe_app_termination() {
    echo "  [SAFE] Проверяем запущенные процессы BabylonFish3..."
    
    # Ищем все процессы BabylonFish3
    local pids=$(pgrep -f "BabylonFish3" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        echo "  [SAFE] Найдены процессы: $pids"
        
        # Сначала пробуем мягкое завершение
        for pid in $pids; do
            echo "  [SAFE] Отправляем SIGTERM процессу $pid..."
            kill -TERM "$pid" 2>/dev/null || true
        done
        
        sleep 2
        
        # Проверяем, остались ли процессы
        pids=$(pgrep -f "BabylonFish3" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            echo "  [SAFE] Процессы все еще запущены, отправляем SIGKILL..."
            for pid in $pids; do
                kill -KILL "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
        
        echo "  [SAFE] ✅ Все процессы BabylonFish3 остановлены"
    else
        echo "  [SAFE] ✅ Процессы BabylonFish3 не найдены"
    fi
}

# ============================================================================
# ОСНОВНОЙ СКРИПТ
# ============================================================================

echo "=== BabylonFish 3.0 Safe Permissions Fix ==="
echo "Запущено пользователем: $CURRENT_USER"
echo "Таймаут операций: ${TIMEOUT_SECONDS} секунд"
echo ""

# 1. Открываем системные настройки (с защитой от зависаний)
echo "1. Открываем системные настройки (безопасно)..."
safe_open_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" "Настройки доступности"
sleep 2
safe_open_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" "Настройки мониторинга ввода"
sleep 2

# 2. Сбрасываем TCC permissions (с защитой от зависаний)
echo ""
echo "2. Сбрасываем TCC permissions (безопасно)..."
safe_tcc_reset "Accessibility"
safe_tcc_reset "All"

# 3. Безопасная остановка приложения
echo ""
echo "3. Безопасная остановка BabylonFish3..."
safe_app_termination

# 4. Очистка кэшей (с защитой от ошибок)
echo ""
echo "4. Очистка кэшей (безопасно)..."

# Launch Services cache
echo "  [SAFE] Очищаем кэш Launch Services..."
safe_execute "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true" 15

# App-specific caches
echo "  [SAFE] Очищаем кэши приложения..."
for cache_dir in "$HOME/Library/Containers/$APP_ID" "$HOME/Library/Caches/$APP_ID"; do
    if [ -d "$cache_dir" ]; then
        echo "  [SAFE] Удаляем: $cache_dir"
        rm -rf "$cache_dir" 2>/dev/null || true
    fi
done

# Preferences
local prefs_file="$HOME/Library/Preferences/$APP_ID.plist"
if [ -f "$prefs_file" ]; then
    echo "  [SAFE] Удаляем файл настроек: $prefs_file"
    rm -f "$prefs_file" 2>/dev/null || true
fi

# 5. Проверка состояния (информационно)
echo ""
echo "5. Проверка текущего состояния..."

# Проверяем доступность tccutil
if command -v tccutil >/dev/null 2>&1; then
    echo "  [INFO] tccutil доступен"
    
    # Проверяем статус Accessibility
    echo "  [INFO] Проверяем статус Accessibility..."
    if timeout 5 tccutil status Accessibility "$APP_ID" 2>/dev/null; then
        echo "  [INFO] ✅ Accessibility статус получен"
    else
        echo "  [INFO] ⚠️ Не удалось получить статус Accessibility"
    fi
else
    echo "  [INFO] ⚠️ tccutil недоступен"
fi

# 6. Инструкции для пользователя
echo ""
echo "=== ИНСТРУКЦИИ ДЛЯ ПОЛЬЗОВАТЕЛЯ ==="
echo ""
echo "1. ✅ Системные настройки должны быть открыты в двух вкладках:"
echo "   - Доступность (Accessibility)"
echo "   - Мониторинг ввода (Input Monitoring)"
echo ""
echo "2. 🔍 Убедитесь, что BabylonFish3 НЕ находится в этих списках"
echo ""
echo "3. ❌ Закройте полностью окно Системных настроек"
echo ""
echo "4. 🚀 Запустите BabylonFish3 снова:"
echo "   open dist/BabylonFish3_final_v*.app"
echo ""
echo "5. ✅ При появлении запросов, добавьте BabylonFish3 в ОБА списка:"
echo "   - Доступность (Accessibility)"
echo "   - Мониторинг ввода (Input Monitoring)"
echo ""
echo "6. 🔄 Перезагрузите компьютер если проблемы остаются"
echo ""
echo "=== СКРИПТ ЗАВЕРШЕН БЕЗОПАСНО ==="
echo "Время выполнения: $(date)"
echo ""

# Завершаем скрипт с кодом успеха
exit 0