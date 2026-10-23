# Контекст Beads — CRM VetPetCare

Общие условия работы: прочитай AGENTS.md и docs/development/beads.md соответствующей ветки. CLAUDE.md импортирует AGENTS.md. Контекст продукта и решения — GitHub context #7; задача — GitHub issue по external_ref и Beads show ID.

Используй только `python3 scripts/beads.py`: настоящий bd с проверкой workspace `vpc-crm`, версии и маршрутизации. Сырой bd может выбрать родительскую базу клиента.

Начало: `dolt pull`, `ready --json`, `show ID --json`, сверка scope/PR/CI/HEAD и checkpoint. Пишет только оркестратор последовательными командами. Workers читают `--readonly show ID --json`; claim выполняет оркестратор перед назначением реализации.

Статусы: backlog → open (Ready) → in_progress → review → closed; blocked — зависимость/ограничение. Не claim backlog, review, blocked или эпик. `ready` не выдаёт полномочия. GitHub-контракт/приёмка и Projects отражают те же задачи; автоматического bridge нет.

Перед завершением/передачей: checkpoint в Beads и GitHub issue, `dolt commit`, `dolt push`, проверка результата. Review остаётся открытым до принятия и разрешённого merge. Не закрывай незавершённую задачу ради session-close checklist. Для кода/правил closed/Done требует PR MERGED и issue CLOSED. Новое обнаруженное неразрешённое дело — backlog.

Merge, production и новые провайдеры — в пределах прямого поручения владельца. PR #6 этим подключением не меняется. Реальные клиентские данные/секреты в Beads запрещены, как в GitHub. JSONL — export, не sync/backup. Не переинициализируй, не удаляй .dolt/LOCK и не делай force-push.
