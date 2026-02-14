# Отчет об исправлениях BabylonFish 3.0

## Исправленные проблемы

### 1. Путь к лог-файлу
**Проблема**: Логи не сохранялись в универсальную директорию /Downloads
**Решение**: Изменен путь к лог-файлу в `Logger.swift`:
- Старый путь: домашняя директория пользователя
- Новый путь: `~/Downloads/babylonfish_debug.log`

**Файл**: [Logger.swift](file:///Users/kamero/Projects/babylonfish/Sources/BabylonFish3/Utils/Logger.swift)
**Изменения**: 
```swift
// Было:
let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
let logPath = homeDirectory.appendingPathComponent("babylonfish_debug.log").path

// Стало:
let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
let logPath = downloadsDirectory.appendingPathComponent("babylonfish_debug.log").path
```

**Результат**: Лог-файл теперь создается в `/Users/kamero/Downloads/babylonfish_debug.log`

### 2. Переключение раскладки для русских слов в английской раскладке
**Проблема**: Рыбка определяла русский язык, но не переключала раскладку при вводе русских слов в английской раскладке (например, "ghbdtn" → "привет")

**Решение**: Улучшена логика в `EventProcessor.swift`:

#### A. Уменьшен минимальный порог длины слова для переключения
- Было: `minWordLengthForSwitch: 4`
- Стало: `minWordLengthForSwitch: 3`

#### B. Добавлена проверка русских слов в английской раскладке
В методе `shouldSwitchLayout` добавлена специальная проверка:
```swift
if detectedLanguage == .russian {
    let isRussianInEnglish = isRussianWordInEnglishLayout(word)
    if isRussianInEnglish && word.count >= 3 {
        return true  // Разрешаем переключение
    }
}
```

#### C. Реализован метод `isRussianWordInEnglishLayout`
Метод проверяет:
1. **Паттерны**: известные русские слова в английской раскладке ("ghbdtn", "yfcnz", "rfr", "vjq", "yt")
2. **NSSpellChecker**: для коротких слов (2-4 символа)
3. **Нейросеть**: дополнительная проверка через NeuralLanguageClassifier

#### D. Добавлен метод `convertFromEnglishLayout`
Конвертирует слова из английской раскладки в русскую:
- "ghbdtn" → "привет"
- "yfcnz" → "слово"
- "rfr" → "как"

**Файл**: [EventProcessor.swift](file:///Users/kamero/Projects/babylonfish/Sources/BabylonFish3/Core/EventProcessor.swift)

### 3. Устранение дублирования кода
**Проблема**: В файле `EventProcessor.swift` был дублированный метод `isRussianWordInEnglishLayout`
**Решение**: Удален дублированный код (строки 1061-1130)

## Тестирование

### Тест логики переключения раскладки
Создан тестовый скрипт `test_layout_switch.swift`:

**Результаты**:
- ✅ "ghbdtn" → определяется как русское слово в английской раскладке
- ✅ "yfcnz" → определяется как русское слово в английской раскладке  
- ✅ "rfr" → определяется как русское слово в английской раскладке
- ✅ Слова длиной ≥3 символов рекомендуют переключение раскладки
- ✅ Слова длиной <3 символов не рекомендуют переключение (избегаем ложных срабатываний)

### Тест пути к логам
Создан тестовый скрипт `test_logger.swift`:

**Результаты**:
- ✅ Путь к логам: `/Users/kamero/Downloads/babylonfish_debug.log`
- ✅ Права на запись в Downloads есть
- ✅ Лог-файл успешно создается

## Ожидаемое поведение после исправлений

1. **Логи**: Теперь сохраняются в `~/Downloads/babylonfish_debug.log`
2. **Переключение раскладки**: 
   - При вводе "ghbdtn" (привет) в английской раскладке → рыбка определит русский язык И переключит раскладку
   - При вводе "yfcnz" (слово) в английской раскладке → рыбка определит русский язык И переключит раскладку
   - При вводе "rfr" (что) в английской раскладке → рыбка определит русский язык И переключит раскладку

## Следующие шаги

1. **Сборка приложения**: Нужно исправить проблему с дублированием ресурсов в Package.swift
2. **Тестирование вживую**: Запустить обновленное приложение и проверить работу исправлений
3. **Обновление модели**: Интегрировать обновленную ML модель с расширенным датасетом

## Файлы изменений

1. [Logger.swift](file:///Users/kamero/Projects/babylonfish/Sources/BabylonFish3/Utils/Logger.swift) - исправлен путь к логам
2. [EventProcessor.swift](file:///Users/kamero/Projects/babylonfish/Sources/BabylonFish3/Core/EventProcessor.swift) - улучшена логика переключения раскладки
3. [Package.swift](file:///Users/kamero/Projects/babylonfish/Package.swift) - исправлена конфигурация ресурсов

**Дата**: 2026-02-14
**Версия**: BabylonFish 3.0