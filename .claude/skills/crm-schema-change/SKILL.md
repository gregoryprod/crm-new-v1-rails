---
name: crm-schema-change
description: Change the VetPetCare CRM PostgreSQL schema safely in Rails — migration with SQL constraints, db/structure.sql, seeds, reversible and additive steps, compatibility with databases migrated by the old Node app. Use when a task needs a new table, column, index, enum value or constraint: «добавь поле», «новая таблица», «миграция», «измени схему».
---

# Изменение схемы БД

Схема живёт в `db/structure.sql` (SQL-формат, не `schema.rb`): только так сохраняются CHECK,
составные внешние ключи, частичные индексы и `EXCLUDE` против двойной записи.

## Правила

1. **Никогда не меняй `db/drizzle/*.sql` и миграцию `AdoptDrizzleSchema`.** Их хэши записаны в журнал существующих баз.
2. **Аддитивно.** Сначала добавляй (колонка с default/NULL, новая таблица), код переводи отдельным шагом, удаляй старое отдельной выкаткой. `bin/kamal rollback` возвращает код, но не базу.
3. **Ограничения — в базе.** Деньги `integer` в копейках с CHECK, статусы — CHECK `IN (...)` или PostgreSQL enum, связи — FK с `ON DELETE RESTRICT`, время — `timestamptz`.
4. **Не называй колонку `hash`, `type`, `class`, `id` (кроме PK), `attributes`.** Если имя занято наследием — `ignored_columns` + `raw_insert_all`/`content_hash_of`, `inheritance_column = nil` для `type`.
5. **Служебные строки** (одиночные записи настроек) — в `db/seeds.rb`, идемпотентно.
6. **ПДн**: новые поля с персональными данными не попадают в `LogEvent`, в JSON-ответы только по необходимости.

## Шаги

```sh
bin/rails generate migration AddXToY
# в миграции: add_column / create_table + execute для CHECK и составных ключей; def down там, где возможно
LANG=en_US.UTF-8 bin/rails db:migrate          # обновит db/structure.sql
bin/rails db:test:prepare test
git diff db/structure.sql                       # проверь: только твои изменения
```

Enum PostgreSQL: `execute "ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'SPECIALIST'"` (вне транзакции:
`disable_ddl_transaction!`).

## Перед выкаткой

- Миграция выполняется автоматически в `bin/docker-entrypoint` (`db:prepare`). Долгие операции на больших
  таблицах (`CREATE INDEX` без `CONCURRENTLY`, перезапись таблицы) согласуй отдельно.
- Свежий бэкап и проверка восстановления — по `docs/deploy/README.md`.
- В CI шаг «Schema from scratch» проверяет, что `structure.sql` совпадает с миграциями.
