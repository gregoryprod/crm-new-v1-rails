# Полная выгрузка базы YCLIENTS: все клиенты (карточка + комментарии + файлы), все записи за всю историю,
# сотрудники, справочники. Повторный запуск продолжает с места остановки (кэш raw/clients/<id>.json).
# Результат: export/full/ — raw/*.json + CSV (разделитель ;, UTF-8 BOM) + отчёт по дублям.
# -CsvOnly: не обращаться к API, пересобрать CSV и отчёт из raw/
param(
  [string]$From = '2000-01-01',
  [string]$To   = (Get-Date).AddYears(1).ToString('yyyy-MM-dd'),
  [int]$Threads = 4,
  [switch]$CsvOnly
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$out = Join-Path $PSScriptRoot 'export\full'
New-Item -ItemType Directory -Force -Path "$out\raw\clients" | Out-Null

function Save($name, $obj) { $obj | ConvertTo-Json -Depth 30 | Set-Content "$out\raw\$name.json" -Encoding utf8 }
function Load($name) { Get-Content "$out\raw\$name.json" -Raw -Encoding UTF8 | ConvertFrom-Json }
function SaveCsv($name, $rows) { @($rows) | Export-Csv "$out\$name.csv" -Delimiter ';' -Encoding utf8BOM -NoTypeInformation }
# custom_fields приходят объектом { "<code>": значение }
function CF($obj, $code) { if ($obj -and $obj.custom_fields) { $obj.custom_fields.$code } }

# Общий HTTP-вызов: используется и в основном потоке, и в параллельных (передаётся строкой)
$callDef = @'
function Call($method, $path, $body = $null) {
  $p = @{ Method = $method; Uri = "https://api.yclients.ru$path"; Headers = $headers; ContentType = 'application/json; charset=utf-8'; SkipHeaderValidation = $true }
  if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10)) }
  for ($try = 1; $try -le 6; $try++) {
    Start-Sleep -Milliseconds $pause
    try { return Invoke-RestMethod @p }
    catch {
      $code = [int]$_.Exception.Response.StatusCode
      if ($code -eq 429 -or $code -ge 500 -or $code -eq 0) { Start-Sleep -Seconds (5 * $try); continue }
      Write-Host "  ! $method $path -> HTTP ${code}: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
      return $null
    }
  }
  Write-Host "  ! $method $path -> не удалось после 6 попыток" -ForegroundColor Yellow
  $null
}
'@

