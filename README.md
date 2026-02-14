# BabylonFish 3.0

Mac-приложение для автоматического переключения раскладки клавиатуры с исправлением опечаток и анализом контекста.

## Основные возможности

- **Автоматическое переключение раскладки** - определяет язык набранного текста и переключает раскладку
- **Исправление опечаток** - исправляет опечатки в реальном времени
- **Автодополнение** - предлагает варианты завершения слов
- **Нейросетевое определение языка** - использует ML-модель для точного определения языка
- **Анализ контекста** - учитывает контекст для более точных исправлений

## Установка

```bash
./install.sh
```

## Документация

Вся документация находится в папке [docs/](docs/):

- [AGENTS.md](docs/AGENTS.md) - описание агентов и их ролей
- [ARCHITECTURE_V2.md](docs/ARCHITECTURE_V2.md) - архитектура проекта
- [BUILD_REPORT.md](docs/BUILD_REPORT.md) - отчет о сборке
- [CHANGELOG_v3.0.61.md](docs/CHANGELOG_v3.0.61.md) - история изменений
- [DATASET_UPDATE_REPORT.md](docs/DATASET_UPDATE_REPORT.md) - отчет об обновлении датасета
- [FIX_REPORT.md](docs/FIX_REPORT.md) - отчет об исправлениях
- [FIX_SUMMARY.md](docs/FIX_SUMMARY.md) - сводка исправлений
- [TESTING.md](docs/TESTING.md) - тестирование
- [TESTING_CHECKLIST.md](docs/TESTING_CHECKLIST.md) - чеклист тестирования
- [TESTING_PERMISSIONS.md](docs/TESTING_PERMISSIONS.md) - тестирование прав доступа
- [TRAINING_PLAN.md](docs/TRAINING_PLAN.md) - план обучения ML-модели
- [test_babylonfish3_final.md](docs/test_babylonfish3_final.md) - финальный тестовый отчет

## Структура проекта

```
babylonfish/
├── Sources/BabylonFish3/     # Исходный код приложения
├── ML/                       # ML-модели и датасеты
├── docs/                     # Документация
├── Resources/                # Ресурсы (иконки)
├── build/                    # Собранные бинарники
└── scripts/                  # Скрипты сборки и установки
```

## Скрипты

- `build.sh` - основной скрипт сборки
- `install.sh` - установка приложения
- `fix_permissions_safe.sh` - безопасное исправление прав (с защитой от зависаний)
- `uninstall_app.sh` - удаление приложения

## Лицензия

MIT