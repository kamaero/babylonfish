# BabylonFish - Agent Guidelines

This document provides guidelines for AI agents working on BabylonFish - a macOS keyboard layout auto-switching application.

## Project Overview

BabylonFish automatically detects and switches keyboard layouts when users type in the wrong language. Features:
- Automatic layout switching (e.g., "ghbdtn" → "привет")
- Double Shift shortcut for manual correction
- Context-aware processing (ignores password fields)
- Typo correction and auto-completion (v3)

## Build Commands

### Development Build
```bash
# Build BabylonFish2 (legacy)
swift build --product BabylonFish2

# Build BabylonFish3 (current)
swift build --product BabylonFish3

# Build for specific architecture
swift build -c debug --product BabylonFish3 --arch arm64
swift build -c debug --product BabylonFish3 --arch x86_64
```

### Release Build
```bash
# Build and install universal binary
./install_app.sh

# Manual build for both architectures
swift build -c release --product BabylonFish3 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish3 --disable-sandbox

# Create universal binary
lipo -create -output "BabylonFish" \
  ".build/arm64-apple-macosx/release/BabylonFish3" \
  ".build/x86_64-apple-macosx/release/BabylonFish3"
```

### Package Management
```bash
# Update dependencies
swift package update

# Clean build
rm -rf .build
```

## Testing Commands

### Manual Testing
```bash
# Run the application
./run_app.sh
# Or directly
open ~/Applications/BabylonFish.app

# Check debug logs
tail -f ~/babylonfish_debug.log
# Clear debug logs
> ~/babylonfish_debug.log
```

### Test Scripts
```bash
# Run BabylonFish3 test suite
./test_babylonfish3.sh

# Test contextual processing
swift test_contextual.swift
```

### Testing Scenarios
1. **Simple word detection**: Type "ghbdtn" (English) → "привет" (Russian)
2. **Short word detection**: Type "rfr" → "как"
3. **Double Shift**: Select text, double-tap Left Shift
4. **Context awareness**: Should ignore password fields
5. **Typo correction**: "havv" → "have" (v3 only)
6. **Auto-completion**: Partial words (v3 only)

### Debug Log Analysis
Check `~/babylonfish_debug.log` for:
- `Event received: type=10` - Events captured
- `Language detected:` - Language detection working
- `Switching layout to...` - Layout switching attempted
- `Found matching source:` - Layout source found
- `Context check:` - Context analysis results

## Code Style Guidelines

### File Organization
```
Sources/BabylonFish2/
├── Core/           # Core engine components
├── Language/       # Language detection and processing
├── Configuration/  # App configuration and state
├── UI/            # User interface components
└── Utils/         # Utility classes and helpers
```

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `EventProcessor`, `LanguageDetector`)
- **Structs**: `PascalCase` (e.g., `AppConfig`, `KeyCombo`)
- **Enums**: `PascalCase` with cases in `camelCase` (e.g., `Language.english`, `Language.russian`)
- **Variables**: `camelCase` (e.g., `currentBuffer`, `isEnabled`)
- **Constants**: `camelCase` or `UPPER_SNAKE_CASE` for global constants
- **Functions**: `camelCase` (e.g., `detectLanguage()`, `switchLayout()`)

### Import Order
```swift
// 1. Foundation and system frameworks
import Foundation
import Cocoa
import Carbon

// 2. Third-party dependencies (none currently)

// 3. Local modules (if any)
```

### Type Annotations
- Always specify return types for functions
- Use explicit type annotations for public API
- Prefer `let` over `var` for immutable values
- Use optionals appropriately with `?` and `!` only when safe

### Error Handling
```swift
// Use do-catch for recoverable errors
do {
    try someOperation()
} catch {
    logDebug("Error: \(error)")
}

// Use optional binding for expected failures
guard let result = try? operation() else {
    return
}

// Log errors to debug log
logDebug("Error description")
```

### Logging
- Use `logDebug()` function for all debug logging
- Logs go to `~/babylonfish_debug.log`
- Include timestamps and context in log messages
- Use descriptive messages that help with debugging

### Swift Conventions
- Use Swift's modern concurrency (`async/await`) when appropriate
- Prefer value types (structs) over reference types (classes) when possible
- Use protocols for abstraction
- Follow Swift API Design Guidelines

### Memory Management
- Use `weak` references for delegates to avoid retain cycles
- Properly handle `Unmanaged` types when working with Core Foundation
- Clean up resources in `deinit` when necessary

