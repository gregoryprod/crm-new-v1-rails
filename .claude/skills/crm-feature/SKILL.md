---
name: crm-feature
description: Implement a feature or fix in the VetPetCare CRM (Rails 8) end to end — service in app/services, controller and route, ERB/Turbo page or JSON endpoint, Minitest on real PostgreSQL, checks and commit. Use for any change to CRM behaviour: «добавь функцию в CRM», «сделай экран», «новый эндпоинт», «доработай заявки/расписание/оплаты», a GitHub issue of vpc-crm.
---

# Новая функция в CRM VetPetCare

Перед началом прочитай `docs/development/rails-guide.md` (правила проекта) и `docs/product/PRD.md`
(что уже есть). Если не уверен в API или соглашении Rails — skill `rails-guides` (официальное руководство
нашей версии, нужный раздел); тесты — по skill `rails-testing`. Требования — из ТЗ v1 и issue; не добавляй то, чего там нет.

## 1. Определи границы

- Требование: номер FR/AC в `ТЗ CRM VetPetCare v1.md` или пункт issue. Если его нет — спроси владельца, не придумывай.
- Где живёт логика: найди сервис в `app/services/<область>` (`leads`, `calendar`, `booking`, `clients`, `full_crm`, `notifications`, `yclients`). Новая область — новая папка-модуль.
- Меняется ли схема БД? Да → сначала skill `crm-schema-change`.
- Меняется ли HTTP-контракт (`/api/...`)? Квиз сайта и `public/full-crm` зависят от него: изменения только обратно совместимые и с явным согласованием.

## 2. Сервис

- Модуль с `module_function` в `app/services/<область>/<имя>.rb`; один файл — одна константа (Zeitwerk).
- Каждая команда — одна `ActiveRecord::Base.transaction`. Внутри: блокировка → проверка → запись → `AuditLog.write!`.
- Расписание: всегда `Calendar::Service.lock_calendar` до проверки окна. Не проверяй доступность вне блокировки.
- Повторы: принимай `operationId`/ключ идемпотентности, сохраняй результат, повтор с тем же id и другими данными → 409.
- Ошибки предметной области — свой класс в отдельном файле (`<область>/error.rb`) со `status` и `code`.
- Время: хранить UTC, считать в `+03:00`, показывать в `AppEnv.server.crm_time_zone`.
- Колонку `hash` пиши только через `raw_insert_all`, читай через `content_hash_of`.

## 3. HTTP

- JSON: контроллер в `app/controllers/api/`, наследник `ApiController`. Используй `require_staff`, `require_same_origin!` для изменений, `read_json_body(лимит)`, `render_json` / `render_error`. Коды ошибок — строки snake_case.
- Страница: контроллер-наследник `ApplicationController`, `require_page_role`, ERB во `app/views/<контроллер>/`. Действия — `form_with` (CSRF-токен Rails), ответ — `redirect_to … status: :see_other` с `flash[:notice]`/`[:alert]`.
- Маршрут в `config/routes.rb` рядом с соседями.
- Без собственного JavaScript. Нужна интерактивность — параметры в URL, формы, Turbo.

## 4. Тесты

- `test/integration/*_test.rb` для HTTP и страниц, `test/services/*_test.rb` для модулей.
- Данные только синтетические: `test/support/factory.rb` (`staff`, `lead_body`, `doctor_with_service`, `shift`, `client_with_patient`).
- Покрой: успех, отказ прав (401/403), неверный ввод (400 с именами полей), конфликт версии (409), повтор операции, аудит.
- Конкурентные и денежные сценарии проверяй против ограничений БД, не моков.

## 5. Проверки и коммит

Запусти skill `crm-verify`. Затем:

```sh
git add -A && python3 scripts/check-repository-data.py
git commit -m "Add <что>"        # английский, глагол в начале, до 72 символов
```

Обнови `docs/product/PRD.md` (таблица «Что реализовано»), если появилась новая возможность.
Push, PR, merge и выкатка — по правилам AGENTS.md (merge и production только по команде владельца).
