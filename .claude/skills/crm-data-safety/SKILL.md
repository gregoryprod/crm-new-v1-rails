---
name: crm-data-safety
description: Guard client personal data and secrets in the VetPetCare CRM — logging rules, error messages, test data, git hygiene, env and Kamal secrets, review checklist for PII leaks. Use before committing, when adding logs, errors, exports, new fields with personal data, or when asked «проверь, что не утекут данные», «безопасно ли», «нет ли ПДн в логах».
---

# Безопасность данных CRM

CRM хранит ФИО, телефоны, сведения о питомцах, согласия и оплаты. Правило: персональные данные
живут только в базе и на экранах сотрудников. Они не попадают в логи, ошибки, Git, issue, чат и CI.

## Чек-лист изменения

- [ ] Логи только через `LogEvent.info/warn/error`: идентификаторы, флаги, счётчики, класс ошибки и SQLSTATE. Никаких `error.message`, `params`, тел запросов.
- [ ] `config.filter_parameters` фильтрует всё (`/.*/`) — не сужай.
- [ ] Ответ об ошибке содержит код (`invalid_request`) и имена полей, но не введённые значения.
- [ ] Импорты печатают только счётчики и внешние id. Ошибки источника — с именем файла, без содержимого (`Yclients::SourceError`).
- [ ] Токены и пароли: в БД только хэши (`token_hash`, HMAC, argon2), сам токен — в cookie или ответе один раз. Токен Telegram вырезается из ошибок (`TelegramChannel.redact`).
- [ ] Новое поле с ПДн: нужно ли оно в JSON-ответе? В аудит пишем только то, что нужно для истории.
- [ ] Тесты и фикстуры — синтетические (`example.test`, телефоны +7999…), создаются тестом.
- [ ] URL и параметры запросов без ПДн (`page_url` хранится без query и fragment; путь, похожий на телефон или почту, обрезается до `/`).

## Перед коммитом

```sh
git status --short                         # нет .env, private/, export/, *.csv, *.xlsx, дампов
python3 scripts/check-repository-data.py   # индекс не содержит игнорируемых данных
git diff --cached | grep -nE '\+7[0-9]{10}|@[a-z0-9-]+\.(ru|com)' || true   # глазами проверь совпадения
```

`.env` и `.kamal/*.env` игнорируются. `.kamal/secrets` хранит только ссылки `$VAR`. В Git не должно
быть значений секретов, даже тестовых для production.

## Секреты на сервере

Через переменные окружения машины выкатки или менеджер паролей → Kamal. `AUTH_SECRET` нельзя менять
после запуска: от него зависят хэши сессий, лимитов и чеки записи.

## Если утечка уже случилась

Остановись и сообщи владельцу: что, где, с какого времени. Не переписывай историю Git сам
(force push только по прямой просьбе). Секрет — перевыпустить.
