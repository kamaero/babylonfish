#!/usr/bin/env python3
"""
Генератор датасета для BabylonFish ML модели
Создает разнообразные примеры для классификации: en, ru, ru_wrong
"""

# Английские слова и фразы
english_words = [
    # Общие слова
    "hello", "world", "good", "morning", "evening", "night", "day", "week", "month", "year",
    "time", "date", "now", "today", "tomorrow", "yesterday", "please", "thank", "you", "welcome",
    "sorry", "excuse", "yes", "no", "maybe", "ok", "okay", "right", "wrong", "true", "false",
    "new", "old", "big", "small", "long", "short", "high", "low", "fast", "slow",
    "good", "bad", "better", "best", "worse", "worst", "more", "less", "much", "many",
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "first", "second", "third", "last", "next", "previous", "before", "after", "during", "while",
    "with", "without", "from", "to", "at", "in", "on", "by", "for", "of",
    "and", "or", "but", "if", "then", "else", "when", "where", "why", "how",
    "what", "which", "who", "whom", "whose", "this", "that", "these", "those",

    # IT и программирование
    "computer", "software", "hardware", "program", "code", "developer", "engineer",
    "algorithm", "function", "variable", "constant", "array", "string", "number", "boolean",
    "class", "object", "method", "property", "protocol", "interface", "struct", "enum",
    "if", "else", "for", "while", "switch", "case", "break", "continue", "return",
    "import", "export", "module", "package", "library", "framework", "dependency",
    "git", "commit", "push", "pull", "merge", "branch", "repository", "clone",
    "debug", "error", "warning", "exception", "throw", "catch", "try", "finally",
    "database", "query", "table", "column", "row", "index", "key", "value",
    "api", "rest", "json", "xml", "http", "https", "url", "uri", "endpoint",
    "server", "client", "request", "response", "header", "body", "status", "code",
    "test", "unit", "integration", "mock", "stub", "assert", "expect", "verify",
    "build", "compile", "deploy", "release", "version", "update", "patch", "hotfix",
    "macos", "ios", "android", "windows", "linux", "unix", "system", "kernel",
    "swift", "python", "javascript", "java", "cpp", "rust", "go", "ruby", "php",
    "xcode", "vscode", "terminal", "console", "shell", "bash", "zsh", "command",
    "file", "folder", "directory", "path", "extension", "name", "size", "permission",
    "memory", "cpu", "disk", "network", "internet", "wifi", "bluetooth", "usb",

    # Apple/Mac специфика
    "macbook", "imac", "macmini", "macpro", "iphone", "ipad", "ipod", "watch",
    "appstore", "icloud", "finder", "dock", "spotlight", "mission", "control",
    "siri", "airdrop", "handoff", "continuity", "sidecar", "universal", "clipboard",
    "keyboard", "mouse", "trackpad", "monitor", "display", "resolution", "color",
    "setting", "preference", "option", "choice", "selection", "default", "custom",
    "accessibility", "security", "privacy", "permission", "authorization", "login",
    "password", "username", "email", "address", "phone", "contact", "message",

    # Фразы
    "hello world", "how are you", "good morning", "good evening", "thank you",
    "you are welcome", "excuse me", "sorry about that", "no problem", "that is fine",
    "see you later", "have a nice day", "take care", "good luck", "best wishes",
    "i am fine", "i am good", "what is up", "not much", "same here",
    "let me know", "keep in touch", "stay safe", "be careful", "all the best",
    "programming is fun", "code is poetry", "debug this", "fix the bug", "release it",
    "push to production", "merge the branch", "commit changes", "pull request", "code review",
    "system settings", "preferences", "access control", "user permissions", "admin rights",
    "keyboard layout", "input method", "text input", "spell checker", "autocorrect"
]

