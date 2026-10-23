---
name: rails-kamal-deploy
description: Set up, change and troubleshoot Kamal 2 deployment of any Rails 8 app — config/deploy.yml (servers and roles, proxy and SSL, registry, builder, env and secrets, accessories such as PostgreSQL and backups, destinations like staging), first setup, deploy, rollback, logs, console, locks and pruning — using the docs of the installed Kamal version. Use for «настрой Kamal», «деплой Rails на сервер», «добавь staging», «почему не поднялся контейнер», «откати», «как хранить секреты в Kamal». For this CRM's own runbook and permissions see crm-deploy.
---

# Kamal 2 для Rails

Kamal собирает Docker-образ приложения, доставляет его на серверы по SSH и переключает трафик через
kamal-proxy без простоя. Сервер нужен только с SSH и Docker (Kamal ставит Docker сам).

**Права:** настройка конфигурации — обычная работа. Выкатка, изменение сервера, перенос данных — только по
прямой команде владельца проекта (для CRM — skill `crm-deploy`).

## Источник правды — документация установленной версии

```sh
bin/kamal version
bin/kamal docs                 # общий раздел; отдельные: proxy, accessory, builder, env, registry, role, servers, ssh
bin/kamal docs proxy
bin/kamal help deploy          # параметры любой команды
```

Ключи конфигурации меняются между версиями: проверяй по `bin/kamal docs <раздел>`, а не по памяти или блогам.
Kamal отвергает неизвестные ключи. Повторяющиеся блоки выноси в `x-`-якоря YAML.

## Минимальный `config/deploy.yml`

```yaml
service: app
image: app
servers:
  web:
    hosts: [ <%= ENV.fetch("KAMAL_HOST") %> ]
  worker:                                   # фоновые процессы — отдельная роль с cmd
    hosts: [ <%= ENV.fetch("KAMAL_HOST") %> ]
    cmd: bin/rails some:work
proxy:
  host: <%= ENV.fetch("APP_HOST") %>
  ssl: true                                 # Let's Encrypt; нужна A-запись и свободные 80/443
  app_port: 80                              # Thruster в образе Rails 8 слушает 80
  healthcheck: { path: /up }
registry:
  server: localhost:5555                    # локальный registry: образ едет по SSH, внешний сервис не нужен
builder:
  arch: amd64                               # Mac на ARM собирает amd64 — эмуляция или builder.remote
env:
  clear: { RAILS_LOG_LEVEL: info }
  secret: [ SECRET_KEY_BASE, DATABASE_URL ]
accessories:
  db:
    image: postgres:17-alpine
    host: <%= ENV.fetch("KAMAL_HOST") %>
    port: "127.0.0.1:5432:5432"             # только локально на сервере
    env: { secret: [ POSTGRES_PASSWORD ] }
    directories: [ data:/var/lib/postgresql/data ]
```

Пустые значения из `ENV.fetch(..., "")` бери в кавычки (`"<%= … %>"`), иначе YAML даст `nil` и Kamal откажет.

## Секреты

- `.kamal/secrets` хранит только ссылки `KEY=$KEY` и коммитится; значения — в переменных окружения или менеджере паролей.
- Встроенные помощники: `bin/kamal secrets fetch --adapter <1password|bitwarden|lastpass|doppler|aws_secrets_manager|gcp_secret_manager|…>`
  (`bin/kamal secrets help fetch`). В `.kamal/secrets`: `SECRETS=$(kamal secrets fetch …)`, затем `KEY=$(kamal secrets extract KEY $SECRETS)`.
- **`bin/kamal config` печатает секреты.** Для проверки — `bin/kamal config > /dev/null`, смотри код возврата.
- Секрет, нужный только одной роли, объявляй в `env.secret` этой роли.

## Команды

| Задача | Команда |
|---|---|
| Первый раз: Docker, registry, proxy, accessories, приложение | `bin/kamal setup` |
| Выкатка | `bin/kamal deploy` (`redeploy` — без подготовки серверов) |
| Какие версии запущены | `bin/kamal app details`, `bin/kamal app containers` |
| Откат кода | `bin/kamal rollback <версия>` (база не откатывается!) |
| Логи | `bin/kamal app logs -f`, роль: `-r worker`, accessory: `bin/kamal accessory logs db` |
| Консоль, команда в контейнере | `bin/kamal app exec -i --reuse "bin/rails console"` |
| Перезапуск accessory | `bin/kamal accessory reboot db` (осторожно: БД) |
| Страница «идут работы» на время операции | `bin/kamal app maintenance`, вернуть — `bin/kamal app live` |
| Кто и когда выкатывал | `bin/kamal audit` |
| Зависший lock после прерванной выкатки | `bin/kamal lock status`, затем `bin/kamal lock release` |
| Чистка старых образов | `bin/kamal prune all` |
| Отдельное окружение | `config/deploy.staging.yml` + `bin/kamal deploy -d staging` |

Удобные сокращения задавай в `aliases:` (`bin/kamal console`, `bin/kamal logs`).

## Миграции и откат

- Rails 8 `bin/docker-entrypoint` выполняет `bin/rails db:prepare` при старте сервера: на пустой базе загрузит
  схему и seeds, на существующей — применит миграции.
- Откат кода не откатывает схему. Миграции аддитивные: сначала добавляем, удаляем старое отдельной выкаткой.
- Долгие миграции (перестройка больших таблиц, индексы без `CONCURRENTLY`) — отдельная согласованная операция с бэкапом.

## Диагностика

| Симптом | Где смотреть |
|---|---|
| Деплой ждёт и падает на healthcheck | `bin/kamal app logs`: ошибка старта, миграция, нет переменной; путь `proxy.healthcheck.path` |
| Контейнер убит | память: `dmesg \| grep -i oom` на сервере, лимиты `options.memory`, swap |
| Сертификат не выпускается | A-запись домена, свободный порт 80, `bin/kamal proxy logs` |
| `Host not permitted` от Rails | `config.hosts` в `production.rb` не содержит домен |
| Бесконечные редиректы | `config.assume_ssl = true` за kamal-proxy, `force_ssl` с исключением `/up` |
| Старые CSS/JS у пользователей | файлы без версии в имени (из `public/`) раздаются с долгим кэшем — ставь `no-cache` |
| Сборка на Mac долгая или падает | эмуляция amd64: `builder.remote` на сервере сборки или сборка в CI |

Производительность на сервере: руководство `tuning_performance_for_deployment`
(`ruby .claude/skills/rails-guides/scripts/guide.rb tuning_performance_for_deployment`) — Puma, YJIT, память.