## Architecture Notes

### Event Processing Flow
```
CGEvent → EventTapManager → EventProcessor → BufferManager
                                      ↓
                            ContextAnalyzer (context check)
                                      ↓
                            LanguageDetector (language detection)
                                      ↓
                            LayoutSwitcher (switch + retype)
```

### Configuration
- Use `AppConfig` struct for Codable configuration
- Migrate from UserDefaults to structured config
- Support backward compatibility for user settings

### Performance Requirements
- Event processing must be fast (< 1ms)
- Language detection should be efficient
- Memory usage should be minimal
- Avoid blocking the main thread

### Security Requirements
- Never log sensitive information (passwords, etc.)
- Respect privacy - don't send data externally
- Handle permissions appropriately
- Validate all inputs and configurations

## Agent Operations

### Before Making Changes
1. **Always run tests**: Use `./test_babylonfish3.sh` or manual testing
2. **Check logs**: Verify `~/babylonfish_debug.log` for errors
3. **Build verification**: Run `./install_app.sh` to ensure build works

### Code Quality Checks
- **No linting tools**: This project doesn't use SwiftLint or other linters
- **Manual verification**: Check code follows existing patterns
- **Performance**: Event processing must remain under 1ms

### Testing Requirements
- **Unit tests**: Not currently implemented; focus on manual testing
- **Integration tests**: Use `test_contextual.swift` for contextual processing
- **Manual testing**: Always test typing scenarios before committing

### Common Pitfalls
1. **Permissions**: App needs Accessibility + Input Monitoring permissions
2. **Event capture**: Verify events are received in debug logs
3. **Layout switching**: Ensure Russian/English layouts are installed
4. **Memory leaks**: Check for retain cycles in delegates

### Quick Reference
```bash
# Build and test
./install_app.sh
./test_babylonfish3.sh
tail -f ~/babylonfish_debug.log

# Reset if needed
tccutil reset Accessibility com.babylonfish.app
> ~/babylonfish_debug.log
```

## Recent Development Progress

### Current Version: 3.0.40
**Date**: 12.02.2026  
**Status**: Stable build with post-switch context tracking

### Problem Solved: Post-Correction Gibberish Issue
**Scenario**: User types "ghbdtn!" → BabylonFish correctly converts to "привет!" and switches to Russian layout → User continues typing Russian words on physical English layout → BabylonFish incorrectly tries to convert them back, creating gibberish like "rjycthdfwbz" instead of "конвертация"

**Root Cause**: After auto-switching layout, BabylonFish didn't track that it was the one who switched, and didn't maintain context about expected user behavior.

### Solution Implemented

#### 1. Enhanced Context Tracking (`EventProcessor.swift`)
```swift
struct ProcessingContext {
    // ... existing fields ...
    var lastLayoutSwitchByApp: Bool = false  // true if BabylonFish switched
    var expectedLayoutLanguage: Language?    // What language we expect after switch
    var postSwitchWordCount: Int = 0         // Words typed after BabylonFish switch
    var postSwitchBuffer: [String] = []      // Buffer for post-switch words
}
```

#### 2. Smart Post-Switch Logic
- After BabylonFish switches layout, assumes user will type on new layout for 5 seconds
- If user types language different from expected, assumes it's correct behavior
- Prevents unnecessary re-switching that caused gibberish

#### 3. Manual Switch Detection
- Detects Cmd+Space / Ctrl+Space shortcuts
- Monitors layout changes: if user manually switches, resets BabylonFish tracking
- Prevents BabylonFish from fighting user's manual choices

#### 4. Stability Fixes
- **Recursion protection**: Added `maxRecursionDepth = 3` to prevent infinite loops
- **Tap re-enable limits**: Limited attempts to re-enable disabled event taps (max 3 attempts)
- **Fallback mode**: Automatic switch to fallback if tap fails repeatedly

### Current Issues & Next Steps

#### ✅ Working:
- Language detection (bi/trigrams + neural network)
- Basic layout switching ("ghbdtn" → "привет")
- Post-switch context tracking
- Manual switch detection
- System stability (no hangs)

#### ✅ Fixed:
1. **Word conversion with punctuation**: Enhanced `separateWordAndPunctuation()` to handle all cases
   - Problem: "ghbdtn!" → should delete "ghbdtn!" and type "привет!" (with exclamation)
   - Solution: Now correctly preserves leading and trailing punctuation
   - Handles: quotes, brackets, multiple punctuation marks, etc.

