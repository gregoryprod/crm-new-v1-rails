# Разработка CRM на Ruby on Rails

Практическое руководство для агентов и разработчиков. Общие правила процесса — в
[AGENTS.md](../../AGENTS.md) и [workflow](workflow.md). Решение о стеке — в
[ADR 0003](decisions/0003-rails-and-kamal.md).

## Стек

| Часть | Что используем |
|---|---|
| Язык и фреймворк | Ruby 3.4 (`.ruby-version`), Rails 8.1 |
| База | PostgreSQL 17 (локально допустима 14+), схема в `db/structure.sql` |
| Интерфейс | ERB-шаблоны, Hotwire Turbo (формы и ссылки без перезагрузки), Propshaft, importmap |
| Пароли | argon2id (`argon2`), совместимо с хэшами прежней версии |
| Телефоны | `phonelib` (метаданные libphonenumber), E.164, регион по умолчанию RU |
| Фоновая работа | таблица `outbox` + процесс `bin/rails notifications:work` (роль `worker` в Kamal) |
| Деплой | Kamal 2, kamal-proxy (SSL), Thruster, локальный registry |
| Тесты | Minitest на реальной PostgreSQL, без моков базы |

Своего JavaScript нет. Исключения: `public/full-crm` (готовое приложение рабочего пространства,
в очереди на перевод на Rails) и `docs/quiz/lead-snippet.js` (код квиза для чужого сайта).

## Карта кода

```text
app/
  controllers/
    api_controller.rb          база JSON API: no-store, коды ошибок, лимит тела, Origin, require_staff
    api/…                      JSON API (тот же контракт, что был в Next.js)
    application_controller.rb  база страниц: require_page_role, CSRF-токены Rails, flash
    calendar_controller.rb     расписание на формах: каждое действие → Calendar::Service.execute
    leads_controller.rb, clients_controller.rb, pages_controller.rb, quiz_controller.rb, sessions_controller.rb
  services/                    вся бизнес-логика; контроллеры только разбирают вход и рисуют ответ
    app_env.rb                 проверка переменных окружения (как zod-схемы раньше)
    leads/   payload, intake (транзакция приёма), throttle (лимиты), staff (список/карточка/правка)
    calendar/ slots (окна), commands (схема команд), service (блокировка, команды, снимок)
    booking/ receipt (чек заявки), service (публичная запись)
    outbox.rb, notifications/  протокол доставки, Telegram, воркер
    full_crm/  рабочее пространство и проекции аналитики (порт analytics-model.mjs)
    yclients/, legacy/         импорты
    json.rb, crypto_helpers.rb, log_event.rb, phone.rb, text_rules.rb
  models/                      тонкие модели над существующими таблицами
  views/                       ERB; общие куски в views/shared
db/
  drizzle/*.sql                исходные миграции прежней версии (не менять)
  migrate/                     миграции Rails; первая — AdoptDrizzleSchema
  structure.sql                актуальная схема (генерируется, коммитится)
  seeds.rb                     служебные строки (idempotent)
lib/tasks/crm.rake             операционные команды
config/deploy.yml, .kamal/secrets   деплой
test/                          integration/ — HTTP и страницы, services/ — модули
```

## Правила проекта (обязательные)

1. **Логика — в `app/services`.** Контроллер: проверить доступ → разобрать вход → вызвать сервис → отрисовать. Так один сервис обслуживает и JSON API, и страницу.
2. **Контракт API не меняется без задачи.** Пути, коды, ключи JSON (camelCase), формат времени `2026-10-19T07:05:03.123Z` (`Json.iso`). Ответы рисуются через `render_json`, не `render json:`.
3. **Записи — в одной транзакции с аудитом.** `AuditLog.write!` внутри той же транзакции, что и изменение.
4. **Конкурентность решает PostgreSQL.** Календарь: `Calendar::Service.lock_calendar` (строка `calendar_state FOR UPDATE`) до проверки окна. Заявки: advisory lock на ключ и телефон. Окончательная защита — ограничения БД (`EXCLUDE`, `UNIQUE`). Не проверяй «свободно ли» вне блокировки.
5. **Идемпотентность.** Команды с `operationId`/`idempotency_key`; повтор возвращает сохранённый результат, иной запрос с тем же id → 409.
6. **Кэш запросов выключен.** `around_action { ActiveRecord::Base.uncached }` в обоих базовых контроллерах. Не включай его обратно: `UPDATE … RETURNING`, `FOR UPDATE` и `clock_timestamp()` должны каждый раз идти в базу. Ошибка проявляется как «одно событие отправлено 100 раз».
7. **Колонка `hash`.** В `calendar_operations`, `booking_operations`, `legacy_client_records`, `legacy_imports` она скрыта от ActiveRecord (`ignored_columns`): `hash` — зарезервированный метод Ruby. Писать через `Model.raw_insert_all`, читать через `Model.content_hash_of`.
8. **Время.** Хранение UTC, расчёты календаря — фиксированный `+03:00` (`Calendar::Slots::OFFSET`), показ — `CRM_TIME_ZONE`.
9. **ПДн и секреты.** Логи только через `LogEvent` (идентификаторы, флаги, класс ошибки и SQLSTATE). `filter_parameters` фильтрует все параметры. Сообщения ошибок, которые видит пользователь, не содержат введённых значений.
10. **Формы, а не JS.** Интерактив — обычные Rails-формы (`form_with`) и ссылки с параметрами состояния; Turbo делает их быстрыми. Своё JS добавляй только с обоснованием в задаче.

