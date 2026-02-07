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