#### ✅ Fixed:
1. **Space handling**: Improved word boundary detection in BufferManager
   - Problem: Multi-word sentences didn't process correctly
   - Solution: Strict boundaries (space, tab, newline) trigger word completion
   - Punctuation stays with word (e.g., 'ghbdtn!' keeps '!')
   - Multiple words processed sequentially

2. **Complete conversion flow**: 
   - Detect wrong-language word ✓
   - Delete it completely (including punctuation) ✓  
   - Type corrected version (with original punctuation) ✓
   - Switch layout if needed ✓

### Testing Commands Added
```bash
# Test post-switch logic
swift test_post_switch.swift

# Test stability fixes  
swift test_stability.swift

# Test complete scenario
swift test_scenario_final.swift
```

### Key Code Locations
- `Sources/BabylonFish3/Core/EventProcessor.swift:886-910` - Enhanced ProcessingContext
- `Sources/BabylonFish3/Core/EventProcessor.swift:408-418` - Post-switch logic in shouldSwitchLayout
- `Sources/BabylonFish3/Core/EventProcessor.swift:195-225` - Manual switch detection
- `Sources/BabylonFish3/Core/EventTapManager.swift:227-248` - Tap re-enable limits

### Remaining Tasks
1. **Test edge cases**: mixed punctuation, numbers, special characters
2. **Enable advanced features** (typo correction, auto-complete) once core is stable
3. **Performance optimization** for long texts
4. **UI improvements**: Visual indicators for layout switching

### Recently Fixed
1. **Punctuation handling**: Enhanced `separateWordAndPunctuation()` function
   - Now handles leading and trailing punctuation separately
   - Preserves punctuation order and position
   - Works with quotes, brackets, multiple punctuation marks
   - Test with: `swift test_full_flow.swift`

2. **Word boundary detection**: Improved BufferManager logic
   - Strict boundaries (space, tab, newline) trigger word completion
   - Punctuation stays with word (e.g., 'ghbdtn!' keeps '!')
   - Multiple words processed sequentially
   - Test with: `swift test_buffer_fixed.swift`

3. **System stability**: Added recursion protection and tap re-enable limits
   - Prevents infinite loops when event tap is disabled
   - Maximum 3 re-enable attempts with 5-second cooldown
   - Automatic fallback mode after failures
   - Test with: `swift test_stability.swift`

## Current Working Detection & Conversion Methods (v3.0.58+)

### Language Detection System

#### 1. **Multi-Layer Detection Approach**
BabylonFish использует комбинированный подход для максимальной точности:

**Layer 1: Pattern Matching (Быстрая проверка)**
- Проверка по заранее определенным паттернам английских слов в русской раскладке
- Примеры: "руддщ" → "hello", "щт" → "in", "йфя" → "was", "еуые" → "test"
- Работает для коротких слов (2+ символа) через `isEnglishWordInRussianLayout()`

**Layer 2: System Dictionary (NSSpellChecker)**
- Использует системный словарь macOS для проверки валидности слов
- Проверяет слова в обеих раскладках (en_US и ru_RU)
- Если слово валидно в целевой раскладке и невалидно в исходной → переключение
- Обрабатывает склонения и большую часть словарного запаса автоматически

**Layer 3: Neural Language Detection (CoreML)**
- Использует Apple NLLanguageRecognizer для определения языка текста
- Порог уверенности: 0.7 (настраивается)
- Кэширование предсказаний для производительности
- Работает с контекстом (последние 3 слова)

**Layer 4: Contextual Analysis**
- Анализирует контекст ввода (тип приложения, поле ввода)
- Игнорирует парольные поля и системные диалоги
- Учитывает историю переключений

### Conversion Logic

#### 1. **Word Processing Pipeline**
```
1. Event Capture → 2. Buffer Management → 3. Word Completion Detection → 
4. Language Detection → 5. Layout Switching Decision → 6. Event Generation
```

#### 2. **Buffer Management (BufferManager.swift)**
- Максимальный размер буфера: 1000 символов
- Определение границ слов: пробел, табуляция, новая строка
- Обработка пунктуации: знаки препинания остаются с словом
- Очистка буфера при специальных событиях (Cmd, Ctrl, Escape)

#### 3. **Layout Switching Logic (EventProcessor.swift)**
**Критерии для переключения:**
1. Слово длиной ≥ 4 символа ИЛИ короткое слово (2+ символа) в паттернах
2. Язык определен с уверенностью ≥ 0.7
3. Слово валидно в целевой раскладке (через NSSpellChecker)
4. Контекст позволяет переключение (не парольное поле и т.д.)

