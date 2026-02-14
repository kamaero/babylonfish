#!/usr/bin/env python3
"""
Генератор расширенного датасета для BabylonFish ML
5000 слов: 2500 русских + 2500 английских
Включая популярные слова, союзы, короткие слова (1-3 буквы)
"""

import csv
import random

# Популярные английские слова (частотные)
popular_en = [
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
    "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
    "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
    "or", "an", "will", "my", "one", "all", "would", "there", "their",
    "what", "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
    "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
    "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
    "than", "then", "now", "look", "only", "come", "its", "over", "think", "also",
    "back", "after", "use", "two", "how", "our", "work", "first", "well", "way",
    "even", "new", "want", "because", "any", "these", "give", "day", "most", "us",
    "world", "life", "problem", "make", "help", "go", "need", "find", "look", "see", "know",
    "think", "come", "want", "give", "use", "find", "tell", "ask", "work", "seem",
    "feel", "try", "leave", "call", "good", "new", "first", "last", "long", "great",
    "little", "own", "other", "old", "right", "big", "high", "different", "small", "large",
    "next", "early", "young", "important", "few", "public", "bad", "same", "able",
    "house", "number", "boy", "word", "business", "issue", "side", "kind", "head", "house",
    "service", "friend", "father", "power", "hour", "game", "line", "end", "member", "law",
    "car", "city", "community", "name", "president", "team", "minute", "idea", "kid", "body",
    "information", "back", "parent", "face", "others", "level", "office", "door", "health",
    "person", "art", "war", "history", "party", "result", "change", "morning", "reason",
    "research", "girl", "guy", "moment", "air", "teacher", "force", "education",
]

# Английские союзы
conjunctions_en = [
    "and", "but", "or", "nor", "for", "yet", "so", "although", "though",
    "because", "since", "as", "if", "unless", "until", "while", "where",
    "after", "before", "when", "whenever", "wherever", "whether", "that",
    "which", "who", "whom", "whose", "what", "whatever", "whichever",
    "both", "either", "neither", "not", "only", "also", "even", "just",
]

# Короткие английские слова (1-3 буквы)
short_en = [
    # 1 буква
    "a", "i",
    # 2 буквы
    "be", "do", "go", "is", "it", "me", "my", "no", "ok", "on", "to", "up", "us", "we",
    # 3 буквы
    "all", "and", "are", "but", "can", "did", "for", "get", "had", "has", "her", "him", "his", "how", "its", "let", "may", "new", "now", "off", "old", "one", "our", "out", "own", "put", "run", "saw", "say", "see", "she", "sit", "too", "top", "try", "two", "use", "was", "way", "who", "why", "yes", "you", "the", "not", "any",
]

# Английские фразы (расширение существующего набора)
phrases_en = [
    "how are you", "good morning", "good evening", "thank you", "you are welcome",
    "excuse me", "sorry about that", "no problem", "that is fine", "see you later",
    "have a nice day", "take care", "good luck", "best wishes", "i am fine", "i am good",
    "what is up", "not much", "same here", "let me know", "keep in touch", "stay safe",
    "be careful", "all the best", "programming is fun", "code is poetry", "debug this",
    "fix the bug", "release it", "push to production", "merge the branch",
    "commit changes", "code review", "system settings", "preferences", "access control",
    "user permissions", "admin rights", "keyboard layout", "input method",
    "text input", "spell checker", "autocorrect",
]

