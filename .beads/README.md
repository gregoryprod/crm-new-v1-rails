# Beads CRM VetPetCare

[Процесс, установка и восстановление](../docs/development/beads.md). Prefix: `vpc-crm`; CLI: `1.3.0`, embedded Dolt. База синхронизируется через `refs/dolt/data` существующего приватного репозитория.

Используй `python3 scripts/beads.py` из корня: помощник проверяет workspace и исключает родительскую базу клиента. Конфигурация и соответствие GitHub IDs — в Git; база, исполняемые файлы, credentials и runtime игнорируются. Общие инструкции — [AGENTS.md](../AGENTS.md), CLAUDE.md импортирует их.

`github-map.json` содержит исходные ссылки, без копий статусов/требований. Для новых задач источник соответствия — `external_ref` в Beads. Context #7 не является исполняемой задачей.