**Особые случаи:**
- Короткие слова: "рщц" → "how", "фку" → "are", "нщг" → "you"
- Слова с пунктуацией: "руддщ!" → "hello!" (сохраняет знаки препинания)
- Многословные предложения: обрабатываются последовательно

#### 4. **Event Generation & Recursion Protection**
**Генерация событий:**
- Удаление неправильного слова: `createBackspaceEvents(count:)`
- Ввод правильного слова: `getKeyEventsForWord()`
- Сохранение пунктуации: `separateWordAndPunctuation()`

**Защита от рекурсии (EventTapManager.swift):**
- Переменная `isSendingEvents` отслеживает отправку событий
- Установка `sourcePid` для всех отправляемых событий как PID BabylonFish
- Игнорирование событий от самого BabylonFish в `shouldIgnoreEvent()`
- Предотвращение бесконечных циклов при отключении event tap

### Key Configuration Parameters

#### Language Detection
```swift
// EventProcessor.swift
minWordLengthForSwitch = 4  // Минимальная длина для обычных слов
englishInRussianPatterns = ["руддщ", "щт", "йфя", "еуые", "рщц", "яку", "нщг", "фку", ...]

// NeuralLanguageClassifier.swift  
confidenceThreshold = 0.7  // Порог уверенности для нейросети
```

#### Performance Settings
```swift
// BabylonFishEngine.swift
maxBufferSize = 1000
maxWordLength = 50
maxProcessingTime = 0.05  // 50ms
cacheTTL = 3600  // 1 час
```

### Testing Scenarios (Рабочие)

#### ✅ English → Russian
- "ghbdtn" → "привет" (с пунктуацией: "ghbdtn!" → "привет!")
- "rfr" → "как"
- "cnjq" → "слово"

#### ✅ Russian → English (Reverse Conversion)
- "руддщ" → "hello" (с пунктуацией: "руддщ!" → "hello!")
- "рщц" → "how"
- "фку" → "are" 
- "нщг" → "you"
- "яку" → ??? (требует добавления в паттерны)

#### ✅ Multi-Word Processing
- "ghbdtn rfr" → "привет как" (последовательная обработка)
- "руддщ фку нщг" → "hello are you"

#### ✅ Context Awareness
- Игнорирование парольных полей
- Отслеживание ручных переключений (Cmd+Space)
- Контекст после переключения (5-секундное окно)

### Known Issues & Solutions

#### ✅ Решено:
1. **Рекурсия событий**: Добавлена защита в `EventTapManager.swift`
2. **Пунктуация**: Улучшена функция `separateWordAndPunctuation()`
3. **Буфер переполнения**: Добавлена очистка при специальных событиях
4. **Короткие слова**: Обход `minWordLengthForSwitch` для паттернов
5. **"яку" → "you"**: Добавлено в паттерны как "you (альтернативная раскладка)"
6. **Ложные срабатывания NSSpellChecker**: Исправлена логика проверки коротких слов (2-4 символа)

#### 🔄 В работе:
1. **UI индикаторы**: Визуальная обратная связь о переключении
2. **Контекстный анализ**: Улучшение анализа на уровне предложений

### Enhanced Typo Correction with CoreML+NSSpellChecker Integration (v3.0.60+)

#### 1. **Advanced Typo Correction System**
BabylonFish теперь использует комбинированный подход для исправления опечаток:

**Layer 1: EnhancedTypoCorrector (Основной движок)**
- Интегрирует CoreML и NSSpellChecker для максимальной точности
- Использует многоуровневую систему оценки исправлений
- Поддерживает контекстно-зависимые исправления

**Layer 2: Neural Language Classification (CoreML)**
- Использует `NeuralLanguageClassifier` для определения языка с высокой точностью
- Порог уверенности: 0.6 (настраивается)
- Кэширование результатов для производительности
- Работает как с отдельными словами, так и с контекстом

**Layer 3: System Dictionary Validation (NSSpellChecker)**
- Проверяет валидность слов в системном словаре macOS
- Поддерживает английский (en_US) и русский (ru_RU) языки
- Предоставляет предложения по исправлению для невалидных слов
- Обрабатывает склонения и грамматические формы

**Layer 4: Context-Aware Correction**
- Учитывает частоту слов в пользовательском контексте
- Анализирует пары слов для лучшего предсказания
- Учитывает тип приложения и поле ввода