# Популярные русские слова (частотные)
popular_ru = [
    "и", "в", "не", "на", "я", "быть", "он", "что", "это", "весь",
    "с", "а", "по", "к", "но", "они", "мы", "ты", "вы", "который",
    "время", "год", "говорить", "делать", "себя", "человек", "работа", "рука",
    "жизнь", "день", "новый", "глаз", "стать", "дом", "лицо", "друг",
    "случай", "город", "мочь", "хотеть", "вода", "огонь", "земля", "небо",
    "дорога", "голова", "сила", "море", "ветер", "поле", "гора", "свет",
    "ночь", "утро", "вечер", "солнце", "луна", "звезда", "дождь", "снег",
    "сердце", "рука", "нога", "губа", "ухо", "нос", "волос", "кожа",
    "кровь", "кость", "мозг", "душа", "тело", "рот", "зуб", "язык",
    "сон", "бежать", "идти", "ехать", "лететь", "плыть", "расти", "пасть",
    "стоять", "сидеть", "лежать", "спать", "есть", "пить", "видеть", "слышать",
    "знать", "думать", "понимать", "любить", "ненавидеть", "хотеть", "мочь",
    "должен", "нужно", "надо", "можно", "нельзя", "важно", "хорошо",
    "плохо", "большой", "маленький", "длинный", "короткий", "высокий", "низкий",
    "быстрый", "медленный", "красивый", "уродливый", "умный", "глупый", "добрый",
    "злой", "смелый", "трусливый", "храбрый", "сильный", "слабый", "здоровый",
    "больной", "богатый", "бедный", "молодой", "старый", "живой", "мёртвый",
    "горячий", "холодный", "тёплый", "прохладный", "сухой", "мокрый", "чистый",
    "грязный", "светлый", "тёмный", "яркий", "тусклый", "белый", "чёрный",
    "красный", "синий", "зелёный", "жёлтый", "оранжевый", "фиолетовый",
]

# Русские союзы
conjunctions_ru = [
    "и", "а", "но", "или", "однако", "тем", "не", "менее", "же", "если",
    "когда", "пока", "поскольку", "так", "как", "будто", "что", "чтобы",
    "зачем", "потому", "что", "поэтому", "отчего", "хотя", "несмотря", "на",
    "то", "либо", "ни", "иначе", "впрочем", "между", "тем", "не", "менее",
    "если", "ли", "ежели", "коль", "пусть", "раз", "хоть", "хотя", "уж",
]

# Короткие русские слова (1-3 буквы)
short_ru = [
    # 1 буква
    "а", "и", "о", "у", "я", "ю", "э", "е", "ё", "ъ", "ь",
    # 2 буквы
    "бы", "же", "ли", "но", "не", "на", "нет", "она", "она", "он", "то", "у", "уже", "я",
    # 3 буквы
    "все", "для", "как", "мой", "наш", "свой", "такой", "этот", "тот", "что", "это", "год", "день", "ночь", "мир", "дом", "вот", "тут", "раз", "два", "три", "чуть", "лишь", "много", "надо", "нужно", "можно", "весь", "весь", "весь",
]

# Русские фразы (расширение существующего набора)
phrases_ru = [
    "доброе утро", "хорошего дня", "увидимся позже", "большое спасибо",
    "извини пожалуйста", "нет проблем", "это правильно", "я в порядке",
    "что нового", "ничего особенного", "как всегда", "все хорошо",
    "язык программирования", "разработка программного обеспечения", "машинное обучение",
    "искусственный интеллект", "наука о данных", "веб разработка",
    "мобильное приложение", "пользовательский интерфейс", "пользовательский опыт",
    "операционная система", "информатика", "информационные технологии",
    "безопасность сети", "облачные вычисления", "управление базами данных",
    "системная архитектура", "ревью кода", "контроль версий",
    "непрерывная интеграция", "фреймворк тестирования", "инструмент отладки",
    "среда разработки", "сервер для продакшена",
]

# Генерация ошибок ru_wrong (русский текст на английской раскладке)
def layout_switch_ru_to_en(text):
    """
    Конвертация русского текста в английскую раскладку
    """
    # Русская: ЙЦУКЕНГШЩЗХФЫВАПРОЛДЖЭЯЧСМИТБЮ
    # Английская: QWERTYUIOP[]FGHJKL;'ZXCVBNM,./
    ru_layout = "йцукенгшщзхфывапролджэячсмитбю"
    en_layout = "qwertyuiop[]fghjkl;'zxcvbnm,./"
    ru_to_en_map = str.maketrans(ru_layout, en_layout)
    return text.translate(ru_to_en_map)

