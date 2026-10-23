---
name: crm-deploy
description: Deploy or roll back the VetPetCare CRM with Kamal 2 — preflight gates, bin/kamal setup/deploy/rollback, backup and restore check, database transfer from the old Node version, post-deploy verification. Use when asked to «задеплой», «выкати», «откати», «kamal deploy», «перенеси базу на сервер», «проверь прод». Only on the owner's explicit command.
---

# Деплой CRM через Kamal

Полная инструкция: `docs/deploy/README.md`. Этот скилл — порядок действий и стоп-условия.

## Стоп-условия (не продолжай без явного «да» владельца)

- Нет прямой команды Артёма на выкатку в этом разговоре или задаче. Подготовка конфигурации ≠ разрешение.
- Перенос клиентской базы, первый приём живых заявок, включение воркера с настоящим ботом — каждое отдельно.
- CI не зелёный на коммите, который выкатываем.
- Нет свежего бэкапа (для обычной выкатки — последний ночной; для миграции схемы — снятый прямо сейчас).

## Перед выкаткой

```sh
git status --short                      # чисто
git log -1 --format=%H                  # этот SHA станет версией
bin/kamal config > /dev/null            # переменные KAMAL_HOST, CRM_HOST и др. заданы
bin/rails db:test:prepare test          # или зелёный CI на этом SHA
```

Секреты только из переменных окружения или менеджера паролей (`.kamal/secrets` содержит ссылки
`$VAR`). Никогда не печатай значения в чат, логи и коммиты.

## Выкатка

| Случай | Команда |
|---|---|
| Первый раз на сервер | `bin/kamal setup` |
| Обычная | `bin/kamal deploy` |
| Только перезапуск | `bin/kamal app boot` |
| Откат кода | `bin/kamal rollback <SHA>` (база не откатывается) |
| Воркер уведомлений | роль `worker`, логи `bin/kamal app logs -r worker` |

## После выкатки (проверь по живому адресу)

```sh
curl -fsS https://$CRM_HOST/up
curl -fsS https://$CRM_HOST/api/health          # {"status":"ok","database":"up"}
bin/kamal app logs | tail -50                   # нет "level":"error"
```

- Вход сотрудника, список заявок, расписание открываются.
- Если менялась доставка уведомлений — статус последней заявки в карточке («Доставлено в Telegram»).
- HTTP-смоук `scripts/smoke-http.mjs` — только на стенде или с согласия владельца (создаёт синтетическую заявку).

## Перенос базы из Node-версии

Только с разрешения владельца, до приёма живых заявок: `pg_dump --format=custom` → `pg_restore` в
`vpc-crm-db` → `bin/kamal app boot`. Rails распознает схему (`AdoptDrizzleSchema`) и ничего не перепишет.
Затем `bin/rails full_crm:projections` (пробный), при различиях `APPLY=1`.

## Отчёт владельцу

Простыми словами: что выкатили (что изменилось для работы), всё ли открывается, есть ли риски, как
откатить. Без SHA и терминов, если он не просит.
