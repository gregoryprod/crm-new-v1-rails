---
name: crm-verify
description: Run the full verification of the VetPetCare CRM before a commit, PR or deploy — rubocop, zeitwerk, Minitest on PostgreSQL, Brakeman (via a brace-free path), repository data check, Kamal config, HTTP smoke against a running server, and parity with the old Node version. Use for «проверь», «прогони тесты», «готово ли к PR», «сверь с Node».
---

# Проверка CRM

Окружение: Ruby из `.ruby-version`, `LANG=en_US.UTF-8`, `TEST_DATABASE_URL` на отдельную тестовую базу
(её очищают тесты — никогда не указывай рабочую).

## Обязательный набор — одна команда

```sh
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bin/ci
```

`bin/ci` (шаги в `config/ci.rb`) прогоняет стиль, загрузку кода, аудит гемов и importmap, Brakeman
(через ссылку без фигурных скобок), тесты на PostgreSQL, проверку данных в Git и конфигурацию Kamal.
Вывод короткий: по строке ✅/❌ на шаг. Запускай целиком, а не отдельные команды — так меньше
вывода в контекст. Пока идёт работа над одной частью, гоняй только её тесты:
`bin/rails test test/integration/<файл>_test.rb`.

Упал шаг — запусти именно его команду из `config/ci.rb`, чтобы увидеть подробности.

## HTTP-смоук против запущенного сервера

```sh
APP_ORIGIN=http://127.0.0.1:3200 OWNER_EMAIL=<синтетический> OWNER_PASSWORD=<синтетический> \
LEADS_ALLOWED_ORIGINS=http://127.0.0.1:3200 node scripts/smoke-http.mjs
```

17 шагов `ok`. Это исходный тест Node-версии: он проверяет, что HTTP-контракт не сломан.

## Сверка с Node-версией (когда менялись импорт или аналитика)

1. Синтетическая выгрузка YClients (генератор пишет `raw/records.json`, `clients.json`, `staff_schedule.json`).
2. Две пустые базы через `bin/rails db:create db:migrate db:seed`, одинаковые врачи.
3. Rails: `DIRS=… APPLY=1 bin/rails yclients:import_calendar`; Node (эталон на `de8a6d3`):
   `./node_modules/.bin/tsx scripts/import-yclients-calendar.ts DIR --apply`.
4. Сравни md5 содержимого таблиц `clients`, `patients`, `appointments`, `doctor_services`,
   `calendar_intervals`, `legacy_client_records`, `audit_log` и `batchId` проекций при одном `CUTOFF`.

## Интерфейс

Если менялись страницы — открой их в браузере на синтетических данных: изменённый сценарий,
ошибка ввода, ширина 390 px без горизонтальной прокрутки. Скриншот — доказательство в PR.

## Отчёт

Перечисли команды и их итог (число тестов, предупреждения), что не проверено и почему. Не пиши
«всё работает» без вывода команд.