# Русские слова и фразы
russian_words = [
    # Общие слова
    "привет", "мир", "доброе", "утро", "вечер", "день", "ночь", "неделя", "месяц", "год",
    "время", "дата", "сейчас", "сегодня", "завтра", "вчера", "пожалуйста", "спасибо", "тебя", "приветствую",
    "извини", "прости", "да", "нет", "может", "хорошо", "окей", "правильно", "неправильно", "да", "нет",
    "новый", "старый", "большой", "маленький", "длинный", "короткий", "высокий", "низкий", "быстрый", "медленный",
    "хороший", "плохой", "лучше", "лучший", "хуже", "худший", "больше", "меньше", "много", "мало",
    "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
    "первый", "второй", "третий", "последний", "следующий", "предыдущий", "до", "после", "во время", "пока",
    "с", "без", "от", "к", "в", "на", "по", "для", "из", "о",
    "и", "или", "но", "если", "тогда", "иначе", "когда", "где", "почему", "как",
    "что", "который", "кто", "кого", "чей", "этот", "тот", "эти", "те",

    # IT и программирование
    "компьютер", "программа", "код", "разработчик", "инженер",
    "алгоритм", "функция", "переменная", "константа", "массив", "строка", "число", "логический",
    "класс", "объект", "метод", "свойство", "протокол", "интерфейс", "структура", "перечисление",
    "если", "иначе", "для", "пока", "переключатель", "случай", "прерывание", "продолжение", "вернуть",
    "импорт", "экспорт", "модуль", "пакет", "библиотека", "фреймворк", "зависимость",
    "гит", "коммит", "пуш", "пулл", "слияние", "ветка", "репозиторий", "клон",
    "отладка", "ошибка", "предупреждение", "исключение", "выбросить", "поймать", "попробовать", "наконец",
    "база данных", "запрос", "таблица", "колонка", "строка", "индекс", "ключ", "значение",
    "апи", "ресурс", "джейсон", "эксэмэль", "хттп", "хттпс", "урл", "ури", "эндпоинт",
    "сервер", "клиент", "запрос", "ответ", "заголовок", "тело", "статус", "код",
    "тест", "юнит", "интеграционный", "мок", "заглушка", "проверка", "ожидание", "верификация",
    "сборка", "компиляция", "развертывание", "релиз", "версия", "обновление", "патч", "хотфикс",
    "макос", "айос", "андроид", "виндоус", "линукс", "юникс", "система", "ядро",
    "свифт", "питон", "джаваскрипт", "джава", "си плюс плюс", "раст", "го", "руби", "пхп",
    "икскод", "вскулкод", "терминал", "консоль", "шелл", "баш", "зш", "команда",
    "файл", "папка", "директория", "путь", "расширение", "имя", "размер", "права",
    "память", "процессор", "диск", "сеть", "интернет", "вайфай", "блютус", "юэсби",

    # Фразы
    "привет мир", "как дела", "доброе утро", "добрый вечер", "спасибо тебе",
    "не за что", "извини меня", "прости за это", "нет проблем", "все в порядке",
    "увидимся позже", "хорошего дня", "пока", "удачи", "наилучших пожеланий",
    "я в порядке", "я хорошо", "что нового", "ничего особенного", "так же",
    "дай знать", "держись", "будь осторожен", "все самое лучшее", "счастливо",
    "программирование это весело", "код это поэзия", "отладь это", "исправь ошибку", "выпусти релиз",
    "запуши в продакшн", "смержи ветку", "закоммити изменения", "запуши запрос", "ревью кода",
    "системные настройки", "предпочтения", "контроль доступа", "права пользователя", "админ права",
    "раскладка клавиатуры", "метод ввода", "ввод текста", "проверка орфографии", "автоисправление"
]

# Раскладки для конвертации
en_layout = "qwertyuiop[]asdfghjkl;'zxcvbnm,./QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?"
ru_layout = "йцукенгшщзхъфывапролджэячсмитьбю.ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"

def convert_to_wrong_layout(russian_text):
    """Конвертирует русский текст в 'неправильную' раскладку"""
    result = ""
    for char in russian_text:
        if char in ru_layout:
            ru_index = ru_layout.index(char)
            if ru_index < len(en_layout):
                result += en_layout[ru_index]
            else:
                result += char
        else:
            result += char  # Сохраняем пробелы и знаки препинания
    return result