#### 2. **Correction Pipeline**
```
1. Word Input → 2. Language Detection (CoreML) → 3. Spelling Check (NSSpellChecker) →
4. Suggestion Generation → 5. Neural Filtering → 6. Context Scoring → 7. Apply Correction
```

#### 3. **Key Features**

**Intelligent Suggestion Ranking:**
- Комбинирует оценки от CoreML (семантическая схожесть) и NSSpellChecker (лексическая правильность)

### Enhanced Context Analysis with Sentence Boundaries (v3.0.61+)

#### 1. **Sentence-Level Context Analysis**
BabylonFish теперь анализирует контекст на уровне предложений, а не отдельных слов:

**EnhancedSentenceBuffer:**
- Обнаружение границ предложений (точки, восклицательные знаки, вопросительные знаки)
- Отслеживание завершенных и незавершенных предложений
- Анализ доминирующего языка в контексте предложения
- Определение согласованности языка текущего слова с контекстом

**Improved Decision Logic:**
- Приоритет нейросети при высокой уверенности (≥0.9) даже при противоречивом контексте
- Использование контекста только при согласованности языка слова с контекстом
- Игнорирование контекста при смешанных языковых паттернах

#### 2. **Sentence Boundary Detection**
```
Границы предложений: . ! ? … 。 ！ ？
Разделители: , ; : ， ； ：

Алгоритм:
1. Накопление текста до обнаружения границы
2. Анализ языка накопленного предложения
3. Конвертация всего предложения при обнаружении ошибки раскладки
4. Сброс контекста после завершения предложения
```

#### 3. **Context Priority Rules**

**Согласованный контекст:**
- Язык слова согласуется с доминирующим языком контекста → Используем контекст

**Несогласованный контекст:**
- Язык слова не согласуется с контекстом → Игнорируем контекст, используем нейросеть

**Смешанный контекст:**
- Разные языки в контексте → Используем обычную детекцию

**Высокая уверенность нейросети:**
- Уверенность ≥0.9 → Приоритет нейросети над контекстом

#### 4. **Implementation Details**

**EnhancedSentenceBuffer.swift:**
- `addText(text: String, language: Language, isComplete: Bool)`: Добавление текста с учетом границ
- `getContext(forWord: String) -> EnhancedSentenceContext`: Получение контекста для слова
- `clear()`: Очистка буфера при смене контекста

**ContextAnalyzer.swift:**
- `detectLanguageWithEnhancedContext()`: Улучшенная детекция с учетом границ предложений
- Использование `EnhancedSentenceBuffer` вместо `SentenceBuffer`
- Анализ согласованности языка слова с контекстом

**EventProcessor.swift:**
- Улучшенная логика принятия решений с проверкой согласованности
- Приоритет нейросети при высокой уверенности
- Логирование метода принятия решения для отладки

#### 5. **Testing Scenarios**

**Сценарий 1: Смешанные языки в одном предложении**
```
Ввод: "Hello привет world мир"
Ожидание: Контекст игнорируется, используется нейросеть для каждого слова
```

**Сценарий 2: Ошибка раскладки в середине предложения**
```
Ввод: "Привет ghbdtn мир" (ghbdtn = привет в английской раскладке)
Ожидание: Конвертация "ghbdtn" → "привет" после завершения предложения
```

**Сценарий 3: Высокая уверенность нейросети**
```
Ввод: "heccrbq" (классифицируется как English с уверенностью 0.9)
Контекст: Russian (предыдущие слова на русском)
Ожидание: Используется English (приоритет нейросети при высокой уверенности)
```
- Учитывает расстояние Левенштейна для оценки схожести слов
- Применяет весовые коэффициенты для разных факторов

**Context Integration:**
- Анализирует историю ввода пользователя
- Учитывает частоту слов и пар слов
- Поддерживает обучение на основе пользовательских исправлений

**Performance Optimization:**
- Многоуровневое кэширование результатов
- Асинхронная обработка для предотвращения блокировок
- Автоматическая очистка кэша при изменении конфигурации

#### 4. **Configuration Parameters**
```swift
// EnhancedTypoCorrector.swift
isEnabled = true                    // Включить исправление опечаток
autoCorrectEnabled = true           // Автоматически применять исправления
suggestionEnabled = true            // Показывать предложения
maxEditDistance = 2                 // Максимальное расстояние редактирования
minConfidence = 0.7                 // Минимальная уверенность для применения
contextWeight = 0.3                 // Вес контекста в оценке
useNeuralForTypos = true            // Использовать CoreML для опечаток
neuralConfidenceThreshold = 0.6     // Порог уверенности для нейросети
```

