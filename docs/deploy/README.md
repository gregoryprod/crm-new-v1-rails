# Деплой CRM через Kamal 2

**Кто выполняет:** только по прямой команде владельца (Артёма). Подготовка конфигурации
не разрешает выкатку, перенос базы и приём живых заявок, это отдельные решения.
**Скилл для агента:** `crm-deploy` (`.claude/skills/crm-deploy/SKILL.md`).

## Как устроено

```text
Mac/CI ──docker build (amd64)──► локальный registry ──SSH──► сервер
                                                             ├─ kamal-proxy :80/:443 (Let's Encrypt)
                                                             ├─ vpc-crm-web     (Thruster + Puma, /up)
                                                             ├─ vpc-crm-worker  (bin/rails notifications:work)
                                                             ├─ vpc-crm-db      (postgres:17, том data/)
                                                             └─ vpc-crm-backup  (pg_dump раз в сутки, 30 дней)
```

Конфигурация — `config/deploy.yml`, ссылки на секреты — `.kamal/secrets`. При старте веб-контейнер
выполняет `bin/rails db:prepare` и `db:seed` (`bin/docker-entrypoint`).

## Что нужно заранее

| Что | Откуда |
|---|---|
| Сервер в РФ, Ubuntu/Debian, SSH-ключ | Артём (NFR-01) |
| Домен CRM с A-записью на сервер | Артём, `[PLACEHOLDER: Артём]` |
| Порты 80 и 443 свободны (их займёт kamal-proxy) | проверить `ss -ltnp` на сервере |
| Docker на машине, с которой выкатываем (OrbStack/Docker Desktop) или удалённый builder | разработчик |
| Origin сайта с квизом, версии оферты и маркетингового согласия | Артём |
| Бот и ID чата администраторов | Артём (этап 2 плана) |

Ресурсы: на 2 ядрах и 2 ГБ памяти лимиты контейнеров рассчитаны так: веб 700 МБ, воркер
300 МБ, БД 600 МБ, бэкап 128 МБ. Это оценка, не замер. Обязательно включи swap 2 ГБ:

```sh
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Переменные на машине выкатки

```sh
export KAMAL_HOST=<IP сервера>
export CRM_HOST=<домен CRM>
export KAMAL_SSH_USER=<пользователь с правом на docker>     # по умолчанию root
export LEADS_ALLOWED_ORIGINS=https://<сайт с квизом>
export CONSENT_PD_VERSION=<версия оферты>  CONSENT_MARKETING_VERSION=<версия согласия>
# Секреты (из менеджера паролей, не в файлы репозитория):
export SECRET_KEY_BASE=$(bin/rails secret)
export AUTH_SECRET=<32+ символа, не менять после запуска: от него зависят сессии и хэши>
export POSTGRES_PASSWORD=<пароль БД>
export TELEGRAM_BOT_TOKEN=<токен>  TELEGRAM_ADMIN_CHAT_ID=<id чата>
```

Проверка без выкатки: `bin/kamal config > /dev/null` (код 0 — конфигурация верна). Без `> /dev/null` команда печатает и секреты: не запускай её так при агенте или в записи экрана.

## Первая выкатка

```sh
bin/kamal setup            # Docker на сервере, registry, kamal-proxy, accessories, приложение
bin/kamal app logs         # ждём "Listening on http://0.0.0.0:80"
curl -fsS https://$CRM_HOST/up && curl -fsS https://$CRM_HOST/api/health
bin/kamal seed-owner       # OWNER_EMAIL/OWNER_NAME/OWNER_PASSWORD передать через env на сервере
```

Затем HTTP-смоук против сервера (создаёт одну синтетическую заявку; выполнять только на стенде
или с согласия владельца):

```sh
APP_ORIGIN=https://$CRM_HOST OWNER_EMAIL=… OWNER_PASSWORD=… LEADS_ALLOWED_ORIGINS=https://$CRM_HOST node scripts/smoke-http.mjs
```

## Обычная выкатка и откат

```sh
bin/kamal deploy                       # после зелёного CI; без простоя
bin/kamal app details                  # какие версии запущены
bin/kamal rollback <версия>            # версия = SHA коммита из `bin/kamal app containers`
```

Откат возвращает код, но не базу. Поэтому миграции пишем обратимыми и аддитивными: сначала
добавить, потом в отдельной выкатке удалять старое.

## Перенос базы из Node-версии

Схема та же. Rails распознаёт базу, мигрированную Node-версией, по журналу Drizzle
(`AdoptDrizzleSchema`) и ничего в ней не меняет, кроме служебных таблиц Rails.

```sh
# на машине с локальной Node-базой (данные клиентов: только с разрешения владельца)
pg_dump --format=custom --no-owner --file=vpc_crm.dump "$OLD_DATABASE_URL"
scp vpc_crm.dump $KAMAL_SSH_USER@$KAMAL_HOST:/tmp/
# на сервере, до первого приёма заявок:
docker exec -i vpc-crm-db pg_restore --no-owner -U vpc -d vpc_crm < /tmp/vpc_crm.dump && rm /tmp/vpc_crm.dump
bin/kamal app boot                     # db:prepare применит только служебную миграцию Rails
```

После переноса пересобери аналитику: `bin/kamal app exec "bin/rails full_crm:projections"`
(пробный прогон), затем с `APPLY=1`, если документы различаются.

## Бэкапы и проверка восстановления

- Accessory `backup` раз в сутки пишет `pg_dump` в `~/vpc-crm-backup/backups` на сервере, хранит 30 дней (NFR-04).
- **Открыто:** копия вне сервера (S3-совместимое хранилище в РФ) и бэкап файлов (появятся с анкетами).
- Проверка восстановления (до запуска заявок и затем регулярно):

```sh
ssh $KAMAL_HOST
LATEST=$(ls -t ~/vpc-crm-backup/backups/vpc_crm-*.dump | head -1)
docker exec vpc-crm-db createdb -U vpc vpc_restore_check
docker exec -i vpc-crm-db pg_restore -U vpc -d vpc_restore_check < "$LATEST"
docker exec vpc-crm-db psql -U vpc -d vpc_restore_check -c "select count(*) from clients; select count(*) from appointments;"
docker exec vpc-crm-db dropdb -U vpc vpc_restore_check
```

## Диагностика

| Симптом | Что смотреть |
|---|---|
| `/up` не отвечает после deploy | `bin/kamal app logs`, нехватка памяти: `dmesg | grep -i oom` |
| Уведомления не уходят | `bin/kamal app logs -r worker`; в карточке заявки статус и текст ошибки доставки |
| `503 intake_unavailable` на `/api/leads` | не заданы `LEADS_ALLOWED_ORIGINS` или версии согласий |
| Квиз получает 403 | origin сайта не в `LEADS_ALLOWED_ORIGINS` (точное совпадение, https) |
| Сертификат не выпускается | A-запись домена, свободный порт 80, `bin/kamal proxy logs` |

Консоль: `bin/kamal console`. База: `bin/kamal dbc`.

## Известные ограничения

- Одна роль БД (`vpc`) для миграций и приложения. Разделение ролей — в roadmap, этап 2.
- Бэкапы пока лежат на том же сервере.
- Мониторинга и оповещений о падении пока нет.