## Как добавить функцию

1. Найди требование в ТЗ (FR/AC) и задачу в GitHub/Beads.
2. Сервис в `app/services/<область>/`: чистые функции и одна транзакция на команду.
3. Если нужна схема — миграция (см. ниже), затем `bin/rails db:migrate` и коммит `db/structure.sql`.
4. Контроллер и маршрут (`config/routes.rb`): JSON — в `app/controllers/api`, страница — рядом с остальными.
5. Тесты: интеграционный на HTTP/странице и, при необходимости, на сервис. Реальная PostgreSQL, синтетические данные из `test/support/factory.rb`.
6. Проверки (раздел ниже), коммит, PR.

Подробный пошаговый сценарий — skill `crm-feature` (`.claude/skills/crm-feature/SKILL.md`).

## Миграции и схема

- Новая миграция: `bin/rails generate migration Name`, затем SQL-конструкции через `execute`, если нужны CHECK, составные ключи или частичные индексы.
- Схема только в SQL (`config.active_record.schema_format = :sql`); `schema.rb` не используем.
- Миграции обратимые, где возможно: `bin/kamal rollback` откатывает код, не базу.
- Новые служебные строки — в `db/seeds.rb`, идемпотентно (`ON CONFLICT DO NOTHING`).
- Никогда не редактируй `db/drizzle/*.sql`: их хэши записаны в журнал Drizzle существующих баз.

Скилл: `crm-schema-change`.

## Локальный запуск

```sh
rbenv install 3.4.5            # на Mac с Homebrew под Intel: arch -x86_64 rbenv install 3.4.5
bundle install
cp .env.example .env           # заполнить DATABASE_URL, TEST_DATABASE_URL, APP_ORIGIN, AUTH_SECRET…
bin/rails db:prepare           # схема + служебные строки
OWNER_EMAIL=… OWNER_NAME=… OWNER_PASSWORD=… bin/rails crm:seed_owner
bin/rails server -p 3200       # APP_ORIGIN=http://127.0.0.1:3200
```

Переменная `LANG=en_US.UTF-8` (или `C.UTF-8`) обязательна: без неё Ruby читает файлы как US-ASCII.

### Ловушка: фигурные скобки в пути

Рабочая папка клиента называется `{vpc}`. Для Ruby скобки — спецсимвол поиска по маске
(`Dir.glob`), поэтому в такой папке:

- миграции ищутся по относительному пути (`migrations_paths: db/migrate` в `database.yml`);
- код перезагружается на каждый запрос (`reload_classes_only_on_change = false` в development);
- Brakeman и похожие инструменты нужно запускать через символическую ссылку без скобок:
  `ln -s "$PWD" /tmp/vpc-crm && bin/brakeman -p /tmp/vpc-crm`.

В Docker (`/rails`) и CI проблемы нет.

## Проверки перед коммитом

```sh
bin/ci        # все проверки из config/ci.rb, ~15 секунд, итог по строке на шаг
# по запущенному серверу (локальному или тестовому):
APP_ORIGIN=… OWNER_EMAIL=… OWNER_PASSWORD=… LEADS_ALLOWED_ORIGINS=… node scripts/smoke-http.mjs
```

Скилл: `crm-verify`.

## Операционные команды

| Команда | Что делает |
|---|---|
| `bin/rails crm:seed_owner` | Создаёт OWNER из `OWNER_*`; существующего не трогает |
| `bin/rails notifications:work` (`ONCE=1`) | Доставка уведомлений из outbox в Telegram |
| `bin/rails yclients:import_calendar DIRS=… [APPLY=1]` | Импорт визитов, записей, смен; по умолчанию пробный прогон |
| `bin/rails yclients:normalize_cards [APPLY=1]` | Приводит импортированные карточки к формату рабочего пространства |
| `bin/rails full_crm:projections [CUTOFF=…] [APPLY=1 [REPLACE=1]]` | Пересобирает документы аналитики рабочего пространства |
| `bin/rails full_crm:import_documents SOURCE=… [APPLY=1]` | Однократный импорт готовых документов рабочего пространства |
| `bin/rails legacy:import SOURCE=… [APPLY=1]` | Импорт старой локальной JSON-базы в пустую БД |

Импорт реальных выгрузок — только по поручению владельца; скилл `crm-yclients-import`.
