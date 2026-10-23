---
name: crm-yclients-import
description: Import YCLIENTS exports into the VetPetCare CRM safely — dry run, apply, card normalization, workspace projections, legacy JSON import — with privacy rules for client data. Use for «импортируй YClients», «загрузи выгрузку», «обнови аналитику рабочего пространства», «перенеси старые данные». Real exports only on the owner's explicit instruction.
---

# Импорт из YClients

Выгрузки содержат персональные данные клиентов. Работай только с каталогом, который владелец
явно назвал для этой задачи. Не копируй выгрузки в репозиторий, чат, issue или логи.

## Порядок

```sh
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# 0. Свежий бэкап базы (docs/deploy/README.md) — импорт не удаляет, но добавляет много строк.
# 1. Пробный прогон: ничего не пишет, печатает только счётчики и id записей YCLIENTS.
DIRS=/abs/private/export-2026-10 bin/rails yclients:import_calendar
# 2. Покажи владельцу счётчики: new / existing / skipped с причинами. Применяй после его «да».
DIRS=/abs/private/export-2026-10 APPLY=1 bin/rails yclients:import_calendar
# 3. Карточки в формат рабочего пространства (идемпотентно).
bin/rails yclients:normalize_cards && APPLY=1 bin/rails yclients:normalize_cards
# 4. Аналитика рабочего пространства.
bin/rails full_crm:projections                     # покажет absent/same/differs
APPLY=1 REPLACE=1 bin/rails full_crm:projections   # REPLACE только если владелец согласен заменить
```

Несколько выгрузок с перекрытием: `DIRS=dir1,dir2` — побеждает более свежая копия записи.

## Что гарантирует импорт

- Только вставка. Строки, изменённые в CRM, не перезаписываются; удалённые в CRM не возвращаются.
- Идентификаторы детерминированные (`CryptoHelpers.legacy_id`): повтор не создаёт дублей.
- Записи без клиента становятся перерывами врача; посетители без карты пропускаются (`client_without_yclients_card`).
- Пересечения с активными приёмами пропускаются (`overlaps_active_appointment`): база не допускает двойной записи.
- Исторические суммы — стоимость услуг, не оплата: в журнал оплат CRM не попадают.

## Причины пропуска (для отчёта владельцу)

`invalid_time`, `unknown_doctor` (врача нет в справочнике CRM — сначала добавить), `removed_in_crm`,
`cancelled_for_unknown_client`, `patient_removed_in_crm`, `overlaps_active_appointment`,
`overlaps_existing_shift`, `client_without_yclients_card`. По `skippedRecordIds` владелец находит записи в YCLIENTS.

## Старая локальная JSON-база

`SOURCE=/abs/private/dir bin/rails legacy:import` (пробный), затем `APPLY=1` — только в пустую базу.
Готовые документы рабочего пространства: `SOURCE=… bin/rails full_crm:import_documents [APPLY=1]`.

## Чего не делать

- Не запускай `yclients-export-*.ps1` и авторизацию в YClients без отдельного поручения.
- Не сливай клиентов по совпадению телефона или имени: только кандидаты, решение за человеком.
- Не публикуй вывод с именами и телефонами: команды печатают только счётчики, так и оставь.
