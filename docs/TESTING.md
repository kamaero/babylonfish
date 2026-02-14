# Инструкция по тестированию BabylonFish

## Текущая версия с расширенным логированием

Приложение обновлено для диагностики проблемы с автоматическим переключением.

## Шаги для тестирования:

### 1. Запустите обновленное приложение

```bash
# Закройте старую версию (через меню в трее -> Quit)
# Затем запустите новую:
open ~/Applications/BabylonFish.app
```

### 2. Очистите лог-файл

```bash
> ~/babylonfish_debug.log
```

### 3. Попробуйте набрать текст

Откройте любой текстовый редактор (TextEdit, Notes, терминал) и попробуйте:

**Тест 1: Простое слово**
- Переключитесь на английскую раскладку
- Наберите: `ghbdtn` (должно переключиться на "привет")

**Тест 2: Короткое слово**
- Переключитесь на английскую раскладку  
- Наберите: `rfr` (должно переключиться на "как")

**Тест 3: Double Shift (должен работать)**
- Наберите что-то не в той раскладке
- Выделите текст
- Дважды быстро нажмите Left Shift

### 4. Проверьте логи

```bash
cat ~/babylonfish_debug.log
```

## Что искать в логах:

### Если автопереключение НЕ работает:

**Вариант А: События не доходят**
```
[время] Starting InputListener...
[время] Event tap created and enabled.
```
Если после этого НЕТ строк `Event received: type=...` — значит события не перехватываются.

**Вариант Б: События доходят, но не обрабатываются**
```
[время] Event received: type=10
[время] Key: 5 -> en:'g' ru:'п'
[время] Key: 6 -> en:'h' ru:'р'
```
Если есть такие строки, но нет `Language detected:` — проблема в LanguageManager.

**Вариант В: Язык определяется, но не переключается**
```
[время] Language detected: russian for buffer: [5, 6, 11, 2]
[время] Switching layout to russian...
[время] Executing switchAndReplace -> russian
```
Если есть эти строки, но нет `Found matching source:` — проблема с поиском раскладки.

### Если автопереключение РАБОТАЕТ:

Вы должны увидеть полную цепочку:
```
[время] Event received: type=10
[время] Key: 5 -> en:'g' ru:'п'
[время] Key: 6 -> en:'h' ru:'р'
[время] Key: 11 -> en:'b' ru:'и'
[время] Key: 2 -> en:'d' ru:'в'
[время] Language detected: russian for buffer: [5, 6, 11, 2]
[время] Switching layout to russian...
[время] Executing switchAndReplace -> russian
[время] Deleting 4 characters...
[время] Attempting to switch input source to one containing: Russian
[время] Found matching source: com.apple.keylayout.Russian. Selecting...
[время] Input source switch command sent.
[время] Re-typing 4 keys...
```

## Возможные проблемы и решения:

### Проблема 1: События не перехватываются

**Симптом:** В логе только `Event tap created and enabled.`, но нет `Event received:`

**Решение:**
1. Проверьте права Accessibility:
   ```bash
   # Сбросьте права
   tccutil reset Accessibility com.babylonfish.app
   ```
2. Откройте Системные настройки -> Конфиденциальность и безопасность -> Универсальный доступ
3. Удалите BabylonFish из списка (кнопка "-")
4. Перезапустите приложение
5. Разрешите доступ когда появится запрос

### Проблема 2: Раскладка не найдена

**Симптом:** В логе есть `Attempting to switch...`, но нет `Found matching source:`

**Решение:** Проверьте доступные раскладки:
```bash
# Запустите в терминале:
swift -e '
import Carbon
let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
for source in sources {
    if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        print(id)
    }
}
'
```

Убедитесь, что в списке есть раскладки содержащие "Russian" и "US" (или "English").

### Проблема 3: Минимальная длина буфера

**Симптом:** Короткие слова не переключаются

**Текущее ограничение:** Минимум 2 символа (было 3)

Если нужно переключать даже однобуквенные слова, измените в [InputListener.swift:144](file:///Users/xkr/Projects/babylonfish/BabylonFish/Sources/BabylonFish/InputListener.swift#L144):
```swift
guard keyBuffer.count >= 1 else { return }  // Было: >= 2
```

## Отправка отчета

Если проблема не решается, отправьте:
1. Полный лог: `cat ~/babylonfish_debug.log`
2. Список раскладок (команда выше)
3. Описание того, что вы пытались набрать