if (-not $CsvOnly) {
  $cfg = @{}
  Get-Content (Join-Path $PSScriptRoot '.env') -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^\s*([^=#]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
  }
  $company = $cfg['YCLIENTS_COMPANY_ID']
  $headers = @{
    'Accept'        = 'application/vnd.yclients.v2+json'
    'Authorization' = "Bearer $($cfg['YCLIENTS_PARTNER_TOKEN']), User $($cfg['YCLIENTS_USER_TOKEN'])"
  }
  $pause = 260
  . ([scriptblock]::Create($callDef))

  Write-Host "== Справочники"
  Save 'company' (Call GET "/api/v1/company/$company/").data
  Save 'custom_fields_client' (Call GET "/api/v1/custom_fields/client/$company").data
  Save 'custom_fields_record' (Call GET "/api/v1/custom_fields/record/$company").data
  Save 'services' (Call GET "/api/v1/company/$company/services/").data
  Save 'service_categories' (Call GET "/api/v1/company/$company/service_categories/").data
  Save 'positions' (Call GET "/api/v1/company/$company/staff/positions/").data
  Save 'users' (Call GET "/api/v1/company/$company/users").data
  Save 'client_labels' (Call GET "/api/v1/labels/$company/clients").data
  Save 'resources' (Call GET "/api/v1/resources/$company").data

  Write-Host "== Сотрудники"
  Save 'staff' @((Call GET "/api/v1/company/$company/staff/").data)
  Save 'staff_legacy' (Call GET "/api/v1/staff/$company/").data

  if (-not (Test-Path "$out\raw\records.json")) {
    Write-Host "== Записи $From — $To"
    $records = [Collections.Generic.List[object]]::new(); $page = 1
    do {
      $r = Call GET "/api/v1/records/$company`?page=$page&count=200&start_date=$From&end_date=$To&with_deleted=1&include_finance_transactions=1&include_consumables=1"
      if (-not $r) { throw "Не удалось получить страницу $page записей" }
      @($r.data) | ForEach-Object { $records.Add($_) }; $total = $r.meta.total_count
      Write-Host "  страница $page`: $($records.Count) / $total"
      $page++
    } while (@($r.data).Count -gt 0 -and $records.Count -lt $total)
    Save 'records' $records
  } else { Write-Host "== Записи: уже скачаны (raw/records.json)" }

  Write-Host "== Список клиентов"
  $ids = [Collections.Generic.HashSet[long]]::new(); $page = 1
  do {
    $r = Call POST "/api/v1/company/$company/clients/search" @{ page = $page; page_size = 200; fields = @('id'); order_by = 'id'; order_by_direction = 'ASC' }
    if (-not $r) { throw "Не удалось получить страницу $page клиентов" }
    @($r.data) | ForEach-Object { [void]$ids.Add([long]$_.id) }; $total = $r.meta.total_count
    if ($page % 5 -eq 0) { Write-Host "  $($ids.Count) / $total" }
    $page++
  } while (@($r.data).Count -gt 0)
  Write-Host "  по поиску: $($ids.Count) (YCLIENTS сообщает $total)"
  # клиенты, которые есть в записях, но не попали в поиск (например, удалённые)
  $extra = 0
  (Load 'records') | Where-Object client | ForEach-Object { if ($ids.Add([long]$_.client.id)) { $extra++ } }
  Write-Host "  + из записей: $extra"
  Save 'client_ids' @($ids)

  $todo = @($ids | Where-Object { -not (Test-Path "$out\raw\clients\$_.json") })
  Write-Host "== Карточки клиентов: осталось $($todo.Count) из $($ids.Count), потоков $Threads"
  $started = Get-Date
  $todo | ForEach-Object -ThrottleLimit $Threads -Parallel {
    $headers = $using:headers; $company = $using:company; $dir = "$using:out\raw\clients"
    $pause = 250 * $using:Threads   # суммарно ≈ 4 запроса/сек
    . ([scriptblock]::Create($using:callDef))
    $card = Call GET "/api/v1/client/$company/$_"
    if (-not $card) { return }   # не сохраняем — повторится при следующем запуске
    $obj = [ordered]@{
      client   = $card.data
      comments = @((Call GET "/api/v1/company/$company/clients/$_/comments").data)
      files    = @((Call GET "/api/v1/company/$company/clients/files/$_").data)
    }
    $obj | ConvertTo-Json -Depth 30 | Set-Content "$dir\$_.json" -Encoding utf8
  }
  $done = @(Get-ChildItem "$out\raw\clients" -Filter *.json).Count
  Write-Host "  скачано карточек: $done / $($ids.Count) за $([int]((Get-Date) - $started).TotalMinutes) мин"
  if ($done -lt $ids.Count) { Write-Host "  Не все карточки скачаны — запустите скрипт ещё раз, он докачает остальные." -ForegroundColor Yellow }
}

# ================= CSV и проверка дублей (всегда из raw/) =================
Write-Host "== Сборка CSV"
$staff = @(Load 'staff'); $records = @(Load 'records')
$byId = @{}; $comments = @{}; $files = @{}
Get-ChildItem "$out\raw\clients" -Filter *.json | ForEach-Object {
  $o = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $id = "$($o.client.id)"; $byId[$id] = $o.client; $comments[$id] = @($o.comments); $files[$id] = @($o.files)
}
$clients = @($byId.Values | Sort-Object id)

SaveCsv 'staff' ($staff | ForEach-Object { [pscustomobject]@{
  id = $_.id; ФИО = $_.name; Специализация = $_.specialization; Должность = $_.position.title
  Телефон = $_.user.phone; Email = $_.user.email; Уволен = $_.fired; Дата_увольнения = $_.dismissal_date
  Скрыт_онлайн = $_.hidden; Услуг = @($_.services_links).Count; user_id = $_.user_id
  ФИО_полное = ("$($_.employee.surname) $($_.employee.firstname) $($_.employee.patronymic)").Trim(); Дата_приёма = $_.employee.date_admission
  Описание = ($_.information -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
} })

function ClientRow($c) { [pscustomobject]@{
  id = $c.id; Фамилия = $c.surname; Имя = $c.name; Отчество = $c.patronymic; Телефон = $c.phone; Email = $c.email
  Дата_рождения = $c.birth_date; Пол = $c.sex; Кличка = (CF $c 'klichka-pitomtsa'); Порода_пол = (CF $c 'poroda-i-pol-pitomtsa')
  Визитов = $c.visits; Потрачено = $c.spent; Оплачено = $c.paid; Баланс = $c.balance; Скидка = $c.discount
  Категории = (@($c.categories | ForEach-Object title) -join ', '); Комментарий = $c.comment
  Комментариев = @($comments["$($c.id)"]).Count; Файлов = @($files["$($c.id)"]).Count; Изменён = $c.last_change_date
} }

$attendance = @{ '-1' = 'не пришёл'; '0' = 'ожидание'; '1' = 'пришёл'; '2' = 'подтвердил' }
function RecordRow($r) {
  $cl = if ($r.client) { $byId["$($r.client.id)"] }
  [pscustomobject]@{
    id = $r.id; Дата = $r.datetime; Длительность_мин = [int]($r.length / 60); Врач = $r.staff.name; staff_id = $r.staff_id
    Клиент = if ($r.client) { "$($r.client.surname) $($r.client.name)".Trim() }; client_id = $r.client.id; Телефон = $r.client.phone
    Кличка = (CF $cl 'klichka-pitomtsa'); Порода_пол = (CF $cl 'poroda-i-pol-pitomtsa')
    Услуги = (@($r.services | ForEach-Object title) -join ' + ')
    Стоимость = (@($r.services | ForEach-Object cost) | Measure-Object -Sum).Sum
    Оплачено_полностью = $r.paid_full; Явка = $attendance["$($r.attendance)"]; Онлайн = $r.online
    Удалена = $r.deleted; Комментарий = $r.comment; Источник = (CF $r 'kak-vi-o-nas-uznali')
    Создана = $r.create_date; visit_id = $r.visit_id
  }
}

SaveCsv 'clients' ($clients | ForEach-Object { ClientRow $_ })
SaveCsv 'records' ($records | Sort-Object datetime | ForEach-Object { RecordRow $_ })

# --- Состоявшиеся записи: не удалены, клиент пришёл; без дублей (по id и по клиент+время+врач)
$recDupId = @($records | Group-Object id | Where-Object Count -gt 1)
$done = @($records | Where-Object { -not $_.deleted -and $_.attendance -eq 1 } |
  Group-Object id | ForEach-Object { $_.Group[0] })
$recDupSlot = @($done | Where-Object client | Group-Object { "$($_.client.id)|$($_.datetime)|$($_.staff_id)" } | Where-Object Count -gt 1)
$done = @($done | Group-Object { if ($_.client) { "$($_.client.id)|$($_.datetime)|$($_.staff_id)" } else { "id$($_.id)" } } |
  ForEach-Object { $_.Group[0] } | Sort-Object datetime)
$doneClients = @($done | Where-Object client | ForEach-Object { $byId["$($_.client.id)"] } | Where-Object { $_ } |
  Group-Object id | ForEach-Object { $_.Group[0] })
SaveCsv 'records_состоялись' ($done | ForEach-Object { RecordRow $_ })
SaveCsv 'clients_состоялись' ($doneClients | ForEach-Object { ClientRow $_ })

# --- Возможные дубли клиентов (не удаляются автоматически — только отчёт)
function NormPhone($p) { $d = "$p" -replace '\D', ''; if ($d.Length -eq 11 -and $d[0] -eq '8') { $d = '7' + $d.Substring(1) }; if ($d.Length -eq 10) { $d = '7' + $d }; $d }
function Norm($s) { ("$s".ToLower() -replace 'ё', 'е' -replace '[^a-zа-я0-9]', '') }
$rules = [ordered]@{
  'телефон'          = { $p = NormPhone $_.phone; if ($p.Length -ge 10) { $p } }
  'email'            = { $e = "$($_.email)".Trim().ToLower(); if ($e -match '@') { $e } }
  'ФИО+кличка'       = { $n = Norm "$($_.surname)$($_.name)$($_.patronymic)"; $k = Norm (CF $_ 'klichka-pitomtsa'); if ($n -and $k) { "$n|$k" } }
  'фамилия+имя+отчество' = { if ($_.surname -and $_.patronymic) { Norm "$($_.surname)|$($_.name)|$($_.patronymic)" } }
}
$recCount = @{}; $records | Where-Object client | ForEach-Object { $recCount["$($_.client.id)"]++ }
$dupRows = [Collections.Generic.List[object]]::new(); $groupNo = 0; $dupSummary = [ordered]@{}
foreach ($rule in $rules.Keys) {
  $groups = @($clients | ForEach-Object { $k = & $rules[$rule]; if ($k) { [pscustomobject]@{ k = $k; c = $_ } } } |
    Group-Object k | Where-Object Count -gt 1)
  $dupSummary[$rule] = "$($groups.Count) групп, $(($groups | Measure-Object Count -Sum).Sum) карточек"
  foreach ($g in $groups) {
    $groupNo++
    $sameName = @($g.Group | ForEach-Object { Norm "$($_.c.surname)$($_.c.name)" } | Sort-Object -Unique).Count -eq 1
    $verdict = if ($rule -ne 'email' -or $sameName) { 'вероятный дубль' } else { 'проверить: общий email, разные имена' }
    foreach ($x in $g.Group) {
      $row = [ordered]@{ Группа = $groupNo; Вывод = $verdict; Совпадение = $rule; Записей = [int]$recCount["$($x.c.id)"] }
      (ClientRow $x.c).PSObject.Properties | ForEach-Object { $row[$_.Name] = $_.Value }
      $dupRows.Add([pscustomobject]$row)
    }
  }
}
SaveCsv 'дубли_клиентов' $dupRows

$report = @"
Полная выгрузка YCLIENTS — $(Get-Date -Format 'yyyy-MM-dd HH:mm')

Клиентов: $($clients.Count)
Записей всего: $($records.Count) (удалённых: $(@($records | Where-Object deleted).Count))
Записей состоялось: $($done.Count), клиентов с состоявшимися записями: $($doneClients.Count)
Сотрудников: $($staff.Count)

Дубли записей:
  одинаковый id: $($recDupId.Count)
  клиент+время+врач (среди состоявшихся): $($recDupSlot.Count) групп — оставлена одна запись из группы

Возможные дубли клиентов (см. дубли_клиентов.csv, автоматически НЕ объединялись):
$(($dupSummary.GetEnumerator() | ForEach-Object { "  $($_.Key): $($_.Value)" }) -join "`n")
  итого групп «вероятный дубль»: $(@($dupRows | Where-Object Вывод -eq 'вероятный дубль' | Group-Object Группа).Count), «проверить»: $(@($dupRows | Where-Object Вывод -ne 'вероятный дубль' | Group-Object Группа).Count)
  не скачаны (удалены в YCLIENTS, есть только в записях): $(@((Load 'client_ids') | Where-Object { -not $byId["$_"] }).Count)
"@
$report | Set-Content "$out\отчёт.txt" -Encoding utf8BOM
Write-Host "`n$report"
