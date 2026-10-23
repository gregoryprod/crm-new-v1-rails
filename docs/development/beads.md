# Beads: агентские задачи CRM

Beads хранит исполняемые задачи, статусы, зависимости, claim и найденные follow-up. GitHub issue — контракт/приёмка и история для владельца; Projects — проекция этих же задач. `external_ref` содержит полный URL issue. `.beads/github-map.json` — исходное соответствие IDs, без второго списка статусов. Для новых задач проверяй `external_ref`, не создавай дубль по одному названию.

## Установка и маршрутизация

Проверенная версия `bd` — **1.3.0**, режим embedded; системный CLI и глобальные hooks не меняются. Для Mac/Linux нужны Python3, Git, gh и доступ к приватному репозиторию. Dolt CLI нужен для Git transport; текущая проверка использует установленный 2.2.2. Upstream для server mode рекомендует pin 2.2.0; embedded engine включён в bd и отдельного sql-server не требует. Обновление версии/схемы — отдельная проверяемая задача, а не `brew upgrade` между агентскими сессиями.

```sh
python3 scripts/install-beads.py
chmod 700 .beads
git config --local beads.role maintainer
python3 scripts/beads.py bootstrap --yes
python3 scripts/beads.py prime
python3 scripts/beads.py where --json
```

Installer скачивает официальный release 1.3.0, проверяет закреплённый SHA-256 и сохраняет только бинарник в игнорируемую `.orchestration/bin/bd`. Не запускает установщик из сети и не меняет глобальные конфиги. На новом клоне `bootstrap` восстанавливает базу из `refs/dolt/data`; на существующей базе используй `dolt pull`. **Не запускай init/reinit/import поверх общей базы.**

CLI-помощник обнаруживает только `.beads/config.yaml` с prefix `vpc-crm` среди worktree этого Git-репозитория. Все linked worktree используют единственную инициализированную CRM-базу. Если таких баз несколько, явно задай `BEADS_DIR` для одной из них и разберись в расхождении; helper ничего не удаляет. Родительская база клиента `vpc` не подходит. В старом worktree без новых файлов используй абсолютный путь к `scripts/beads.py` из Beads-worktree; сырой `bd` там может открыть родительскую базу.

В Git входят config, metadata, ссылки и инструкции. `.beads/embeddeddolt`, credentials, backups и runtime игнорируются. Логи/CLI лежат в `.orchestration`. В Beads запрещены те же реальные выгрузки, контакты и секреты, что в GitHub.

## Один контракт, один граф

| Beads | Projects | Основание |
|---|---|---|
| backlog | Backlog | Scope или готовность не подтверждены. |
| open | Ready | Поручение разрешено, контракт полон, зависимости приняты. |
| in_progress | In progress | Оркестратор выполнил claim и назначил Worker/владение. |
| review | Review | Результат готов; ожидается приёмка/разрешённый merge. |
| blocked | Blocked | Конкретный блокер и условие возобновления записаны. |
| closed | Done | Принят результат; для кода/правил PR MERGED и issue CLOSED. |

`backlog`/`review` настроены как custom status в общей Dolt-базе. `ready` вычисляет отсутствие блокеров у `open`, а не полномочия; исходное поручение всегда проверяется отдельно. Контекст #7 отсутствует в исполняемом графе. Эпики — контейнеры, нельзя claim вместо дочерних задач. GitHub Assignee — человек, Beads assignee/actor — выполняющий агент; Worker/Review agent/human_owner записаны в metadata.

Оркестратор — **единственный writer** общей Beads-базы, последовательными CLI-командами. Workers читают задачу (`--readonly show ID --json`) и возвращают отчёт. Максимум две независимые реализации в отдельных worktree; embedded Dolt не даёт распределённый атомарный claim между независимыми клонами. `dolt pull`/`push` и назначение одним оркестратором предотвращают две независимые очереди; два оркестратора одновременно не запускаются.

## Работа и передача

```sh
python3 scripts/beads.py dolt pull
python3 scripts/beads.py ready --json
python3 scripts/beads.py show ID --json
python3 scripts/beads.py --actor Codex update ID --claim
```

Сначала scope/владение и claim, затем Project In progress и начальный checkpoint в issue. После проверенного результата: Beads `review`, Project Review, PR и checkpoint с SHA/CI/следующим шагом. Завершение CLI не заменяет проверки. Review не закрывается ради «завершения сессии».

```sh
python3 scripts/beads.py update ID --status review
python3 scripts/beads.py comments add ID "Checkpoint: head SHA; результат/ограничение; ссылка на GitHub checkpoint; следующий шаг"
python3 scripts/beads.py dolt commit -m "Checkpoint задачи"
python3 scripts/beads.py dolt push
```

При принятом и прямо разрешённом merge сначала читай PR MERGED и issue CLOSED, затем `close ID --reason "Принят PR URL, merge SHA"`, Project Done и Dolt commit/push. После фактического события проверь зависимости. Если issue закрыт без принятого результата, Beads автоматически не закрывается.

Новая разрешённая самостоятельная задача получает Beads ID и GitHub-контракт с взаимными ссылками. Найденная неразрешённая работа сразу получает `backlog`; до разрешения не может стать Ready. Создавай через `create --description ... --external-ref URL`, затем `update ID --status backlog`, связывай `dep add CHILD BLOCKER` или `--deps discovered-from:PARENT`. Не используй `bd edit`. Не создавай Markdown TODO как живой tracker.

Пиши краткий checkpoint в комментарий Beads и полный в GitHub issue; включай base/head/worktree, команды и результаты, ограничения и следующий ответственный шаг. Перед передачей или завершением сессии: Dolt commit/push и readback. Если remote недоступен, обозначь, что результат остаётся локальным, и не запускай новую задачу по старому `ready`.

Синхронизация Beads ↔ GitHub — явный шаг оркестратора, автоматического двухстороннего bridge нет. Нельзя массово перезаписать одну систему старым снимком другой. При расхождении останови claim и сверяй последнее разрешённое событие, PR/CI и checkpoint; для приёмки решающее доказательство — команда владельца/принятый PR. Процесс/статусы меняет оркестратор в обеих системах, требования остаются в GitHub.

## Sync и проверка

Dolt remote `origin` использует существующий приватный vpc-crm и отдельный `refs/dolt/data`, а не новую публичную базу. `git clone` сам этот ref не восстанавливает. После bootstrap сверяй `list --all --json`, `blocked --json` и `ready --json` с GitHub-контрактами. JSONL — export/interchange, не cross-machine sync и не полный backup. Нельзя вручную править `.dolt`, снимать LOCK или делать force-push для устранения расхождения.

Проверки подключения: штатные Python/Repository safety tests, тесты маршрутизации от родительской базы, реальный Dolt push и bootstrap в чистом клоне с readback задач/зависимостей. На момент подключения Beads в PR #11 задача #2 была `review`, #3 и #4 — `blocked`; PR #6 тогда не изменялся. Это историческая проверка интеграции. Актуальные статусы и SHA восстанавливай из [контекста #7](https://github.com/artemiyvladimirov-cmyk/vpc-crm/issues/7), связанных issues/PR и Beads после `dolt pull`.

Основание: отдельное поручение владельца, [Beads](https://beads.gascity.com/), [sync](https://beads.gascity.com/getting-started/sync-setup), [worktree](https://beads.gascity.com/reference/worktrees), [режимы Dolt](https://beads.gascity.com/architecture/dolt). Интеграции Claude/Codex используют общий AGENTS.md/CLI; глобальные plugins/hooks и unattended runner не устанавливаются.
