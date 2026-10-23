# Решение 0001: стек каркаса и ORM

Статус: принято в задаче [#2](https://github.com/artemiyvladimirov-cmyk/vpc-crm/issues/2). Дата проверки источников: 2026-10-11.

## ORM: Drizzle

**Выбор: Drizzle ORM 0.45.4 + drizzle-kit 0.31.11, драйвер `pg` (node-postgres).** Prisma не выбрана.

Обоснование в одной строке: SQL-близкий тонкий слой без отдельного движка и генерации клиента, явные транзакции (`db.transaction(tx => …)`) для сценария «лид + клиент + животное + согласие + outbox + audit», `jsonb`, составные FK и CHECK в схеме, миграции — обычные SQL-файлы в `drizzle/`, которые читаются на ревью.

Детали:

- Миграции генерирует `npm run db:generate` (drizzle-kit) из `src/db/schema.ts`; применяет `npm run db:migrate` через `drizzle-orm/node-postgres/migrator` — без drizzle-kit в рантайме. Повторный запуск ничего не делает (журнал `drizzle.__drizzle_migrations`).
- Официальная страница [Drizzle + PostgreSQL](https://orm.drizzle.team/docs/get-started/postgresql-new) сейчас ставит `drizzle-orm@rc`/`drizzle-kit@rc` (1.0.0-rc). В npm `latest` = 0.45.4 (`npm view drizzle-orm dist-tags`). Для CRM с ПДн выбран стабильный `latest`; переход на 1.0 — отдельной задачей после GA с проверкой генерации миграций.
- Prisma допустима по архитектуре, но добавляет генерацию клиента/движок и отдельный DSL схемы; выигрыша для v0.1 нет.

## Версии (проверено `npm view <pkg> version` и официальной документацией)

| Пакет | Версия | Примечание |
|---|---|---|
| Node.js | 24 LTS (целевая, `.nvmrc`), 22 LTS поддерживается | [nodejs.org/previous-releases](https://nodejs.org/en/about/previous-releases): v24 Krypton и v22 Jod — LTS, v20 — EOL. `engines`: `^22.13.0 \|\| ^24.0.0` (минимум из vitest 5 и ESLint 10). CI проверяет обе. |
| next | 16.4.0 | [Installation](https://nextjs.org/docs/app/getting-started/installation) (docs 16.4.0): Node ≥ 20.9, TypeScript ≥ 5.1, `next build` больше не запускает линтер, ESLint вызывается напрямую. |
| react / react-dom | 19.3.0 | |
| typescript | 6.0.3 | `latest` = 7.0.2, но `typescript-eslint` 8.x (зависимость eslint-config-next) требует `typescript <6.1.0`. |
| eslint | 10.12.0 | [eslint.org/version-support](https://eslint.org/version-support): поддерживается только v10, v9 — EOL. eslint-config-next 16.4.0 тянет eslint-plugin-react/import/jsx-a11y с peer `eslint ≤ 9`; `npm ci` выдает предупреждения `ERESOLVE overriding peer dependency`, но устанавливает. Проверено файлом-пробником: правила `react-hooks/rules-of-hooks`, `react/jsx-key`, `@next/next/no-img-element` срабатывают. Если плагин сломается — откат на 9.39.5. |
| eslint-config-next | 16.4.0 | flat config: `core-web-vitals` + `typescript`. |
| drizzle-orm / drizzle-kit | 0.45.4 / 0.31.11 | см. выше. |
| pg / @types/pg | 8.23.1 | |
| zod | 4.6.5 | валидация env и тел запросов. |
| @node-rs/argon2 | 2.2.2 | argon2id, готовые бинарники для linux/darwin/win, без node-gyp. |
| vitest | 5.0.3 | Node `^22.12 \|\| ^24`. |
| tsx | 4.23.15 | запуск TS-скриптов migrate/seed. |

Все версии зафиксированы точно в `package.json` и `package-lock.json`.

## Сессии и защита входа

- Серверная таблица `sessions` (открытый вопрос 7 архитектуры): в cookie — случайный 256-битный токен, в БД — только HMAC-SHA256(AUTH_SECRET, token). Абсолютный срок `SESSION_TTL_HOURS` (12 ч), проверка по часам БД. Выход и деактивация пользователя отзывают сессии (`revoked_at`).
- Cookie: `HttpOnly`, `SameSite=Lax`, `Path=/`; для https-origin — `Secure` и префикс `__Host-`. http допустим только для loopback (`APP_ORIGIN` валидируется).
- CSRF: POST-маршруты требуют `Origin` == `APP_ORIGIN` (отсутствующий Origin отклоняется), вход — только `application/json`.
- Перебор: счетчики fixed-window в PostgreSQL (`login_throttle`), ключ — HMAC(email) и HMAC(IP), попытка учитывается атомарно **до** проверки пароля, поэтому параллельный залп не обходит лимит; состояние общее для инстансов и переживает рестарт. IP учитывается только при `TRUST_PROXY=true`.
- Неверный пароль, неизвестный email и неактивный пользователь дают одинаковый ответ 401; для неизвестного email выполняется фиктивная проверка argon2.

## PostgreSQL

Compose и CI — PostgreSQL 17 (требование 16+). Локально дополнительно проверено на отдельной тестовой PostgreSQL 14.19 (совместимость: `gen_random_uuid()` встроена с 13).
