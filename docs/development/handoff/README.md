# Переносимый пакет разработки CRM

Контракт передачи: [issue #13](https://github.com/artemiyvladimirov-cmyk/vpc-crm/issues/13), Beads `vpc-crm-qb2`. Дата снимка — **11.10.2026**. Пакет переносит инфраструктуру **разработки CRM**, требования и общую память; продуктовые функции v1 и production ещё предстоит реализовать.

[Результат проверки чистого клона](verification.md) подтверждает восстановление Beads и приложения без копирования локального runtime. Актуальные head/CI/review пакета находятся в PR #14 и checkpoint issue #13.

## Что готово и где проверить

| Результат | Где находится | Стадия на дату снимка |
|---|---|---|
| Защита выгрузок и синтетические проверки | экспортные скрипты, `.gitignore`, `tests/`, PR #5 | MERGED, issue #1 closed |
| Правила общей работы и контекст | `AGENTS.md`, `CLAUDE.md`, `docs/development/workflow.md`, issue #7, PR #9 | MERGED |
| Агентская очередь Beads и перенос через GitHub | `scripts/beads.py`, `scripts/install-beads.py`, `.beads/`, `refs/dolt/data`, PR #11 | MERGED, issue #10 closed |
| Приложение и БД, вход, роли ADMIN/OWNER, аудит, outbox-таблица, Docker, CI | `src/`, `drizzle/`, `compose.yaml`, `.github/workflows/`, PR #6 | MERGED, issue #2 closed |
| Приём квиза, идемпотентность, согласия, кандидаты в дубли, лимиты; список/карточка/правки лидов | PR #12, `docs/quiz/`, `src/modules/leads/` | OPEN, issue #3 / `vpc-crm-t90` review |
| Доставка уведомлений и retry | issue #4 / `vpc-crm-17k` | blocked до принятого merge #3 |
| Дизайн VetPetCare и полная CRM v1 | исходное ТЗ, [дизайн](design-reference.md), [этапы](v1-delivery.md), [команда](team.json) | цель согласована; реализация v1 и перенос дизайна в UI не начаты |

На этой стадии карточки владельца и питомца используются в сценарии лида; это ещё не полноценные клиентские карточки CRM v1. Outbox записывается транзакционно, но его доставка не реализована. Роль специалиста, расписание, записи, платежи, анкеты, чат, выписки, поддержка и импорт реальных данных не готовы.

`main` при подготовке пакета: `57b395c5062bda96fb84abf6ea6c3efa40c82ee8`. Проверенный head PR #12: `99679040ca3b10841be2a2e5ae4e62c06ded3d27`. [CI PR #12](https://github.com/artemiyvladimirov-cmyk/vpc-crm/actions/runs/38153079251): все 10 checks успешны. [Независимое ревью Codex](https://github.com/artemiyvladimirov-cmyk/vpc-crm/pull/12#issuecomment-6110864720) относится к этому SHA. Локально проверены 154 TS-теста, 11 Python-тестов, typecheck/lint/build, HTTP-сценарий и UI 1440/390. Это доказательства PR #12, а не автоматическая проверка твоего окружения или GitHub approval. Наличие workflow не доказывает включённую branch protection.

## Источники, которые должен прочитать новый агент

1. [HANDOFF.md](../../../HANDOFF.md), [AGENTS.md](../../../AGENTS.md), [README](../../../README.md), [workflow](../workflow.md).
2. [Контекст #7](https://github.com/artemiyvladimirov-cmyk/vpc-crm/issues/7) и **последние комментарии** выбранного issue/PR. `gh issue view 7 --repo artemiyvladimirov-cmyk/vpc-crm --comments`; аналогично #3/#4/#13. Для JSON явно добавь `comments` к `--json`.
3. [Архитектура квиза](../../../Архитектура%20CRM%20—%20сбор%20лидов%20из%20квиза.md), [контракт v0.1](../../../Промпт%20—%20сбор%20лидов%20из%20квиза.md), [ТЗ CRM v1](../../../ТЗ%20CRM%20VetPetCare%20v1.md). При расхождениях с исходным путём клиента приоритет у ТЗ v1. `[ДОП]`, `[РЕК]`, открытые вопросы остаются такими.
4. [Beads](../beads.md), задачи по `external_ref` после восстановления remote, CI текущего SHA. [state.json](state.json) — карта источников и датированный снимок; [team.json](team.json) — согласованные роли без автоматического запуска.

## Доступы и инструменты

| Что нужно | Как получить / проверить |
|---|---|
| Приватный `artemiyvladimirov-cmyk/vpc-crm` | Личный доступ Артёма; `gh auth status`, `gh repo view artemiyvladimirov-cmyk/vpc-crm` |
| Node/npm, Python 3, Git, Docker | Node 24 LTS либо 22 ≥ 22.13; версии зависимостей закреплены lockfile; PG 17 в compose |
| Beads | Локальный installer 1.3.0; Mac arm64/x86_64 и Linux aarch64/x86_64. Нативный Windows этим installer не покрыт; используй Linux/WSL-окружение с Git/Docker/gh |
| Dolt CLI для Git transport | Проверена версия 2.2.2; установи официальный бинарник этой версии. Embedded engine включён в bd; отдельный Dolt SQL-server не нужен |
| Приватная доска `gregoryprod/projects/1` | Отдельное приглашение владельца доски; право на репозиторий не даёт право на Project. Для CLI изменения нужен scope `project` у собственного gh-token |
| GPT-6.1-Sol / GPT-6-Luna, Claude Code | Личный вход/доступ в среде Артёма; названия в team.json не устанавливают модели и не выдают API-ключи |
| Дизайн `gregoryprod/vetpetcare/landing` | В пакет включены токены и pinned provenance. Для исходных шрифтов/ассетов и дальнейшей сверки понадобится доступ к этому репозиторию |

Если доска недоступна, восстанови Issues и Beads; отметь отсутствие доступа к Project и не объявляй его статусы сверенными. Не создавай заменяющую доску автоматически. Передача не меняет доступы и не устанавливает глобальные hooks.

## Восстановить Beads на новом клоне

Находясь в корне **CRM**, установи Dolt CLI 2.2.2 и проверь `dolt version`. Затем:

```sh
python3 scripts/install-beads.py
chmod 700 .beads
git config --local beads.role maintainer
python3 scripts/beads.py bootstrap --yes
python3 scripts/beads.py prime
python3 scripts/beads.py where --json
python3 scripts/beads.py list --all --json
python3 scripts/beads.py blocked --json
python3 scripts/beads.py ready --json
python3 scripts/beads.py show vpc-crm-t90 --json
python3 scripts/beads.py show vpc-crm-17k --json
python3 scripts/beads.py show vpc-crm-qb2 --json
git ls-remote origin refs/dolt/data
```

`bootstrap` запускается **только если локальной базы ещё нет**. Если `.beads/embeddeddolt` уже существует, вместо bootstrap выполни `python3 scripts/beads.py dolt pull`. В linked worktree helper выбирает единственную базу этого CRM-репозитория; не используй родительский `bd`. Если баз несколько, helper остановится: прочитай beads.md и явно выбери проверенный `BEADS_DIR`, не удаляй базы.

`git clone` не восстанавливает `refs/dolt/data` сам. Не заменяй remote JSONL-экспортом, не запускай init/reinit/import и не переноси `.dolt`/LOCK с Mac. Связь #3 → #2 и #4 → #3 должна сохраниться; состояния сверяются с фактическим merge, а не только `ready`.

**Один писатель:** Артём должен подтвердить, какой оркестратор теперь пишет в общий Beads. До этого новый агент только читает; оркестратор автора при передаче завершает checkpoint и прекращает claims. Рабочие агенты используют `--readonly`. Embedded Dolt между компьютерами не даёт распределённой блокировки. Перед разрешённым claim — pull; после изменения — Dolt commit/push и readback. Конфликт требует сверки событий, не force-push. Синхронизация Issues/Beads/Projects пока ручная, runner/bridge отсутствуют.

## Поднять приложение локально

Внешних интеграций для локальной CRM не нужно. В отдельном окружении:

```sh
npm ci
cp .env.example .env
```

Заполни `.env` своими локальными значениями. `POSTGRES_PASSWORD`, `AUTH_SECRET` и `OWNER_PASSWORD` сгенерируй у себя, например `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"` для каждого отдельно. URL-safe пароль удобно включить в `DATABASE_URL=postgresql://vpc:<пароль>@127.0.0.1:5432/vpc_crm`. `POSTGRES_PASSWORD` должен совпадать с паролем в URL. Если порт занят, выбери другой `POSTGRES_PORT` и тот же порт в URL. Существующий compose-volume не меняет пароль пользователя при редактировании `.env`; используй свою отдельную БД/проект, не удаляй чужой volume.

Для dev:

```dotenv
APP_ORIGIN=http://localhost:3000
LEADS_ALLOWED_ORIGINS=http://localhost:3000
CONSENT_PD_VERSION=synthetic-local-v1
CONSENT_MARKETING_VERSION=synthetic-local-v1
OWNER_EMAIL=owner@example.test
OWNER_NAME=Локальный владелец
```

Версии `synthetic-local-v1` допустимы **только для синтетического стенда**. Для реального квиза нужны точный origin и версии действительно опубликованных документов из решения владельца; не подставляй их по догадке. Также заполни обязательные пустые `AUTH_SECRET`, `OWNER_PASSWORD`, `POSTGRES_PASSWORD`, `DATABASE_URL`.

```sh
docker compose up -d postgres
npm run db:migrate
npm run seed:owner
npm run dev
```

Открой `http://localhost:3000/api/health` (ожидается `status=ok`, `database=up`), затем `/login` и `/crm`; войди своим OWNER. Seed создаёт первого владельца, не перезаписывает существующего. Контракт и snippet квиза: [docs/quiz/README.md](../../quiz/README.md). Пустой список в новой базе ожидаем; синтетический сценарий создаёт smoke.

### Проверить свой стенд

`npm test` удаляет таблицы **TEST_DATABASE_URL**. Создай отдельную локальную БД `vpc_crm_test`, например `docker compose exec postgres sh -c 'createdb -U "$POSTGRES_USER" vpc_crm_test'` (если существует — сначала проверь её назначение). Укажи отдельный loopback URL в `.env`. Не ставь там рабочую БД. Vitest сам `.env` не загружает: если переменные не экспортированы оболочкой, используй ниже запуск с `node --env-file`. В CI переменные уже заданы окружением, поэтому там используется `npm test`.

```sh
npm run typecheck
npm run lint
node --env-file=.env ./node_modules/vitest/vitest.mjs run
npm run build
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/check-repository-data.py
```

Для production-сборки **локального тестового стенда** останови свой dev-сервер и поменяй `APP_ORIGIN` и `LEADS_ALLOWED_ORIGINS` на `http://127.0.0.1:3103`. Запусти `npx next start --hostname 127.0.0.1 --port 3103`, в другом терминале — `npm run test:smoke`. Smoke создаёт синтетические записи/пользователей в `DATABASE_URL`; используй только свой стенд. Проверь руками список, фильтры, карточку, изменение статуса/ответственного/комментария и историю, desktop и ширину 390px. Проверка export safety требует PowerShell 7: `pwsh -NoProfile -File tests/export-safety.ps1`.

Старый `http://127.0.0.1:3103` автора доступен лишь на его Mac; его процесс, порт 25433 и временная PG-база не являются инфраструктурой Артёма. Секреты, БД и тестовые логины не переносим: они создаются заново.

## Карта переносимых и внешних данных

| Артефакт | Как восстановить |
|---|---|
| Код, миграции, compose, env-template, lockfile, CI, тесты | Git checkout ветки передачи; после принятия — main |
| Требования, ADR, правила и инструкции | Документы этого репозитория |
| Контракты, решения, ревью и CI | GitHub issues/comments/PR/checks; прочитать живые источники |
| Граф задач/claim/checkpoints | Beads remote `refs/dolt/data`, bootstrap/pull; не копирование local runtime |
| Дизайн | Токены в пакете + pinned reference; исходные ассеты отдельно из разрешённого источника |
| Локальный `.env`, сессии GitHub/Claude/Codex | Создать собственные локально; в Git и инструкциях их нет |
| Реальные Yclients-выгрузки, анкеты, контакты, транскрипты, рабочие БД | В Git не входят; хранить приватно, передавать владельцем отдельным защищённым способом после отдельного поручения |
| `.orchestration`, сырые модельные логи, локальные worktree и временный PostgreSQL | Не нужны для восстановления; результат заменён переносимыми checkpoints и источниками доказательств |
| Агентские финансовые книги/клиентские материалы, старый Telegram-бот и VPS агентства | Вне CRM-репозитория и этой передачи; не являются текущим CRM production |

На production CRM в этой работе не развёртывали; рабочий адрес/хост/backup не подтверждены. `compose.yaml` — локальная БД, а не production runbook. Требования РФ-хостинга, backup/restore, мониторинга и безопасного релиза входят в будущий этап v1. Нельзя переносить серверные credentials или запускать существующего бота, считая это частью bootstrap.

## Продолжить разработку

Сначала свежая проверка PR #12 и отдельная команда на merge. Затем retarget/проверка/принятие PR передачи. Только по этим событиям #3 и #13 становятся Done; оркестратор закрывает Beads и синхронизирует Project. В случае замечаний задачи остаются review и исправляются по лимиту AGENTS.md.

После принятия #3 проверь #4 и обнови его контракт для доставки. Для полной v1 оркестратор создаёт эпик и законченные дочерние сценарии по [v1-delivery.md](v1-delivery.md), с FR/AC, зависимостями, владельцами файлов и независимым ревью. Стадии в документе — предложение декомпозиции, а не второй исполняемый backlog. Артём выбирает ближайший приоритет; реализация стартует только после проверки готовности контракта и полномочий.
