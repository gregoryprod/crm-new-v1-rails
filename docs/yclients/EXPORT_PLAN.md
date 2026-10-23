# Выгрузка данных из YCLIENTS: клиенты и врачи

Источник: официальная OpenAPI‑спецификация https://developers.yclients.com/ru/ (извлечена 2026‑10‑03 → `openapi.json`, 248 путей / 304 метода, список — `endpoints.txt`).

## 0. Доступ и ограничения

| Что | Значение |
|---|---|
| Базовый URL | `https://api.yclients.ru` |
| Заголовки | `Accept: application/vnd.yclients.v2+json`, `Content-Type: application/json` |
| Авторизация | `Authorization: Bearer <partner_token>, User <user_token>` |
| Partner token | регистрация в маркетплейсе https://yclients.ru/appstore/developers → «Настройки аккаунта» → API‑ключ |
| User token | `POST /api/v1/auth` логином/паролем сотрудника с правами (при 2FA — второй шаг с кодом, в ответе `uuid`). При смене пароля токен меняется |
| Лимит | **200 запросов/мин или 5 запросов/сек на IP** |
| Лицензия | при неоплаченной лицензии филиала — 402/403 «Необходимо продлить лицензию» → выгружать до окончания подписки |

Важно: у пользователя, под которым берётся user token, должны быть права на просмотр клиентов, их телефонов, финансов, файлов и т.п. — иначе поля придут пустыми/замаскированными. Лучше владелец/администратор сети.

Медицинских сущностей (медкарта, анамнез, диагнозы) в API **нет**. Всё «медицинское» в YCLIENTS обычно живёт в: доп. полях клиента/записи, комментариях к клиенту, комментариях к записи, файлах клиента.

## 1. Структура (сначала)

| Данные | Метод |
|---|---|
| Сети и их филиалы | `GET /api/v1/groups` |
| Филиалы | `GET /api/v1/companies?my=1` (+ `include[]=staff&include[]=positions&include[]=accounts&include[]=storages`) |
| Компания | `GET /api/v1/company/{id}/` |
| Доп. поля клиентов / записей (схема) | `GET /api/v1/custom_fields/client/{company_id}`, `GET /api/v1/custom_fields/record/{company_id}` |
| Категории (метки) клиентов | `GET /api/v1/labels/{company_id}/clients` (и `/labels/{company_id}/{entity}`) |
| Услуги / категории услуг | `GET /api/v1/company/{company_id}/services/{service_id}`, `GET /api/v1/company/{company_id}/service_categories/{id}`, сетевые: `GET /api/v1/chain/{chain_id}/service_categories` |
| Ресурсы (кабинеты, аппараты) | `GET /api/v1/resources/{company_id}` |

## 2. Врачи (сотрудники)

| Данные | Метод |
|---|---|
| Список / карточка | `GET /api/v1/company/{company_id}/staff/{staff_id}` (без id → список). Устаревший аналог `GET /api/v1/staff/{company_id}/{staff_id}` : в новом методе пример ответа короткий, а полный объект сотрудника в доке шире (rating, information, votes_count, comments_count, weight, image_group) — **на старте выгрузить обоими и сравнить** |
| Должности | `GET /api/v1/company/{company_id}/staff/positions/` |
| График работы | `GET /api/v1/company/{company_id}/staff/schedule?start_date=&end_date=&staff_ids[]=&include[]=busy_intervals&include[]=off_day_type` |
| Связь врач ↔ услуга (цены, длительность) | в карточке услуги (`staff[]`) / `POST .../services/{id}/staff` (запись) |
| Тех. карты врач+услуга | `GET /api/v1/technological_cards/default_for_staff_and_service/{company_id}/{staffId}/{serviceId}/` |
| Отзывы о врачах | `GET /api/v1/comments/{company_id}/` |
| Пользователи (логины сотрудников, телефон, email, роль) | `GET /api/v1/company/{company_id}/users`, права: `/users/{user_id}/permissions`, роли: `/users/{user_id}/roles` |
| Зарплатные схемы/расчёты | `GET /api/v1/company/{company_id}/salary/period/staff/{staff_id}/`, `.../salary/calculation/staff/{staff_id}/`, `.../salary/payroll/staff/{staff_id}/calculation/` |
| Чаевые | `GET /api/v1/tips/{company_id}/settings` |

Поля сотрудника: `id, api_id, name, specialization, position{id,title}, weight, show_rating, rating, votes_count, comments_count, avatar, avatar_big, information (HTML), hidden, fired, status (удалён), image_group, user_id`. Телефон/email врача — через `user_id` → `/company/{id}/users`.
Уволенные и удалённые тоже возвращаются (`fired=1`, `status=1`) — нужны для истории записей.

## 3. Клиенты

### 3.1 Список (получение всех ID)
`POST /api/v1/company/{company_id}/clients/search`
```json
{ "page": 1, "page_size": 200, "fields": ["id","name","phone","email"],
  "order_by": "id", "order_by_direction": "ASC" }
```
- `page_size` макс. **200**; `meta.total_count` — всего клиентов.
- `order_by`: id, name, phone, email, discount, first_visit_date, last_visit_date, sold_amount, visits_count.
- Фильтры (`filters[]`, `operation` AND/OR): id, quick_search, sold_amount, importance, category, birthday, gender, has_mobile_app, record{staff, service, service_category, status, created, records_count, sold_amount}, client{id,birthday}, sale{abonement_balance}.
- Полный перечень допустимых `fields` в доке не описан → проверить опытным путём (ожидаемо: surname, patronymic, sex, birth_date, discount, card, comment, categories, first_visit_date, last_visit_date, sold_amount, visits_count, importance…).