def generate_dataset(target_count=1200):
    """Генерирует датасет"""
    dataset = []

    # Добавляем оригинальные данные из sample_dataset.csv
    original_data = [
        ("hello world", "en"), ("how are you", "en"), ("programming is fun", "en"),
        ("swift language", "en"), ("apple macbook pro", "en"), ("keyboard layout", "en"),
        ("input monitoring", "en"), ("system settings", "en"), ("access control", "en"),
        ("permissions reset", "en"),
        ("привет мир", "ru"), ("как дела", "ru"), ("программирование это весело", "ru"),
        ("язык свифт", "ru"), ("яблочный ноутбук", "ru"), ("раскладка клавиатуры", "ru"),
        ("мониторинг ввода", "ru"), ("системные настройки", "ru"), ("контроль доступа", "ru"),
        ("сброс прав", "ru"),
        ("ghbdtn", "ru_wrong"), ("rfr ltkf", "ru_wrong"), ("ntcn", "ru_wrong"),
        ("fggkt", "ru_wrong"), ("qwerty", "en"), ("йцукен", "ru"),
        ("building project", "en"), ("сборка проекта", "ru"), ("version control", "en"),
        ("контроль версий", "ru")
    ]
    dataset.extend(original_data)

    # Генерируем английские примеры
    for word in english_words:
        dataset.append((word.lower(), "en"))
        if len(dataset) >= target_count:
            break

    # Генерируем русские примеры
    for word in russian_words:
        dataset.append((word, "ru"))
        if len(dataset) >= target_count:
            break

    # Генерируем ru_wrong примеры (русский на английской раскладке)
    russian_to_convert = russian_words[:250]  # Увеличили до 250 слов
    for word in russian_to_convert:
        wrong_layout = convert_to_wrong_layout(word)
        # Добавляем только если конвертация дала результат отличный от оригинала
        if wrong_layout != word and len(wrong_layout) > 2:
            dataset.append((wrong_layout.lower(), "ru_wrong"))
        if len(dataset) >= target_count:
            break

    # Если ещё нужно больше примеров, добавляем фразы и комбинации
    if len(dataset) < target_count:
        en_phrases = [
            "good morning", "have a nice day", "see you later", "thank you very much",
            "excuse me please", "no problem at all", "that is correct", "i am fine",
            "what is new", "nothing special", "same as always", "all good here",
            "programming language", "software development", "machine learning",
            "artificial intelligence", "data science", "web development", "mobile app",
            "user interface", "user experience", "operating system", "computer science",
            "information technology", "network security", "cloud computing", "database management",
            "system architecture", "code review", "version control", "continuous integration",
            "testing framework", "debugging tool", "development environment", "production server",
            "access control", "user permissions", "admin rights", "system preferences"
        ]
        for phrase in en_phrases:
            dataset.append((phrase.lower(), "en"))
            if len(dataset) >= target_count:
                break

    if len(dataset) < target_count:
        ru_phrases = [
            "доброе утро", "хорошего дня", "увидимся позже", "большое спасибо",
            "извини пожалуйста", "нет проблем", "это правильно", "я в порядке",
            "что нового", "ничего особенного", "как всегда", "все хорошо",
            "язык программирования", "разработка программного обеспечения", "машинное обучение",
            "искусственный интеллект", "наука о данных", "веб разработка", "мобильное приложение",
            "пользовательский интерфейс", "пользовательский опыт", "операционная система", "информатика",
            "информационные технологии", "безопасность сети", "облачные вычисления", "управление базами данных",
            "системная архитектура", "ревью кода", "контроль версий", "непрерывная интеграция",
            "фреймворк тестирования", "инструмент отладки", "среда разработки", "сервер для продакшена"
        ]
        for phrase in ru_phrases:
            dataset.append((phrase, "ru"))
            if len(dataset) >= target_count:
                break

    if len(dataset) < target_count:
        ru_phrases_to_convert = [
            "доброе утро", "хорошего дня", "увидимся позже", "большое спасибо",
            "программирование это интересно", "код это искусство", "исправь ошибку",
            "запуши изменения", "сделай коммит", "открой терминал", "запусти сервер",
            "системные настройки", "настройки клавиатуры", "проверь орфографию", "включи автокоррекцию",
            "как дела", "что нового", "все хорошо", "спасибо тебе", "нет проблем",
            "открой файл", "сохрани изменения", "закрой окно", "перезагрузи систему",
            "включи музыку", "открой браузер", "напиши код", "запуши код",
            "сделай тест", "исправь баг", "проверь логи", "очисти кэш"
        ]
        for phrase in ru_phrases_to_convert:
            wrong_layout = convert_to_wrong_layout(phrase)
            if wrong_layout != phrase:
                dataset.append((wrong_layout.lower(), "ru_wrong"))
            if len(dataset) >= target_count:
                break

    # Дополнительные ru_wrong примеры из комбинаций слов
    if len(dataset) < target_count:
        # Генерируем случайные комбинации из русских слов
        import random
        random.seed(42)
        short_russian_words = [w for w in russian_words if len(w) >= 3 and len(w) <= 8][:100]

        for i in range(50):  # Добавляем 50 комбинаций
            if len(short_russian_words) >= 2:
                word1 = random.choice(short_russian_words)
                word2 = random.choice(short_russian_words)
                phrase = f"{word1} {word2}"
                wrong_layout = convert_to_wrong_layout(phrase)
                if wrong_layout != phrase:
                    dataset.append((wrong_layout.lower(), "ru_wrong"))
            if len(dataset) >= target_count:
                break

    return dataset

def save_dataset(dataset, output_path):
    """Сохраняет датасет в CSV файл"""
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("text,label\n")
        for text, label in dataset:
            # Экранируем запятые в тексте
            escaped_text = f'"{text}"' if ',' in text else text
            f.write(f"{escaped_text},{label}\n")

    print(f"✅ Датасет сохранен в: {output_path}")
    print(f"📊 Всего примеров: {len(dataset)}")

    # Статистика по категориям
    en_count = sum(1 for _, label in dataset if label == "en")
    ru_count = sum(1 for _, label in dataset if label == "ru")
    ru_wrong_count = sum(1 for _, label in dataset if label == "ru_wrong")

    print("📈 Статистика:")
    print(f"   - en (английский): {en_count}")
    print(f"   - ru (русский): {ru_count}")
    print(f"   - ru_wrong (ошибочная раскладка): {ru_wrong_count}")

if __name__ == "__main__":
    dataset = generate_dataset(target_count=1200)
    save_dataset(dataset, "sample_dataset.csv")
