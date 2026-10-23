---
name: rails-testing
description: Write and run fast, trustworthy Minitest tests for a Rails 8.1 app on real PostgreSQL — integration tests for HTTP and pages, service tests, concurrency and constraint tests, synthetic test data, narrow runs while working and bin/ci before committing; diagnose failing or flaky tests. Use for «напиши тесты», «покрой тестами», «почему падает тест», «тесты долго идут», «проверь перед коммитом», or after any change to Rails code.
---

# Тесты в Rails: Minitest на настоящей PostgreSQL

Официальная база — руководство `testing` (`ruby .claude/skills/rails-guides/scripts/guide.rb testing "<раздел>"`):
Integration Testing, The Test Database, Test Helpers, Parallel Testing, Running tests in Continuous Integration (CI).

## Что и где тестировать

| Изменение | Тест | Где |
|---|---|---|
| JSON API, коды ответов, заголовки | `ActionDispatch::IntegrationTest`, запрос как от клиента | `test/integration/` |
| Страница и форма | integration: `get`, `post`/`patch` формы, `assert_redirected_to`, текст в `response.body` | `test/integration/` |
| Бизнес-правило, расчёт | `ActiveSupport::TestCase` на модуль сервиса | `test/services/` |
| Конкурентность, двойная запись, уникальность | Прямо против ограничения БД: ожидать `ActiveRecord::StatementInvalid` с нужным SQLSTATE | `test/integration/` |
| Совместимость (идентификаторы, хэши, формат JSON) | Эталонные значения, посчитанные один раз и вписанные в тест | `test/services/` |

Не мокай базу: транзакции, блокировки, CHECK и EXCLUDE проверяются только на PostgreSQL.
Внешние HTTP-сервисы (Telegram, платежи) — локальная заглушка (`WEBrick` в тесте) или фейковый канал,
никогда не настоящий сервис.

## Данные

- Только синтетика, созданная тестом: `example.test`, телефоны `+7999…`, имена-заглушки. Реальные выгрузки в тестах запрещены.
- Фабрики-методы в `test/support/factory.rb` вместо fixtures: явно видно, что создаёт тест.
- `TEST_DATABASE_URL` — отдельная база, её очищают тесты. Никогда не указывай рабочую.
- Тест не зависит от порядка: каждый создаёт свои данные (транзакционные тесты откатываются сами).

## Как запускать

```sh
bin/rails test test/integration/calendar_test.rb        # во время работы — только свой файл
bin/rails test test/integration/calendar_test.rb:42      # один тест по строке
bin/rails test                                           # весь набор перед коммитом
bin/ci                                                   # всё вместе перед отправкой (стиль, безопасность, тесты)
```

Отчёт после прогона: число тестов, проверок и падений. Не «всё работает» без вывода.

## Структура теста

```ruby
test "повтор операции возвращает тот же результат, другой запрос с тем же id — 409" do
  op = SecureRandom.uuid
  command("create_booking", payload, operation_id: op)
  assert_response :ok
  first = json
  command("create_booking", payload, operation_id: op)
  assert_equal first, json
  command("create_booking", other_payload, operation_id: op)
  assert_response :conflict
end
```

Проверяй сценарий целиком: успех, отказ прав (401/403), неверный ввод (400 и имена полей), конфликт
версии (409), повтор операции, запись в аудит, отсутствие ПДн в ответе об ошибке.

## Ловушки, найденные на этом проекте

- **Кэш запросов внутри теста.** Rails выполняет тест внутри executor, и кэш запросов живёт между запросами
  одного теста. Одинаковый SQL (`UPDATE … RETURNING`, `SELECT … FOR UPDATE`, `clock_timestamp()`) вернёт старый
  ответ. В `config/environments/test.rb` стоит `config.active_support.executor_around_test_case = false`,
  в контроллерах — `ActiveRecord::Base.uncached`.
- **`now()` в транзакционном тесте** не движется: весь тест — одна транзакция. Время из разных шагов теста
  сравнивай с запасом или явно двигай данные (`update_all("next_attempt_at = now()")`).
- **Ruby `String#split` выбрасывает пустые хвосты** (`"a x".split("x")` → `["a "]`), в отличие от JavaScript. Для замены подстроки используй `gsub`.
- **`assert_response :payload_too_large`** устарело в Rack 3 — пиши `:content_too_large`.
- **Параллельный запуск** (`parallelize`) создаёт базы `<имя>-0`, `<имя>-1`. С единственной `TEST_DATABASE_URL`
  на чужом сервере включай его осознанно: нужны права на создание баз.

## Медленные или нестабильные тесты

1. Запусти один файл с `--verbose`, найди медленный тест.
2. Чаще всего виноваты лишние записи в setup, хэширование паролей (argon2 медленный — кэшируй хэш в фабрике)
   или реальные сетевые вызовы.
3. Нестабильный тест — почти всегда зависимость от времени или порядка. Зафиксируй время или данные, не повторяй тест «до зелёного».