#### 5. **Testing Scenarios**

**English Typo Correction:**
- "teh" → "the" (common typo)
- "adn" → "and" (transposition)
- "yuor" → "your" (misspelling)
- "wht" → "what" (missing vowel)
- "hw" → "how" (transposition)

**Russian Typo Correction:**
- "прв" → "при" (missing vowel)
- "спсибо" → "спасибо" (missing vowel)
- "пака" → "пока" (vowel substitution)

**Cross-Layout Correction:**
- "руддщ" → "hello" (English word in Russian layout)
- "фку" → "are" (English word in Russian layout)
- "яку" → "you" (English word in Russian layout)

#### 6. **Integration Points**

**Core Components:**
- `EnhancedTypoCorrector.swift`: Основной движок исправления опечаток
- `NeuralLanguageClassifier.swift`: Классификация языка через CoreML
- `SystemDictionaryService.swift`: Обертка для NSSpellChecker
- `EventProcessor.swift`: Интеграция с основным потоком обработки

**Key Methods:**
- `correctTypos(in:language:context:)`: Основной метод исправления
- `getSuggestions(for:language:context:)`: Получение предложений
- `configure(...)`: Настройка параметров корректора
- `getStatistics()`: Получение статистики работы

#### 7. **Fixed Issues in v3.0.61+**

**Critical NSSpellChecker Fix for Short Words:**
- **Problem**: NSSpellChecker считал большинство коротких русских слов (2-4 символа) валидными английскими словами
- **Example**: "а", "в", "и", "к", "о", "с", "у", "я", "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты"
- **Impact**: Ложные срабатывания при определении английских слов в русской раскладке
- **Solution**: Улучшенная логика в `isEnglishWordInRussianLayout()`:
  1. Проверяем оба языка через NSSpellChecker (английский и русский)
  2. Сравниваем результаты:
     - Если слово валидно только в английском → английское слово в русской раскладке
     - Если слово валидно в обоих языках → неоднозначный случай (возвращаем false)
     - Если слово не валидно ни в одном языке → не английское слово в русской раскладке
- **Code Location**: `EventProcessor.swift`, метод `isEnglishWordInRussianLayout()`

**"яку" → "you" Pattern Clarification:**
- **Problem**: Паттерн "яку" был помечен как неоднозначный ("??? (возможно you, но нщг тоже you)")
- **Solution**: Уточнён комментарий → "you (альтернативная раскладка)"
- **Code Location**: `EventProcessor.swift`, массив `englishInRussianPatterns`

#### 8. **Build & Deployment**
- **Version**: 3.0.61+ (with enhanced typo correction and NSSpellChecker fixes)
- **Requirements**: macOS 11.0+, CoreML framework
- **Permissions**: Input Monitoring for real-time correction
- **Performance**: < 5ms per word correction

### Code References

#### Основные файлы:
- `EventProcessor.swift`: Основная логика обработки и переключения
- `EventTapManager.swift`: Управление event tap и защита от рекурсии
- `BufferManager.swift`: Управление буфером ввода
- `EnhancedTypoCorrector.swift`: Улучшенный корректор опечаток с CoreML+NSSpellChecker
- `NeuralLanguageClassifier.swift`: Нейросетевая детекция языка
- `SystemDictionaryService.swift`: Обертка для NSSpellChecker
- `TypoCorrector.swift`: Базовый корректор опечаток (legacy)

#### Ключевые методы:
- `shouldSwitchLayout()`: Принятие решения о переключении
- `isEnglishWordInRussianLayout()`: Проверка паттернов
- `sendEvents()`: Отправка событий с защитой от рекурсии
- `processCharacter()`: Обработка символов в буфере
- `correctTypos(in:language:context:)`: Исправление опечаток
- `getSuggestions(for:language:context:)`: Получение предложений по исправлению

### Build Status
- **Current**: Enhanced (3.0.60+) - с интеграцией CoreML+NSSpellChecker
- **Configuration**: Полная (все функции включены)
- **Permissions**: Требует Accessibility для контекстной проверки + Input Monitoring
- **Event Tap**: Работает корректно с рекурсивной защитой
- **Typo Correction**: Включено с многоуровневой системой исправлений