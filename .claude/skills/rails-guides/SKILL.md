---
name: rails-guides
description: Answer any "how is this done in Rails" question from the official Ruby on Rails guides of the exact Rails version in Gemfile.lock (8.1.x here) instead of memory — models, migrations, queries, associations, validations, controllers, routing, views and forms, Active Job, caching, security, configuration, autoloading, upgrades — fetching only the needed section to save tokens. Use before writing or reviewing Rails code when unsure of an API, option or convention: «как в Rails сделать…», «правильно ли по Rails», «какой метод миграции», «как настроить…», «что изменилось в Rails 8».
---

# Официальные руководства Rails под версию проекта

Источник — [github.com/rails/rails](https://github.com/rails/rails), папка `guides/source` на теге версии из
`Gemfile.lock`. Тексты руководств под лицензией CC BY-SA 4.0: в репозиторий их не копируем, читаем по запросу.

## Как читать (экономно)

```sh
ruby .claude/skills/rails-guides/scripts/guide.rb --index                     # все руководства версии
ruby .claude/skills/rails-guides/scripts/guide.rb active_record_querying       # оглавление с номерами строк
ruby .claude/skills/rails-guides/scripts/guide.rb active_record_querying "n + 1"   # только нужный раздел
```

Правила:
1. Сначала оглавление, потом **один** раздел. Целиком руководство не читай: они по 20–200 КБ.
2. Версию не угадывай: скрипт берёт её из `Gemfile.lock` (`RAILS_GUIDES_VERSION` — только для другой версии).
3. Точная сигнатура метода — в исходниках установленного гема, а не в руководстве:
   `bundle exec gem contents activerecord | grep <файл>` или `grep -rn "def <метод>" "$(bundle show activerecord)/lib"`.
4. Hotwire (Turbo, Stimulus) и Kamal живут не в rails/rails: README `turbo-rails` в `$(bundle show turbo-rails)`,
   документация Kamal — в `$(bundle show kamal)/lib/kamal/configuration/docs/` (skill `rails-kamal-deploy`).
5. Совет из блога или памяти расходится с руководством своей версии — прав официальный источник.

## Карта тем

| Задача | Руководство (`guide.rb <имя>`) | Ищи раздел |
|---|---|---|
| Модель, атрибуты, колбэки | `active_record_basics`, `active_record_callbacks` | CRUD, Callbacks |
| Миграция, индексы, ограничения | `active_record_migrations` | Using the change Method, Schema Dumping |
| Связи | `association_basics` | Types of Associations |
| Запросы, N+1, блокировки | `active_record_querying` | Eager Loading, strict_loading, Locking Records, in batches |
| Валидации | `active_record_validations` | Validations, Checking Validity |
| PostgreSQL: jsonb, enum, exclusion | `active_record_postgresql` | Datatypes, Exclusion Constraints |
| Контроллеры, параметры, cookies | `action_controller_overview`, `action_controller_advanced_topics` | Strong Parameters, Cookies, Controller Callbacks; `rescue_from`, Request Forgery Protection |
| Маршруты | `routing` | Resource Routing, Non-Resourceful Routes |
| Шаблоны и формы | `layouts_and_rendering`, `form_helpers` | Creating Forms with Model Objects |
| Фоновые задачи | `active_job_basics` | |
| Кэш | `caching_with_rails` | SQL Caching |
| Безопасность | `security` | CSRF, SQL Injection, Logging |
| Настройки | `configuring` | искать по имени настройки |
| Автозагрузка (Zeitwerk) | `autoloading_and_reloading_constants` | config.autoload_lib(ignore:), Eager Loading, Customizing Inflections |
| Тесты | `testing` | skill `rails-testing` |
| Производительность на сервере | `tuning_performance_for_deployment` | Puma, YJIT |
| Обновление Rails | `upgrading_ruby_on_rails`, `8_1_release_notes` | раздел нужной версии |

## Правила Rails, о которые чаще всего спотыкаются

- **Один файл — одна константа** (Zeitwerk): `app/services/booking/error.rb` → `Booking::Error`. Проверка: `bin/rails zeitwerk:check`.
- **Схема с ограничениями PostgreSQL** (CHECK, EXCLUDE, частичные индексы) — только в `db/structure.sql` (`config.active_record.schema_format = :sql`).
- **`return` внутри `transaction do`** коммитит транзакцию. Выходи через `next` или выноси логику в метод.
- **SQL только с плейсхолдерами**: `where("x = ?", v)`, `sanitize_sql_array`. Интерполяция значений — уязвимость.
- **N+1**: `includes`/`preload`, в разработке — `strict_loading`. Сначала посмотри SQL в логе.
- **Кэш запросов ActiveRecord** в рамках запроса возвращает старый результат того же SQL. Для `UPDATE … RETURNING`, `FOR UPDATE`, `clock_timestamp()` нужен `ActiveRecord::Base.uncached` (раздел SQL Caching руководства `caching_with_rails`).
- **Имена колонок `hash`, `type`, `class`, `attributes`** конфликтуют с методами Ruby или ActiveRecord: `ignored_columns` или `inheritance_column = nil`.
- **Параметры в логах**: `config.filter_parameters` — ПДн и секреты фильтруются там.
- **Редирект после формы** — `status: :see_other` (303): Turbo ждёт именно его после POST/PATCH/DELETE.

В проекте CRM эти правила уже применены. Подробности — `docs/development/rails-guide.md`.