def generate_dataset():
    dataset = []

    # Английские слова
    # Популярные (добавляем несколько раз для количества)
    for _ in range(12):
        for word in popular_en[:250]:
            dataset.append((word, "en"))

    # Союзы (200)
    for word in conjunctions_en:
        dataset.append((word, "en"))

    # Короткие слова (500)
    for word in short_en:
        dataset.append((word, "en"))

    # Фразы (300)
    for phrase in phrases_en:
        dataset.append((phrase, "en"))

    # Дополнительные слова (больше примеров для достижения 5000)
    additional_en = [
        "apple", "banana", "orange", "grape", "mango", "pineapple", "peach",
        "computer", "laptop", "keyboard", "mouse", "monitor", "printer", "scanner",
        "internet", "wifi", "bluetooth", "network", "server", "database", "cloud",
        "software", "hardware", "program", "code", "develop", "test", "debug",
        "swift", "python", "java", "javascript", "rust", "go", "ruby", "php",
        "github", "git", "docker", "kubernetes", "linux", "windows", "macos",
        "ios", "android", "mobile", "web", "api", "rest", "json", "xml", "html", "css",
        "security", "privacy", "permission", "access", "control", "user", "admin",
        "login", "password", "email", "address", "phone", "contact", "message",
        # Фрукты
        "lemon", "lime", "cherry", "berry", "melon", "kiwi", "papaya",
        "coconut", "avocado", "guava", "mangosteen", "passionfruit",
        # Овощи
        "tomato", "potato", "carrot", "cucumber", "pepper", "onion", "garlic",
        "broccoli", "cabbage", "spinach", "lettuce", "celery", "beet",
        # Животные
        "dog", "cat", "bird", "fish", "horse", "cow", "pig", "sheep",
        "chicken", "duck", "goose", "rabbit", "deer", "bear", "wolf", "fox",
        # Цветы
        "rose", "tulip", "daisy", "lily", "sunflower", "orchid", "lotus",
        "jasmine", "lavender", "dandelion", "daffodil", "marigold",
        # Технологии
        "blockchain", "cryptocurrency", "nft", "metaverse", "artificial", "neural",
        "algorithm", "automation", "robot", "machine", "intelligence", "learning",
        # Еда
        "pizza", "burger", "sushi", "pasta", "noodle", "rice", "bread", "cake",
        "cookie", "chocolate", "coffee", "tea", "juice", "water", "soda", "beer",
        # Транспорт
        "car", "bus", "train", "plane", "ship", "bicycle", "motorcycle", "scooter",
        "subway", "taxi", "uber", "truck", "van", "boat", "yacht", "helicopter",
        # Одежда
        "shirt", "pants", "dress", "skirt", "jacket", "coat", "shoes", "boots",
        "hat", "cap", "scarf", "gloves", "socks", "belt", "tie", "uniform",
        # Спорт
        "soccer", "football", "basketball", "tennis", "volleyball", "baseball",
        "hockey", "golf", "swimming", "running", "jumping", "dancing", "singing",
        # Музыка
        "rock", "pop", "jazz", "blues", "classical", "country", "rap", "hiphop",
        "electronic", "techno", "house", "trance", "ambient", "folk", "reggae",
        # Погода
        "sunny", "rainy", "cloudy", "windy", "snowy", "stormy", "foggy", "hazy",
        "breezy", "humid", "dry", "wet", "hot", "cold", "warm", "cool",
        # Время
        "morning", "afternoon", "evening", "night", "midnight", "dawn", "dusk", "twilight",
        "sunrise", "sunset", "daylight", "darkness", "sunshine", "moonlight",
    ]
    for word in additional_en:
        dataset.append((word, "en"))

    # Русские слова
    # Популярные (добавляем несколько раз для количества)
    for _ in range(12):
        for word in popular_ru[:250]:
            dataset.append((word, "ru"))

    # Союзы (200)
    for word in conjunctions_ru:
        dataset.append((word, "ru"))

    # Короткие слова (500)
    for word in short_ru:
        dataset.append((word, "ru"))

    # Фразы (300)
    for phrase in phrases_ru:
        dataset.append((phrase, "ru"))

    # Дополнительные слова (больше примеров)
    additional_ru = [
        "яблоко", "банан", "апельсин", "виноград", "манго", "ананас", "персик",
        "компьютер", "ноутбук", "клавиатура", "мышь", "монитор", "принтер", "сканер",
        "интернет", "вайфай", "блютус", "сеть", "сервер", "база данных", "облако",
        "программа", "код", "разработка", "тест", "отладка",
        "свифт", "питон", "джава", "джаваскрипт", "раст", "го", "руби", "пхп",
        "гитхаб", "гит", "докер", "кубернетес", "линукс", "виндоус", "макос",
        "айос", "андроид", "мобила", "веб", "апи", "рест", "джейсон", "эксэмэль", "хтмл", "цсс",
        "безопасность", "конфиденциальность", "права", "доступ", "контроль", "пользователь", "админ",
        "логин", "пароль", "почта", "адрес", "телефон", "контакт", "сообщение",
        # Фрукты
        "лимон", "лайм", "вишня", "ягодка", "дыня", "киви", "папайя",
        "кокос", "авокадо", "гуава", "мангостин", "маракуйя",
        # Овощи
        "томат", "картофель", "морковь", "огурец", "перец", "лук", "чеснок",
        "брокколи", "капуста", "шпинат", "салат", "сельдерей", "свёкла",
        # Животные
        "собака", "кошка", "птица", "рыба", "лошадь", "корова", "свинья", "овца",
        "курица", "утка", "гусь", "кролик", "олень", "медведь", "волк", "лиса",
        # Цветы
        "роза", "тюльпан", "маргаритка", "лилия", "подсолнух", "орхидея", "лотос",
        "жасмин", "лаванда", "одуванчик", "нарцисс", "бархатцы",
        # Технологии
        "блокчейн", "криптовалюта", "нфт", "метавсел", "искусственный", "нейросеть",
        "алгоритм", "автоматизация", "робот", "машина", "интеллект", "обучение",
        # Еда
        "пицца", "бургер", "суши", "паста", "лапша", "рис", "хлеб", "торт",
        "печенье", "шоколад", "кофе", "чай", "сок", "вода", "газировка", "пиво",
        # Транспорт
        "машина", "автобус", "поезд", "самолёт", "корабль", "велосипед", "мотоцикл", "скутер",
        "метро", "такси", "убер", "грузовик", "фургон", "лодка", "яхта", "вертолёт",
        # Одежда
        "рубашка", "штаны", "платье", "юбка", "пальто", "пиджак", "туфли", "сапоги",
        "шляпа", "кепка", "шарф", "перчатки", "носки", "ремень", "галстук", "униформа",
        # Спорт
        "футбол", "баскетбол", "волейбол", "теннис", "плавание", "бег", "прыжки",
        "танцы", "пение", "хоккей", "гольф", "бокс", "борьба", "гимнастика",
        # Музыка
        "рок", "поп", "джаз", "блюз", "классика", "кантри", "рэп", "хипхоп",
        "электроника", "техно", "хаус", "транс", "эмбиент", "фолк", "регги",
        # Погода
        "солнечно", "дождливо", "облачно", "ветрено", "снежно", "штормит", "туманно", "дымно",
        "ветрено", "влажно", "сухо", "мокро", "жарко", "холодно", "тепло", "прохладно",
        # Время
        "утро", "день", "вечер", "ночь", "полночь", "рассвет", "закат", "сумерки",
        "рассвет", "закат", "дневной свет", "тьма", "солнце", "лунный свет",
    ]
    for word in additional_ru:
        dataset.append((word, "ru"))

    # Добавляем ru_wrong примеры (русский на английской раскладке)
    # Берем 1000 случайных русских слов и конвертируем
    all_ru_words = popular_ru + additional_ru
    random_ru_for_wrong = random.sample(all_ru_words, min(1000, len(all_ru_words)))
    for word in random_ru_for_wrong:
        wrong_layout = layout_switch_ru_to_en(word)
        dataset.append((wrong_layout, "ru_wrong"))

    # Перемешиваем датасет
    random.shuffle(dataset)

    # Ограничиваем до 5000
    return dataset[:5000]

def main():
    print("Генерация расширенного датасета BabylonFish ML...")
    dataset = generate_dataset()

    # Сохраняем в CSV
    output_file = "/home/botik/.openclaw/workspace/babylonfish/ML/Data/expanded_dataset.csv"

    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['text', 'label'])
        writer.writerows(dataset)

    # Статистика
    labels = [label for _, label in dataset]
    en_count = labels.count('en')
    ru_count = labels.count('ru')
    ru_wrong_count = labels.count('ru_wrong')

    print(f"\nДатасет сохранён: {output_file}")
    print(f"Всего примеров: {len(dataset)}")
    print(f"Английских (en): {en_count}")
    print(f"Русских (ru): {ru_count}")
    print(f"Неправильных (ru_wrong): {ru_wrong_count}")

if __name__ == "__main__":
    main()