Альтернатива (устаревшая, но с инкрементом): `GET /api/v1/clients/{company_id}?page=&count=&changed_after=&changed_before=` — удобно для дельта‑синхронизации в период переезда.

### 3.2 Полная карточка
`GET /api/v1/client/{company_id}/{id}` → `id, name, surname, patronymic, phone, email, categories, sex, discount, importance, card, birth_date, comment, sms_check, sms_not, spent, balance, visits, last_change_date, custom_fields`.
Для N клиентов = N запросов → при 5 rps ~ 18 000 клиентов/час. Можно сократить, если `fields` в search отдаёт всё нужное.

### 3.3 Всё, что висит на клиенте
| Данные | Метод |
|---|---|
| Комментарии (+ история загрузки файлов) | `GET /api/v1/company/{company_id}/clients/{client_id}/comments` |
| Файлы (снимки, анализы, договоры) | `GET /api/v1/company/{company_id}/clients/files/{client_id}` → `link` (`/client_files/download/...`, относительный — скачивать с yclients.ru с той же авторизацией; проверить) |
| История визитов (услуги, оплаты, расходники, товары, врач) | `POST /api/v1/company/{company_id}/clients/visits/search` `{client_id, client_phone:null, from:null, to:null, payment_statuses:[], attendance:null}`; пагинация по датам через `meta.dateCursor.next.from/to` |
| Личные счета (депозиты) | `GET /api/v1/deposits/company/{company_id}/client/{client_id}`, по сети `GET /api/v1/deposits/chain/{chain_id}`, история `.../deposit_history/{deposit_id}` |
| Карты лояльности | `GET /api/v1/loyalty/client_cards/{client_id}` |
| Абонементы | `GET /api/v1/loyalty/abonements/` (по клиенту), по сети `GET /api/v1/chain/{chain_id}/loyalty/abonements` |
| Сертификаты | `GET /api/v1/loyalty/certificates/` |
| Транзакции лояльности | `GET /api/v1/chain/{chain_id}/loyalty/transactions` |
| Сетевой клиент по телефону | `GET /api/v1/group/{group_id}/clients/?phone=` |

## 4. Записи и визиты (связка клиент ↔ врач — самое ценное)

`GET /api/v1/records/{company_id}?page=&count=&start_date=&end_date=&with_deleted=1&include_finance_transactions=1&include_consumables=1`
- Фильтры: staff_id, client_id, created_user_id, c_start_date/c_end_date, **changed_after/changed_before** (инкремент).
- Поля: services (цены, скидки), staff, client, datetime, length, comment, attendance/visit_attendance, confirmed, online, record_labels, custom_fields, documents, visit_id, deleted, paid_full, prepaid, created_user_id, last_change_date, consumables, finance_transactions.
- Выгружать по месяцам за всю историю, с `with_deleted=1`.

Дополнительно: `GET /api/v1/visits/{visit_id}`, `GET /api/v1/visit/details/{salon_id}/{record_id}/{visit_id}`, `GET /api/v1/technological_cards/record_consumables/{company_id}/{record_id}/`, лист ожидания `GET /api/v2/companies/{company_id}/waiting_list`, групповые события `GET /api/v1/activity/{company_id}/search/`.

## 5. Финансы (при необходимости)
`GET /api/v1/transactions/{company_id}`, `GET /api/v1/timetable/transactions/{company_id}` (по визиту/записи), кассы `GET /api/v1/accounts/{company_id}`, ККМ `GET /api/v1/kkm_transactions/{company_id}`, товарные транзакции `GET /api/v1/storages/transactions/{company_id}`, продажи `GET /api/v1/company/{company_id}/sale/{document_id}`.

## 6. Порядок выгрузки

1. Получить partner token + user token (админ сети).
2. groups → companies → custom_fields, labels, positions, services, resources.
3. staff (оба метода) + users + schedule.
4. clients/search (все ID, page_size=200) → client/{id} для каждого.
5. По каждому клиенту: comments, files (+скачать бинарники), loyalty cards, deposits.
6. records по месяцам за всю историю (with_deleted=1, include_*=1).
7. Сохранять **сырые JSON‑ответы** (raw слой) + нормализовать в свою БД; ключи — YCLIENTS id.
8. На время переезда — инкрементальная досинхронизация по `changed_after` (records, clients).

Технически: троттлинг ≤ 4 rps с ретраями на 429/5xx, логирование, возобновление с места остановки.

## 7. Что API не даёт / риски
- Нет медкарт, нет массового экспорта одним файлом — только постраничный обход.
- Список `fields` для clients/search не документирован.
- Устаревшие методы (`/clients`, `/staff/{company_id}`) могут отключить — использовать сейчас.
- Параллельно сделать ручной экспорт из веб‑интерфейса (Клиенты → Экспорт в Excel) как контрольную сверку.
- Персональные (а для клиники — медицинские) данные: перенос = обработка ПДн по 152‑ФЗ, хранить на защищённой инфраструктуре в РФ.
